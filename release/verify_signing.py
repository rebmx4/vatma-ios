"""Check archive entitlements after macOS codesign verification, without reading secrets."""
from pathlib import Path
import plistlib
import sys


def verify(data):
    info = plistlib.loads(data)
    if info.get("application-identifier") != "GR3WB4Z646.ru.atma.app":
        raise ValueError("Wrong signed application identifier")
    if info.get("com.apple.developer.team-identifier") != "GR3WB4Z646":
        raise ValueError("Wrong signing team")
    for key in ("aps-environment", "com.apple.security.application-groups",
                "com.apple.developer.networking.networkextension", "com.apple.developer.associated-domains"):
        if key in info:
            raise ValueError("Unexpected legacy signed entitlement")
    if info.get("get-task-allow") is True:
        raise ValueError("Distribution archive must not permit debugging")
    groups = info.get("keychain-access-groups", [])
    if any(group != "GR3WB4Z646.ru.atma.app" for group in groups):
        raise ValueError("Unexpected shared keychain group")
    return {"status": "passed", "scope": "signed archive entitlement identity"}


if __name__ == "__main__":
    import json
    print(json.dumps(verify(Path(sys.argv[1]).read_bytes()), indent=2))
