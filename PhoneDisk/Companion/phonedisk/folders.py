import json
import os
import stat
import uuid
from pathlib import Path

from .storage import Folder, TransferError, attributes, directory_id, file_info, name_ok, parts


BACKUP_PATHS = {"photo": "/Фото", "video": "/Видео"}
MEDIA = {
    ".mp4": "video/mp4", ".m4v": "video/mp4", ".mov": "video/quicktime", ".webm": "video/webm",
    ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".gif": "image/gif", ".webp": "image/webp",
}
VIDEO = {ext for ext, mime in MEDIA.items() if mime.startswith("video/")} | {
    ".avi", ".mts", ".m2ts", ".mkv", ".mpg", ".mpeg", ".wmv",
}


class SharedFolders:
    def __init__(self, state):
        self.config = state / "folders.json"

    def records(self):
        if not self.config.exists():
            return {}
        return json.loads(self.config.read_text(encoding="utf-8"))

    def save(self, records):
        temporary = self.config.with_suffix(".tmp")
        temporary.write_text(json.dumps(records, ensure_ascii=False), encoding="utf-8")
        os.replace(temporary, self.config)

    def add(self, value, backup):
        path = Path(value)
        if not path.is_absolute() or ".." in path.parts or (os.name == "nt" and len(path.drive) != 2):
            raise TransferError(400, "invalid-folder")
        volume, inode = directory_id(path)
        records = self.records()
        for key, record in records.items():
            if record["backup"] == backup and os.path.normcase(record["path"]) == os.path.normcase(str(path)):
                if (volume, inode) == (record["volume"], record["inode"]):
                    return key
                break
        key = "folder-" + uuid.uuid4().hex
        # A changed directory gets a new ID so an old job can't write to it.
        records[key] = {"name": path.name or path.anchor, "path": str(path), "backup": backup,
                        "volume": volume, "inode": inode}
        if backup:
            records = {k: v for k, v in records.items() if not v["backup"] or k == key}
        self.save(records)
        return key

    def remove(self, source):
        records = self.records()
        if source in records:
            records.pop(source)
            self.save(records)

    def roots(self, scopes):
        result = []
        for source, record in self.records().items():
            permissions = scopes.get(source, [])
            if "view" not in permissions:
                continue
            try:
                self(source, "/")
                available = True
            except (OSError, TransferError):
                available = False
            result.append({"source": source, "name": record["name"], "available": available,
                           "permissions": permissions})
        return result

    def __call__(self, source, folder, prepare=False):
        relative = parts(folder)
        record = self.records().get(source)
        if record is None:
            raise TransferError(404, "unknown-source")
        base = Path(record["path"])
        if directory_id(base) != (record["volume"], record["inode"]):
            raise TransferError(409, "folder-changed")
        parent = base.joinpath(*relative)
        if record["backup"] and prepare and folder in BACKUP_PATHS.values():
            parent.mkdir(exist_ok=True)
        dev, inode = directory_id(parent)
        binding = json.dumps([dev, inode, str(parent).casefold()], separators=(",", ":"))
        return Folder(parent, base / ".phone-disk-v2", str(dev), binding)

    def file(self, source, relative):
        location = parts(relative)
        if not location:
            raise TransferError(400, "invalid-file")
        return self(source, "/" + "/".join(location[:-1])).path / location[-1]

    def list(self, source, relative):
        folder = self(source, relative).path
        entries = []
        with os.scandir(folder) as children:
            for child in children:
                if not name_ok(child.name):
                    continue
                try:
                    info = attributes(Path(child.path))
                except (OSError, TransferError):
                    continue
                if info is None or not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)):
                    continue
                is_folder = stat.S_ISDIR(info.st_mode)
                extension = Path(child.name).suffix.lower()
                media = "video" if extension in VIDEO else "image" if MEDIA.get(extension, "").startswith("image/") else None
                entries.append({"name": child.name, "path": relative.rstrip("/") + "/" + child.name,
                                "directory": is_folder, "size": None if is_folder else info.st_size,
                                "media": None if is_folder else media,
                                "playable": not is_folder and extension in MEDIA})
        return sorted(entries, key=lambda item: (not item["directory"], item["name"].casefold()))

    def trash(self, source, relative):
        path = self.file(source, relative)
        file_info(path)
        trash = self(source, "/").path / ".phone-disk-trash"
        trash.mkdir(exist_ok=True)
        directory_id(trash)
        # Retain the original name and contents on the same volume.
        record = trash / uuid.uuid4().hex
        record.mkdir()
        os.rename(path, record / path.name)
