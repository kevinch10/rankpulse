# RankPulse ⚽

**Live projection of the FIFA men's world ranking.** FIFA only publishes its ranking a few times a year. RankPulse takes the latest official ranking and applies every international result played since, using FIFA's published formula. That way you can see where teams stand *right now*.

## How it works

```
GitHub Actions (every 3h)
  ├─ official ranking  ← api.fifa.com
  ├─ match results     ← martj42/international_results (+ data/manual_results.csv)
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

W = 1 win, 0.5 draw, 0 loss. Shootout winner 0.75, loser 0.5. Losers in a finals knockout tie keep their points.

**Known approximations.** The results feed doesn't record the tournament stage. So knockout ties are detected only when they go to penalties, and Nations League finals count as group games. All friendlies use I=10 (FIFA gives I=5 to friendlies outside international windows).

## Adding results faster

The results feed is community-maintained and can lag by days or weeks. To add a match right away, append it to `data/manual_results.csv`, using the dataset's team names (e.g. `United States`, `South Korea`):

```csv
date,home_team,away_team,home_score,away_score,tournament,shootout_winner
2026-09-05,Spain,Portugal,2,1,UEFA Nations League,
```

Pushing that file triggers a rebuild. Manual rows override feed rows for the same date and teams.

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
