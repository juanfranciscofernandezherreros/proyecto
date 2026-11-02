"""Resolve a Flashscore match ID through its browser redirect.

The short ``/match/<id>/`` link is intentionally opened in a real browser:
Flashscore redirects it to the canonical basketball URL, whose team slugs must
not be guessed by batch scripts.  stdout contains only that final URL.
"""

from __future__ import annotations

import argparse
import sys
import time
from urllib.parse import parse_qs, urlparse

from selenium import webdriver
from selenium.webdriver.chrome.options import Options


def is_canonical_match_url(url: str, match_id: str) -> bool:
    parsed = urlparse(url)
    return (
        parsed.scheme in {"http", "https"}
        and "flashscore.com" in parsed.netloc
        and "/match/basketball/" in parsed.path
        and parse_qs(parsed.query).get("mid") == [match_id]
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("match_id")
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args()

    options = Options()
    options.add_argument("--headless=new")
    options.add_argument("--disable-gpu")
    options.add_argument("--window-size=1280,900")

    driver = webdriver.Chrome(options=options)
    try:
        driver.get(f"https://www.flashscore.com/match/{args.match_id}/")
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            current_url = driver.current_url
            if is_canonical_match_url(current_url, args.match_id):
                print(current_url)
                return 0
            time.sleep(0.25)
        print(
            f"Flashscore did not redirect {args.match_id} to a canonical basketball URL; "
            f"last URL: {driver.current_url}",
            file=sys.stderr,
        )
        return 1
    finally:
        driver.quit()


if __name__ == "__main__":
    raise SystemExit(main())
