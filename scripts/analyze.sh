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

  # "(m/f/d)", "(w/m/d)", "m/f/x", "(all genders)" and friends are boilerplate
  # that would otherwise keep otherwise-identical titles in separate buckets.
  def strip_diversity:
    gsub("\\((?:[mfwdx](?:[ /]*[mfwdx])+)\\)"; " ")
    | gsub("\\b[mfwdx](?:/[mfwdx])+\\b"; " ")
    | gsub("\\ball genders\\b"; " ")
    | gsub("\\bdiverse\\b"; " ");

  # Pure seniority modifiers, leftover diversity initials and stopwords. Role
  # nouns such as manager, head or director are deliberately kept: dropping
  # them collapses genuinely different jobs into one bucket.
  def noise_tokens:
    [
      "senior", "sr", "staff", "principal", "junior", "jr", "mid", "intermediate",
      "lead", "associate", "entry", "level", "i", "ii", "iii", "iv",
      "m", "f", "w", "d", "x",
      "a", "an", "and", "at", "for", "in", "of", "or", "the", "to", "with"
    ];

  # Word order varies upstream ("Senior Software Engineer (m/f/d) Data" vs
  # "(Senior) Software Engineer Data (m/f/d)"), so compare sorted token sets.
  def norm_title:
    ascii_downcase
    | strip_diversity
    | gsub("[^a-z0-9 ]"; " ")
    | [splits(" +")]
    | map(select(length > 0))
    | map(select(. as $token | noise_tokens | index($token) | not))
    | unique
    | join(" ");

  def collapse_ws:
    ascii_downcase | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "");

  (.jobs // [])
  | unique_by(.url)
  | map(. + { age_days: age_days(.date), norm_title: (.title | norm_title), title_key: (.title | collapse_ws) })
  | group_by(.company_slug)
  | map(
      . as $cjobs
      | {
          company: $cjobs[0].company,
          company_slug: $cjobs[0].company_slug,
          total: ($cjobs | length),
          undated: ($cjobs | map(select((.date // "") == "")) | length),
          oldest_date: ($cjobs | map(.date) | map(select(. != "")) | min),
          newest_date: ($cjobs | map(.date) | map(select(. != "")) | max),
          oldest_age_days: ($cjobs | map(.age_days) | map(select(. != null)) | max),
          stale_jobs: ($cjobs | map(select(.age_days != null and .age_days > 90))),
          duplicate_groups: (
            $cjobs | group_by(.date + "::" + .title_key)
            | map(select(length > 1))
            | map({ date: .[0].date, title: .[0].title, count: length, urls: (map(.url)) })
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
      total_jobs: ((map(.total) | add) // 0),
      undated_jobs: ((map(.undated) | add) // 0),
      flagged_companies: (map(select(.flagged)) | length),
      companies: .
    }
' "$IN" > "$OUT"

echo "Flagged $(jq -r '.flagged_companies' "$OUT") of $(jq -r '.total_companies' "$OUT") companies"
