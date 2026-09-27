#!/usr/bin/env python3
"""Build data/rankings.json: the latest official FIFA men's ranking, a live
projection that applies every international result played since, recent
results and upcoming fixtures.

The ranking and most matches come from FIFA's public API (each ranked team's
match calendar). Competitions that feed doesn't carry — AFCON qualifiers and
a few invitational tournaments — are filled in from backup sources; see
sources.py.

Live points use FIFA's SUM formula (in use since 2018):
    P = P_before + I * (W - W_e)
    W_e = 1 / (10 ** (-(P_team - P_opp) / 600) + 1)
"""

import csv
import json
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import sources

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "rankings.json"
MANUAL = ROOT / "data" / "manual_results.csv"
WINDOWS = ROOT / "data" / "match_windows.json"

API = "https://api.fifa.com/api/v3"
RESULT_DAYS = 45    # show at least this many days of results
FIXTURE_DAYS = 21   # and this many days of upcoming fixtures

FINISHED, LIVE = 0, 3  # MatchStatus values

WORLD_CUP = "FIFA World Cup™"
CONFED_FINALS = {
    "UEFA EURO", "CAF Africa Cup of Nations", "AFC Asian Cup",
    "Concacaf Gold Cup", "Copa América", "OFC Nations Cup",
}
NATIONS_LEAGUES = {"UEFA Nations League", "Concacaf Nations League"}
LATE_STAGE = re.compile(r"quarter|semi|^final$|3rd|third|bronze", re.I)


def text(localized):
    return (localized or [{}])[0].get("Description", "").strip()


def load_windows():
    try:
        return [tuple(w) for w in json.loads(WINDOWS.read_text(encoding="utf-8"))["windows"]]
    except FileNotFoundError:
        return []


MATCH_WINDOWS = load_windows()


def in_match_window(day):
    """Whether a date falls in a FIFA international window. Dates beyond the
    last known window are given the benefit of the doubt."""
    if not day or not MATCH_WINDOWS or day > MATCH_WINDOWS[-1][1]:
        return True
    return any(start <= day <= end for start, end in MATCH_WINDOWS)


def importance(competition, stage, day=None):
    """Match importance (I) and whether it's a knockout tie of a final
    competition (where losers don't drop points)."""
    group = stage.startswith(("First Stage", "Group"))
    if competition == WORLD_CUP:
        return (60 if LATE_STAGE.search(stage) else 50), not group
    if competition in CONFED_FINALS:
        return (40 if LATE_STAGE.search(stage) else 35), not group
    if competition in NATIONS_LEAGUES:  # league phase 15, play-offs and finals 25
        return (25 if re.search(r"final|semi|quarter|play-?off|3rd|third", stage, re.I) else 15), False
    if "qualif" in competition.lower() or competition == "Continental Qualifier":
        return 25, False
    # friendlies and non-confederation tournaments: 10 in a window, 5 outside
    return (10 if in_match_window(day) else 5), False


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "rankpulse/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def load_official():
    rows = get(f"{API}/rankings/?gender=1&count=300")["Results"]
    teams = {}
    for r in rows:
        teams[r["IdTeam"]] = {
            "id": r["IdTeam"],
            "code": r["IdCountry"],
            "name": text(r["TeamName"]),
            "confed": r["ConfederationName"],
            "officialRank": r["Rank"],
            "officialPoints": r["DecimalTotalPoints"],
            "previousRank": r["PrevRank"],
        }
    meta = {"pubDate": rows[0]["PubDate"], "nextPubDate": rows[0].get("NextPubDate")}
    return teams, meta


