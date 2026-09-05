#!/usr/bin/env bash
# Is point-in-time recovery actually protecting the local database?
#
# Prints the archiver's own counters and the age of the newest archived WAL
# segment. Exits 1 when archiving is off, has never succeeded, or the last
# archive failed — the states in which the RPO promise is false.
#
# Interpreting the age: with archive_timeout=300 a healthy idle database
# archives a segment at least every five minutes, so an age above ~6 minutes
# means archiving has stalled. A freshly started database has archived nothing
# yet; give it one archive_timeout before reading anything into that.
set -euo pipefail
cd "$(dirname "$0")/../.."

psql() { docker compose exec -T db psql -U raajjepro -d raajjepro -Atc "$1"; }

archive_mode=$(psql "show archive_mode")
archive_timeout=$(psql "show archive_timeout")
# Timestamps contain spaces, so split on the psql field separator, not whitespace.
IFS='|' read -r archived failed last_wal last_time last_failed_wal last_failed_time <<<"$(psql \
  "select archived_count, failed_count,
          coalesce(last_archived_wal,'-'), coalesce(last_archived_time::text,'-'),
          coalesce(last_failed_wal,'-'),   coalesce(last_failed_time::text,'-')
   from pg_stat_archiver")"
age=$(psql "select coalesce(extract(epoch from now()-last_archived_time)::int::text,'-') from pg_stat_archiver")

echo "archive_mode      $archive_mode"
echo "archive_timeout   $archive_timeout"
echo "archived_count    $archived"
echo "failed_count      $failed"
echo "last_archived     $last_wal  at $last_time"
[[ "$age" != "-" ]] && echo "last_archive_age  ${age}s"
[[ "$failed" != "0" ]] && echo "last_failed       $last_failed_wal  at $last_failed_time"
echo "base_backups      $(docker compose exec -T db sh -c 'ls -1 /var/lib/postgresql/backups 2>/dev/null | wc -l')"

if [[ "$archive_mode" != "on" ]]; then
  echo; echo "PITR: NOT PROTECTED — archive_mode is off"; exit 1
fi
if [[ "$archived" == "0" ]]; then
  echo; echo "PITR: NOT YET — nothing archived (wait one archive_timeout after first start)"; exit 1
fi
if [[ "$last_failed_time" != "-" && "$last_failed_time" > "$last_time" ]]; then
  echo; echo "PITR: FAILING — the most recent archive attempt failed"; exit 1
fi
echo; echo "PITR: archiving (RPO bound: $archive_timeout)"
