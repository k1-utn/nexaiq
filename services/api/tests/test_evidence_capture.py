import asyncio
from datetime import UTC, datetime
from uuid import UUID

import pytest
from fastapi import HTTPException

from app.core.auth import RequestContext
from app.services import supabase_gateway as gateway_module
from app.services.evidence_validator import read_validated_capture
from app.services.supabase_gateway import SupabaseGateway, _storage_object_already_exists


class FakeUpload:
    def __init__(self, data: bytes, *, filename: str, content_type: str) -> None:
        self.data = data
        self.filename = filename
        self.content_type = content_type

    async def read(self, size: int) -> bytes:
        return self.data[:size]


def validate(data: bytes, *, content_type: str = "image/jpeg"):
    return asyncio.run(
        read_validated_capture(
            FakeUpload(data, filename="capture.jpg", content_type=content_type),  # type: ignore[arg-type]
            capture_kind="photo",
            captured_at=datetime.now(UTC),
            privacy_flags={"may_contain_face": False},
            original_metadata={"width": 100},
        )
    )


def test_photo_validation_hashes_content_and_keeps_minimized_metadata() -> None:
    capture = validate(b"\xff\xd8\xff" + b"test-photo")
    assert capture.provenance.mime_type == "image/jpeg"
    assert capture.provenance.byte_size == 13
    assert len(capture.provenance.content_sha256) == 64
    assert capture.provenance.privacy_flags == {"may_contain_face": False}


def test_photo_validation_rejects_extension_only_spoofing() -> None:
    with pytest.raises(HTTPException) as exc_info:
        validate(b"not-an-image")
    assert exc_info.value.status_code == 415


def test_privacy_flags_must_be_booleans() -> None:
    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(
            read_validated_capture(
                FakeUpload(b"\xff\xd8\xffphoto", filename="capture.jpg", content_type="image/jpeg"),  # type: ignore[arg-type]
                capture_kind="photo",
                captured_at=datetime.now(UTC),
                privacy_flags={"may_contain_face": "unknown"},
                original_metadata={},
            )
        )
    assert exc_info.value.status_code == 422


class FakeResponse:
    def __init__(self, status_code: int, payload: object | None = None) -> None:
        self.status_code = status_code
        self.payload = payload

    def json(self) -> object:
        return self.payload


class FakeCaptureClient:
    object_urls: list[str] = []
    upload_attempts = 0
    rpc_attempts = 0

    async def __aenter__(self) -> "FakeCaptureClient":
        return self

    async def __aexit__(self, *args: object) -> None:
        return None

    async def post(self, url: str, **kwargs: object) -> FakeResponse:
        if "/storage/v1/object/" in url:
            type(self).object_urls.append(url)
            type(self).upload_attempts += 1
            if type(self).upload_attempts > 1:
                return FakeResponse(409, {"code": "ResourceAlreadyExists"})
            return FakeResponse(201)
        payload = kwargs["json"]
        assert isinstance(payload, dict)
        type(self).rpc_attempts += 1
        return FakeResponse(
            200,
            [
                {
                    "scan_session_id": "00000000-0000-0000-0000-000000000020",
                    "scan_session_media_id": "00000000-0000-0000-0000-000000000021",
                    "media_id": payload["p_media_id"],
                    "already_persisted": type(self).rpc_attempts > 1,
                }
            ],
        )


def test_capture_retry_uses_stable_media_identity(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(gateway_module.settings, "supabase_url", "https://project.supabase.co")
    monkeypatch.setattr(gateway_module.settings, "supabase_publishable_key", "publishable-key")
    monkeypatch.setattr(gateway_module.httpx, "AsyncClient", lambda **kwargs: FakeCaptureClient())
    FakeCaptureClient.object_urls = []
    FakeCaptureClient.upload_attempts = 0
    FakeCaptureClient.rpc_attempts = 0
    context = RequestContext(
        organization_id=UUID("00000000-0000-0000-0000-000000000001"),
        actor_id=UUID("00000000-0000-0000-0000-000000000002"),
        authentication_context="supabase_verified_user",
        bearer_token="user-token",  # noqa: S106 - inert test value
    )
    capture = validate(b"\xff\xd8\xfftest-photo")
    capture_id = UUID("00000000-0000-0000-0000-000000000010")

    async def persist_twice():
        gateway = SupabaseGateway()
        first = await gateway.persist_capture(
            context=context,
            repair_order_id=UUID("00000000-0000-0000-0000-000000018472"),
            client_session_id=UUID("00000000-0000-0000-0000-000000000011"),
            client_capture_id=capture_id,
            capture_kind="photo",
            sequence_number=0,
            capture=capture,
        )
        second = await gateway.persist_capture(
            context=context,
            repair_order_id=UUID("00000000-0000-0000-0000-000000018472"),
            client_session_id=UUID("00000000-0000-0000-0000-000000000011"),
            client_capture_id=capture_id,
            capture_kind="photo",
            sequence_number=0,
            capture=capture,
        )
        return first, second

    first, second = asyncio.run(persist_twice())
    assert first.media_id == second.media_id
    assert not first.already_persisted
    assert second.already_persisted
    assert len(FakeCaptureClient.object_urls) == 2
    assert FakeCaptureClient.object_urls[0] == FakeCaptureClient.object_urls[1]


@pytest.mark.parametrize(
    ("status_code", "payload"),
    [
        (409, {"code": "ResourceAlreadyExists"}),
        (409, {"code": "KeyAlreadyExists"}),
        (400, {"error": "Duplicate"}),
    ],
)
def test_storage_duplicate_responses_are_idempotent(
    status_code: int, payload: dict[str, str]
) -> None:
    assert _storage_object_already_exists(FakeResponse(status_code, payload))  # type: ignore[arg-type]


def test_other_storage_errors_are_not_treated_as_success() -> None:
    assert not _storage_object_already_exists(  # type: ignore[arg-type]
        FakeResponse(400, {"code": "InvalidMimeType"})
    )
