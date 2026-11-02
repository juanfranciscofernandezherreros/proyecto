"""Extract the newest 10 or 15 completed French LNB matches into canonical CSVs."""

from __future__ import annotations

import argparse

from recent_competition import run_recent_competition


URL = "https://www.flashscore.com/basketball/france/lnb/results/"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matches", type=int, default=10, choices=(10, 15))
    parser.add_argument("--workers", type=int, choices=(1, 2, 3), default=3)
    parser.add_argument("--attempts", type=int, default=3, choices=range(1, 6))
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--recover", action="store_true")
    args = parser.parse_args()
    return run_recent_competition(
        url=URL, country="france", competition="lnb", matches=args.matches,
        workers=args.workers, resume=args.resume, recover=args.recover,
        attempts=args.attempts,
    )


if __name__ == "__main__":
    raise SystemExit(main())
