"""Select available phone/tablet UUIDs from simctl JSON, without fixed runtime names."""
import json
import re
import sys


def select(payload):
    runtimes = sorted(payload["devices"], key=lambda key: tuple(map(int, re.findall(r"\d+", key))), reverse=True)
    for runtime in runtimes:
        if ".iOS-" not in runtime:
            continue
        rows = [row for row in payload["devices"][runtime] if row.get("isAvailable")]
        phone = next((row for row in rows if row["name"].startswith("iPhone")), None)
        tablet = next((row for row in rows if row["name"].startswith("iPad")), None)
        if phone and tablet:
            return {"iphone": phone["udid"], "ipad": tablet["udid"], "runtime": runtime}
    raise ValueError("Available iPhone and iPad simulators on the same iOS runtime are required")


if __name__ == "__main__":
    print(json.dumps(select(json.load(sys.stdin)), indent=2))
