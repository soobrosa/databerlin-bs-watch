#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$ROOT/data"
IN="$DATA_DIR/jobs.json"
OUT="$DATA_DIR/flagged.json"

TODAY="$(date -u +%Y-%m-%d)"

jq --arg today "$TODAY" '
  def to_epoch($d): $d | strptime("%Y-%m-%d") | mktime;
  def age_days($d):
    if ($d // "") == "" then null
    else ((to_epoch($today) - to_epoch($d)) / 86400) | floor
    end;

  def strip_levels:
    ascii_downcase
    | gsub("[^a-z0-9 ]"; " ")
    | gsub("\\b(senior|staff|principal|lead|junior|jr|sr|mid|intermediate|head of|head|director|vp|chief|manager|associate|i|ii|iii|iv)\\b"; "")
    | gsub("\\s+"; " ")
    | gsub("^\\s+|\\s+$"; "");

  def collapse_ws:
    ascii_downcase | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "");

  ($today) as $t
  | .jobs
  | map(. + { age_days: age_days(.date), norm_title: (.title | strip_levels), title_key: (.title | collapse_ws) })
  | group_by(.company)
  | map(
      . as $cjobs
      | {
          company: $cjobs[0].company,
          total: ($cjobs | length),
          oldest_date: ($cjobs | map(.date) | map(select(. != "")) | min),
          newest_date: ($cjobs | map(.date) | map(select(. != "")) | max),
          oldest_age_days: ($cjobs | map(.age_days) | map(select(. != null)) | max),
          stale_jobs: ($cjobs | map(select(.age_days != null and .age_days > 90))),
          duplicate_groups: (
            $cjobs | group_by(.date + "::" + .title_key)
            | map(select(length > 1))
            | map({ date: .[0].date, title: .[0].title, count: length })
          ),
          multi_seniority_groups: (
            $cjobs | group_by(.norm_title)
            | map(select((map(.seniority) | unique | length) > 1 and (.[0].norm_title | length) > 3))
            | map({ norm_title: .[0].norm_title, seniorities: (map(.seniority) | unique), count: length, sample_title: .[0].title })
          ),
          jobs: $cjobs
        }
    )
  | map(. + {
      reasons: (
        [
          (if (.stale_jobs | length) > 0 then "stale" else empty end),
          (if (.duplicate_groups | length) > 0 then "duplicates" else empty end),
          (if (.multi_seniority_groups | length) > 0 then "multi-seniority" else empty end)
        ]
      )
    })
  | map(. + { flagged: ((.reasons | length) > 0) })
  | sort_by(-(.stale_jobs | length), -(.duplicate_groups | length), -(.multi_seniority_groups | length), -.total)
  | {
      generated_at: $today,
      total_companies: length,
      total_jobs: (map(.total) | add),
      flagged_companies: (map(select(.flagged)) | length),
      companies: .
    }
' "$IN" > "$OUT"

echo "Flagged $(jq -r '.flagged_companies' "$OUT") of $(jq -r '.total_companies' "$OUT") companies"
