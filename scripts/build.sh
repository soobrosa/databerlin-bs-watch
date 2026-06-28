#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cp "$ROOT/data/jobs.json" "$ROOT/public/jobs.json"
cp "$ROOT/data/flagged.json" "$ROOT/public/flagged.json"

{
  printf 'window.DATA = '
  cat "$ROOT/data/flagged.json"
  printf ';\n'
} > "$ROOT/public/flagged.js"

echo "Wrote $ROOT/public/{jobs.json,flagged.json,flagged.js}"
