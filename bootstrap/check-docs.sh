#!/usr/bin/env bash
# Every repo path or script a guide mentions must exist (and scripts must be executable).  ./bootstrap/check-docs.sh
# Catches stale references before an attendee does. Does not replace a human reading the labs cold.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
bad=0
for f in README.md docs/platform-setup.md docs/attendee-prerequisites.md modules/*/lab.md; do
  [ -f "$f" ] || continue
  for p in $(sed -E 's#https?://[^ )>]+##g' "$f" | grep -o -E '(bootstrap|modules|platform|apps|runbooks|crossplane|docs|\.github)/[A-Za-z0-9_./-]+' | sed -E 's/[.,;:)]+$//' | sort -u); do
    case "$p" in *'*'*|*'<'*) continue ;; esac
    if [ ! -e "$p" ]; then echo "MISSING   $f -> $p"; bad=1
    elif case "$p" in *.sh) true ;; *) false ;; esac && [ ! -x "$p" ]; then echo "NOT EXEC  $f -> $p"; bad=1; fi
  done
done
[ "$bad" -eq 0 ] && echo "docs: all referenced paths exist" || exit 1
