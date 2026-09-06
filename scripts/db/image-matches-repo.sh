#!/usr/bin/env bash
# The running database is the image the repository specifies.
#
# A container created before an image change keeps running the old image
# indefinitely: `docker compose up -d` does not recreate it, and nothing else
# notices. That is how the Postgres 18 bump stayed broken through ten commits
# — every local check passed against a container that was still Postgres 16,
# and only CI, which builds from nothing, ever saw the failure.
#
# Skips silently when Docker or the container is not running: this script must
# keep working on a machine with the database down.
set -uo pipefail
cd "$(dirname "$0")/../.."

command -v docker >/dev/null 2>&1 || exit 0
docker compose ps --status running --services 2>/dev/null | grep -qx db || exit 0

want="$(sed -n 's/^FROM postgres:\([0-9][0-9]*\).*/\1/p' infra/postgres/Dockerfile | head -1)"
[[ -n "$want" ]] || { echo "could not read the major version from infra/postgres/Dockerfile"; exit 1; }

got="$(docker compose exec -T db sh -c 'echo $PG_MAJOR' 2>/dev/null | tr -d '\r\n')"
[[ -n "$got" ]] || { echo "could not read PG_MAJOR from the running container"; exit 1; }

if [[ "$got" != "$want" ]]; then
  cat <<MSG
the running container is PostgreSQL $got, the repository specifies $want.
Every check that touches the database is passing against the wrong version.
  docker compose down -v && docker compose up -d --build --wait db
then re-apply both migrations (see HANDOVER.md "Set up"). -v is required:
the 18 image will not adopt a data directory laid out by an older one.
MSG
  exit 1
fi
