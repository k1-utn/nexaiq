from dataclasses import dataclass
from typing import Annotated
from uuid import UUID

import httpx
from fastapi import Header, HTTPException, status

from app.core.config import settings


@dataclass(frozen=True)
class RequestContext:
    organization_id: UUID
    actor_id: UUID | None
    authentication_context: str
    bearer_token: str | None


async def require_request_context(
    authorization: Annotated[str | None, Header()] = None,
    organization_id: Annotated[UUID | None, Header(alias="X-NexaIQ-Organization-ID")] = None,
) -> RequestContext:
    """Verify the Supabase user and tenant membership before any data operation."""
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="Authentication required"
        )
    if organization_id is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Organization scope required"
        )
    if not settings.supabase_url or not settings.supabase_publishable_key:
        raise HTTPException(status_code=503, detail="Authentication service is not configured")

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="Bearer authentication required")
    headers = {
        "apikey": settings.supabase_publishable_key,
        "Authorization": f"Bearer {token}",
    }
    async with httpx.AsyncClient(timeout=10) as client:
        user_response = await client.get(f"{settings.supabase_url}/auth/v1/user", headers=headers)
        if user_response.status_code != 200:
            raise HTTPException(status_code=401, detail="Invalid or expired session")
        actor_id = UUID(user_response.json()["id"])
        member_response = await client.get(
            f"{settings.supabase_url}/rest/v1/organization_members",
            headers=headers,
            params={
                "select": "id",
                "organization_id": f"eq.{organization_id}",
                "user_id": f"eq.{actor_id}",
                "status": "eq.active",
                "limit": "1",
            },
        )
        if member_response.status_code != 200 or not member_response.json():
            raise HTTPException(status_code=403, detail="Organization access denied")

    return RequestContext(
        organization_id=organization_id,
        actor_id=actor_id,
        authentication_context="supabase_verified_user",
        bearer_token=token,
    )
