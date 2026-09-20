#!/bin/sh
set -eu
cd /opt/mmemo/current
./deploy/backup.sh
latest=$(find /opt/mmemo/backups -name 'mmemo-*.dump' | sort | tail -1)
restore_db=mmemo_restore_check
trap 'docker exec mmemo-db-1 dropdb --if-exists -U mmemo mmemo_restore_check >/dev/null' EXIT
docker exec mmemo-db-1 createdb -U mmemo "$restore_db"
docker exec -i mmemo-db-1 pg_restore -U mmemo -d "$restore_db" --exit-on-error < "$latest"
original=$(docker exec mmemo-db-1 psql -U mmemo -d mmemo -Atc "SELECT count(*),md5(COALESCE(string_agg(row_to_json(t)::text,'' ORDER BY id),'')) FROM todos t;")
restored=$(docker exec mmemo-db-1 psql -U mmemo -d "$restore_db" -Atc "SELECT count(*),md5(COALESCE(string_agg(row_to_json(t)::text,'' ORDER BY id),'')) FROM todos t;")
[ "$original" = "$restored" ] || { echo 'Restore verification failed'; exit 1; }
printf 'PASS: original and restored %s\n' "$original"
