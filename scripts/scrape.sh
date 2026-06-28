#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$ROOT/data"
mkdir -p "$DATA_DIR"

URL="https://databerlin.net/jobs/"
RAW="$DATA_DIR/raw.html"
TSV="$DATA_DIR/cards.tsv"
OUT="$DATA_DIR/jobs.json"

curl -sSL --compressed \
  -A "Mozilla/5.0 (compatible; databerlin-bs-watch/1.0; +https://github.com/)" \
  "$URL" -o "$RAW"

rg -oN --multiline --multiline-dotall \
  '<a href="(/jobs/[^"]+)"[^>]*data-category="([^"]*)"[^>]*data-seniority="([^"]*)"[^>]*data-company="([^"]*)"[^>]*data-company-name="([^"]*)"[^>]*data-date="([^"]*)"[^>]*data-title="([^"]*)"' \
  -r '$1	$2	$3	$4	$5	$6	$7' \
  "$RAW" \
  | awk -F'\t' 'NF==7 && !seen[$0]++' \
  > "$TSV"

ROW_COUNT="$(wc -l < "$TSV" | tr -d ' ')"
if [ "$ROW_COUNT" -lt 50 ]; then
  echo "ERROR: only $ROW_COUNT rows extracted, layout may have changed" >&2
  exit 1
fi

jq -Rn --arg today "$(date -u +%Y-%m-%d)" '
  [inputs | select(length>0) | split("\t") | {
    url: ("https://databerlin.net" + .[0]),
    category: .[1],
    seniority: .[2],
    company_slug: .[3],
    company: .[4],
    date: (.[5][0:10]),
    title: (.[6] | gsub("^\\s+|\\s+$"; "") | gsub("\\s+"; " "))
  }]
  | { fetched: $today, count: length, jobs: . }
' "$TSV" > "$OUT"

echo "Wrote $(jq -r '.count' "$OUT") jobs to $OUT"
