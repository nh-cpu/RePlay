"""Owned output directories, atomic artifacts, and content-addressed stages."""

import hashlib
import json
import os
from contextlib import contextmanager
from pathlib import Path


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def json_bytes(value) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode()


def stage_key(stage: str, inputs) -> str:
    # Versions belong to individual stages so chart edits never invalidate music.
    return digest(json_bytes({"cache_format": 2, "stage": stage, "inputs": inputs}))


class Store:
    def __init__(self, root: Path):
        self.root = root.resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.manifest = self.root / ".afterimage.json"
        if self.manifest.exists():
            self.data = json.loads(self.manifest.read_text(encoding="utf-8"))
            if self.data.get("owner") != "afterimage-levelgen":
                raise ValueError("Output directory has an unknown owner; choose an empty folder")
        else:
            if any(self.root.iterdir()):
                raise ValueError("Output must be empty or already owned by afterimage-levelgen")
            self.data = {"owner": "afterimage-levelgen", "files": {}, "stages": {}}
            self._save()

    def _atomic(self, path: Path, data: bytes):
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name(path.name + ".tmp")
        with temporary.open("xb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(path)

    def _save(self):
        self._atomic(self.manifest, json_bytes(self.data))

    @contextmanager
    def lock(self):
        path = self.root / ".running"
        try:
            with path.open("x") as stream:
                stream.write(str(os.getpid()))
        except FileExistsError:
            raise ValueError("Output is locked. If the previous process stopped, remove .running and retry") from None
        try:
            self.verify()
            yield self
        finally:
            path.unlink(missing_ok=True)

    def verify(self):
        for name, expected in self.data["files"].items():
            path = self.root / name
            if path.is_symlink() or (path.exists() and digest(path.read_bytes()) != expected):
                raise ValueError(f"Refusing to overwrite modified artifact: {name}; use a new output folder")

    def write(self, name: str, data: bytes):
        path = self.root / name
        if path.resolve().parent != self.root:
            raise ValueError("Artifacts must be direct children of the output directory")
        if path.exists():
            expected = self.data["files"].get(name)
            if path.is_symlink() or expected != digest(path.read_bytes()):
                raise ValueError(f"Refusing to overwrite unrelated or modified file: {name}")
        self._atomic(path, data)
        self.data["files"][name] = digest(data)
        self._save()

    def write_json(self, name: str, value):
        self.write(name, json_bytes(value))

    def cached(self, stage: str, key: str, name: str) -> bool:
        path = self.root / name
        return (self.data["stages"].get(stage) == key and path.is_file()
                and self.data["files"].get(name) == digest(path.read_bytes()))

    def commit(self, stage: str, key: str):
        self.data["stages"][stage] = key
        self._save()

    def read_json(self, name: str):
        return json.loads((self.root / name).read_text(encoding="utf-8"))
