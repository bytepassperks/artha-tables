#!/usr/bin/env bash
# Universal Artha rebrand quality gate.
#
# Asserts the thin Artha white-label layer survived an upstream merge. The
# per-module rules live in deploy/artha/deploy.conf as two arrays:
#
#   REBRAND_REQUIRE=( "path|grep-pattern|description" ... )   # must be present
#   REBRAND_FORBID=(  "path|grep-pattern|description" ... )   # must be absent
#
# grep patterns are matched as fixed strings (grep -F). A missing file is a
# failure for REQUIRE and a pass for FORBID. Exits non-zero (failing the gate,
# aborting the deploy) on the first violation.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1090
. "$HERE/deploy.conf"

fail=0
ok()   { printf '  ok   %s\n' "$*"; }
bad()  { printf '  FAIL %s\n' "$*" >&2; fail=1; }

echo "== verify-rebrand: ${MODULE_NAME:-module} =="

for entry in "${REBRAND_REQUIRE[@]:-}"; do
  [ -n "$entry" ] || continue
  file="${entry%%|*}"; rest="${entry#*|}"; pat="${rest%%|*}"; desc="${rest#*|}"
  if [ ! -f "$file" ]; then bad "[require] missing file: $file ($desc)"; continue; fi
  if grep -qF -- "$pat" "$file"; then ok "[require] $desc"; else bad "[require] '$pat' not in $file ($desc)"; fi
done

for entry in "${REBRAND_FORBID[@]:-}"; do
  [ -n "$entry" ] || continue
  file="${entry%%|*}"; rest="${entry#*|}"; pat="${rest%%|*}"; desc="${rest#*|}"
  if [ ! -f "$file" ]; then ok "[forbid] $desc (file absent)"; continue; fi
  if grep -qF -- "$pat" "$file"; then bad "[forbid] '$pat' leaked into $file ($desc)"; else ok "[forbid] $desc"; fi
done

if [ "$fail" -ne 0 ]; then
  echo "== verify-rebrand FAILED — rebrand drifted, deploy aborted ==" >&2
  exit 1
fi
echo "== verify-rebrand passed =="
