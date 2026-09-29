# World Football Rankings ⚽

*Unofficial fan project — not affiliated with, endorsed by or connected to FIFA.*

**Live projection of the FIFA men's world ranking, plus daily results and fixtures for every ranking match in every confederation.** FIFA only publishes its ranking a few times a year. World Football Rankings takes the latest official ranking and applies every international result played since, using FIFA's published formula. That way you can see where teams stand *right now*.

**Live site:** https://kevinch10.github.io/rankpulse/

It covers everything FIFA counts: friendlies, UEFA and Concacaf Nations League, World Cup and continental qualifiers, and continental and world finals (AFCON, Asian Cup, Gold Cup, EURO, Copa América, OFC Nations Cup, World Cup). It also covers regional tournaments like the ASEAN and Gulf Cups.

## How it works

```
GitHub Actions (scheduled)
  ├─ unit tests                          tests/test_update.py
  ├─ official ranking                    ← api.fifa.com/api/v3/rankings
  ├─ each ranked team's match calendar   ← api.fifa.com/api/v3/calendar/matches?idTeam=…
  ├─ backup sources for what FIFA's feed lacks (scripts/sources.py)
  │    • AFCON qualifiers                ← Wikipedia results (data/extra_sources.json)
  │    • invitational cups, stragglers   ← martj42/international_results
  ├─ manual corrections                  ← data/manual_results.csv
  ├─ scripts/update.py → data/rankings.json (live period + every scheduled fixture)
  └─ scripts/history.py → data/history.json (the year before, rebuilt daily)
```

The Results tab opens on the past week, with Past month / 3 months / year a tap away. History is replayed period by period from FIFA's official releases (`data/releases.json`, which picks up new releases automatically), so every match shows the points it was worth at the time. Fixtures cover everything FIFA has already scheduled, currently about six months ahead.

### Competitions covered

Everything that counts towards the ranking, in all six confederations: World Cup finals and qualifiers; EURO, Copa América, AFCON, Asian Cup, Gold Cup and OFC Nations Cup finals **and their qualifiers**; UEFA and Concacaf Nations League; friendlies; and FIFA-sanctioned regional/invitational tournaments (FIFA Arab Cup, FIFA Series, ASEAN, Gulf Cup, King's Cup, Baltic Cup…), which count as friendlies.

FIFA's own calendar API has no CAF qualifiers, so AFCON qualifying results are read from Wikipedia. When the next cycle starts, add its pages to `data/extra_sources.json`. A match found in several sources always uses FIFA's record, and results from backup sources are labelled "via Wikipedia" or "via community data" on the site.

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

**Friendlies outside international windows** count I=5 instead of 10. The window dates live in `data/match_windows.json`. Extend that file when FIFA confirms future windows.

### Accuracy testing

```bash
python3 -m unittest discover -s tests     # formula, weights, Wikipedia parser, merging
python3 scripts/validate.py --verbose     # replay every official release since Sept 2025
```

`validate.py` starts from each official release, replays every match up to the next one, and compares the result with FIFA's published points. It also runs weekly on GitHub Actions. Latest result:

| Period | Teams matching FIFA (±0.02) |
|---|---|
| Jun → Jul 2026 (World Cup) | **211 / 211** |
| Apr → Jun 2026 | 194 / 211 |
| Jan → Apr 2026 | 184 / 211 |
| Dec 2025 → Jan 2026 (AFCON) | 202 / 211 |
| Nov → Dec 2025 | 184 / 211 |
| Oct → Nov 2025 | 197 / 211 |
| Sep → Oct 2025 | 196 / 211 |

The remaining gaps come in matched pairs from individual matches FIFA changed after they were played: forfeits (e.g. South Africa v Lesotho, Equatorial Guinea v Malawi), sanctions (Malaysia), and one ranking-cutoff edge case. None are missing competitions. To reproduce one exactly, add it to `data/manual_results.csv`.

## Correcting a result

To fix a result (e.g. a forfeit) or add a missing one, append a row to `data/manual_results.csv` using FIFA's team names:

```csv
date,home_team,away_team,home_score,away_score,competition,stage,note
2026-09-24,Wales,Iceland,3,0,UEFA Nations League,League B,Example: forfeit awarded by FIFA
```

Pushing that file triggers a rebuild.

## Fantasy matches

Pair any two national teams, choose a multiplier (×5 to ×60, FIFA's match weights) and optionally make it a knockout. The app shows the points each team would gain or lose for every result, and where each would rank afterwards.

- **Free:** one pairing per day (its multiplier can be changed freely). The count is kept on the device or in the browser.
- **Premium (iOS, StoreKit 2):** unlimited fantasy matches and no ads anywhere (the ads SDK, consent and tracking prompts are skipped entirely). Products are `app.rankpulse.premium.monthly` ($1.99) and `app.rankpulse.premium.yearly` ($9.99), each with a 1-week free trial, in subscription group `21500001`. `ios/Premium.storekit` lets you test purchases locally: run from Xcode (▶), and no real money is charged. Before release, create the same products in App Store Connect.

## Favourites, notifications and predictions

- **Favourites:** star any team. On the web this is saved in your browser; in the iOS app, swipe left on a team or tap ★ on its page.
- **Notifications (iOS):** when a favourite's live points change, the app posts a notification with the match and the new rank. It checks whenever you open the app and in the background via iOS Background App Refresh (iOS decides the timing — usually within an hour or two of a new result).
- **Predictions:** every upcoming fixture shows the points each team would gain or lose for a win, draw or loss (and a penalty-shootout win/loss in knockout ties), computed from both teams' current live points with the same formula.

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

**Web app (no App Store needed):** open the site in Safari → Share → **Add to Home Screen**.

**Native iOS app** (SwiftUI, iOS 18+) lives in [`ios/`](ios):

- **Rankings / Results / Fixtures** tabs, favourites, calendar, period and competition filters.
- **Home-screen widget** (small and medium, plus lock-screen styles): favourites' live rank, points change and next match. It falls back to the top of the table. The app and widget share favourites through the App Group `group.app.rankpulse`.
- **Notifications** (on/off switches under the bell button): points and places changes, **rival watch** (who a favourite overtook or was overtaken by), match reminders an hour before kick-off with the points at stake, milestones (#1, top 10/20/50/100), a **weekly digest** every Monday at 9:00 (places, points, results and next match for each favourite; you can send a preview from settings), and official ranking release day. They run on-device using background refresh and scheduled local notifications, so no push server is needed.
- **Ads (free version):** a Google AdMob bottom banner, plus a 320×100 ad after every 12 rows in Results and Fixtures (every 30 in Rankings). Google's consent form (EU/UK) and Apple's App Tracking Transparency prompt run before any ad loads.

### Before publishing with real ads
The project uses Google's **test** ad IDs. Replace them with your own from [admob.google.com](https://admob.google.com):
1. `ios/RankPulse/Info.plist` → `GADApplicationIdentifier` (your AdMob app ID).
2. `ios/Shared/Config.swift` → `bannerAdUnitID` and `inlineAdUnitID` (your ad unit IDs).
3. In AdMob → Privacy & messaging, create the GDPR consent message and the IDFA explainer.
4. App Store Connect → App Privacy: declare the data used by the Google Mobile Ads SDK (identifiers, usage data, diagnostics) for advertising.

```bash
open ios/RankPulse.xcodeproj    # pick your iPhone and press Run
```

The project is generated from `ios/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`cd ios && xcodegen`). Publishing to the App Store needs an Apple Developer Program membership ($99/year).
