"""File and volume checks shared by the transfer service and Windows adapter."""

import hashlib
import json
import os
import re
import stat
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path


BUFFER = 1024 * 1024
REPARSE = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
DIGEST = re.compile(r"[a-f0-9]{64}\Z")
WINDOWS_NAME = re.compile(r"(?:con|prn|aux|nul|com[1-9¹²³]|lpt[1-9¹²³])(?:\.|$)", re.I)
FORBIDDEN = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


class TransferError(Exception):
    def __init__(self, status, code):
        super().__init__(code)
        self.status = status
        self.code = code


def name_ok(name):
    return (isinstance(name, str) and 0 < len(name) <= 240 and name == name.strip()
            and not name.endswith(".") and not name.lower().startswith(".phone-disk-")
            and not WINDOWS_NAME.match(name) and not FORBIDDEN.search(name))


def parts(path):
    if not isinstance(path, str) or not path.startswith("/") or len(path) > 1500:
        raise TransferError(400, "invalid-path")
    names = path[1:].split("/") if path != "/" else []
    if any(not name_ok(name) for name in names):
        raise TransferError(400, "invalid-path")
    return names


def attributes(path):
    try:
        info = path.lstat()
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & REPARSE:
        raise TransferError(409, "unsafe-path")
    return info


def directory_id(path):
    result = None
    for component in (*reversed(path.parents), path):
        info = attributes(component)
        if info is None or not stat.S_ISDIR(info.st_mode):
            raise TransferError(404, "folder-unavailable")
        result = (info.st_dev, info.st_ino)
    return result


def file_info(path):
    info = attributes(path)
    if info is None or not stat.S_ISREG(info.st_mode):
        raise TransferError(404, "file-unavailable")
    return info


def version(info):
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns


@contextmanager
def checked_file(path, mode="rb"):
    before = file_info(path)
    with path.open(mode, buffering=BUFFER) as stream:
        if version(os.fstat(stream.fileno())) != version(before):
            raise TransferError(409, "file-changed")
        yield stream


def hash_file(path):
    with checked_file(path) as stream:
        before = version(os.fstat(stream.fileno()))
        digest = hashlib.sha256()
        buffer = bytearray(BUFFER)
        view = memoryview(buffer)
        for count in iter(lambda: stream.readinto(buffer), 0):
            digest.update(view[:count])
        if version(os.fstat(stream.fileno())) != before or version(file_info(path)) != before:
            raise TransferError(409, "file-changed")
        return digest.hexdigest()


@dataclass(frozen=True)
class Folder:
    path: Path
    staging: Path
    volume: str
    identity: str
