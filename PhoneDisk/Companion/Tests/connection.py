"""HTTPS acceptance checks using disposable directories and synthetic media."""

import argparse
import hashlib
import http.client
import json
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs, urlencode, urlsplit


COMPANION = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(COMPANION))


class Client:
    def __init__(self, server, state):
        self.server = server
        self.pins = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        self.pins.check_hostname = False
        self.pins.load_verify_locations(cafile=str(state / "computer.pem"))

    def request(self, method, path, *, body=None, token=None, headers=None, expect=200):
        headers = dict(headers or {})
        if isinstance(body, dict):
            body = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        if token:
            headers["Authorization"] = "Bearer " + token
        connection = http.client.HTTPSConnection("127.0.0.1", self.server.server_port, context=self.pins, timeout=20)
        try:
            connection.connect()
            certificate = connection.sock.getpeercert(binary_form=True)
            assert hashlib.sha256(certificate).hexdigest() == self.server.fingerprint
            connection.request(method, path, body=body, headers=headers)
            response = connection.getresponse()
            data = response.read()
            assert response.status == expect, (method, path.split("?")[0], response.status, expect, data[:100] if response.status >= 400 else "")
            if response.headers.get_content_type() == "application/json" and data:
                data = json.loads(data)
            return response.headers, data
        finally:
            connection.close()

    def pair(self, invite, device, *, expect=200):
        return self.request("POST", "/api/companion/pair",
                            body={"code": invite["code"], "deviceId": device, "name": "Проверочный iPhone"}, expect=expect)[1]


@contextmanager
def running(state, ffmpeg):
    from phonedisk.service import CompanionServer

    with CompanionServer(state, COMPANION / "web", ffmpeg, loopback=True, port=0) as server:
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            yield Client(server, state)
        finally:
            server.shutdown()
            worker.join()


def invitation(client):
    import qrcode

    add = qrcode.QRCode.add_data
    encoded = []

    def capture(qr, value, *args, **kwargs):
        encoded.append(value)
        return add(qr, value, *args, **kwargs)

    with patch.object(qrcode.QRCode, "add_data", capture):
        reply = client.server.admin({"action": "invite"})
    assert len(encoded) == 1 and reply["expiresIn"] == 180
    assert len(reply["matrix"]) >= 29 and all(len(row) == len(reply["matrix"]) for row in reply["matrix"])
    link = urlsplit(encoded[0])
    assert (link.scheme, link.netloc, link.path) == ("https", "rynpro.ru", "/disk/connect/")
    assert not link.query and link.fragment
    qr = {name: values[0] for name, values in parse_qs(link.fragment).items()}
    assert qr["v"] == "1" and qr["pin"] == client.server.fingerprint
    assert qr["id"] == client.server.journal.server_id and int(qr["port"]) == client.server.server_port
    return qr


def location(endpoint, source, relative):
    return endpoint + "?" + urlencode({"source": source, "path": relative})


