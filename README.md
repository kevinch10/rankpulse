# World Football Rankings ⚽

*Unofficial fan project — not affiliated with, endorsed by or connected to FIFA.*

**Live projection of the FIFA men's world ranking, plus daily results and fixtures for every ranking match in every confederation.** FIFA only publishes its ranking a few times a year. World Football Rankings takes the latest official ranking and applies every international result played since, using FIFA's published formula. That way you can see where teams stand *right now*.

**Live site:** https://kevinch10.github.io/rankpulse/

It covers everything FIFA counts: friendlies, UEFA and Concacaf Nations League, World Cup and continental qualifiers, and continental and world finals (AFCON, Asian Cup, Gold Cup, EURO, Copa América, OFC Nations Cup, World Cup). It also covers regional tournaments like the ASEAN and Gulf Cups.

## How it works

```
GitHub Actions (scheduled)
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
- **Forfeits and sanctions** that FIFA applies after a match (e.g. the South Africa v Lesotho forfeit, applied in the October 2025 ranking). Add these to `data/manual_results.csv`.
- **Friendlies outside FIFA's international windows** count I=5 officially. FIFA's API doesn't mark them, so all friendlies use I=10 here.

## Favourites, notifications and predictions

- **Favourites:** star any team. On the web this is saved in your browser; in the iOS app, swipe left on a team or tap ★ on its page.
- **Notifications (iOS):** when a favourite's live points change, the app posts a notification with the match and the new rank. It checks whenever you open the app and in the background via iOS Background App Refresh (iOS decides the timing — usually within an hour or two of a new result).
- **Predictions:** every upcoming fixture shows the points each team would gain or lose for a win, draw or loss (and a penalty-shootout win/loss in knockout ties), computed from both teams' current live points with the same formula.

## Correcting a result

To fix a result (e.g. a forfeit) or add a missing one, append a row to `data/manual_results.csv` using FIFA's team names:

```csv
date,home_team,away_team,home_score,away_score,competition,stage,note
2026-09-24,Wales,Iceland,3,0,UEFA Nations League,League B,Example: forfeit awarded by FIFA
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

## iPhone

**Web app (no App Store needed):** open the site in Safari → Share → **Add to Home Screen**. It runs full-screen with its own icon and works offline.

**Native iOS app** (SwiftUI, iOS 18+) lives in [`ios/`](ios). It reads the same `data/rankings.json` the website publishes, caches it for offline use, and ships a bundled snapshot so it works on first launch.

```bash
open ios/RankPulse.xcodeproj    # then pick a simulator or your iPhone and press Run
```

- Set `Config.dataURL` in `ios/RankPulse/Config.swift` to your published `https://<user>.github.io/rankpulse/data/rankings.json`.
- The project is generated from `ios/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`cd ios && xcodegen`) if you change the file layout.
- To run on your own iPhone: Xcode → target → Signing & Capabilities → choose your Apple ID team (free).
- To publish on the App Store you need an Apple Developer Program membership ($99/year), then Product → Archive → Distribute.
