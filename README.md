# databerlin-bs-watch

Daily audit of [databerlin.net/jobs](https://databerlin.net/jobs/) that flags listings smelling like ghost jobs, CV harvesting, or headcount theatre.

## Rules

A company is flagged if any of the following holds:

- **stale** &mdash; at least one role is older than 90 days
- **duplicates** &mdash; the same title is posted on the same date more than once
- **multi-seniority** &mdash; the same normalised role title is cloned across two or more seniority levels (a common funnel-padding tactic)

## How it runs

`.github/workflows/refresh.yml` runs daily at 06:17 UTC. It:

1. `scripts/scrape.sh` &mdash; downloads the listings HTML and extracts job-card metadata to `data/jobs.json`
2. `scripts/analyze.sh` &mdash; groups by company and applies the rules into `data/flagged.json`
3. `scripts/build.sh` &mdash; copies the JSON into `public/`
4. Deploys `public/` to the `gh-pages` branch

Local run:

```bash
brew install ripgrep jq   # or apt
bash scripts/scrape.sh
bash scripts/analyze.sh
bash scripts/build.sh
open public/index.html
```

## Setup

1. Push to GitHub.
2. Repo settings &rarr; Pages &rarr; source = `gh-pages` branch, root.
3. Trigger the workflow once (`Actions` &rarr; `refresh` &rarr; `Run workflow`) so the `gh-pages` branch is created.
