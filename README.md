# databerlin-bs-watch

Daily audit of [databerlin.net/jobs](https://databerlin.net/jobs/) that flags listings smelling like ghost jobs, CV harvesting, or headcount theatre.

## Rules

A company is flagged if any of the following holds:

- **stale** &mdash; at least one role is older than 90 days
- **duplicates** &mdash; the same title is posted on the same date as two or more separate listings
- **multi-seniority** &mdash; the same normalised role title is cloned across two or more seniority levels (a common funnel-padding tactic)

Listings are deduplicated by job URL before the rules run: the source page renders some
jobs several times with `data-date` timestamps minutes apart, which would otherwise inflate
job counts and make every repeated job look like a same-day duplicate. Title normalisation
strips diversity boilerplate (`(m/f/d)`, `all genders`), seniority modifiers and word order,
but keeps role nouns such as *manager* or *head*. Listings with no posting date cannot be
aged, so they are counted and shown separately instead of silently escaping the stale rule.

## How it runs

`.github/workflows/refresh.yml` runs daily at 06:17 UTC. It:

1. `scripts/scrape.sh` &mdash; downloads the listings HTML and runs `scripts/extract.py`, which
   parses each `<div class="job-card">`, decodes HTML entities and deduplicates by job URL
   into `data/jobs.json`. It exits non-zero with a specific message if the card markup no
   longer matches, so an upstream layout change fails loudly instead of producing no data.
2. `scripts/analyze.sh` &mdash; groups by company and applies the rules into `data/flagged.json`
3. `scripts/build.sh` &mdash; copies the JSON into `public/`
4. Deploys `public/` to the `gh-pages` branch

Local run:

```bash
brew install jq   # or apt; python3 is also required
bash scripts/scrape.sh
bash scripts/analyze.sh
bash scripts/build.sh
open public/index.html
```

## Setup

1. Push to GitHub.
2. Repo settings &rarr; Pages &rarr; source = `gh-pages` branch, root.
3. Trigger the workflow once (`Actions` &rarr; `refresh` &rarr; `Run workflow`) so the `gh-pages` branch is created.
