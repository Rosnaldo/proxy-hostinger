#!/bin/sh
# Renders each app's nginx config into /etc/nginx/conf.d/<app>.conf. Run by the nginx
# image's entrypoint at container start (mounted in /docker-entrypoint.d/).
#
# Each app is mounted at /modules/<app>/ (docker-compose.yml): its nginx.conf
# (<app>/nginx/prod/https/nginx.conf) is a template filled from its own .env.prod. Only
# the variables set in that file are replaced, so ${BASE_DOMAIN} is a different domain
# per app and nginx's own $vars are kept.
set -eu

# Hosts no app serves: the TLS handshake is refused, so no app's certificate is shown
# for a domain it doesn't belong to. Replaces the image's welcome page.
cat > /etc/nginx/conf.d/default.conf <<'EOF'
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_reject_handshake on;
}
EOF

for dir in /modules/*/; do
    app=$(basename "$dir")
    vars=$(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/${\1}/p' "$dir/.env.prod" | tr '\n' ' ')
    (set -a; . "$dir/.env.prod"; envsubst "$vars" < "$dir/nginx.conf" > "/etc/nginx/conf.d/$app.conf")
    echo "$0: rendered $app"
done
