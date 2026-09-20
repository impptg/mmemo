#!/bin/sh
set -eu
umask 077
cd /opt/mmemo/current
backup_dir=/opt/mmemo/backups
mkdir -p "$backup_dir"
backup_path="$backup_dir/mmemo-$(date -u +%Y%m%dT%H%M%SZ).dump"
docker compose --env-file /opt/mmemo/server.env -f deploy/compose.yaml -p mmemo exec -T db pg_dump -U mmemo -d mmemo -Fc > "$backup_path.tmp"
mv "$backup_path.tmp" "$backup_path"
find "$backup_dir" -name 'mmemo-*.dump' -mtime +14 -delete
printf 'Saved %s\n' "$backup_path"
