"""Backup result sources for matches FIFA's calendar API doesn't carry.

FIFA's per-team calendar covers almost every ranking match, but not all:
it has no CAF (AFCON) qualifiers at all, and it skips a few invitational
tournaments (King's Cup, Baltic Cup, ...). Two backups fill the gaps:

* Wikipedia "Football box" results on the pages listed in
  data/extra_sources.json — fast (usually same day), used for whole
  competitions FIFA's feed lacks.
* The community dataset martj42/international_results — complete but can lag
  by weeks, used to backfill anything else that's still missing.

FIFA's own data always wins when a match appears in more than one source.
"""

import csv
import io
import json
import re
import sys
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXTRA_SOURCES = ROOT / "data" / "extra_sources.json"

USER_AGENT = "WorldFootballRankings/1.0 (https://github.com/kevinch10/rankpulse; hourly bot)"
WIKI_API = "https://en.wikipedia.org/w/api.php"
COMMUNITY_RESULTS = "https://raw.githubusercontent.com/martj42/international_results/master/results.csv"
COMMUNITY_SHOOTOUTS = "https://raw.githubusercontent.com/martj42/international_results/master/shootouts.csv"

# Wikipedia codes that differ from FIFA's
WIKI_CODE_ALIASES = {"DRC": "COD"}

# Community dataset team names that differ from FIFA's
COMMUNITY_NAMES = {
    "Brunei": "Brunei Darussalam", "Cape Verde": "Cabo Verde", "China": "China PR",
    "Taiwan": "Chinese Taipei", "DR Congo": "Congo DR", "Czech Republic": "Czechia",
    "Ivory Coast": "Côte d'Ivoire", "North Korea": "DPR Korea", "Hong Kong": "Hong Kong, China",
    "Iran": "IR Iran", "South Korea": "Korea Republic", "Kyrgyzstan": "Kyrgyz Republic",
    "Saint Kitts and Nevis": "St Kitts and Nevis", "Saint Lucia": "St Lucia",
    "Saint Vincent and the Grenadines": "St Vincent and the Grenadines", "Gambia": "The Gambia",
    "Turkey": "Türkiye", "United States Virgin Islands": "US Virgin Islands", "United States": "USA",
}

# Community tournament names -> FIFA's, so importance() treats them the same
COMMUNITY_COMPETITIONS = {
    "Friendly": "Friendlies",
    "FIFA World Cup": "FIFA World Cup™",
    "FIFA World Cup qualification": "FIFA World Cup™ Qualifiers",
    "African Cup of Nations": "CAF Africa Cup of Nations",
    "African Cup of Nations qualification": "CAF Africa Cup of Nations Qualifiers",
    "UEFA Euro": "UEFA EURO",
    "UEFA Euro qualification": "UEFA EURO Qualifiers",
    "Gold Cup": "Concacaf Gold Cup",
    "CONCACAF Nations League": "Concacaf Nations League",
    "Oceania Nations Cup": "OFC Nations Cup",
}

FINISHED = 0
SCHEDULED = 1


def _get(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8")


# ---------- Wikipedia ----------

FOOTBALL_BOX_START = re.compile(r"\{\{\s*Football box(?:\s+collapsible)?\s*[|\n]", re.I)
FIELD = re.compile(r"^[ \t]*\|[ \t]*(\w+)[ \t]*=[ \t]*(.*?)[ \t]*$", re.M)  # empty values stay empty
TEAM = re.compile(r"\{\{\s*fb(?:-rt)?\s*\|\s*([A-Z]{3})", re.I)
START_DATE = re.compile(r"\{\{\s*Start date\s*\|\s*(\d{4})\s*\|\s*(\d{1,2})\s*\|\s*(\d{1,2})", re.I)
UTZ = re.compile(r"\{\{\s*UTZ\s*\|\s*(\d{1,2}):(\d{2})\s*\|\s*([+-]?\d+(?:\.\d+)?)", re.I)
SCORE = re.compile(r"(\d+)\s*[–\-−]\s*(\d+)")


def football_box_bodies(wikitext):
    """The inside of every {{Football box ...}}, found by counting braces so
    nested templates and a closing '}}' on the last field's line both work."""
    for start in FOOTBALL_BOX_START.finditer(wikitext):
        depth, i = 0, start.start()
        while i < len(wikitext) - 1:
            pair = wikitext[i:i + 2]
            if pair == "{{":
                depth += 1; i += 2; continue
            if pair == "}}":
                depth -= 1; i += 2
                if depth == 0:
                    break
                continue
            i += 1
        # put each top-level "|field =" on its own line for FIELD
        yield "\n" + wikitext[start.end() - 1:i - 2].replace("}}|", "}}\n|")


def parse_football_boxes(wikitext):
    """Yield dicts for each {{Football box}}: date, home, away (FIFA codes),
    scores (None if unplayed), penalties, and UTC kickoff when known."""
    for body in football_box_bodies(wikitext):
        f = dict(FIELD.findall(body))
        d, t1, t2 = START_DATE.search(f.get("date", "")), TEAM.search(f.get("team1", "")), TEAM.search(f.get("team2", ""))
        if not (d and t1 and t2):
            continue
        day = date(int(d[1]), int(d[2]), int(d[3]))
        kickoff = datetime(day.year, day.month, day.day, 12, tzinfo=timezone.utc)
        if (t := UTZ.search(f.get("time", ""))):
            offset = timedelta(hours=float(t[3]))
            kickoff = datetime(day.year, day.month, day.day, int(t[1]), int(t[2]), tzinfo=timezone.utc) - offset
        # Strip links/templates around the score, e.g. [[...|2–1]] or {{nowrap|2–1}}
        raw_score = re.sub(r"\[\[[^\]|]*\|([^\]]*)\]\]", r"\1", f.get("score", ""))
        s = SCORE.search(raw_score)
        pens = SCORE.search(f.get("penaltyscore", "") or f.get("penalties", ""))
        code = lambda c: WIKI_CODE_ALIASES.get(c.upper(), c.upper())
        yield {
            "date": day.isoformat(),
            "kickoff": kickoff.isoformat().replace("+00:00", "Z"),
            "home": code(t1[1]),
            "away": code(t2[1]),
            "homeScore": int(s[1]) if s else None,
            "awayScore": int(s[2]) if s else None,
            "homePens": int(pens[1]) if s and pens else None,
            "awayPens": int(pens[2]) if s and pens else None,
            "city": re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]", r"\1", f.get("location", "") or f.get("stadium", "")).split(",")[-1].strip()[:40],
        }


