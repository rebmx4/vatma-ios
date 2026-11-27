import argparse
import json
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "vendor"))
from phonedisk.service import CompanionServer, PORT
from phonedisk.storage import TransferError


def send(payload):
    print(json.dumps(payload, ensure_ascii=True), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--loopback", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    ffmpeg = root / "media" / "ffmpeg.exe"
    try:
        server = CompanionServer(args.state, root / "web", ffmpeg if ffmpeg.is_file() else None,
                                 loopback=args.loopback, port=args.port)
    except OSError:
        send({"error": "startup"})
        return 1
    with server:
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        send({"ready": True, "port": server.server_port})
        try:
            for line in sys.stdin:
                try:
                    send(server.admin(json.loads(line)))
                except TransferError as error:
                    send({"error": error.code})
                except (ValueError, KeyError, OSError):
                    send({"error": "disk-io"})
        finally:
            server.shutdown()
            worker.join()
    return 0


if __name__ == "__main__":
    sys.exit(main())
