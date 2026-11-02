"""Submit the already consolidated EuroLeague run in the required batch order."""

import json
import time
from pathlib import Path
from urllib.request import Request, urlopen


ROOT = Path(r"C:\data\basketball-ready\current")
LAUNCHER = "http://localhost:8088"
FILES = (
    "RESULTS_20261026085554_europe_euroleague.csv",
    "SCORE_SUMMARY_20261026085554_all.csv",
    "STATS_ALL_PERIODS_20261026085554_all.csv",
    "PLAYER_STATS_20261026085554_all.csv",
    "POINT_BY_POINT_20261026085554_all.csv",
)


def request(path: str, method: str = "GET", body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {} if data is None else {"Content-Type": "application/json"}
    with urlopen(Request(path, data=data, headers=headers, method=method), timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


for filename in FILES:
    submitted = request(f"{LAUNCHER}/batch-launches", "POST", {"file": str(ROOT / filename)})
    request_id = submitted["requestId"]
    while True:
        result = request(f"{LAUNCHER}/batch-launches/{request_id}")
        if result["status"] in {"COMPLETED", "FAILED"}:
            print(f"{filename}: {result['status']} ({result['batch']})", flush=True)
            if result["status"] == "FAILED":
                raise SystemExit(1)
            break
        time.sleep(2)
