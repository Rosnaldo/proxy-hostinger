# proxy-hostinger

Central nginx for every app on the Hostinger server. It is the only stack that
publishes ports 80 and 443; it gets the Let's Encrypt certificates and routes each
domain to its app.

```
proxy-hostinger/
├── docker-compose.yml
├── .env.prod                    where each app's nginx folder is on this server
├── nginx/
│   ├── http/default.conf        nginx-http: ACME challenge + redirect to HTTPS
│   └── render-modules.sh        nginx-https: fills each app's config at startup
├── certbot/                     ACME challenge files (git-ignored)
└── letsencrypt/                 certificates, live/<domain>/ (git-ignored)
```

The HTTPS routes belong to each app, in its own repo:

- `<app>/nginx/prod/https/nginx.conf`: a `server` block (no `events`/`http`), a
  template using the variables of
- `<app>/nginx/.env.prod`: `BASE_DOMAIN` and `ADMIN_EMAIL` (certbot) plus whatever
  else the template uses.

`render-modules.sh` fills each template with its own app's `.env.prod` only, so every
app can call its domain `BASE_DOMAIN`; nginx's `$vars` are left alone. `certbot` reads
the same files to get one certificate per `BASE_DOMAIN` (plus `www.`).

## How the apps are reached

The proxy and the apps share the external Docker network `edge`. Each app puts on it
only the services nginx talks to, with a prefixed alias so names from different stacks
(`backend`, `redis`, ...) don't clash:

| App        | Alias on `edge`         | Port | Paths                           |
| ---------- | ----------------------- | ---- | ------------------------------- |
| forecast   | `forecast-backend`      | 8000 | `/backend/ /static/ /health/`   |
| callcenter | `callcenter-iam`        | 5002 | `/iam/`                         |
| callcenter | `callcenter-realtime`   | 5003 | `/realtime/`                    |
| callcenter | `callcenter-chatbot`    | 5004 | `/chatbot/`                     |
| callcenter | `callcenter-keycloak`   | 8080 | `/auth/`                        |

Upstreams are resolved per request (Docker DNS), so the proxy starts and keeps
serving one app while the other is down; that app's routes answer 502 meanwhile.

## Deploy

1. DNS: A records for each domain and its `www.` pointing to the server.
2. Once per server: `docker network create edge`
3. In each app, `docker compose -f docker-compose.prod.yml up -d --build --remove-orphans`.
   `--remove-orphans` removes the app's old nginx/certbot containers, freeing 80/443.
4. Here: set the paths in `.env.prod`, then `docker compose --env-file .env.prod up -d`

On the first `up`, `certbot` gets one certificate per domain (including `www.`) and
`nginx-https` restarts until they exist. `certbot-renew` tries every 12h and
`nginx-https` reloads every 6h to pick up renewed certificates.

## Adding an app

1. In the app's compose: join `edge` with an `<app>-<service>` alias (see the apps'
   compose files) and declare `edge` as `external: true`.
2. In the app: `nginx/prod/https/nginx.conf` (a `server` block proxying to those
   aliases through variables, see the callcenter one) and `nginx/.env.prod`.
3. Here: the folder's path in `.env.prod`, and in `docker-compose.yml` mount both files
   under `/modules/<app>/` in `nginx-https` and the `.env.prod` in `certbot`.
4. `docker compose --env-file .env.prod up -d --force-recreate nginx-https certbot`
# proxy-hostinger
