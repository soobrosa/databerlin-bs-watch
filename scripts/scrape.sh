#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$ROOT/data"
mkdir -p "$DATA_DIR"

URL="https://databerlin.net/jobs/"
RAW="$DATA_DIR/raw.html"
OUT="$DATA_DIR/jobs.json"
MIN_JOBS="${MIN_JOBS:-50}"

curl -sSL --compressed --fail \
  -A "Mozilla/5.0 (compatible; databerlin-bs-watch/1.0; +https://github.com/)" \
  "$URL" -o "$RAW"

python3 "$ROOT/scripts/extract.py" "$RAW" "$OUT" "$MIN_JOBS"
