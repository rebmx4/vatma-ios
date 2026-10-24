"""Select available phone/tablet UUIDs from simctl JSON, without fixed runtime names."""
import argparse
import json
import re
import sys


def select(payload, ios_version=None):
    requested = None
    if ios_version is not None:
        version = re.fullmatch(r"(\d+)\.(\d+)(?:\.\d+)?", ios_version)
        if version is None:
            raise ValueError(f"Invalid iOS SDK version: {ios_version}")
        requested = ".iOS-" + "-".join(version.groups())
    runtimes = sorted(payload["devices"], key=lambda key: tuple(map(int, re.findall(r"\d+", key))), reverse=True)
    for runtime in runtimes:
        if ".iOS-" not in runtime or (requested is not None and not runtime.endswith(requested)):
            continue
        rows = [row for row in payload["devices"][runtime] if row.get("isAvailable")]
        # Prefer actual App Store screenshot families; retain the runtime-safe fallback.
        phone = next((row for row in rows if re.fullmatch(r"iPhone \d+ Pro Max", row["name"])), None)
        phone = phone or next((row for row in rows if row["name"].startswith("iPhone")), None)
        tablet = next((row for row in rows if row["name"].startswith("iPad") and "13-inch" in row["name"]), None)
        tablet = tablet or next((row for row in rows if row["name"].startswith("iPad")), None)
        if phone and tablet:
            return {"iphone": phone["udid"], "ipad": tablet["udid"], "runtime": runtime}
    suffix = f" matching iOS SDK {ios_version}" if ios_version is not None else ""
    raise ValueError("Available iPhone and iPad simulators on the same iOS runtime" + suffix + " are required")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ios-version", help="Require the active SDK major/minor runtime")
    arguments = parser.parse_args()
    print(json.dumps(select(json.load(sys.stdin), ios_version=arguments.ios_version), indent=2))
