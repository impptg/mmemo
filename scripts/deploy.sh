#!/bin/sh
# Usage: sh scripts/deploy.sh root@SERVER; SSH must already be configured.
set -eu
cd "$(dirname "$0")/.."
server=${1:?Specify SSH destination}
pnpm install --frozen-lockfile
pnpm build
pnpm check
release=$(mktemp /tmp/mmemo-release.XXXXXX)
trap 'rm -f "$release"' EXIT
COPYFILE_DISABLE=1 tar -czf "$release" package.json pnpm-lock.yaml pnpm-workspace.yaml apps/server/package.json apps/server/dist packages/contracts/package.json packages/contracts/dist database deploy
scp "$release" "$server:/opt/mmemo/release.tgz"
ssh "$server" 'set -eu; cd /opt/mmemo/current; deploy/backup.sh; tar -xzf /opt/mmemo/release.tgz; docker compose --env-file /opt/mmemo/server.env -f deploy/compose.yaml -p mmemo up -d --build --wait; docker cp pp-web-site:/etc/nginx/conf.d/mmemo-ip.conf "/opt/mmemo/backups/mmemo-ip-before-$(date -u +%Y%m%dT%H%M%SZ).conf"; docker cp deploy/ip-https.conf pp-web-site:/etc/nginx/conf.d/mmemo-ip.conf; docker exec pp-web-site nginx -t; docker exec pp-web-site nginx -s reload; curl --fail --silent --show-error https://59.110.153.116/health'
