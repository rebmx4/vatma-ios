"""Canonical identity of the standalone browser App Store release."""
import argparse

APP_ID = "6826668990"
BUNDLE_ID = "ru.atma.browser"
TEAM_ID = "GR3WB4Z646"
SKU = "ATMA_BROWSER_IOS_001"

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("field", choices=("app-id", "bundle-id"))
    field = parser.parse_args().field
    print(APP_ID if field == "app-id" else BUNDLE_ID)
