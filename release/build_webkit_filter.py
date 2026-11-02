"""Build the bundled WebKit rules from the pinned ATMA2 host snapshot."""

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOSTS = ROOT / "release" / "atma2-hosts.json"
BASE = ROOT / "release" / "content-blocker-base.json"
OUTPUT = ROOT / "BrowserUI" / "content-blocker.json"
HOST_PATTERN = re.compile(r"[a-z0-9-]+(?:\.[a-z0-9-]+)*\Z")
SOURCE_SHA256 = "ec33270e74e408b3c9086a0527c2ad7bebbb8b2aa5cc8d5d4f9e3500aa822c24"
HOSTS_SHA256 = "e4fac0392719ceca7cfae603f198c04644ee7154666e919e6e404698c892235f"


def build():
    source = json.loads(HOSTS.read_text(encoding="utf-8"))
    hosts = source["hosts"]
    assert source["schema"] == 1
    assert source["source_sha256"] == SOURCE_SHA256
    assert source["hosts_sha256"] == HOSTS_SHA256
    assert len(hosts) == 82498 and hosts == sorted(set(hosts))
    assert all(HOST_PATTERN.fullmatch(host) for host in hosts)
    assert hashlib.sha256("\n".join(hosts).encode()).hexdigest() == source["hosts_sha256"]
    rules = json.loads(BASE.read_text(encoding="utf-8"))
    assert len(rules) == 27
    for host in hosts:
        domain = host.replace(".", r"\.")
        rules.append({
            "trigger": {
                "url-filter": rf"^https?://+([^:/]+\.)?{domain}[:/]",
                "url-filter-is-case-sensitive": True,
            },
            "action": {"type": "block"},
        })
    for path in ("pagead/", "youtubei/v1/player/ad_break"):
        rules.append({
            "trigger": {"url-filter": rf"^https?://+([^:/]+\.)?youtube\.com/{path}",
                        "url-filter-is-case-sensitive": True},
            "action": {"type": "block"},
        })
    # The ATMA2 baseline excludes main_frame. Apply that exception after
    # network blocks, then still allow cosmetic rules for the page itself.
    rules.append({"trigger": {"url-filter": ".*", "resource-type": ["top-document"]},
                  "action": {"type": "ignore-previous-rules"}})
    rules.extend([
        {"trigger": {"url-filter": ".*", "if-domain": ["*rutube.ru"]},
         "action": {"type": "css-display-none", "selector":
                    '.video-player [class*="communication-banner-module__container"]'
                    '[aria-label="Коммуникационный баннер"]:has(> img[class*="banner-picture-module__img"])'}},
        {"trigger": {"url-filter": ".*", "if-domain": ["*vkvideo.ru"]},
         "action": {"type": "css-display-none", "selector":
                    '[class*="VideoAdsWidget__videoShowcaseSlot"], .textAds.pub_300x250'}},
    ])
    return (json.dumps(rules, ensure_ascii=False, separators=(",", ":")) + "\n").encode()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    result = build()
    if arguments.check:
        if OUTPUT.read_bytes() != result:
            parser.error("Bundled content rules differ from pinned sources")
    else:
        OUTPUT.write_bytes(result)
    print(json.dumps({"rules": len(json.loads(result)), "bytes": len(result), "checked": arguments.check}))
