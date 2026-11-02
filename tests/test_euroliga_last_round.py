import sys
import unittest
from pathlib import Path

# Los scripts de Python del proyecto viven en python\.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

from euroliga_last_round import completed_matches, match_id


class EuroleagueLastRoundTests(unittest.TestCase):
    def test_selects_the_newest_completed_matches_in_source_order(self):
        rows = [
            {"Match": "A vs B", "Result": "90-80", "Match Link": "https://x/?mid=abc123"},
            {"Match": "C vs D", "Result": "scheduled", "Match Link": "https://x/?mid=def456"},
            {"Match": "E vs F", "Result": "70 - 71", "Match Link": "https://x/?mid=ghi789"},
        ]
        self.assertEqual([row["Match"] for row in completed_matches(rows, 2)], ["A vs B", "E vs F"])

    def test_rejects_a_missing_or_invalid_match_id(self):
        with self.assertRaises(ValueError):
            match_id({"Match Link": "https://x/no-id"})


if __name__ == "__main__":
    unittest.main()
