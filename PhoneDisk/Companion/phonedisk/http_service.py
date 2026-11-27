"""Resumable transfer protocol used by the Windows companion."""

import hashlib
import json
import logging
import re
import socket
import threading
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl, urlsplit

from .storage import BUFFER, TransferError, checked_file, file_info, hash_file, version

TOKEN = re.compile(r"[A-Za-z0-9_-]{43}\Z")
UPLOAD = re.compile(r"/api/v2/uploads/([a-f0-9]{32})(?:(/finish)|/parts/([0-9]{1,5}))?\Z")
RANGE = re.compile(r"bytes=([0-9]{0,19})-([0-9]{0,19})\Z")
MAX_JSON = 8192
LOG = logging.getLogger("phone-disk.transfers")


def json_unique(values):
    result = dict(values)
    if len(result) != len(values):
        raise ValueError("Duplicate keys")
    return result


def token_hash(token):
    return hashlib.sha256(token.encode("ascii")).hexdigest()


class TransferServer(ThreadingHTTPServer):
    daemon_threads = True
    # Let a burst of range requests reach the existing 24-request admission limit.
    request_queue_size = 32

    def __init__(self, address, journal, access, handler):
        self.journal = journal
        self.access = access
        self.slots = threading.BoundedSemaphore(24)
        self.hash_cache = OrderedDict()
        self.hash_lock = threading.Lock()
        super().__init__(address, handler)

    def file_hash(self, path, info):
        key = version(info)
        with self.hash_lock:
            digest = self.hash_cache.get(key)
            if digest:
                self.hash_cache.move_to_end(key)
                return digest
        digest = hash_file(path)
        if version(file_info(path)) != key:
            raise TransferError(409, "file-changed")
        with self.hash_lock:
            self.hash_cache[key] = digest
            if len(self.hash_cache) > 1024:
                self.hash_cache.popitem(last=False)
        return digest


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "PhoneDisk"
    timeout = 30

    def log_message(self, *_):
        pass

    def handle(self):
        try:
            super().handle()
        except ConnectionError:
            self.close_connection = True

    def respond(self, status, length, extra=None):
        self.send_response(status)
        self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "private, no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        if self.close_connection:
            self.send_header("Connection", "close")
        self.end_headers()

    def reply(self, status, payload):
        raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        self.respond(status, len(raw), {"Content-Type": "application/json"})
        if self.command != "HEAD":
            self.wfile.write(raw)

    def read(self, count):
        data = self.rfile.read(min(count, self.pending_part))
        self.pending_part -= len(data)
        return data

    def drain_part(self):
        while self.pending_part and self.read(BUFFER):
            pass

    def reject(self, status, code):
        self.close_connection = True
        try:
            self.drain_part()
            self.reply(status, {"error": code})
        except (ConnectionError, socket.timeout):
            pass

    def length(self, maximum):
        headers = self.headers.get_all("Content-Length") or []
        if len(headers) != 1 or self.headers.get("Transfer-Encoding") or not re.fullmatch(r"[0-9]{1,12}", headers[0]):
            raise TransferError(411, "invalid-length")
        length = int(headers[0])
        if length > maximum:
            raise TransferError(413, "request-too-large")
        return length

    def body(self):
        if self.headers.get_content_type() != "application/json":
            raise TransferError(415, "invalid-type")
        try:
            return json.loads(self.rfile.read(self.length(MAX_JSON)), object_pairs_hook=json_unique)
        except (ValueError, UnicodeError) as error:
            raise TransferError(400, "invalid-json") from error

    def file(self, query):
        source, relative = location_query(query)
        self.server.access.check(self, source, "download")
        path = self.server.journal.folders.file(source, relative)
        info = file_info(path)
        self.stream_file(path, info, self.server.file_hash(path, info))

    def stream_file(self, path, info, digest, content_type="application/octet-stream", *, checksum=True):
        etag = '"' + digest + '"'
        total = info.st_size
        start, end, status = 0, total - 1, 200
        headers = {"Content-Type": content_type, "Accept-Ranges": "bytes", "ETag": etag}
        if checksum:
            headers.update({"X-File-SHA256": digest, "X-File-Size": str(total)})
        selector = self.headers.get("Range")
        if selector and self.headers.get("If-Range", etag) == etag:
            match = RANGE.fullmatch(selector)
            if match and (match[1] or match[2]):
                if match[1]:
                    start = int(match[1])
                    end = min(end, int(match[2])) if match[2] else end
                else:
                    start = max(0, total - int(match[2]))
            if not match or not (match[1] or match[2]) or start > end:
                return self.respond(416, 0, {**headers, "Content-Range": f"bytes */{total}"})
            status = 206
            headers["Content-Range"] = f"bytes {start}-{end}/{total}"
        with checked_file(path) as stream:
            if version(info) != version(file_info(path)):
                raise TransferError(409, "file-changed")
            remain = end - start + 1
            self.respond(status, remain, headers)
            if self.command == "GET":
                stream.seek(start)
                while remain:
                    block = stream.read(min(BUFFER, remain))
                    if not block:
                        self.close_connection = True
                        break
                    self.wfile.write(block)
                    remain -= len(block)

    def handle_api(self):
        method = self.command
        parsed = urlsplit(self.path)
        route = parsed.path
        access = self.server.access
        journal = self.server.journal
        if route == "/api/v2/file" and method in ("GET", "HEAD"):
            return self.file(parsed.query)
        if route == "/api/v2/uploads" and method == "POST":
            body = self.body()
            device = access.check_upload(self, body)
            return self.reply(200, journal.create(body, owner=device))
        match = UPLOAD.fullmatch(route)
        if match:
            transfer, finish, part = match.groups()
            entry = journal.record(transfer)
            device = access.check(self, entry["source"], "create")
            if entry["owner"] != device:
                raise TransferError(404, "upload-unavailable")
            if method == "GET" and not finish and part is None:
                return self.reply(200, journal.maybe_finalize(transfer))
            if method == "POST" and finish:
                if self.length(0):
                    raise TransferError(400, "unexpected-body")
                return self.reply(200, journal.finalize(transfer))
            if method == "PUT" and part is not None:
                length = self.length(entry["chunk"])
                self.pending_part = length
                result = journal.put(transfer, int(part), self.pending_part, self.headers.get("X-Part-SHA256"), self)
                self.drain_part()
                access.check(self, entry["source"], "create")
                return self.reply(200, result)
        raise TransferError(404, "unknown-route")

    def dispatch(self):
        self.pending_part = 0
        if not self.server.slots.acquire(blocking=False):
            self.close_connection = True
            return self.reply(429, {"error": "busy"})
        try:
            self.handle_api()
        except (BrokenPipeError, ConnectionError, socket.timeout):
            self.close_connection = True
        except TransferError as error:
            self.reject(error.status, error.code)
        except ValueError:
            self.reject(400, "invalid-request")
        except OSError as error:
            LOG.warning("I/O failure, errno=%s", error.errno)
            self.reject(507 if error.errno == 28 else 503, "disk-io")
        finally:
            self.server.slots.release()

    do_GET = do_HEAD = do_POST = do_PUT = do_DELETE = dispatch


def location_query(query):
    values = parse_qsl(query, keep_blank_values=True, strict_parsing=True, max_num_fields=2)
    location = dict(values)
    if len(values) != 2 or location.keys() != {"source", "path"}:
        raise TransferError(400, "invalid-path")
    return location["source"], location["path"]
