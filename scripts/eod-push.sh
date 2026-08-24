#!/usr/bin/env bash
# End-of-day: verify, commit, push. Safe to run any number of times.
#   scripts/eod-push.sh ["optional commit subject"]
set -euo pipefail
# Work from this script's own repository, whatever the caller's cwd is.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
cd "$(git rev-parse --show-toplevel)"

DRY=0
SUBJECT=""
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY=1 ;;
    -*) echo "Unknown option: $arg" >&2
        echo "Usage: scripts/eod-push.sh [--dry-run] [\"commit subject\"]" >&2
        exit 2 ;;
    *)  SUBJECT="$arg" ;;
  esac
done

echo "── RaajjePro · end of day ─────────────────────────"
date '+%Y-%m-%d %H:%M %Z'

# 1. Design prototypes must pass before anything is committed.
shopt -s nullglob
DC=(mockups/design-composer/*.dc.html)
if (( ${#DC[@]} )); then
  echo
  echo "Checking ${#DC[@]} design prototypes…"
  if ! python3 docs/design/verify-dc.py "${DC[@]}"; then
    echo
    echo "STOPPED — a prototype failed its check. Nothing committed."
    echo "Fix it, or commit by hand if you know why it is failing."
    exit 1
  fi
fi

# 2. Remote sanity. This repo has had a wrong-remote incident before.
REMOTE=$(git remote get-url origin)
case "$REMOTE" in
  *raajjePro*) ;;
  *) echo; echo "STOPPED — origin is $REMOTE, which is not raajjePro."; exit 1 ;;
esac

# 3. Nothing to do is a normal outcome, not an error.
if [[ -z "$(git status --porcelain)" ]]; then
  echo
  echo "Working tree clean."
  UNPUSHED=$(git log --oneline @{u}..HEAD 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$UNPUSHED" != "0" ]]; then
    if (( DRY )); then
      echo "$UNPUSHED commit(s) not yet pushed — dry run, not pushing."
    else
      echo "$UNPUSHED commit(s) not yet pushed — pushing."
      git push origin "$(git rev-parse --abbrev-ref HEAD)"
    fi
  else
    echo "Nothing to push. Done."
  fi
  exit 0
fi

# 4. Show what is about to go in.
echo
git status --short
echo

if (( DRY )); then
  echo "Dry run — the above would be committed as:"
  echo "    ${SUBJECT:-End of day $(date '+%Y-%m-%d')}"
  echo "Nothing committed, nothing pushed."
  exit 0
fi

SUBJECT="${SUBJECT:-End of day $(date '+%Y-%m-%d')}"
git add -A
git commit -q -m "$SUBJECT" -m "$(git diff --cached --stat | tail -1)"
git push origin "$(git rev-parse --abbrev-ref HEAD)"

echo
echo "Pushed:"
git log --oneline -1