def load_matches(teams, since, until):
    def team_calendar(team_id):
        url = (f"{API}/calendar/matches?language=en&count=500&idTeam={team_id}"
               f"&from={since}T00:00:00Z&to={until}T23:59:59Z")
        return get(url)["Results"]

    with ThreadPoolExecutor(12) as pool:
        calendars = list(pool.map(team_calendar, teams))

    matches = {}
    for m in (m for cal in calendars for m in cal):
        home, away = m["Home"], m["Away"]
        if not (home and away and home["IdTeam"] in teams and away["IdTeam"] in teams):
            continue  # TBD slots, or a guest side that isn't FIFA-ranked
        competition, stage = text(m["CompetitionName"]), text(m["StageName"])
        matches[m["IdMatch"]] = {
            "id": m["IdMatch"],
            "kickoff": m["Date"],
            "date": m["LocalDate"][:10],  # FIFA cuts rankings by local match date
            "home": home["IdTeam"],
            "away": away["IdTeam"],
            "homeScore": m["HomeTeamScore"],
            "awayScore": m["AwayTeamScore"],
            "homePens": m["HomeTeamPenaltyScore"],
            "awayPens": m["AwayTeamPenaltyScore"],
            "status": m["MatchStatus"],
            "competition": competition,
            "stage": stage,
            "city": text((m.get("Stadium") or {}).get("CityName")),
            "source": "FIFA",
        }
    return list(matches.values())


def add_backup_sources(matches, teams, since, until):
    """Fill in matches FIFA's feed lacks (see sources.py)."""
    by_code = {t["code"]: tid for tid, t in teams.items()}
    by_name = {t["name"]: tid for tid, t in teams.items()}
    wiki = sources.load_wikipedia(by_code, since, until)
    community = sources.load_community(by_name, since, until)
    merged, added = sources.merge(matches, wiki, community)
    for m in merged:
        m.setdefault("id", f"{m['source']}-{m['date']}-{m['home']}-{m['away']}")
    by_source = {}
    for m in merged[len(matches):]:
        by_source[m["source"]] = by_source.get(m["source"], 0) + 1
    print(f"backup sources added {added} matches: {by_source or 'none'}", file=sys.stderr)
    return merged


def apply_manual(matches, teams):
    """data/manual_results.csv corrects or adds results (e.g. forfeits
    awarded after the match). Team names must match FIFA's."""
    if not MANUAL.exists():
        return matches
    by_name = {t["name"]: t["id"] for t in teams.values()}
    by_key = {sources.pair_key(m): m for m in matches}
    for r in csv.DictReader(MANUAL.open(encoding="utf-8")):
        home, away = by_name.get(r["home_team"]), by_name.get(r["away_team"])
        if not (home and away):
            print(f"manual_results.csv: unknown team in {r}", file=sys.stderr)
            continue
        m = by_key.get((r["date"], frozenset((home, away))))
        if m is None:
            m = {"id": f"manual-{r['date']}-{home}-{away}", "kickoff": f"{r['date']}T12:00:00Z",
                 "date": r["date"], "home": home, "away": away, "homePens": None, "awayPens": None,
                 "competition": r["competition"] or "Friendlies", "stage": r.get("stage", ""), "city": ""}
            matches.append(m)
        if m["home"] != home:  # the correction lists the teams the other way round
            m["home"], m["away"] = home, away
        m.update(homeScore=int(r["home_score"]), awayScore=int(r["away_score"]),
                 status=FINISHED, source="Manual", note=r.get("note") or "Manual correction")
    return matches


def expected(p_team, p_opp):
    return 1 / (10 ** (-(p_team - p_opp) / 600) + 1)


def points_change(p_home, p_away, w_home, w_away, i, knockout):
    dh = i * (w_home - expected(p_home, p_away))
    da = i * (w_away - expected(p_away, p_home))
    if knockout:  # losers in a finals knockout tie keep their points
        dh, da = max(dh, 0), max(da, 0)
    return dh, da


def result_weights(m):
    """W for each side: win 1, draw 0.5, loss 0; shootout winner 0.75, loser 0.5."""
    hs, as_ = m["homeScore"], m["awayScore"]
    if hs != as_:
        w_home = 1.0 if hs > as_ else 0.0
        return w_home, 1.0 - w_home
    if m["homePens"] is not None:
        return (0.75, 0.5) if m["homePens"] > m["awayPens"] else (0.5, 0.75)
    return 0.5, 0.5


