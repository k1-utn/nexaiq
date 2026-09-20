from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.core.auth import RequestContext, require_request_context
from app.domain.connectors import (
    ConnectorDeviceRegistration,
    ConnectorDeviceRegistrationResult,
    ConnectorFileProvenance,
    ConnectorFileSyncResult,
)
from app.services.connector_validator import read_validated_connector_file
from app.services.supabase_gateway import SupabaseGateway

router = APIRouter(tags=["Windows EMS connector"])


@router.post("/devices/register", response_model=ConnectorDeviceRegistrationResult)
async def register_device(
    registration: ConnectorDeviceRegistration,
    context: Annotated[RequestContext, Depends(require_request_context)],
) -> ConnectorDeviceRegistrationResult:
    registered = await SupabaseGateway().register_connector_device(
        context=context,
        registration=registration,
    )
    return ConnectorDeviceRegistrationResult(
        connector_device_id=registered.connector_device_id,
        device_status="active",
    )


@router.post("/files", response_model=ConnectorFileSyncResult)
async def upload_ems_file(
    file: Annotated[UploadFile, File(description="Unmodified authorized EMS export file")],
    location_id: Annotated[UUID, Form()],
    device_identifier: Annotated[UUID, Form()],
    client_batch_id: Annotated[UUID, Form()],
    client_file_id: Annotated[UUID, Form()],
    connector_version: Annotated[str, Form(min_length=1, max_length=40)],
    discovered_at: Annotated[datetime, Form()],
    context: Annotated[RequestContext, Depends(require_request_context)],
) -> ConnectorFileSyncResult:
    validated = await read_validated_connector_file(file)
    persisted = await SupabaseGateway().persist_connector_file(
        context=context,
        location_id=location_id,
        device_identifier=device_identifier,
        client_batch_id=client_batch_id,
        client_file_id=client_file_id,
        connector_version=connector_version,
        discovered_at=discovered_at,
        connector_file=validated,
    )
    return ConnectorFileSyncResult(
        organization_id=context.organization_id,
        location_id=location_id,
        connector_device_id=persisted.connector_device_id,
        connector_sync_batch_id=persisted.connector_sync_batch_id,
        connector_sync_file_id=persisted.connector_sync_file_id,
        client_batch_id=client_batch_id,
        client_file_id=client_file_id,
        provenance=ConnectorFileProvenance(
            source_filename=validated.source_filename,
            file_extension=validated.file_extension,
            mime_type=validated.mime_type,
            byte_size=len(validated.data),
            content_sha256=validated.content_sha256,
            discovered_at=discovered_at,
        ),
        persistence_status=(
            "already_persisted" if persisted.already_persisted else "persisted"
        ),
    )
