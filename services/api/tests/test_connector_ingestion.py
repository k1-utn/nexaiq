import asyncio
from datetime import UTC, datetime
from uuid import UUID

import pytest
from fastapi import HTTPException

from app.core.auth import RequestContext
from app.domain.connectors import ConnectorDeviceRegistration
from app.services import supabase_gateway as gateway_module
from app.services.connector_validator import read_validated_connector_file
from app.services.supabase_gateway import SupabaseGateway


class FakeUpload:
    def __init__(self, data: bytes, *, filename: str, content_type: str) -> None:
        self.data = data
        self.filename = filename
        self.content_type = content_type

    async def read(self, size: int) -> bytes:
        return self.data[:size]


def test_connector_file_validation_hashes_untrusted_ems_data() -> None:
    validated = asyncio.run(
        read_validated_connector_file(
            FakeUpload(  # type: ignore[arg-type]
                b"00\tTEST REPAIR ORDER\r\n01\t2025 TOYOTA RAV4\r\n",
                filename="sample.AD1",
                content_type="application/octet-stream",
            )
        )
    )

    assert validated.source_filename == "sample.AD1"
    assert validated.file_extension == ".ad1"
    assert len(validated.content_sha256) == 64


@pytest.mark.parametrize(
    ("filename", "data"),
    [
        ("malware.exe", b"MZpayload"),
        ("archive.zip", b"PK\x03\x04payload"),
        ("script.ps1", b"Write-Host unsafe"),
    ],
)
def test_connector_file_validation_rejects_executable_content(
    filename: str,
    data: bytes,
) -> None:
    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(
            read_validated_connector_file(
                FakeUpload(  # type: ignore[arg-type]
                    data,
                    filename=filename,
                    content_type="application/octet-stream",
                )
            )
        )
    assert exc_info.value.status_code == 415


class FakeResponse:
    def __init__(self, status_code: int, payload: object | None = None) -> None:
        self.status_code = status_code
        self.payload = payload

    def json(self) -> object:
        return self.payload


class FakeConnectorClient:
    registration_payload: dict[str, object] | None = None
    file_payloads: list[dict[str, object]] = []
    object_urls: list[str] = []

    async def __aenter__(self) -> "FakeConnectorClient":
        return self

    async def __aexit__(self, *args: object) -> None:
        return None

    async def post(self, url: str, **kwargs: object) -> FakeResponse:
        if "/storage/v1/object/" in url:
            type(self).object_urls.append(url)
            return FakeResponse(201)
        payload = kwargs["json"]
        assert isinstance(payload, dict)
        if url.endswith("/register_connector_device"):
            type(self).registration_payload = payload
            return FakeResponse(
                200,
                [{"connector_device_id": "00000000-0000-0000-0000-000000000030"}],
            )
        if url.endswith("/finalize_connector_ems_batch"):
            return FakeResponse(
                200,
                [
                    {
                        "import_status": "waiting_for_core_files",
                        "repair_order_id": None,
                        "estimate_version_id": None,
                    }
                ],
            )
        type(self).file_payloads.append(payload)
        return FakeResponse(
            200,
            [
                {
                    "connector_device_id": "00000000-0000-0000-0000-000000000030",
                    "connector_sync_batch_id": "00000000-0000-0000-0000-000000000031",
                    "connector_sync_file_id": "00000000-0000-0000-0000-000000000032",
                    "already_persisted": False,
                }
            ],
        )


def test_connector_registration_and_file_sync_keep_secret_server_side(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(gateway_module.settings, "supabase_url", "https://project.supabase.co")
    monkeypatch.setattr(gateway_module.settings, "supabase_secret_key", "sb_secret_test")
    monkeypatch.setattr(gateway_module.httpx, "AsyncClient", lambda **kwargs: FakeConnectorClient())
    FakeConnectorClient.registration_payload = None
    FakeConnectorClient.file_payloads = []
    FakeConnectorClient.object_urls = []
    context = RequestContext(
        organization_id=UUID("00000000-0000-0000-0000-000000000001"),
        actor_id=UUID("00000000-0000-0000-0000-000000000002"),
        authentication_context="supabase_verified_user",
        bearer_token="user-token",  # noqa: S106 - inert test value
    )
    device_identifier = UUID("00000000-0000-0000-0000-000000000010")
    location_id = UUID("00000000-0000-0000-0000-000000000011")
    batch_id = UUID("00000000-0000-0000-0000-000000000012")
    file_id = UUID("00000000-0000-0000-0000-000000000013")
    discovered_at = datetime.now(UTC)

    async def run_sync() -> None:
        gateway = SupabaseGateway()
        await gateway.register_connector_device(
            context=context,
            registration=ConnectorDeviceRegistration(
                device_identifier=device_identifier,
                location_id=location_id,
                device_name="Test workstation",
                connector_version="0.1.0",
                watch_path_sha256="a" * 64,
            ),
        )
        connector_file = await read_validated_connector_file(
            FakeUpload(  # type: ignore[arg-type]
                b"00\tTEST\r\n",
                filename="sample.ad1",
                content_type="application/octet-stream",
            )
        )
        await gateway.persist_connector_file(
            context=context,
            location_id=location_id,
            device_identifier=device_identifier,
            client_batch_id=batch_id,
            client_file_id=file_id,
            connector_version="0.1.0",
            discovered_at=discovered_at,
            connector_file=connector_file,
            parse_status="withheld_by_minimization",
            extracted_payload={"table": "ad1", "reason": "privacy_minimization"},
        )

    asyncio.run(run_sync())

    assert FakeConnectorClient.registration_payload is not None
    assert FakeConnectorClient.registration_payload["p_actor_id"] == str(context.actor_id)
    assert len(FakeConnectorClient.file_payloads) == 1
    payload = FakeConnectorClient.file_payloads[0]
    assert payload["p_client_file_id"] == str(file_id)
    assert payload["p_parse_status"] == "withheld_by_minimization"
    assert payload["p_extracted_payload"]["table"] == "ad1"
    assert payload["p_storage_object_path"].startswith(
        f"{context.organization_id}/{device_identifier}/{batch_id}/{file_id}/"
    )
    assert "user-token" not in str(payload)