def replay(points, matches):
    """Apply finished matches in order to `points` (team id -> points), and
    annotate each match with I and each side's points change."""
    for m in matches:
        h, a = m["home"], m["away"]
        if m["status"] != FINISHED or h not in points or a not in points:
            continue
        w_home, w_away = result_weights(m)
        i, knockout = importance(m["competition"], m["stage"], m["date"])
        dh, da = points_change(points[h], points[a], w_home, w_away, i, knockout)
        points[h] += dh
        points[a] += da
        m.update(counted=True, importance=i, homeDelta=round(dh, 2), awayDelta=round(da, 2))
    return points


def project(teams, matches, since):
    """Live points: the official points plus every finished match since."""
    points = {tid: t["officialPoints"] for tid, t in teams.items()}
    return replay(points, [m for m in matches if m["date"] >= since])


def predict(fixtures, points):
    """Annotate each fixture with the points each side would gain or lose for
    every possible result, from both teams' current live points."""
    for m in fixtures:
        h, a = m["home"], m["away"]
        i, knockout = importance(m["competition"], m["stage"], m["date"])
        outcomes = {"win": (1.0, 0.0), "draw": (0.5, 0.5), "loss": (0.0, 1.0)}
        if knockout:  # a level knockout tie is settled on penalties
            del outcomes["draw"]
            outcomes |= {"pensWin": (0.75, 0.5), "pensLoss": (0.5, 0.75)}
        home, away = {}, {}
        for name, (wh, wa) in outcomes.items():
            dh, da = points_change(points[h], points[a], wh, wa, i, knockout)
            home[name] = round(dh, 2)
            # the away side's win is the home side's loss, and so on
            flip = {"win": "loss", "loss": "win", "draw": "draw", "pensWin": "pensLoss", "pensLoss": "pensWin"}[name]
            away[flip] = round(da, 2)
        m.update(importance=i, knockout=knockout,
                 expectedHome=round(expected(points[h], points[a]), 3),
                 prediction={"home": home, "away": away})


def main():
    teams, meta = load_official()
    since = meta["pubDate"][:10]  # a ranking published on day D includes matches up to D-1
    today = date.today()
    fetch_from = min(date.fromisoformat(since), today - timedelta(days=RESULT_DAYS))
    # One day of slack either side: FIFA filters by UTC kickoff, we filter by local date.
    until = today + timedelta(days=FIXTURE_DAYS)
    matches = load_matches(teams, fetch_from - timedelta(days=1), until)
    matches = add_backup_sources(matches, teams, fetch_from.isoformat(), until.isoformat())
    matches = apply_manual(matches, teams)
    matches = sorted((m for m in matches if m["date"] >= fetch_from.isoformat()), key=lambda m: m["kickoff"])
    points = project(teams, matches, since)
    predict([m for m in matches if m["status"] not in (FINISHED, LIVE)], points)

    live = sorted(teams.values(), key=lambda t: (-points[t["id"]], t["officialRank"]))
    for rank, t in enumerate(live, 1):
        t["liveRank"] = rank
        t["livePoints"] = round(points[t["id"]], 2)
        t["pointsChange"] = round(t["livePoints"] - t["officialPoints"], 2)
        t["rankChange"] = t["officialRank"] - rank

    code = {tid: t["code"] for tid, t in teams.items()}
    name = {tid: t["name"] for tid, t in teams.items()}
    for m in matches:
        m["homeName"], m["awayName"] = name[m["home"]], name[m["away"]]
        m["home"], m["away"] = code[m["home"]], code[m["away"]]
        m.pop("id")

    played = [m for m in matches if m["status"] in (FINISHED, LIVE)]
    fixtures = [m for m in matches if m["status"] not in (FINISHED, LIVE) and m["date"] >= today.isoformat()]
    out = {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "official": meta,
        "matchesSince": since,
        "teams": live,
        "results": list(reversed(played)),
        "fixtures": fixtures,
    }
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    counted = sum(1 for m in matches if m.get("counted"))
    print(f"{len(live)} teams · {counted} matches counted since {since} · "
          f"{len(played)} results · {len(fixtures)} fixtures", file=sys.stderr)


if __name__ == "__main__":
    main()
