from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import estimate_ingestion, evidence, health, supplement_analysis
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
    allow_headers=[
        "Authorization",
        "Content-Type",
        "Idempotency-Key",
        "X-NexaIQ-Organization-ID",
    ],
)
app.include_router(health.router)
app.include_router(estimate_ingestion.router, prefix="/v1/estimate-ingestion")
app.include_router(evidence.router, prefix="/v1/evidence")
app.include_router(supplement_analysis.router, prefix="/v1/supplement-analysis")
