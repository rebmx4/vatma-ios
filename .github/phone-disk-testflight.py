import json
import os
import sys
import time
from urllib.error import HTTPError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

import jwt


BASE = "https://api.appstoreconnect.apple.com"
APP = "6838673473"
BUNDLE = "ru.atma.phonedisk"
GROUP = "8deacc74-64c6-4c95-9da1-9225fdd6873f"
VERSION = "1.0.0"


def api(path, query=None, body=None):
    url = path if path.startswith("https://") else BASE + path
    if urlparse(url).netloc != urlparse(BASE).netloc:
        raise RuntimeError("Unexpected App Store Connect response URL")
    if query:
        url += "?" + urlencode(query)
    now = int(time.time())
    token = jwt.encode(
        {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now,
         "exp": now + 600, "aud": "appstoreconnect-v1"},
        os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].replace("\\n", "\n"),
        algorithm="ES256", headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"]})
    headers = {"Authorization": "Bearer " + token}
    data = None
    if body:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    try:
        with urlopen(Request(url, data=data, headers=headers), timeout=30) as response:
            return json.loads(response.read()) if response.status != 204 else {}
    except HTTPError as error:
        result = json.loads(error.read())
        codes = ",".join(str(item.get("code", "?")) for item in result.get("errors", []))
        raise RuntimeError(f"App Store Connect returned HTTP {error.code}: {codes}") from None


def resources(path, fields):
    result = api(path, {"limit": 200, **fields})
    yield from result["data"]
    while result.get("links", {}).get("next"):
        result = api(result["links"]["next"])
        yield from result["data"]


def validate_target():
    app = api(f"/v1/apps/{APP}", {"fields[apps]": "bundleId"})["data"]
    if app["attributes"]["bundleId"] != BUNDLE:
        raise RuntimeError("Unexpected application bundle")
    groups = list(resources(f"/v1/apps/{APP}/betaGroups",
                            {"fields[betaGroups]": "name,isInternalGroup,hasAccessToAllBuilds"}))
    owner = [group for group in groups if group["id"] == GROUP]
    if len(owner) != 1 or not owner[0]["attributes"].get("isInternalGroup") or owner[0]["attributes"]["name"] != "Владелец":
        raise RuntimeError("Expected one existing internal owner group")
    if any(group["id"] != GROUP
           and group["attributes"].get("hasAccessToAllBuilds") for group in groups):
        raise RuntimeError("An additional group has automatic access")


def enable_associated_domains():
    identifiers = list(resources("/v1/bundleIds", {"filter[identifier]": BUNDLE}))
    if len(identifiers) != 1 or identifiers[0]["attributes"]["identifier"] != BUNDLE:
        raise RuntimeError("Expected one Bundle ID for PhoneDisk")
    bundle = identifiers[0]["id"]
    capability = "ASSOCIATED_DOMAINS"
    current = resources(f"/v1/bundleIds/{bundle}/bundleIdCapabilities", {})
    if any(item["attributes"]["capabilityType"] == capability for item in current):
        return
    api("/v1/bundleIdCapabilities", body={"data": {
        "type": "bundleIdCapabilities",
        "attributes": {"capabilityType": capability},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle}}},
    }})


def next_build():
    known = []
    for item in resources(f"/v1/apps/{APP}/builds", {"fields[builds]": "version"}):
        value = item["attributes"]["version"]
        if value.isdigit():
            known.append(int(value))
    for item in resources(f"/v1/apps/{APP}/buildUploads",
                          {"fields[buildUploads]": "cfBundleVersion,platform"}):
        value = str(item["attributes"].get("cfBundleVersion") or "")
        if item["attributes"].get("platform") == "IOS" and value.isdigit():
            known.append(int(value))
    return max(68, max(known, default=0) + 1)


def groups_for_build(build):
    groups = resources(f"/v1/apps/{APP}/betaGroups", {"fields[betaGroups]": "isInternalGroup"})
    linked = set()
    for group in groups:
        items = resources(f"/v1/betaGroups/{group['id']}/builds", {"fields[builds]": "version"})
        if any(item["id"] == build for item in items):
            linked.add(group["id"])
    return linked


def assign(num):
    deadline = time.monotonic() + 16 * 60
    recorded = None
    while time.monotonic() < deadline:
        matches = api("/v1/builds", {
            "filter[app]": APP, "filter[version]": num,
            "fields[builds]": "version,processingState,buildAudienceType,expired", "limit": 2,
        })["data"]
        if len(matches) > 1:
            raise RuntimeError("More than one matching build")
        if matches:
            item = matches[0]
            attributes = item["attributes"]
            status = attributes["processingState"]
            if status != recorded:
                print(f"Apple processing state: {status}", flush=True)
                recorded = status
            if status in ("INVALID", "FAILED"):
                raise RuntimeError(f"Apple build processing {status}")
            if status == "VALID":
                if attributes.get("expired"):
                    raise RuntimeError("Expected an active build")
                build = item["id"]
                pre = api(f"/v1/builds/{build}/preReleaseVersion",
                          {"fields[preReleaseVersions]": "version,platform"})["data"]["attributes"]
                if pre["version"] != VERSION or pre["platform"] != "IOS":
                    raise RuntimeError("App Store Connect reported a different version or platform")
                links = groups_for_build(build)
                print(f"Existing build {build}; owner linked: {GROUP in links}", flush=True)
                if links - {GROUP}:
                    raise RuntimeError("Build already has another group")
                if GROUP not in links:
                    api(f"/v1/betaGroups/{GROUP}/relationships/builds",
                        body={"data": [{"type": "builds", "id": build}]})
                    print("Added build to the existing owner group.", flush=True)
                verify(build)
                return
        time.sleep(25)
    raise RuntimeError("Apple processing has not finished. Check the existing upload; do not upload it again.")


def verify(build):
    for _ in range(15):
        groups = groups_for_build(build)
        detail = api("/v1/buildBetaDetails", {"filter[build]": build,
                     "fields[buildBetaDetails]": "internalBuildState"})["data"]
        detail = detail[0]["attributes"] if len(detail) == 1 else {}
        if groups == {GROUP} and detail.get("internalBuildState") == "IN_BETA_TESTING":
            print(f"VALID / IN_BETA_TESTING / Владелец / {build}", flush=True)
            return
        time.sleep(10)
    raise RuntimeError(f"Build {build} exists but internal testing has not been verified.")


if __name__ == "__main__":
    validate_target()
    if sys.argv[1] == "next":
        print(next_build())
    elif sys.argv[1] == "assign":
        assign(os.environ["DISK_BUILD"])
    elif sys.argv[1] == "enable-associated-domains":
        enable_associated_domains()
    else:
        raise SystemExit("Expected next, assign or enable-associated-domains")
