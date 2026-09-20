import hashlib
import re
from dataclasses import dataclass
from pathlib import PurePath

from fastapi import HTTPException, UploadFile, status

from app.core.config import settings

SAFE_EXTENSION = re.compile(r"^\.[a-z0-9]{1,8}$")
BLOCKED_EXTENSIONS = {
    ".bat",
    ".cmd",
    ".com",
    ".dll",
    ".exe",
    ".js",
    ".msi",
    ".ps1",
    ".scr",
    ".vbs",
    ".zip",
}
BLOCKED_SIGNATURES = (
    b"MZ",
    b"PK\x03\x04",
    b"\x7fELF",
    b"#!",
)
ALLOWED_MIME_TYPES = {
    "application/json",
    "application/octet-stream",
    "application/xml",
    "text/plain",
    "text/xml",
}


@dataclass(frozen=True)
class ValidatedConnectorFile:
    data: bytes
    source_filename: str
    file_extension: str
    mime_type: str
    content_sha256: str


async def read_validated_connector_file(file: UploadFile) -> ValidatedConnectorFile:
    source_filename = PurePath((file.filename or "").replace("\\", "/")).name
    if not source_filename or len(source_filename) > 180:
        raise HTTPException(status_code=422, detail="Connector filename is invalid")

    extension = PurePath(source_filename).suffix.lower()
    if not SAFE_EXTENSION.fullmatch(extension) or extension in BLOCKED_EXTENSIONS:
        raise HTTPException(status_code=415, detail="Unsupported connector file extension")

    mime_type = (file.content_type or "application/octet-stream").lower()
    if mime_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(status_code=415, detail="Unsupported connector file MIME type")

    data = await file.read(settings.max_connector_file_bytes + 1)
    if not data:
        raise HTTPException(status_code=422, detail="Connector file is empty")
    if len(data) > settings.max_connector_file_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="Connector file is too large",
        )
    if any(data.startswith(signature) for signature in BLOCKED_SIGNATURES):
        raise HTTPException(status_code=415, detail="Executable or archived files are not accepted")

    return ValidatedConnectorFile(
        data=data,
        source_filename=source_filename,
        file_extension=extension,
        mime_type=mime_type,
        content_sha256=hashlib.sha256(data).hexdigest(),
    )
