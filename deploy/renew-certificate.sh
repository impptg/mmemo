#!/bin/sh
set -eu
docker run --rm -v /opt/mmemo/letsencrypt:/etc/letsencrypt -v /opt/mmemo/acme:/var/www/acme certbot/certbot renew --quiet --no-random-sleep-on-renew "$@"
docker cp -L /opt/mmemo/letsencrypt/live/59.110.153.116/fullchain.pem pp-web-site:/etc/nginx/ssl/mmemo-fullchain.pem
docker cp -L /opt/mmemo/letsencrypt/live/59.110.153.116/privkey.pem pp-web-site:/etc/nginx/ssl/mmemo-privkey.pem
docker cp /opt/mmemo/current/deploy/ip-https.conf pp-web-site:/etc/nginx/conf.d/mmemo-ip.conf
docker exec pp-web-site nginx -t
docker exec pp-web-site nginx -s reload
