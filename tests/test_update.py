"""Unit tests for the ranking engine and backup sources (no network).

    python3 -m unittest discover -s tests
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import sources  # noqa: E402
import update  # noqa: E402


class FormulaTests(unittest.TestCase):
    def test_expected_result(self):
        self.assertAlmostEqual(update.expected(1500, 1500), 0.5)
        self.assertAlmostEqual(update.expected(1800, 1500) + update.expected(1500, 1800), 1.0)
        # 600 points apart ≈ 10:1 expectation
        self.assertAlmostEqual(update.expected(2100, 1500), 10 / 11, places=6)

    def test_points_are_zero_sum_outside_knockouts(self):
        for w in [(1, 0), (0.5, 0.5), (0, 1)]:
            dh, da = update.points_change(1800, 1600, *w, 25, False)
            self.assertAlmostEqual(dh + da, 0, places=9)

    def test_known_value(self):
        # Spain (2002.34) v Croatia (1727.14), Nations League league phase (I=15)
        win, _ = update.points_change(2002.34, 1727.14, 1, 0, 15, False)
        draw, _ = update.points_change(2002.34, 1727.14, 0.5, 0.5, 15, False)
        loss, _ = update.points_change(2002.34, 1727.14, 0, 1, 15, False)
        self.assertEqual((round(win, 2), round(draw, 2), round(loss, 2)), (3.87, -3.63, -11.13))

    def test_knockout_losers_keep_points(self):
        dh, da = update.points_change(1500, 1800, 0, 1, 60, True)
        self.assertEqual(dh, 0)
        self.assertGreater(da, 0)

    def test_result_weights(self):
        m = {"homeScore": 2, "awayScore": 1, "homePens": None, "awayPens": None}
        self.assertEqual(update.result_weights(m), (1.0, 0.0))
        m |= {"homeScore": 1, "awayScore": 1}
        self.assertEqual(update.result_weights(m), (0.5, 0.5))
        m |= {"homePens": 3, "awayPens": 4}
        self.assertEqual(update.result_weights(m), (0.5, 0.75))


class ImportanceTests(unittest.TestCase):
    IN_WINDOW = "2026-09-25"
    OUTSIDE = "2026-08-15"

    def check(self, competition, stage, expected, day=IN_WINDOW):
        self.assertEqual(update.importance(competition, stage, day), expected, f"{competition} / {stage} / {day}")

    def test_competition_table(self):
        self.check("FIFA World Cup™", "First Stage", (50, False))
        self.check("FIFA World Cup™", "Round of 32", (50, True))
        self.check("FIFA World Cup™", "Round of 16", (50, True))
        self.check("FIFA World Cup™", "Quarter-final", (60, True))
        self.check("FIFA World Cup™", "Final", (60, True))
        self.check("FIFA World Cup™", "Bronze final", (60, True))
        self.check("CAF Africa Cup of Nations", "Group Stage", (35, False))
        self.check("CAF Africa Cup of Nations", "8th Finals", (35, True))
        self.check("CAF Africa Cup of Nations", "Quarter-finals", (40, True))
        self.check("Concacaf Gold Cup", "Final", (40, True))
        self.check("UEFA Nations League", "League A", (15, False))
        self.check("UEFA Nations League", "Play-offs C/D", (25, False))
        self.check("UEFA Nations League", "Final", (25, False))
        self.check("UEFA Nations League", "", (15, False))
        self.check("Concacaf Nations League", "League C", (15, False))
        self.check("FIFA World Cup™ Qualifiers", "Round One", (25, False))
        self.check("CAF Africa Cup of Nations Qualifiers", "Group stage", (25, False))
        self.check("CAF Africa Cup of Nations Qualifiers", "Preliminary round", (25, False))
        self.check("Continental Qualifier", "Round Three", (25, False))
        self.check("AFC Asian Cup qualification", "", (25, False))
        self.check("Friendlies", "Friendlies 1", (10, False))
        self.check("FIFA ASEAN Cup™", "Division 2", (10, False))
        self.check("King's Cup", "", (10, False))

    def test_friendlies_outside_windows(self):
        self.check("Friendlies", "Friendlies 3", (5, False), day=self.OUTSIDE)
        self.check("ASEAN Championship", "Group Stage", (5, False), day=self.OUTSIDE)
        # qualifiers are never discounted
        self.check("FIFA World Cup™ Qualifiers", "Round One", (25, False), day=self.OUTSIDE)
        # dates past the last known window are given the benefit of the doubt
        self.check("Friendlies", "Friendlies 1", (10, False), day="2099-01-01")


WIKITEXT = """
==Matches==
{{Football box
|id         = NIG v LES
|date       = {{Start date|2026|9|25|df=y}}
|time       = {{UTZ|15:00|0}}
|team1      = {{fb-rt|NIG}}
|score      = 2–1
|team2      = {{fb|LES}}
|goals1     =
*[[Daniel Sosah|Sosah]] {{goal|38}}
|goals2     =
*[[Sera Motebang|Motebang]] {{goal|85|pen.}}
|stadium    = [[Accra Sports Stadium]], [[Accra]] (Ghana)
}}
{{Football box
|date       = {{Start date|2026|9|29|df=y}}
|time       = {{UTZ|15:00|2}}
|team1      = {{fb-rt|LES}}
|score      =
|team2      = {{fb|MAR}}
|referee    = }}
{{Football box collapsible
| date = {{Start date|2026|3|26|df=y}}
| team1 = {{fb-rt|DRC}}
| score = [[Some match article|1–1]]
| penaltyscore = 4–3
| team2 = {{fb|ZAM}}
}}
"""


class WikipediaParserTests(unittest.TestCase):
    def setUp(self):
        self.matches = list(sources.parse_football_boxes(WIKITEXT))

    def test_finds_every_box(self):
        self.assertEqual(len(self.matches), 3)

    def test_played_match(self):
        m = self.matches[0]
        self.assertEqual((m["date"], m["home"], m["away"], m["homeScore"], m["awayScore"]),
                         ("2026-09-25", "NIG", "LES", 2, 1))
        self.assertEqual(m["kickoff"], "2026-09-25T15:00:00Z")

    def test_unplayed_match_with_closing_braces_on_last_line(self):
        m = self.matches[1]
        self.assertEqual((m["home"], m["away"], m["homeScore"]), ("LES", "MAR", None))
        self.assertEqual(m["kickoff"], "2026-09-29T13:00:00Z")  # 15:00 at UTC+2

    def test_linked_score_penalties_and_code_alias(self):
        m = self.matches[2]
        self.assertEqual((m["home"], m["homeScore"], m["awayScore"], m["homePens"], m["awayPens"]),
                         ("COD", 1, 1, 4, 3))


class MergeTests(unittest.TestCase):
    def test_primary_wins_and_dates_within_a_day_match(self):
        fifa = [{"date": "2026-09-25", "home": "A", "away": "B", "source": "FIFA"}]
        wiki = [{"date": "2026-09-26", "home": "B", "away": "A", "source": "Wikipedia"},
                {"date": "2026-09-25", "home": "C", "away": "D", "source": "Wikipedia"}]
        community = [{"date": "2026-09-25", "home": "C", "away": "D", "source": "Community dataset"}]
        merged, added = sources.merge(fifa, wiki, community)
        self.assertEqual(added, 1)
        self.assertEqual([m["source"] for m in merged], ["FIFA", "Wikipedia"])


if __name__ == "__main__":
    unittest.main()
