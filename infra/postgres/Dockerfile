# Local PostgreSQL for RaajjePro.
#
# The stock postgres image has no pg_cron. This adds the Debian package for the
# matching major version and nothing else — configuration lives in
# docker-compose.yml so that it is visible next to the ports and volumes it
# depends on.
#
# The package version is read from $PG_MAJOR, which the postgres image sets, so
# it tracks the FROM line automatically. It was hardcoded to 16, and when
# Dependabot bumped the base image to 18 the build still passed — the PG16
# package installs happily onto a PG18 image, into /usr/share/postgresql/16/
# where an 18 server never looks. The failure surfaced only at runtime, as
# FATAL: could not access file "pg_cron", with the server refusing to start.
FROM postgres:18

RUN apt-get update \
 && apt-get install -y --no-install-recommends postgresql-$PG_MAJOR-cron \
 && rm -rf /var/lib/apt/lists/*

# The WAL archive and base-backup targets. Both are mounted as volumes by
# compose; creating them here makes the image usable without compose too.
RUN mkdir -p /var/lib/postgresql/wal_archive /var/lib/postgresql/backups \
 && chown postgres:postgres /var/lib/postgresql/wal_archive /var/lib/postgresql/backups