def fetch_wikitext(titles):
    """Fetch many pages in one API call (Wikipedia rate-limits per request)."""
    texts = {}
    for i in range(0, len(titles), 50):
        params = {"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main",
                  "titles": "|".join(titles[i:i + 50]), "format": "json", "formatversion": 2,
                  "redirects": 1, "maxlag": 5}
        data = json.loads(_get(f"{WIKI_API}?{urllib.parse.urlencode(params)}"))
        for page in data["query"]["pages"]:
            if "revisions" in page:
                texts[page["title"]] = page["revisions"][0]["slots"]["main"]["content"]
            else:
                print(f"wikipedia: missing page {page.get('title')}", file=sys.stderr)
    return texts


def load_wikipedia(teams_by_code, since, until):
    if not EXTRA_SOURCES.exists():
        return []
    config = json.loads(EXTRA_SOURCES.read_text(encoding="utf-8"))["wikipedia"]
    titles = [p for c in config for p in c["pages"]]
    try:
        texts = fetch_wikitext(titles)
    except Exception as e:  # a Wikipedia outage shouldn't stop the update
        print(f"wikipedia: fetch failed ({e})", file=sys.stderr)
        return []
    out = []
    for c in config:
        for page in c["pages"]:
            for m in parse_football_boxes(texts.get(page, "")):
                if not (since <= m["date"] <= until):
                    continue
                if m["home"] not in teams_by_code or m["away"] not in teams_by_code:
                    print(f"wikipedia: unknown team code in {page}: {m['home']} v {m['away']}", file=sys.stderr)
                    continue
                out.append(m | {
                    "home": teams_by_code[m["home"]], "away": teams_by_code[m["away"]],
                    "status": FINISHED if m["homeScore"] is not None else SCHEDULED,
                    "competition": c["competition"], "stage": c.get("stage", ""),
                    "source": "Wikipedia",
                })
    return out


# ---------- community dataset ----------

def load_community(teams_by_name, since, until):
    try:
        results, shootouts = _get(COMMUNITY_RESULTS), _get(COMMUNITY_SHOOTOUTS)
    except Exception as e:
        print(f"community: fetch failed ({e})", file=sys.stderr)
        return []
    so = {(r["date"], r["home_team"], r["away_team"]): r["winner"] for r in csv.DictReader(io.StringIO(shootouts))}
    out = []
    for r in csv.DictReader(io.StringIO(results)):
        if not (since <= r["date"] <= until) or r["home_score"] in ("", "NA"):
            continue
        h = teams_by_name.get(COMMUNITY_NAMES.get(r["home_team"], r["home_team"]))
        a = teams_by_name.get(COMMUNITY_NAMES.get(r["away_team"], r["away_team"]))
        if not (h and a):
            continue
        winner = so.get((r["date"], r["home_team"], r["away_team"]))
        hs, as_ = int(r["home_score"]), int(r["away_score"])
        out.append({
            "date": r["date"], "kickoff": f"{r['date']}T12:00:00Z", "home": h, "away": a,
            "homeScore": hs, "awayScore": as_,
            # the dataset records only the shootout winner; 1–0 keeps W=0.75/0.5 right
            "homePens": (1 if winner == r["home_team"] else 0) if winner else None,
            "awayPens": (1 if winner == r["away_team"] else 0) if winner else None,
            "status": FINISHED, "stage": "", "city": r["city"],
            "competition": COMMUNITY_COMPETITIONS.get(r["tournament"], r["tournament"]),
            "source": "Community dataset",
        })
    return out


# ---------- merging ----------

def pair_key(m, day_offset=0):
    d = (date.fromisoformat(m["date"]) + timedelta(days=day_offset)).isoformat()
    return d, frozenset((m["home"], m["away"]))


def merge(primary, *backups):
    """Add backup matches that aren't already present. Two records are the
    same match if they involve the same teams within a day of each other
    (sources disagree on local vs UTC dates)."""
    merged = list(primary)
    seen = {pair_key(m) for m in merged}
    added = 0
    for source in backups:
        for m in source:
            if any(pair_key(m, o) in seen for o in (-1, 0, 1)):
                continue
            merged.append(m)
            seen.add(pair_key(m))
            added += 1
    return merged, added
