#!/usr/bin/env bash
# Take a base backup of the local RaajjePro database.
#
# Point-in-time recovery needs two things: a continuous WAL archive, which
# docker-compose.yml turns on (archive_mode=on, archive_timeout=300), and a
# base backup to replay that archive onto. This script produces the second.
# Without a base backup the WAL archive is a diary with no first page.
#
#   scripts/db/base-backup.sh          take one now
#   scripts/db/base-backup.sh --list   show what exists
#
# Backups land in the db_backups volume as base-<UTC timestamp>/ containing
# base.tar.gz and pg_wal.tar.gz. Restore procedure: scripts/db/README.md.
# Phase 24 drills the restore against §5's RPO/RTO; this only takes the backup.
set -euo pipefail
cd "$(dirname "$0")/../.."

BACKUP_ROOT=/var/lib/postgresql/backups

if [[ "${1:-}" == "--list" ]]; then
  docker compose exec -T db sh -c "ls -1 $BACKUP_ROOT 2>/dev/null || true"
  exit 0
fi

stamp=$(date -u +%Y%m%dT%H%M%SZ)
target="$BACKUP_ROOT/base-$stamp"

# -X fetch bundles the WAL the backup itself needs, so the tarball restores on
# its own; the archive volume carries everything after it.
docker compose exec -T db pg_basebackup \
  -U raajjepro -D "$target" \
  --format=tar --gzip --checkpoint=fast --wal-method=fetch \
  --label="raajjepro-$stamp" --progress --verbose

echo
echo "Base backup written to $target (inside the db_backups volume)."
echo "WAL archive status:"
docker compose exec -T db psql -U raajjepro -d raajjepro -Atc \
  "select 'archived_count='||archived_count||' last_archived_wal='||coalesce(last_archived_wal,'-')||' last_archived_time='||coalesce(last_archived_time::text,'-')||' failed_count='||failed_count from pg_stat_archiver"
