import os
import uuid
from abc import ABC, abstractmethod
from pathlib import Path

from fastapi import HTTPException, UploadFile

ALLOWED_TYPES = {
    ".pdf": ("application/pdf", b"%PDF"),
    ".txt": ("text/plain", None),
    ".png": ("image/png", b"\x89PNG\r\n\x1a\n"),
    ".jpg": ("image/jpeg", b"\xff\xd8\xff"),
    ".jpeg": ("image/jpeg", b"\xff\xd8\xff"),
}
MAX_FILE_SIZE = 10 * 1024 * 1024


class StorageAdapter(ABC):
    @abstractmethod
    def save(self, stored_name: str, content: bytes) -> None: ...

    @abstractmethod
    def read(self, stored_name: str) -> bytes: ...

    @abstractmethod
    def delete(self, stored_name: str) -> None: ...

    @abstractmethod
    def exists(self, stored_name: str) -> bool: ...


class LocalStorageAdapter(StorageAdapter):
    def __init__(self, root: str | Path):
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, stored_name: str) -> Path:
        path = (self.root / stored_name).resolve()
        if self.root not in path.parents:
            raise ValueError("Invalid storage path")
        return path

    def save(self, stored_name: str, content: bytes) -> None:
        path = self._path(stored_name)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_bytes(content)
        os.replace(temporary, path)

    def read(self, stored_name: str) -> bytes:
        path = self._path(stored_name)
        if not path.is_file():
            raise FileNotFoundError(stored_name)
        return path.read_bytes()

    def delete(self, stored_name: str) -> None:
        self._path(stored_name).unlink(missing_ok=True)

    def exists(self, stored_name: str) -> bool:
        return self._path(stored_name).is_file()


def validate_upload(file: UploadFile, content: bytes) -> tuple[str, str]:
    original = file.filename or ""
    if not original or Path(original).name != original or "/" in original or "\\" in original:
        raise HTTPException(400, "Unsafe filename")
    suffix = Path(original).suffix.lower()
    if suffix not in ALLOWED_TYPES:
        raise HTTPException(415, "File extension is not allowed")
    expected_mime, magic = ALLOWED_TYPES[suffix]
    if file.content_type != expected_mime:
        raise HTTPException(415, "MIME type does not match extension")
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(413, "File is too large")
    if magic and not content.startswith(magic):
        raise HTTPException(415, "File signature does not match type")
    if not content:
        raise HTTPException(400, "Empty file")
    return original, f"{uuid.uuid4().hex}{suffix}"
