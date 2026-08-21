#!/usr/bin/env python3
"""Extract job-card metadata from a databerlin.net/jobs HTML dump into jobs.json.

The listing page uses a "stretched link" card: the metadata lives as data-*
attributes on a wrapping <div class="job-card">, while the canonical job URL is
on a nested <a href="/jobs/...">. Attributes are parsed individually rather than
with one fixed-order regex so that reordering or added attributes upstream does
not silently break extraction.
"""

import html
import json
import re
import sys
from datetime import datetime, timezone

CARD_TAG = re.compile(r'<div\b[^>]*\bclass="job-card\b[^"]*"[^>]*>', re.IGNORECASE)
ATTR = re.compile(r'([A-Za-z][\w:.-]*)(?:="([^"]*)")?')
# Category and company index pages also live under /jobs/, so exclude them.
JOB_HREF = re.compile(r'href="(/jobs/(?!category/|company/)[^"#?]+)"')

BASE = "https://databerlin.net"


def clean(value):
    text = value or ""
    # A handful of upstream titles are double-encoded ("&amp;amp;"), so decode
    # repeatedly until the result stops changing.
    for _ in range(3):
        decoded = html.unescape(text)
        if decoded == text:
            break
        text = decoded
    return re.sub(r"\s+", " ", text).strip()


def parse_cards(raw):
    """Yield one dict per job card in document order, including repeats."""
    tags = list(CARD_TAG.finditer(raw))
    for i, tag in enumerate(tags):
        attrs = {}
        for match in ATTR.finditer(tag.group(0)[len("<div") : -1]):
            attrs[match.group(1).lower()] = match.group(2)

        end = tags[i + 1].start() if i + 1 < len(tags) else len(raw)
        href = JOB_HREF.search(raw, tag.end(), end)

        yield {
            "url": BASE + href.group(1) if href else None,
            "category": clean(attrs.get("data-category")),
            "seniority": clean(attrs.get("data-seniority")),
            "company_slug": clean(attrs.get("data-company")),
            "company": clean(attrs.get("data-company-name")),
            "timestamp": clean(attrs.get("data-date")),
            "title": clean(attrs.get("data-title")),
        }


def dedupe(cards):
    """Collapse cards that share a job URL.

    The listing renders some jobs several times with data-date timestamps that
    differ by minutes within the same day. Treating those as separate postings
    inflates job counts and makes every job look like a same-day duplicate, so
    they are merged here, keeping the earliest timestamp.
    """
    jobs = {}
    for card in cards:
        job = jobs.get(card["url"])
        if job is None:
            job = dict(card)
            job["postings"] = 0
            jobs[card["url"]] = job
        job["postings"] += 1
        if card["timestamp"] and (
            not job["timestamp"] or card["timestamp"] < job["timestamp"]
        ):
            job["timestamp"] = card["timestamp"]
    return list(jobs.values())


def main(raw_path, out_path, min_jobs):
    raw = open(raw_path, encoding="utf-8", errors="replace").read()

    cards = list(parse_cards(raw))
    if not cards:
        sys.exit(
            f"ERROR: no job cards found in {raw_path} "
            "(expected <div class=\"job-card\" data-*>); layout may have changed"
        )

    linked = [c for c in cards if c["url"]]
    if len(linked) < len(cards) * 0.8:
        sys.exit(
            f"ERROR: {len(cards) - len(linked)} of {len(cards)} job cards had no "
            "/jobs/ link; layout may have changed"
        )

    jobs = dedupe(linked)
    if len(jobs) < min_jobs:
        sys.exit(
            f"ERROR: only {len(jobs)} unique jobs extracted (minimum {min_jobs}); "
            "layout may have changed"
        )

    for job in jobs:
        job["date"] = job.pop("timestamp")[:10]

    undated = sum(1 for job in jobs if not job["date"])
    payload = {
        "fetched": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "cards_seen": len(cards),
        "count": len(jobs),
        "undated": undated,
        "jobs": jobs,
    }

    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)
        fh.write("\n")

    print(
        f"Extracted {len(jobs)} unique jobs from {len(cards)} cards "
        f"({undated} undated) to {out_path}"
    )


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]))
