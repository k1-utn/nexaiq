# nexaIQ

Legal-first repair execution intelligence for collision-repair professionals.

This repository contains the sealed Stage 1 foundation and a protected estimate-ingestion proof slice. nexaIQ is decision-support software: AI output remains a candidate until a qualified person reviews it. It does not certify repairs, vehicle safety, OEM compliance, or payment.

## Workspace

- `apps/web` — Next.js operator dashboard and Supabase Auth entry point
- `apps/mobile` — Expo mobile repair-order workspace
- `services/api` — FastAPI service, guarded estimate upload, provenance, and parser
- `packages/shared` — shared TypeScript schemas and product language
- `supabase` — PostgreSQL schema, private Storage policy, RLS, and isolation tests
- `docs` — architecture, security, privacy, legal, AI safety, retention, OEM rights, and incident response

## Local setup

Prerequisites: Node 24+, npm 11+, Python 3.12+, `uv`, and a hosted Supabase development project. Docker is not used.

```powershell
Copy-Item .env.example .env.local
npm install
uv sync --project services/api --locked --extra dev
npm exec supabase -- login
npm exec supabase -- link --project-ref <your-project-ref>
npm run dev:web
```

In another terminal:

```powershell
uv run --project services/api uvicorn app.main:app --app-dir services/api --reload --port 8000
```

Both the web app and API require a real Supabase user session. Configure the URL and publishable key in `.env.local`; never put a secret or service-role key in the app environment.

## Verification

```powershell
npm run check
uv run --project services/api pytest services/api/tests
npm run db:test:linked
npm exec supabase -- db lint --linked --level warning
npm exec supabase -- migration list --linked
```

The database checks execute inside transactions and roll back, but they must only run against a dedicated development or staging project. See `supabase/README.md`.

## Current scope

Implemented: workspace foundation, dashboard, mobile hero screen, auth clients, tenant schema, RBAC model, append-oriented audit events, private media, AI job/result/model provenance, legal acceptance and retention records, secure PDF validation, deterministic estimate parsing, human verification status, and tests.

Not implemented: automatic Mitchell write-back, insurer submission, repair approval, calibration approval, or any autonomous safety-critical decision.

Legal drafts and checklists in this repository are internal product-development material and are **not lawyer-approved**. Review [LEGAL_REVIEW_REQUIRED.md](LEGAL_REVIEW_REQUIRED.md) before any external commercial launch.
