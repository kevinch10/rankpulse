# RankPulse ⚽

**Live projection of the FIFA men's world ranking, plus daily results and fixtures for every ranking match in every confederation.** FIFA only publishes its ranking a few times a year. RankPulse takes the latest official ranking and applies every international result played since, using FIFA's published formula. That way you can see where teams stand *right now*.

It covers everything FIFA counts: friendlies, UEFA and Concacaf Nations League, World Cup and continental qualifiers, and continental and world finals (AFCON, Asian Cup, Gold Cup, EURO, Copa América, OFC Nations Cup, World Cup). It also covers regional tournaments like the ASEAN and Gulf Cups.

## How it works

```
GitHub Actions (every 2h)
  ├─ official ranking                 ← api.fifa.com/api/v3/rankings
  ├─ each ranked team's match calendar ← api.fifa.com/api/v3/calendar/matches?idTeam=…
  │    (211 teams, fetched in parallel, ~6s; + data/manual_results.csv corrections)
  └─ scripts/update.py → data/rankings.json → committed
GitHub Pages serves index.html, which reads data/rankings.json
```

### The formula (FIFA "SUM" method, since 2018)

```
P = P_before + I × (W − W_e)
W_e = 1 / (10^(−dr/600) + 1)        dr = team points − opponent points
```

| Match type | I |
|---|---|
| Friendly / non-confederation tournament | 10 |
| Nations League (UEFA / CONCACAF) | 15 |
| Qualifiers (World Cup, continental) | 25 |
| Continental finals (group / knockout) | 35 / 40 |
| World Cup finals (group / knockout) | 50 / 60 |

W = 1 win, 0.5 draw, 0 loss. Shootout winner 0.75, loser 0.5. Losers in a finals knockout tie keep their points. The stage (group, Round of 16, quarter-final…) comes straight from FIFA's data.

**Accuracy.** Replaying the 2026 World Cup from FIFA's June ranking reproduces FIFA's official July points for all 211 teams, to within 0.01. Replaying earlier periods back to September 2025 matches almost every team. The exceptions:
- **Forfeits and sanctions** that FIFA applies after a match (e.g. South Africa v Lesotho, Oct 2025). Add these to `data/manual_results.csv`.
- **Friendlies outside FIFA's international windows** count I=5 officially. FIFA's API doesn't mark them, so all friendlies use I=10 here.

## Correcting a result

To fix a result (e.g. a forfeit) or add a missing one, append a row to `data/manual_results.csv` using FIFA's team names:

```csv
date,home_team,away_team,home_score,away_score,competition,stage,note
2025-10-10,South Africa,Lesotho,0,3,FIFA World Cup™ Qualifiers,Round One,Forfeit awarded by FIFA
```

Pushing that file triggers a rebuild.

## Run locally

```bash
python3 scripts/update.py      # refresh data/rankings.json (stdlib only, no installs)
python3 -m http.server 8000    # open http://localhost:8000
```

## Deploy

1. Push to GitHub.
2. **Settings → Pages →** Source: *Deploy from a branch*, Branch: `main` / root.
3. **Actions** tab → *Update rankings* → *Run workflow* for the first refresh.

---

Unofficial. Not affiliated with or endorsed by FIFA.
