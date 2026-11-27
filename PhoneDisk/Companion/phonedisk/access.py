import hmac
import json
import secrets
import threading
import time
from http.cookies import CookieError, SimpleCookie
from urllib.parse import urlencode

import qrcode

from .folders import BACKUP_PATHS
from .http_service import TOKEN, token_hash
from .journal import REQUEST_ID
from .storage import TransferError


COOKIE = "__Host-PhoneDisk"
PERMISSIONS = ("view", "download", "create", "delete")


class Access:
    def __init__(self, journal, folders, network, fingerprint):
        self.journal = journal
        self.folders = folders
        self.network = network
        self.fingerprint = fingerprint
        self.invitation = None
        self.lock = threading.Lock()
        with journal.db() as db:
            db.execute("""CREATE TABLE IF NOT EXISTS phones (
                device TEXT PRIMARY KEY REFERENCES devices(device) ON DELETE CASCADE,
                name TEXT NOT NULL, paired INTEGER NOT NULL,
                photo INTEGER NOT NULL DEFAULT 0, video INTEGER NOT NULL DEFAULT 0)""")

    def invite(self, name, port):
        host = self.network.pairing_host()
        if not host:
            raise TransferError(409, "wifi-unavailable")
        code = secrets.token_urlsafe(32)
        payload = {"v": 1, "id": self.journal.server_id, "host": host, "port": port,
                   "pin": self.fingerprint, "code": code}
        if self.network.tailnet:
            payload["tailnet"] = self.network.tailnet
        uri = "https://rynpro.ru/disk/connect/#" + urlencode(payload)
        qr = qrcode.QRCode(box_size=1, border=4)
        qr.add_data(uri)
        matrix = ["".join("1" if cell else "0" for cell in line) for line in qr.get_matrix()]
        with self.lock:
            self.invitation = (code, time.monotonic() + 180)
        return {"matrix": matrix, "expiresIn": 180, "name": name}

    def pair(self, body, local, name):
        if not local:
            raise TransferError(403, "local-pairing-only")
        if not isinstance(body, dict) or set(body) != {"code", "deviceId", "name"}:
            raise TransferError(400, "invalid-pairing")
        code, device, phone = (body[key] for key in ("code", "deviceId", "name"))
        if not isinstance(code, str) or not TOKEN.fullmatch(code) or not isinstance(device, str) or not REQUEST_ID.fullmatch(device):
            raise TransferError(400, "invalid-pairing")
        if not isinstance(phone, str) or not 1 <= len(phone.strip()) <= 100 or not phone.isprintable():
            raise TransferError(400, "invalid-device-name")
        with self.lock:
            if self.invitation is None or self.invitation[1] <= time.monotonic() or not hmac.compare_digest(code, self.invitation[0]):
                raise TransferError(410, "qr-expired")
            token = secrets.token_urlsafe(32)
            expiry = int(time.time()) + 10 * 365 * 24 * 3600
            defaults = {source: (["create"] if record["backup"] else ["view", "download"])
                        for source, record in self.folders.records().items()}
            with self.journal.db() as db:
                db.execute("""INSERT INTO devices VALUES (?,?,?,?)
                    ON CONFLICT(device) DO UPDATE SET hash=excluded.hash,expires=excluded.expires""",
                           (device, token_hash(token), json.dumps(defaults), expiry))
                db.execute("""INSERT INTO phones(device,name,paired) VALUES (?,?,?)
                    ON CONFLICT(device) DO UPDATE SET name=excluded.name,paired=excluded.paired""",
                           (device, phone.strip(), int(time.time())))
            self.invitation = None
        return {"token": token, "expires": expiry, "serverId": self.journal.server_id, "name": name}

    def credential(self, request, *, cookie=True):
        headers = request.headers
        auth = headers.get_all("Authorization") or []
        if auth:
            if len(auth) != 1 or not auth[0].startswith("Bearer "):
                raise TransferError(401, "sign-in")
            value = auth[0][7:]
        elif cookie:
            try:
                values = headers.get_all("Cookie") or []
                cookies = SimpleCookie(values[0]) if len(values) == 1 else {}
                value = cookies[COOKIE].value
            except (CookieError, KeyError):
                raise TransferError(401, "sign-in") from None
            if request.command not in {"GET", "HEAD"} and (
                headers.get("Origin") != request.origin or headers.get("Sec-Fetch-Site", "same-origin") != "same-origin"
            ):
                raise TransferError(403, "invalid-origin")
        else:
            raise TransferError(401, "sign-in")
        if not TOKEN.fullmatch(value):
            raise TransferError(401, "sign-in")
        with self.journal.db() as db:
            device = db.execute("SELECT * FROM devices WHERE hash=? AND expires>?",
                                (token_hash(value), int(time.time()))).fetchone()
        if device is None:
            raise TransferError(401, "sign-in")
        return device, value

    def check(self, request, source, permission):
        device, _ = self.credential(request)
        if not isinstance(source, str) or permission not in json.loads(device["scopes"]).get(source, []):
            raise TransferError(403, "forbidden")
        return device["device"]

    def check_upload(self, request, body):
        if not isinstance(body, dict):
            raise TransferError(400, "invalid-upload")
        source = body.get("source")
        device = self.check(request, source, "create")
        record = self.folders.records().get(source)
        if record is None:
            raise TransferError(404, "unknown-source")
        folder = body.get("folder")
        if record["backup"] and folder not in BACKUP_PATHS.values():
            raise TransferError(403, "invalid-backup-folder")
        if body.get("automatic"):
            if not record["backup"]:
                raise TransferError(403, "invalid-backup-folder")
            settings = self.backups(device)
            if not any(value["enabled"] and value["source"] == source and value["path"] == folder
                       for value in settings.values()):
                raise TransferError(403, "backup-disabled")
        return device

    def phones(self):
        with self.journal.db() as db:
            rows = db.execute("SELECT * FROM phones JOIN devices USING(device) ORDER BY paired DESC").fetchall()
        return [{"id": row["device"], "name": row["name"], "scopes": json.loads(row["scopes"])} for row in rows]

    def set_grants(self, device, grants):
        if not isinstance(grants, dict):
            raise TransferError(400, "invalid-permissions")
        folders = self.folders.records()
        for source, permissions in grants.items():
            folder = folders.get(source)
            allowed = ("create",) if folder and folder["backup"] else PERMISSIONS
            if folder is None or not isinstance(permissions, list) or any(p not in allowed for p in permissions):
                raise TransferError(400, "invalid-permissions")
        with self.journal.db() as db:
            db.execute("UPDATE devices SET scopes=? WHERE device=?", (json.dumps(grants), device))

    def revoke(self, device, digest=None):
        with self.journal.db() as db:
            if digest is None:
                db.execute("DELETE FROM devices WHERE device=?", (device,))
            else:
                db.execute("DELETE FROM devices WHERE device=? AND hash=?", (device, digest))

    def backups(self, device, modify=None):
        with self.journal.db() as db:
            phone = db.execute("SELECT * FROM phones JOIN devices USING(device) WHERE device=?", (device,)).fetchone()
            if phone is None:
                raise TransferError(401, "sign-in")
            scopes = json.loads(phone["scopes"])
            source, label = next(((key, entry["name"]) for key, entry in self.folders.records().items()
                                  if entry["backup"] and "create" in scopes.get(key, [])), (None, None))
            settings = {}
            for key, path in BACKUP_PATHS.items():
                enabled = bool(phone[key])
                if modify and modify.get("type") == key:
                    enabled = modify["enabled"]
                    if enabled and not source:
                        raise TransferError(403, "backup-folder-needed")
                    # The column name is selected from the fixed BACKUP_PATHS map.
                    db.execute(f"UPDATE phones SET {key}=? WHERE device=?", (int(enabled), device))
                settings[key] = {"enabled": enabled and source is not None, "source": source,
                                 "path": path, "label": label}
            return settings
