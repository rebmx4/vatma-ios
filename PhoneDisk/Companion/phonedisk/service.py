import hashlib
import json
import os
import socket
import ssl
import subprocess
import threading
import time
import uuid
from urllib.parse import urlsplit

from .access import Access, COOKIE
from .folders import BACKUP_PATHS, MEDIA, VIDEO, SharedFolders
from .http_service import Handler, TransferServer, location_query
from .journal import Journal
from .network import Network, identity
from .storage import TransferError, checked_file, file_info, version


PORT = 18119
ASSETS = {"/": ("index.html", "text/html; charset=utf-8"),
          "/app.js": ("app.js", "text/javascript; charset=utf-8"),
          "/styles.css": ("styles.css", "text/css; charset=utf-8")}
POLICY = ("default-src 'self'; base-uri 'none'; frame-ancestors 'none'; object-src 'none'; "
          "form-action 'none'; script-src 'self'; style-src 'self'; img-src 'self'; media-src 'self'")


class CompanionServer(TransferServer):
    def __init__(self, state, assets, ffmpeg=None, *, loopback=False, port=PORT):
        folders = SharedFolders(state)
        journal = Journal(state, folders)
        self.tls, self.fingerprint, dns = identity(state, journal.server_id)
        self.network = Network(loopback)
        self.assets = assets
        self.ffmpeg = ffmpeg
        self.covers = state / "covers"
        self.covers.mkdir(exist_ok=True)
        self.cover_slots = threading.BoundedSemaphore(2)
        self.name = (socket.gethostname().strip() or "Мой компьютер")[:100]
        access = Access(journal, folders, self.network, self.fingerprint)
        super().__init__(("127.0.0.1" if loopback else "0.0.0.0", port), journal, access, CompanionHandler)
        self.network.advertise(journal.server_id, self.name, self.server_port, dns)

    def get_request(self):
        connection, address = super().get_request()
        try:
            if not self.network.classify(connection.getsockname()[0], address[0]):
                raise OSError("Connection outside the selected network")
            return self.tls.wrap_socket(connection, server_side=True, do_handshake_on_connect=False), address
        except (OSError, ssl.SSLError):
            connection.close()
            raise

    def cover(self, path, info):
        cache_key = hashlib.sha256(repr((str(path), version(info))).encode()).hexdigest()
        target = self.covers / (cache_key + ".jpg")
        if target.is_file():
            return target
        if not self.ffmpeg:
            raise TransferError(404, "preview-unavailable")
        if not self.cover_slots.acquire(timeout=12):
            raise TransferError(429, "busy")
        temporary = self.covers / (uuid.uuid4().hex + ".jpg")
        try:
            if target.is_file():
                return target
            with checked_file(path):
                result = subprocess.run([str(self.ffmpeg), "-nostdin", "-loglevel", "error", "-protocol_whitelist",
                                         "file,pipe", "-i", str(path), "-map", "0:v:0", "-frames:v", "1",
                                         "-threads", "1", "-vf", "scale=360:360:force_original_aspect_ratio=decrease",
                                         str(temporary)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL, timeout=20,
                                        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            if result.returncode or not temporary.is_file() or version(file_info(path)) != version(info):
                raise TransferError(404, "preview-unavailable")
            os.replace(temporary, target)
            return target
        except subprocess.TimeoutExpired as error:
            raise TransferError(404, "preview-unavailable") from error
        finally:
            self.cover_slots.release()
            temporary.unlink(missing_ok=True)

    def admin(self, command):
        action = command.get("action")
        if action == "state":
            with self.access.lock:
                invitation = self.access.invitation
                inviting = invitation is not None and invitation[1] > time.monotonic()
            return {"name": self.name, "folders": self.journal.folders.records(), "phones": self.access.phones(),
                    "hasNetwork": bool(self.network.local), "hasTailnet": self.network.tailnet is not None,
                    "inviting": inviting}
        if action == "invite":
            if not self.journal.folders.records():
                raise TransferError(409, "folder-needed")
            return self.access.invite(self.name, self.server_port)
        if action == "cancel":
            with self.access.lock:
                self.access.invitation = None
        elif action == "add":
            self.journal.folders.add(command["path"], command.get("backup") is True)
        elif action == "remove":
            self.journal.folders.remove(command["source"])
        elif action == "grant":
            self.access.set_grants(command["device"], command["scopes"])
        elif action == "revoke":
            self.access.revoke(command["device"])
        else:
            raise TransferError(400, "invalid-action")
        return {"ok": True}

    def server_close(self):
        self.network.stop.set()
        super().server_close()


class CompanionHandler(Handler):
    def handle_api(self):
        method = self.command
        parsed = urlsplit(self.path)
        path = parsed.path
        host, port = self.connection.getsockname()
        authority = f"{host}:{port}"
        network = self.server.network.classify(host, self.client_address[0])
        if not network or self.headers.get_all("Host") != [authority] or parsed.netloc or parsed.scheme:
            raise TransferError(403, "wrong-address")
        self.origin = "https://" + authority
        access = self.server.access
        journal = self.server.journal
        folders = journal.folders
        if path == "/api/companion/pair" and method == "POST":
            return self.reply(200, access.pair(self.body(), network == "lan", self.server.name))
        if path == "/api/v2/capabilities" and method == "GET":
            return self.reply(200, {"version": 2, "autoFinishUploads": True, "serverId": journal.server_id,
                                   "lan": network == "lan"})
        if path == "/api/v2/device" and method == "DELETE":
            device, _ = access.credential(self, cookie=False)
            access.revoke(device["device"], device["hash"])
            return self.respond(204, 0)
        if path == "/api/v2/backup-settings" and method == "GET":
            device, _ = access.credential(self)
            return self.reply(200, access.backups(device["device"]))
        if path == "/api/companion/backups" and method == "POST":
            device, _ = access.credential(self)
            body = self.body()
            if (not isinstance(body, dict) or set(body) != {"type", "enabled"}
                    or body["type"] not in tuple(BACKUP_PATHS) or type(body["enabled"]) is not bool):
                raise TransferError(400, "invalid-backup-settings")
            return self.reply(200, access.backups(device["device"], body))
        if path == "/api/companion/catalog" and method == "GET":
            device, _ = access.credential(self)
            scopes = json.loads(device["scopes"])
            if not parsed.query:
                return self.reply(200, {"name": self.server.name, "roots": folders.roots(scopes)})
            source, relative = location_query(parsed.query)
            if "view" not in scopes.get(source, []):
                raise TransferError(403, "forbidden")
            return self.reply(200, {"items": folders.list(source, relative)})
        if path in {"/api/companion/media", "/api/companion/cover"} and method in {"GET", "HEAD"}:
            source, relative = location_query(parsed.query)
            access.check(self, source, "view")
            file = folders.file(source, relative)
            info = file_info(file)
            extension = file.suffix.lower()
            mime = MEDIA.get(extension)
            if path.endswith("/cover") and extension in VIDEO:
                file = self.server.cover(file, info)
                info, mime = file_info(file), "image/jpeg"
            if not mime:
                raise TransferError(404, "preview-unavailable")
            tag = hashlib.sha256(repr(version(info)).encode()).hexdigest()
            return self.stream_file(file, info, tag, mime, checksum=False)
        if path == "/api/companion/trash" and method == "POST":
            source, relative = location_query(parsed.query)
            access.check(self, source, "delete")
            folders.trash(source, relative)
            return self.respond(204, 0)
        if path in ASSETS and method == "GET":
            access.credential(self)
            name, mime = ASSETS[path]
            headers = {"Content-Type": mime, "Content-Security-Policy": POLICY,
                       "Referrer-Policy": "no-referrer"}
            if path == "/" and self.headers.get("Authorization"):
                _, token = access.credential(self, cookie=False)
                headers["Set-Cookie"] = f"{COOKIE}={token}; Secure; HttpOnly; Path=/; SameSite=Strict"
            data = (self.server.assets / name).read_bytes()
            self.respond(200, len(data), headers)
            return self.wfile.write(data)
        super().handle_api()
