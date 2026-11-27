"""Durable multipart uploads on the selected disk."""

import hashlib
import hmac
import os
import re
import shutil
import sqlite3
import stat
import tempfile
import threading
import uuid
from contextlib import closing, contextmanager
from pathlib import Path

from .storage import (BUFFER, DIGEST, TransferError, attributes, checked_file,
                      directory_id, file_info, hash_file, name_ok, parts)


MIB = 1024 * 1024
MAX_FILE = 1024 ** 4
REQUEST_ID = re.compile(r"[a-f0-9]{32}\Z")


class Journal:
    def __init__(self, state, folders):
        state.mkdir(parents=True, exist_ok=True)
        directory_id(state)
        self.database = state / "transfers.sqlite"
        self.folders = folders
        self.locks = tuple(threading.RLock() for _ in range(64))
        self.allocation = threading.Lock()
        with self.db() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript("""
                CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS devices (
                    device TEXT PRIMARY KEY, hash TEXT NOT NULL UNIQUE,
                    scopes TEXT NOT NULL, expires INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS uploads (
                    id TEXT PRIMARY KEY, request TEXT NOT NULL UNIQUE, owner TEXT NOT NULL,
                    source TEXT NOT NULL, folder TEXT NOT NULL, name TEXT NOT NULL,
                    size INTEGER NOT NULL, sha TEXT NOT NULL, chunk INTEGER NOT NULL,
                    binding TEXT NOT NULL, volume TEXT NOT NULL, auto INTEGER NOT NULL,
                    phase TEXT NOT NULL DEFAULT 'open', final_name TEXT,
                    stage_dev INTEGER, stage_ino TEXT,
                    auto_finish INTEGER NOT NULL DEFAULT 0);
                CREATE TABLE IF NOT EXISTS parts (
                    upload TEXT NOT NULL REFERENCES uploads(id), number INTEGER NOT NULL,
                    size INTEGER NOT NULL, sha TEXT NOT NULL, PRIMARY KEY(upload, number));
                CREATE INDEX IF NOT EXISTS upload_content ON uploads(binding, size, sha, phase);
            """)
            if "auto_finish" not in {row[1] for row in db.execute("PRAGMA table_info(uploads)")}:
                db.execute("ALTER TABLE uploads ADD COLUMN auto_finish INTEGER NOT NULL DEFAULT 0")
            db.execute("INSERT OR IGNORE INTO meta VALUES ('server_id', ?)", (uuid.uuid4().hex,))
            self.server_id = db.execute("SELECT value FROM meta WHERE key='server_id'").fetchone()[0]

    @contextmanager
    def db(self):
        with closing(sqlite3.connect(self.database, timeout=15)) as db:
            db.row_factory = sqlite3.Row
            db.execute("PRAGMA synchronous=FULL")
            db.execute("PRAGMA foreign_keys=ON")
            with db:
                yield db

    def record(self, upload):
        if not REQUEST_ID.fullmatch(upload):
            raise TransferError(404, "upload-unavailable")
        with self.db() as db:
            item = db.execute("SELECT * FROM uploads WHERE id=?", (upload,)).fetchone()
        if item is None:
            raise TransferError(404, "upload-unavailable")
        return item

    def describe(self, item):
        with self.db() as db:
            records = db.execute("SELECT number,size FROM parts WHERE upload=? ORDER BY number", (item["id"],)).fetchall()
        complete = item["phase"] == "complete"
        return {"id": item["id"], "size": item["size"], "partSize": item["chunk"],
                "parts": [part["number"] for part in records], "complete": complete,
                "received": item["size"] if complete else sum(part["size"] for part in records),
                "name": item["final_name"] if complete else None}

    def bound(self, item):
        folder = self.folders(item["source"], item["folder"])
        if folder.identity != item["binding"]:
            raise TransferError(409, "destination-changed")
        return folder

    def stage(self, folder, transfer):
        directory_id(folder.staging.parent)
        folder.staging.mkdir(exist_ok=True)
        directory_id(folder.staging)
        return folder.staging / (transfer + ".partial")

    def lock(self, upload):
        return self.locks[int(upload[:8], 16) % len(self.locks)]

    def matching_file(self, folder, name, size, sha):
        # Old versions named collisions with a hex prefix. Scope the import to
        # the selected destination and check content before marking anything done.
        with os.scandir(folder.path) as entries:
            for entry in entries:
                expected = name.casefold()
                candidate = entry.name.casefold()
                if candidate != expected and not candidate.endswith("-" + expected):
                    continue
                info = entry.stat(follow_symlinks=False)
                if stat.S_ISREG(info.st_mode) and info.st_size == size and not getattr(info, "st_file_attributes", 0) & 0x400:
                    if hash_file(Path(entry.path)) == sha:
                        return entry.name
        return None

    def create(self, body, owner):
        fields = {"requestId", "source", "folder", "name", "size", "sha256", "partSize", "automatic"}
        if not isinstance(body, dict) or not fields <= set(body) <= fields | {"autoFinish"}:
            raise TransferError(400, "invalid-upload")
        request, source, path, name, size, sha, chunk, automatic = (body[key] for key in
            ("requestId", "source", "folder", "name", "size", "sha256", "partSize", "automatic"))
        if (not isinstance(request, str) or not REQUEST_ID.fullmatch(request)
            or not isinstance(source, str) or not name_ok(name)
            or type(size) is not int or not 0 <= size <= MAX_FILE or type(automatic) is not bool
            or not isinstance(sha, str) or (not DIGEST.fullmatch(sha) and (automatic or sha != ""))
            or type(chunk) is not int or not MIB <= chunk <= 64 * MIB
            or (size + chunk - 1) // chunk > 32768):
            raise TransferError(400, "invalid-upload")
        auto_finish = body.get("autoFinish", False)
        if type(auto_finish) is not bool:
            raise TransferError(400, "invalid-upload")
        parts(path)
        result = self.reserve(request, source, path, name, size, sha, chunk, automatic, auto_finish, owner)
        return self.maybe_finalize(result["id"])

    def reserve(self, request, source, path, name, size, sha, chunk, automatic, auto_finish, owner):
        with self.allocation:
            with self.db() as db:
                old = db.execute("SELECT * FROM uploads WHERE request=?", (request,)).fetchone()
                if old is not None:
                    expected = (source, path, name, size, chunk, int(automatic))
                    if old["owner"] != owner:
                        raise TransferError(404, "upload-unavailable")
                    if (tuple(old[key] for key in ("source", "folder", "name", "size", "chunk", "auto")) != expected
                        or (sha and old["sha"] != sha)):
                        raise TransferError(409, "request-conflict")
                    if auto_finish and not old["auto_finish"]:
                        db.execute("UPDATE uploads SET auto_finish=1 WHERE id=?", (old["id"],))
                    return self.describe(old)
                folder = self.folders(source, path, prepare=True)
                final_name = None
                if automatic:
                    existing = db.execute("""SELECT * FROM uploads WHERE binding=? AND size=? AND sha=?
                                             AND auto=1 AND owner=? ORDER BY phase LIMIT 1""",
                                          (folder.identity, size, sha, owner)).fetchone()
                    if existing is not None:
                        if auto_finish and not existing["auto_finish"]:
                            db.execute("UPDATE uploads SET auto_finish=1 WHERE id=?", (existing["id"],))
                        return self.describe(existing)
                    final_name = self.matching_file(folder, name, size, sha)
                if final_name is None:
                    pending, reserved = db.execute("""
                        SELECT COUNT(*), COALESCE(SUM(u.size - COALESCE(
                            (SELECT SUM(size) FROM parts WHERE upload=u.id), 0)), 0)
                        FROM uploads u WHERE volume=? AND phase!='complete'
                    """, (folder.volume,)).fetchone()
                    if pending >= 96:
                        raise TransferError(429, "capacity")
                    if shutil.disk_usage(folder.path).free < size + reserved + 64 * MIB:
                        raise TransferError(507, "no-space")
                transfer = uuid.uuid4().hex
                db.execute("""INSERT INTO uploads(id,request,owner,source,folder,name,size,sha,chunk,binding,volume,auto,phase,final_name,auto_finish)
                              VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                           (transfer, request, owner, source, path, name, size, sha, chunk, folder.identity,
                            folder.volume, int(automatic), "complete" if final_name else "open", final_name, int(auto_finish)))
            return self.describe(self.record(transfer))

    def received_part(self, upload, number, length, sha):
        with self.db() as db:
            old = db.execute("SELECT size,sha FROM parts WHERE upload=? AND number=?", (upload, number)).fetchone()
        if old is None:
            return None
        if tuple(old) != (length, sha):
            raise TransferError(409, "part-conflict")
        return self.maybe_finalize(upload)

    def put(self, upload, number, length, sha, stream):
        if not isinstance(sha, str) or not DIGEST.fullmatch(sha):
            raise TransferError(400, "invalid-checksum")
        item = self.record(upload)
        start = number * item["chunk"]
        if not 0 <= start < item["size"] or length != min(item["chunk"], item["size"] - start):
            raise TransferError(400, "invalid-part")
        saved = self.received_part(upload, number, length, sha)
        if saved is not None:
            return saved
        if item["phase"] != "open":
            raise TransferError(409, "already-finished")

        staging = self.stage(self.bound(item), upload).parent
        # Drain each request independently. A waiting part can otherwise stall
        # another stream when both uploads share one connection.
        with tempfile.TemporaryFile(dir=staging) as incoming:
            digest = hashlib.sha256()
            remaining = length
            while remaining:
                data = stream.read(min(BUFFER, remaining))
                if not data:
                    raise TransferError(400, "incomplete-part")
                digest.update(data)
                incoming.write(data)
                remaining -= len(data)
            if not hmac.compare_digest(digest.hexdigest(), sha):
                raise TransferError(422, "checksum-mismatch")
            incoming.seek(0)

            with self.lock(upload):
                saved = self.received_part(upload, number, length, sha)
                if saved is not None:
                    return saved
                item = self.record(upload)
                if item["phase"] != "open":
                    raise TransferError(409, "already-finished")
                folder = self.bound(item)
                stage = self.stage(folder, upload)
                if attributes(stage) is None:
                    if item["stage_ino"] is not None:
                        raise TransferError(409, "staging-missing")
                    with stage.open("xb"):
                        pass
                info = file_info(stage)
                stage_id = (info.st_dev, str(info.st_ino))
                if item["stage_ino"] is not None and stage_id != (item["stage_dev"], item["stage_ino"]):
                    raise TransferError(409, "staging-changed")
                with self.db() as db:
                    db.execute("UPDATE uploads SET stage_dev=?,stage_ino=? WHERE id=?", (*stage_id, upload))
                with checked_file(stage, "r+b") as output:
                    output.seek(start)
                    shutil.copyfileobj(incoming, output, BUFFER)
                    output.flush()
                    os.fsync(output.fileno())
                self.bound(item)
                with self.db() as db:
                    db.execute("INSERT INTO parts VALUES (?,?,?,?)", (upload, number, length, sha))
                return self.maybe_finalize(upload)

    def maybe_finalize(self, upload):
        with self.lock(upload):
            item = self.record(upload)
            result = self.describe(item)
            if item["auto_finish"] and not result["complete"] and result["received"] == item["size"]:
                return self.finalize(upload)
            return result

    def finalize(self, upload):
        with self.lock(upload):
            item = self.record(upload)
            result = self.describe(item)
            if result["complete"]:
                return result
            if result["received"] != item["size"]:
                raise TransferError(409, "upload-incomplete")
            folder = self.bound(item)
            stage = self.stage(folder, upload)
            if item["phase"] == "open":
                if item["size"] == 0 and attributes(stage) is None:
                    with stage.open("xb") as empty:
                        os.fsync(empty.fileno())
                info = file_info(stage)
                if item["stage_ino"] is not None and (info.st_dev, str(info.st_ino)) != (item["stage_dev"], item["stage_ino"]):
                    raise TransferError(409, "staging-changed")
                digest = hash_file(stage) if item["sha"] else self.verify_parts(stage, upload)
                if info.st_size != item["size"] or (item["sha"] and digest != item["sha"]):
                    raise TransferError(422, "checksum-mismatch")
                final_name = item["name"]
                if attributes(folder.path / final_name) is not None:
                    suffix = Path(final_name).suffix
                    final_name = f"{Path(final_name).stem[:175]}-{upload}{suffix[:25]}"
                with self.db() as db:
                    db.execute("UPDATE uploads SET phase='publishing',final_name=?,stage_dev=?,stage_ino=?,sha=? WHERE id=?",
                               (final_name, info.st_dev, str(info.st_ino), digest, upload))
                item = self.record(upload)
            self.bound(item)
            final = folder.path / item["final_name"]
            info = attributes(stage)
            if info is not None:
                if (info.st_dev, str(info.st_ino), info.st_size) != (item["stage_dev"], item["stage_ino"], item["size"]):
                    raise TransferError(409, "staging-changed")
                try:
                    if os.name == "nt":
                        stage.rename(final)  # Windows rename fails if the destination exists.
                    else:
                        os.link(stage, final)
                        stage.unlink()
                except FileExistsError as error:
                    existing = file_info(final)
                    if (existing.st_dev, str(existing.st_ino)) != (item["stage_dev"], item["stage_ino"]):
                        raise TransferError(409, "name-conflict") from error
                    # Recovery after linking the same inode and before unlink on POSIX.
                    stage.unlink()
            else:
                # A previous attempt may have published and crashed before recording the result.
                info = file_info(final)
                if (info.st_dev, str(info.st_ino), info.st_size) != (item["stage_dev"], item["stage_ino"], item["size"]) or hash_file(final) != item["sha"]:
                    raise TransferError(409, "publication-changed")
            with self.db() as db:
                db.execute("UPDATE uploads SET phase='complete' WHERE id=?", (upload,))
            return self.describe(self.record(upload))

    def verify_parts(self, stage, upload):
        with self.db() as db:
            expected = db.execute("SELECT size,sha FROM parts WHERE upload=? ORDER BY number", (upload,)).fetchall()
        result = hashlib.sha256()
        with checked_file(stage) as stream:
            for size, sha in expected:
                part = hashlib.sha256()
                while size:
                    block = stream.read(min(BUFFER,size))
                    if not block:
                        raise TransferError(422, "checksum-mismatch")
                    part.update(block)
                    result.update(block)
                    size -= len(block)
                if part.hexdigest() != sha:
                    raise TransferError(422, "checksum-mismatch")
        return result.hexdigest()
