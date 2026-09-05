#!/usr/bin/env bash
# Everything that can be checked without running the app.
#
# Development happens in VS Code; verification happens here. This is the single
# command that answers "is the repo still consistent?" — run it before you ask
# for a review, and before any commit that touches a prototype or an
# instruction file.
#
#   scripts/verify.sh          run every check
#   scripts/verify.sh --quiet  only report failures
set -uo pipefail
cd "$(dirname "$0")/.."

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

fail=0
run() {
  local name="$1"; shift
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then
    [[ $QUIET -eq 0 ]] && printf '  ok    %s\n' "$name"
  else
    printf '  FAIL  %s\n' "$name"
    sed 's/^/          /' <<<"$out"
    fail=1
  fi
  return 0
}

echo "Verifying $(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD)"
echo

echo "Prototypes"
run "61 design components"  python3 docs/design/verify-dc.py mockups/design-composer/*.dc.html
echo
echo "Navigation"
run "acceptance journeys"   python3 docs/design/checks/journeys.py
echo
echo "Instructions"
run "locked rules"          python3 docs/design/checks/locked-rules.py
echo

if [[ -f backend/package.json ]]; then
  echo "Backend"
  # Resolve the lockfile first. npm scripts run happily against a stale
  # node_modules, so every check below can pass on a tree that a clean
  # checkout cannot even install — which is exactly how a TypeScript major
  # bump kept CI red for three runs while this script reported all green.
  run "lockfile resolves" npm --prefix backend ci --dry-run
  run "typecheck" npm --prefix backend run --silent typecheck
  run "lint"      npm --prefix backend run --silent lint
  run "tests"     npm --prefix backend run --silent test
  echo
fi

if [[ -f frontend/pubspec.yaml ]]; then
  echo "Frontend"
  # Flutter resolves the project from the working directory, so run inside it.
  run "analyze" bash -c 'cd frontend && flutter analyze --no-pub'
  run "tests"   bash -c 'cd frontend && flutter test'
  echo
fi

if [[ $fail -eq 0 ]]; then
  echo "All checks passed."
else
  echo "Something failed above. Nothing was committed."
fi
exit $fail
