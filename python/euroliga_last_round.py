"""Extract the newest completed EuroLeague matches into the canonical CSV layout."""

from __future__ import annotations

import argparse
from recent_competition import (
    DATASETS, SCORE, SCRAPER, WORKSPACE, completed_matches, extract_bundle,
    invoke, match_id, missing_datasets, run_recent_competition,
)


URL = "https://www.flashscore.com/basketball/europe/euroleague/results/"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matches", type=int, default=10, help="Newest completed matches to extract (default: 10, one regular-season round)")
    parser.add_argument("--workers", type=int, choices=(1, 2, 3), default=3, help="Concurrent independent match bundles")
    parser.add_argument("--attempts", type=int, default=3, choices=range(1, 6), help="Automatic targeted recovery passes")
    parser.add_argument("--resume", action="store_true", help="Reuse valid per-match CSVs")
    parser.add_argument("--recover", action="store_true", help="Recover only missing datasets from the latest saved selection")
    args = parser.parse_args()
    return run_recent_competition(
        url=URL,
        country="europe",
        competition="euroleague",
        matches=args.matches,
        workers=args.workers,
        resume=args.resume,
        recover=args.recover,
        selection_name="last-round",
        attempts=args.attempts,
    )
if __name__ == "__main__":
    raise SystemExit(main())
