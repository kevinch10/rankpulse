#!/usr/bin/env python3
"""Accuracy check: replay past official FIFA rankings with our data and formula.

For each pair of consecutive official releases, start from the earlier
release's points, apply every match we have between the two release dates
(using the same sources, importance rules and formula as update.py), and
compare the result with the later release's official points.

    python3 scripts/validate.py            # all known releases
    python3 scripts/validate.py --verbose  # also list each mismatched team

Teams more than 0.02 points off usually point to a forfeit or sanction
applied after the match (add it to data/manual_results.csv), a friendly
played outside an international window (FIFA weighs those I=5, we use 10),
or a match missing from every source.
"""

import argparse
import json
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta

import update

# (dateId, publication date) of official releases, oldest first
RELEASES = [tuple(r) for r in json.loads((update.ROOT / "data" / "releases.json").read_text(encoding="utf-8"))["releases"]]
TOLERANCE = 0.02


def release_points(date_id):
    url = f"https://inside.fifa.com/api/ranking-overview?locale=en&dateId={date_id}"
    rows = update.get(url)["rankings"]
    return {r["rankingItem"]["idTeam"]: r["rankingItem"]["totalPoints"] for r in rows}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    teams, _ = update.load_official()
    with ThreadPoolExecutor(8) as pool:
        snapshots = list(pool.map(release_points, [d for d, _ in RELEASES]))

    first, last = RELEASES[0][1], RELEASES[-1][1]
    matches = update.load_matches(teams, date.fromisoformat(first) - timedelta(days=1), date.fromisoformat(last))
    matches = update.add_backup_sources(matches, teams, first, last)
    matches = update.apply_manual(matches, teams)
    matches = update.normalize_competitions(matches, teams, update.load_catalog())
    matches = [m for m in matches if m["date"] >= first]
    matches.sort(key=lambda m: m["kickoff"])

    total_bad = 0
    for k in range(1, len(RELEASES)):
        start, end = RELEASES[k - 1][1], RELEASES[k][1]
        points = {tid: snapshots[k - 1][tid] for tid in teams if tid in snapshots[k - 1]}
        period = [m for m in matches if m["status"] == update.FINISHED and start <= m["date"] < end
                  and m["home"] in points and m["away"] in points]
        update.replay(points, period)

        official = snapshots[k]
        errors = sorted(((abs(points[t] - official[t]), teams[t]["name"], points[t], official[t])
                         for t in points if t in official), reverse=True)
        bad = [e for e in errors if e[0] > TOLERANCE]
        total_bad += len(bad)
        sources = Counter(m.get("source", "FIFA") for m in period)
        exact = len(errors) - len(bad)
        print(f"{start} → {end}: {len(period):3} matches {dict(sources)}  "
              f"{exact}/{len(errors)} teams exact (±{TOLERANCE}), worst {errors[0][0]:.2f} ({errors[0][1]})")
        if args.verbose:
            for err, name, ours, theirs in bad:
                print(f"      {name:28} ours {ours:8.2f}  official {theirs:8.2f}  diff {ours - theirs:+.2f}")

    print(f"\n{total_bad} team-period mismatches in total")
    return 0


if __name__ == "__main__":
    sys.exit(main())
