# nexaIQ

Legal-first repair execution intelligence for collision-repair professionals.

This repository contains the sealed Stage 1 foundation, sealed Stage 2 estimate-ingestion and human-verification workflow, sealed Stage 3 mobile evidence-capture workflow, and sealed Stage 4 supplement-analysis workflow. nexaIQ is decision-support software: AI output remains a candidate until a qualified person reviews it. It does not certify repairs, vehicle safety, OEM compliance, or payment.

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
uv run --project services/api uvicorn app.main:app --app-dir services/api --reload --host 0.0.0.0 --port 8001
```

For mobile capture, copy `apps/mobile/.env.example` to `apps/mobile/.env.local`, replace the example LAN IP with the computer's current LAN IP, and start Expo:

```powershell
npm run dev:mobile
```

The phone and computer must be on the same private network. Scan the Expo QR code with Expo Go. Durable offline capture is a native mobile feature and is intentionally unavailable in the browser preview.

Both the web app and API require a real Supabase user session. Configure the URL and publishable key in `.env.local`. The Stage 4 API additionally needs server-only Supabase and OpenAI secrets; never expose them through `NEXT_PUBLIC_...` or `EXPO_PUBLIC_...` variables. See [the Stage 4 runbook](docs/ai-safety/STAGE_4_RUNBOOK.md).

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

Implemented and sealed through Stage 4: workspace foundation, dashboard, auth clients, tenant schema, RBAC model, append-oriented audit events, private media, AI job/result/model provenance, legal acceptance and retention records, secure PDF validation, deterministic estimate parsing, immutable source lines, superseding human line reviews, derived estimate verification status, and cross-tenant tests. Stage 3 includes a mobile repair-order list, privacy-aware photo batches and optional voice capture, local image compression, metadata minimization, a durable offline retry queue, authenticated uploads, and idempotent tenant-scoped persistence.

Stage 4 adds fail-closed readiness, server-side private-evidence retrieval, structured vision observations, deterministic verified-estimate comparison, evidence-linked candidate records, AI job/result logs, and append-only human evaluation history. Clear coat is always excluded from missing-operation candidates. External AI remains disabled until an authorized owner approves the provider policy, a pinned model passes evaluation, and server-only credentials are configured.

Not implemented: automatic Mitchell write-back, insurer submission, repair approval, calibration approval, or any autonomous safety-critical decision.

Legal drafts and checklists in this repository are internal product-development material and are **not lawyer-approved**. Review [LEGAL_REVIEW_REQUIRED.md](LEGAL_REVIEW_REQUIRED.md) before any external commercial launch.
