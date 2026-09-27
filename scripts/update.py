#!/usr/bin/env python3
"""Build data/rankings.json: the latest official FIFA men's ranking, a live
projection that applies every international result played since, recent
results and upcoming fixtures.

All data comes from FIFA's public API: the ranking, plus each ranked team's
match calendar (friendlies, Nations Leagues, qualifiers, continental and
world finals, in every confederation).

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

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "rankings.json"
MANUAL = ROOT / "data" / "manual_results.csv"

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


def importance(competition, stage):
    """Match importance (I) and whether it's a knockout tie of a final
    competition (where losers don't drop points). Friendlies are all I=10:
    FIFA gives I=5 to friendlies outside international windows, but its API
    doesn't say which those are."""
    group = stage.startswith(("First Stage", "Group"))
    if competition == WORLD_CUP:
        return (60 if LATE_STAGE.search(stage) else 50), not group
    if competition in CONFED_FINALS:
        return (40 if LATE_STAGE.search(stage) else 35), not group
    if competition in NATIONS_LEAGUES:
        return (15 if stage.startswith("League") else 25), False
    if "Qualif" in competition or competition == "Continental Qualifier":
        return 25, False
    return 10, False


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
        }
    apply_manual(matches, teams)
    return sorted(matches.values(), key=lambda m: m["kickoff"])


def apply_manual(matches, teams):
    """data/manual_results.csv corrects or adds results (e.g. forfeits
    awarded after the match). Team names must match FIFA's."""
    if not MANUAL.exists():
        return
    by_name = {t["name"]: t["id"] for t in teams.values()}
    by_key = {(m["date"], m["home"], m["away"]): m for m in matches.values()}
    for r in csv.DictReader(MANUAL.open(encoding="utf-8")):
        home, away = by_name.get(r["home_team"]), by_name.get(r["away_team"])
        if not (home and away):
            print(f"manual_results.csv: unknown team in {r}", file=sys.stderr)
            continue
        m = by_key.get((r["date"], home, away))
        if m is None:
            m = matches[f"manual-{r['date']}-{home}-{away}"] = {
                "id": f"manual-{r['date']}-{home}-{away}", "kickoff": f"{r['date']}T12:00:00Z",
                "date": r["date"], "home": home, "away": away, "homePens": None, "awayPens": None,
                "competition": r["competition"] or "Friendlies", "stage": r.get("stage", ""), "city": "",
            }
        m.update(homeScore=int(r["home_score"]), awayScore=int(r["away_score"]),
                 status=FINISHED, note=r.get("note") or "Manual correction")


def expected(p_team, p_opp):
    return 1 / (10 ** (-(p_team - p_opp) / 600) + 1)


def points_change(p_home, p_away, w_home, w_away, i, knockout):
    dh = i * (w_home - expected(p_home, p_away))
    da = i * (w_away - expected(p_away, p_home))
    if knockout:  # losers in a finals knockout tie keep their points
        dh, da = max(dh, 0), max(da, 0)
    return dh, da


def project(teams, matches, since):
    """Apply finished matches on or after `since` to the official points.
    Annotates each match in place with I and each side's points change."""
    points = {tid: t["officialPoints"] for tid, t in teams.items()}
    for m in matches:
        if m["status"] != FINISHED or m["date"] < since:
            continue
        h, a = m["home"], m["away"]
        hs, as_ = m["homeScore"], m["awayScore"]
        if hs != as_:
            w_home = 1.0 if hs > as_ else 0.0
            w_away = 1.0 - w_home
        elif m["homePens"] is not None:
            w_home, w_away = (0.75, 0.5) if m["homePens"] > m["awayPens"] else (0.5, 0.75)
        else:
            w_home = w_away = 0.5

        i, knockout = importance(m["competition"], m["stage"])
        dh, da = points_change(points[h], points[a], w_home, w_away, i, knockout)
        points[h] += dh
        points[a] += da
        m.update(counted=True, importance=i, homeDelta=round(dh, 2), awayDelta=round(da, 2))
    return points


def predict(fixtures, points):
    """Annotate each fixture with the points each side would gain or lose for
    every possible result, from both teams' current live points."""
    for m in fixtures:
        h, a = m["home"], m["away"]
        i, knockout = importance(m["competition"], m["stage"])
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
    matches = load_matches(teams, fetch_from - timedelta(days=1), today + timedelta(days=FIXTURE_DAYS))
    matches = [m for m in matches if m["date"] >= fetch_from.isoformat()]
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
