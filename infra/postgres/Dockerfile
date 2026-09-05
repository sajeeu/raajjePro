# Local PostgreSQL for RaajjePro.
#
# The stock postgres image has no pg_cron. This adds the Debian package for the
# matching major version and nothing else — configuration lives in
# docker-compose.yml so that it is visible next to the ports and volumes it
# depends on.
FROM postgres:16

RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-16-cron \
 && rm -rf /var/lib/apt/lists/*

# The WAL archive and base-backup targets. Both are mounted as volumes by
# compose; creating them here makes the image usable without compose too.
RUN mkdir -p /var/lib/postgresql/wal_archive /var/lib/postgresql/backups \
 && chown postgres:postgres /var/lib/postgresql/wal_archive /var/lib/postgresql/backups
