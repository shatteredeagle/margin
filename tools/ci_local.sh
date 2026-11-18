#!/bin/bash
# The CI checks (.github/workflows/ci.yml), runnable locally from the repo root: tools/ci_local.sh
set -e
cd "$(dirname "$0")/.."
for f in Margin/*.lua; do luac5.1 -p "$f"; done
echo "syntax ok"
tmp=$(mktemp -d)
(cd Margin && grep -E '^[A-Za-z0-9_./\\-]+\.lua\s*$' Margin.toc | tr -d '\r' | sed 's/\\/\//g' | sort > "$tmp/listed" && ls *.lua | sort > "$tmp/present")
diff "$tmp/listed" "$tmp/present"
echo "toc ok"
for f in Margin/*.lua; do luac5.1 -l -p "$f" | awk '/GETGLOBAL|SETGLOBAL/ {print $NF}'; done | sort -u > "$tmp/used"
unknown=$(comm -23 "$tmp/used" <(sort tests/allowed_globals.txt))
if [ -n "$unknown" ]; then echo "Unknown globals:"; echo "$unknown"; exit 1; fi
echo "globals ok"
lua5.1 tests/calc_test.lua | tail -1 | grep -q "^calc ok$"
echo "calc ok"
if [ -f tests/ui_smoke.lua ]; then
  lua5.1 tests/ui_smoke.lua | tail -1 | grep -q "^ui smoke ok$"
  echo "ui smoke ok"
fi
rm -rf "$tmp"