def run(temp, ffmpeg):
    state = temp / "state"
    shared = temp / "Видео"
    backup = temp / "Резервные копии"
    shared.mkdir()
    backup.mkdir()
    sample_name = "Проверка + видео.bin"
    sample = b"PhoneDisk range payload" * 4096
    (shared / sample_name).write_bytes(sample)
    (temp / "Скрытый файл.txt").write_text("outside the selected folder", encoding="utf-8")
    if ffmpeg:
        subprocess.run([str(ffmpeg), "-v", "error", "-nostdin", "-f", "lavfi", "-i",
                        "color=c=green:s=176x144:d=0.5", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                        "-movflags", "+faststart", str(shared / "preview.mp4")],
                       check=True, timeout=30)
    phone, second_phone = uuid.uuid4().hex, uuid.uuid4().hex
    upload = bytes(range(256)) * 4160
    part_size = 1024 * 1024
    assert len(upload) > part_size

    with running(state, ffmpeg) as client:
        client.request("GET", "/api/companion/catalog", expect=401)
        client.request("GET", "/", expect=401)
        client.server.admin({"action": "add", "path": str(shared)})
        client.server.admin({"action": "add", "path": str(backup), "backup": True})
        roots = client.server.journal.folders.records()
        source = next(key for key, record in roots.items() if not record["backup"])
        backup_source = next(key for key, record in roots.items() if record["backup"])

        stale = invitation(client)
        with client.server.access.lock:
            client.server.access.invitation = (stale["code"], time.monotonic() - 1)
        client.pair(stale, phone, expect=410)
        code = invitation(client)
        with ThreadPoolExecutor(max_workers=2) as pool:
            def try_pair():
                try:
                    return client.pair(code, phone)
                except AssertionError as error:
                    assert error.args[0][2] == 410
                    return None
            output = list(pool.map(lambda _: try_pair(), range(2)))
        assert sum(reply is not None for reply in output) == 1
        token = next(reply for reply in output if reply)["token"]
        client.pair(code, second_phone, expect=410)
        token2 = client.pair(invitation(client), second_phone)["token"]
        print("One-time QR, expiry and simultaneous requests OK")

        headers, home = client.request("GET", "/", token=token)
        cookie = headers["Set-Cookie"].split(";")[0]
        assert b"app.js" in home and "HttpOnly" in headers["Set-Cookie"]
        web = {"Cookie": cookie}
        client.request("GET", "/app.js", headers=web)
        catalog = client.request("GET", "/api/companion/catalog", headers=web)[1]
        assert [item["source"] for item in catalog["roots"]] == [source]
        contents = client.request("GET", location("/api/companion/catalog", source, "/"), token=token)[1]
        assert sample_name in [item["name"] for item in contents["items"]]
        file_url = location("/api/v2/file", source, "/" + sample_name)
        headers, _ = client.request("HEAD", file_url, token=token)
        assert headers["X-File-SHA256"] == hashlib.sha256(sample).hexdigest()
        reply, sliced = client.request("GET", file_url, token=token, expect=206,
                                      headers={"Range": "bytes=19-128", "If-Range": headers["ETag"]})
        assert sliced == sample[19:129] and reply["Content-Range"] == f"bytes 19-128/{len(sample)}"
        assert client.request("GET", file_url, token=token)[1] == sample
        print("Selected folder, web session, full download and resumption range OK")

        if ffmpeg:
            _, cover = client.request("GET", location("/api/companion/cover", source, "/preview.mp4"), headers=web)
            assert cover[:3] == b"\xff\xd8\xff"
            media, fragment = client.request("GET", location("/api/companion/media", source, "/preview.mp4"),
                                              headers={**web, "Range": "bytes=0-511"}, expect=206)
            assert media.get_content_type() == "video/mp4" and fragment == (shared / "preview.mp4").read_bytes()[:512]
            print("JPEG cover and byte-range video preview OK")
        client.request("POST", location("/api/companion/trash", source, "/" + sample_name), token=token, expect=403)
        manifest = {"requestId": uuid.uuid4().hex, "source": source, "folder": "/", "name": "test upload.bin",
                    "size": len(upload), "sha256": hashlib.sha256(upload).hexdigest(), "partSize": part_size,
                    "automatic": False, "autoFinish": True}
        client.request("POST", "/api/v2/uploads", token=token, body=manifest, expect=403)
        client.server.admin({"action": "grant", "device": phone,
                             "scopes": {source: ["view", "download", "create"], backup_source: ["create"]}})
        client.server.admin({"action": "grant", "device": second_phone,
                             "scopes": {source: ["view", "create"]}})
        client.request("GET", file_url, token=token2, expect=403)
        transfer = "/api/v2/uploads/" + client.request("POST", "/api/v2/uploads", token=token, body=manifest)[1]["id"]
        client.request("GET", transfer, token=token2, expect=404)
        first = upload[:part_size]
        digest = hashlib.sha256(first).hexdigest()
        for _ in range(2):
            client.request("PUT", transfer + "/parts/0", token=token, body=first, headers={"X-Part-SHA256": digest})
        assert client.request("GET", transfer, token=token)[1]["received"] == part_size
        print("Folder permissions, private upload and safe repeat of a part OK")

    with running(state, ffmpeg) as client, running(temp / "unrelated", None) as other:
        assert other.server.journal.server_id != client.server.journal.server_id
        assert other.server.fingerprint != client.server.fingerprint
        other.request("GET", "/api/companion/catalog", token=token, expect=401)
        assert client.request("POST", "/api/v2/uploads", token=token, body=manifest)[1]["parts"] == [0]
        last = upload[part_size:]
        client.request("PUT", transfer + "/parts/1", token=token, body=last, headers={"X-Part-SHA256": hashlib.sha256(last).hexdigest()})
        assert client.request("GET", transfer, token=token)[1]["complete"]
        assert (shared / manifest["name"]).read_bytes() == upload
        print("Independent PCs and upload recovery after a service restart OK")

        before = client.request("GET", "/api/v2/backup-settings", token=token)[1]
        assert not before["photo"]["enabled"] and before["video"]["source"] == backup_source
        options = {"type": "photo", "enabled": True}
        client.request("POST", "/api/companion/backups", headers={**web, "Origin": "https://example.test"},
                       body=options, expect=403)
        actual_origin = f"https://127.0.0.1:{client.server.server_port}"
        settings = client.request("POST", "/api/companion/backups",
                                  headers={**web, "Origin": actual_origin}, body=options)[1]
        assert settings["photo"]["enabled"] and settings["photo"]["path"] == "/Фото"
        fixture_jpg = b"sample original"
        old_photo = {"requestId": uuid.uuid4().hex, "source": backup_source, "folder": "/Фото", "name": "2015-photo.jpg",
                     "size": len(fixture_jpg), "sha256": hashlib.sha256(fixture_jpg).hexdigest(),
                     "partSize": part_size, "automatic": True, "autoFinish": True}
        photo_path = "/api/v2/uploads/" + client.request("POST", "/api/v2/uploads", token=token, body=old_photo)[1]["id"]
        client.request("PUT", photo_path + "/parts/0", token=token, body=fixture_jpg, headers={"X-Part-SHA256": old_photo["sha256"]})
        assert (backup / "Фото" / "2015-photo.jpg").read_bytes() == fixture_jpg
        old_photo["requestId"] = uuid.uuid4().hex
        assert client.request("POST", "/api/v2/uploads", token=token, body=old_photo)[1]["complete"]
        assert len(list((backup / "Фото").iterdir())) == 1
        print("Backup settings and retry without a duplicate OK")

        # A removable disk can disappear and return with the same folder identity.
        shared.rename(temp / "unplugged")
        assert not client.request("GET", "/api/companion/catalog", token=token)[1]["roots"][0]["available"]
        (temp / "unplugged").rename(shared)
        assert client.request("GET", file_url, token=token)[1] == sample
        client.server.admin({"action": "revoke", "device": phone})
        client.request("GET", file_url, token=token, expect=401)
        client.request("GET", "/api/companion/catalog", headers=web, expect=401)
        client.request("GET", "/api/companion/catalog", token=token2)
        print("Temporary disk removal and revocation of token and web session OK")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--wheels", type=Path, required=True)
    parser.add_argument("--ffmpeg", type=Path)
    cli = parser.parse_args()
    sys.path.insert(0, str(cli.wheels.resolve()))
    with tempfile.TemporaryDirectory(prefix="phonedisk-acceptance-") as temporary:
        run(Path(temporary).resolve(), cli.ffmpeg)
