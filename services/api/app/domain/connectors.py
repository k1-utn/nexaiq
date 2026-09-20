from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class ConnectorDeviceRegistration(BaseModel):
    device_identifier: UUID
    location_id: UUID
    device_name: str = Field(min_length=1, max_length=120)
    connector_version: str = Field(min_length=1, max_length=40)
    watch_path_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")


class ConnectorDeviceRegistrationResult(BaseModel):
    connector_device_id: UUID
    device_status: Literal["active"]


class ConnectorFileProvenance(BaseModel):
    source_filename: str
    file_extension: str
    mime_type: str
    byte_size: int
    content_sha256: str
    discovered_at: datetime


class ConnectorFileSyncResult(BaseModel):
    organization_id: UUID
    location_id: UUID
    connector_device_id: UUID
    connector_sync_batch_id: UUID
    connector_sync_file_id: UUID
    client_batch_id: UUID
    client_file_id: UUID
    provenance: ConnectorFileProvenance
    persistence_status: Literal["persisted", "already_persisted"]
    parse_status: Literal["awaiting_format_validation"] = "awaiting_format_validation"
