"""Check the pinned ATMA2 host conversion without claiming WebKit compilation."""

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "release"))
from build_webkit_filter import build, HOSTS, OUTPUT


class FilterSnapshotTests(unittest.TestCase):
    def test_pinned_snapshot_generates_the_bundled_rules(self):
        self.assertEqual(OUTPUT.read_bytes(), build())
        hosts = json.loads(HOSTS.read_text(encoding="utf-8"))["hosts"]
        rules = json.loads(build())
        self.assertEqual(len(hosts), 82498)
        self.assertEqual(len(rules), 27 + len(hosts) + 5)
        self.assertEqual(rules[-3]["trigger"]["resource-type"], ["top-document"])
        self.assertEqual(rules[-3]["action"]["type"], "ignore-previous-rules")
        self.assertEqual(rules[-2]["trigger"]["if-domain"], ["*rutube.ru"])
        self.assertEqual(rules[-1]["trigger"]["if-domain"], ["*vkvideo.ru"])

    def test_host_expression_matches_subdomains_without_suffix_lookalikes(self):
        hosts = json.loads(HOSTS.read_text(encoding="utf-8"))["hosts"]
        rules = json.loads(build())
        for hostname in ("doubleclick.com", "adnxs.net", "smetrics.bravenhealth.com"):
            index = hosts.index(hostname)
            pattern = rules[27 + index]["trigger"]["url-filter"]
            self.assertNotIn("|", pattern)
            self.assertRegex("https://" + hostname + "/ad.js", pattern)
            self.assertRegex("https://sub." + hostname + "/ad.js", pattern)
            self.assertNotRegex("https://" + hostname + ".example/ad.js", pattern)
            self.assertNotRegex("https://not" + hostname + "/ad.js", pattern)


if __name__ == "__main__":
    unittest.main()
