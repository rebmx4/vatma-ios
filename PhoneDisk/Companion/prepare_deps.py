"""Fetch and verify the Windows wheels listed in the package lock."""

import argparse
import hashlib
import io
from pathlib import Path
import urllib.request
from zipfile import ZipFile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("target", type=Path)
    target = parser.parse_args().target.resolve()
    target.mkdir(parents=True, exist_ok=True)
    for line in Path(__file__).with_name("wheels.lock").read_text(encoding="ascii").splitlines():
        filename, digest, url = line.split()
        with urllib.request.urlopen(url, timeout=30) as response:
            wheel = response.read()
        if hashlib.sha256(wheel).hexdigest() != digest:
            raise SystemExit(f"Checksum mismatch: {filename}")
        with ZipFile(io.BytesIO(wheel)) as archive:
            archive.extractall(target)
        print(filename)


if __name__ == "__main__":
    main()
