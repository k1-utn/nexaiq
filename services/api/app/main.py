from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import estimate_ingestion, health
from app.core.config import settings

app = FastAPI(
    title="nexaIQ API",
    version="0.1.0",
    description="Decision-support APIs. Human review is required for material findings.",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type", "X-NexaIQ-Organization-ID"],
)
app.include_router(health.router)
app.include_router(estimate_ingestion.router, prefix="/v1/estimate-ingestion")
