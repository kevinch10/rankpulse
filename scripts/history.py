#!/usr/bin/env python3
"""Build data/history.json: a year of results with the points each
match was worth, plus every team's official rank at each release.

Each period between two official releases is replayed from the earlier
release's official points, so a match's points change is the one the formula
gave at the time (see validate.py for how closely that tracks FIFA).
The period after the latest release lives in rankings.json (the live
projection), so history stops at the latest release.

    python3 scripts/history.py           # rebuild if older than a day or a release is new
    python3 scripts/history.py --force   # rebuild now
"""

import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone

import update

OUT = update.ROOT / "data" / "history.json"
RELEASES = update.ROOT / "data" / "releases.json"
YEARS = 1
MAX_AGE = timedelta(hours=20)


def load_releases():
    return [tuple(r) for r in json.loads(RELEASES.read_text(encoding="utf-8"))["releases"]]


def release_table(date_id):
    url = f"https://inside.fifa.com/api/ranking-overview?locale=en&dateId={date_id}"
    return {r["rankingItem"]["idTeam"]: (r["rankingItem"]["rank"], r["rankingItem"]["totalPoints"])
            for r in update.get(url)["rankings"]}


def up_to_date(releases):
    try:
        old = json.loads(OUT.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return False
    fresh = datetime.now(timezone.utc) - datetime.fromisoformat(old["generatedAt"]) < MAX_AGE
    return fresh and old.get("releases", [{}])[-1].get("date") == releases[-1][1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    cutoff = (date.today() - timedelta(days=365 * YEARS)).isoformat()
    releases = load_releases()
    # start from the last release on or before the cutoff
    first = max((i for i, r in enumerate(releases) if r[1] <= cutoff), default=0)
    releases = releases[first:]
    if not args.force and up_to_date(releases):
        print("history.json is up to date", file=sys.stderr)
        return

    teams, _ = update.load_official()
    with ThreadPoolExecutor(8) as pool:
        tables = list(pool.map(release_table, [r[0] for r in releases]))

    start, end = releases[0][1], releases[-1][1]
    matches = update.load_matches(teams, date.fromisoformat(start) - timedelta(days=1), date.fromisoformat(end))
    matches = update.add_backup_sources(matches, teams, start, end)
    matches = update.apply_manual(matches, teams)
    matches = update.normalize_competitions(matches, teams, update.load_catalog())
    matches = sorted((m for m in matches if start <= m["date"] < end and m["status"] == update.FINISHED),
                     key=lambda m: m["kickoff"])

    for k in range(len(releases) - 1):
        points = {tid: tables[k][tid][1] for tid in teams if tid in tables[k]}
        lo, hi = releases[k][1], releases[k + 1][1]
        update.replay(points, [m for m in matches if lo <= m["date"] < hi])

    code = {tid: t["code"] for tid, t in teams.items()}
    name = {tid: t["name"] for tid, t in teams.items()}
    results = []
    for m in reversed(matches):
        if m["date"] < cutoff:
            continue
        m = {k: v for k, v in m.items() if k not in ("id",)}
        m["homeName"], m["awayName"] = name[m["home"]], name[m["away"]]
        m["home"], m["away"] = code[m["home"]], code[m["away"]]
        results.append(m)

    ranks = {code[tid]: [[r[1], *tables[k][tid]] for k, r in enumerate(releases) if tid in tables[k]]
             for tid in teams}
    out = {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "from": cutoff,
        "to": end,
        "releases": [{"id": r[0], "date": r[1]} for r in releases],
        "results": results,
        "ranks": ranks,  # code -> [[release date, official rank, official points], ...]
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    kb = OUT.stat().st_size // 1024
    print(f"history: {len(results)} results {cutoff} → {end}, {len(releases)} releases, {kb} KB", file=sys.stderr)


if __name__ == "__main__":
    main()
