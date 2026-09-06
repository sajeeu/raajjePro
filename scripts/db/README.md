# Database: point-in-time recovery

Plan §Phase 0 requires PITR "from the first migration", and §5 sets the target: **RPO ≤ 5 minutes, RTO 4 hours**. The database is the only record that a customer paid and a provider confirmed, so a lost hour is an hour of unadjudicable disputes.

## What is configured

In `docker-compose.yml`, on the `db` service:

| Setting | Value | Why |
|---|---|---|
| `wal_level` | `replica` | WAL carries enough to replay |
| `archive_mode` | `on` | every completed segment is copied out |
| `archive_command` | `test ! -f … && cp %p …/wal_archive/%f` | copy to the `db_wal_archive` volume; never overwrite |
| `archive_timeout` | `300` | force a partial segment out every 5 min — **this is what bounds the RPO** |

Plus a base backup to replay onto, taken with `scripts/db/base-backup.sh` into the `db_backups` volume.

## Scripts

| Script | Does |
|---|---|
| `scripts/db/base-backup.sh` | takes a base backup (`pg_basebackup`, tar + gzip, WAL fetched) |
| `scripts/db/base-backup.sh --list` | lists existing base backups |
| `scripts/db/pitr-status.sh` | archiver counters, last archive age; exit 1 if archiving is off, unstarted or failing |

## Restore to a point in time — local procedure

Phase 24 drills this against the RPO/RTO. Until then it is written down so it exists before it is needed.

1. Stop the database: `docker compose stop db`.
2. Move the live data aside inside the volume and unpack the chosen base backup into an empty data directory. `$PGDATA` is used throughout rather than a literal path: PostgreSQL 18's image moved the cluster to a major-version directory (`/var/lib/postgresql/18/docker`), and a restore procedure that hardcodes the old location fails at the one moment it is needed.
   ```bash
   docker compose run --rm --no-deps -u postgres --entrypoint sh db -c '
     set -e
     B=/var/lib/postgresql/backups/base-<STAMP>
     mv $PGDATA $PGDATA.broken
     mkdir -m 700 $PGDATA
     tar -xzf $B/base.tar.gz   -C $PGDATA
     tar -xzf $B/pg_wal.tar.gz -C $PGDATA/pg_wal
     touch $PGDATA/recovery.signal
     cat >> $PGDATA/postgresql.auto.conf <<EOF
   restore_command = '"'"'cp /var/lib/postgresql/wal_archive/%f %p'"'"'
   recovery_target_time = '"'"'<YYYY-MM-DD HH:MM:SS+00>'"'"'
   recovery_target_action = '"'"'promote'"'"'
   EOF'
   ```
3. Start it: `docker compose start db`. PostgreSQL replays archived WAL up to `recovery_target_time`, then promotes. Watch `docker compose logs -f db` for `database system is ready`.
4. Verify the data, then remove the `.broken` directory once satisfied.

Omit `recovery_target_time` to recover to the end of the archive (everything up to the last archived segment — at most 5 minutes before the failure).

## On a managed host

PITR is a checkbox on every managed PostgreSQL (RDS, Cloud SQL, Neon, Supabase …). Turn it on **before** running the first migration there, set the backup retention, and record where the WAL is going. `pg_cron` needs the same two server parameters compose sets locally: `shared_preload_libraries = 'pg_cron'` and `cron.database_name = '<app database>'`.
