#!/usr/bin/env python3
"""Build data/rankings.json: the latest official FIFA men's ranking plus a
live projection that applies every international result played since.

Live points use FIFA's SUM formula (in use since 2018):
    P = P_before + I * (W - W_e)
    W_e = 1 / (10 ** (-(P_team - P_opp) / 600) + 1)
"""

import csv
import io
import json
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "data" / "rankings.json"
MANUAL = ROOT / "data" / "manual_results.csv"

FIFA_API = "https://api.fifa.com/api/v3/rankings/?gender=1&count=300"
RESULTS_CSV = "https://raw.githubusercontent.com/martj42/international_results/master/results.csv"
SHOOTOUTS_CSV = "https://raw.githubusercontent.com/martj42/international_results/master/shootouts.csv"

# Results dataset name -> FIFA name
NAME_MAP = {
    "Brunei": "Brunei Darussalam",
    "Cape Verde": "Cabo Verde",
    "China": "China PR",
    "Taiwan": "Chinese Taipei",
    "DR Congo": "Congo DR",
    "Czech Republic": "Czechia",
    "Ivory Coast": "Côte d'Ivoire",
    "North Korea": "DPR Korea",
    "Hong Kong": "Hong Kong, China",
    "Iran": "IR Iran",
    "South Korea": "Korea Republic",
    "Kyrgyzstan": "Kyrgyz Republic",
    "Saint Kitts and Nevis": "St Kitts and Nevis",
    "Saint Lucia": "St Lucia",
    "Saint Vincent and the Grenadines": "St Vincent and the Grenadines",
    "Gambia": "The Gambia",
    "Turkey": "Türkiye",
    "United States Virgin Islands": "US Virgin Islands",
    "United States": "USA",
}

WORLD_CUP = {"FIFA World Cup"}
CONFED_FINALS = {
    "UEFA Euro", "African Cup of Nations", "AFC Asian Cup",
    "Gold Cup", "Copa América", "Oceania Nations Cup",
}
NATIONS_LEAGUE = {"UEFA Nations League", "CONCACAF Nations League"}


def importance(tournament, knockout):
    """Match importance (I) per FIFA's table. The results feed has no stage
    info, so a penalty shootout is our only signal that a match was a
    knockout tie; everything else in a final tournament counts as group stage."""
    if tournament in WORLD_CUP:
        return 60 if knockout else 50
    if tournament in CONFED_FINALS:
        return 40 if knockout else 35
    if "qualification" in tournament:
        return 25
    if tournament in NATIONS_LEAGUE:
        return 15
    return 10  # friendlies and non-confederation tournaments


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "rankpulse/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8")


def load_official():
    rows = json.loads(fetch(FIFA_API))["Results"]
    teams = {}
    for r in rows:
        name = r["TeamName"][0]["Description"]
        teams[name] = {
            "code": r["IdCountry"],
            "name": name,
            "confed": r["ConfederationName"],
            "officialRank": r["Rank"],
            "officialPoints": r["DecimalTotalPoints"],
            "previousRank": r["PrevRank"],
        }
    meta = {
        "pubDate": rows[0]["PubDate"],
        "nextPubDate": rows[0].get("NextPubDate"),
    }
    return teams, meta


def load_results(since):
    shootouts = {}
    for r in csv.DictReader(io.StringIO(fetch(SHOOTOUTS_CSV))):
        if r["date"] >= since:
            shootouts[(r["date"], r["home_team"], r["away_team"])] = r["winner"]

    matches = {}
    sources = [fetch(RESULTS_CSV)]
    if MANUAL.exists():
        sources.append(MANUAL.read_text(encoding="utf-8"))
    for text in sources:
        for r in csv.DictReader(io.StringIO(text)):
            if r["date"] < since or r["home_score"] in ("", "NA"):
                continue
            key = (r["date"], r["home_team"], r["away_team"])
            if r.get("shootout_winner"):
                shootouts[key] = r["shootout_winner"]
            matches[key] = r  # manual rows override the feed
    return [dict(m, shootout=shootouts.get(k)) for k, m in sorted(matches.items())]


def expected(p_team, p_opp):
    return 1 / (10 ** (-(p_team - p_opp) / 600) + 1)


def project(teams, results):
    points = {n: t["officialPoints"] for n, t in teams.items()}
    applied = []
    for m in results:
        home = NAME_MAP.get(m["home_team"], m["home_team"])
        away = NAME_MAP.get(m["away_team"], m["away_team"])
        if home not in teams or away not in teams:
            continue  # non-FIFA sides (CONIFA, island games, ...)

        hs, as_ = int(m["home_score"]), int(m["away_score"])
        so = m["shootout"]
        so = NAME_MAP.get(so, so) if so else None
        knockout = so is not None
        if hs > as_:
            w_home = 1.0
        elif hs < as_:
            w_home = 0.0
        elif so:
            w_home = 0.75 if so == home else 0.5
        else:
            w_home = 0.5
        w_away = {1.0: 0.0, 0.0: 1.0, 0.75: 0.5, 0.5: 0.75 if so else 0.5}[w_home]

        i = importance(m["tournament"], knockout)
        ph, pa = points[home], points[away]
        dh = i * (w_home - expected(ph, pa))
        da = i * (w_away - expected(pa, ph))
        # Losers in a knockout tie of a final tournament keep their points.
        if knockout and i >= 40:
            dh, da = max(dh, 0), max(da, 0)
        points[home] += dh
        points[away] += da

        applied.append({
            "date": m["date"],
            "home": teams[home]["code"],
            "away": teams[away]["code"],
            "score": f"{hs}-{as_}" + (f" (pens: {teams[so]['code']})" if so in teams else ""),
            "tournament": m["tournament"],
            "importance": i,
            "homeDelta": round(dh, 2),
            "awayDelta": round(da, 2),
        })
    return points, applied


def main():
    teams, meta = load_official()
    # A ranking published on day D includes matches up to D-1.
    since = meta["pubDate"][:10]
    results = load_results(since)
    points, applied = project(teams, results)

    live = sorted(teams.values(), key=lambda t: (-points[t["name"]], t["officialRank"]))
    for rank, t in enumerate(live, 1):
        t["liveRank"] = rank
        t["livePoints"] = round(points[t["name"]], 2)
        t["pointsChange"] = round(t["livePoints"] - t["officialPoints"], 2)
        t["rankChange"] = t["officialRank"] - rank

    out = {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "official": meta,
        "matchesSince": since,
        "teams": live,
        "matches": list(reversed(applied)),
    }
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(live)} teams, {len(applied)} matches since {since}", file=sys.stderr)


if __name__ == "__main__":
    main()
