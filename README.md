# nexaIQ

Legal-first repair execution intelligence for collision-repair professionals.

This repository contains the sealed Stage 1 foundation, sealed Stage 2 estimate-ingestion and human-verification workflow, sealed Stage 3 mobile evidence-capture workflow, sealed Stage 4 supplement-analysis workflow, sealed Stage 5 supplement-review workspace, and the active Stage 6 Windows EMS connector. nexaIQ is decision-support software: AI output remains a candidate until a qualified person reviews it. It does not certify repairs, vehicle safety, OEM compliance, or payment.

## Workspace

- `apps/web` — Next.js operator dashboard and Supabase Auth entry point
- `apps/mobile` — Expo mobile repair-order workspace
- `apps/connector` — Windows system-tray EMS folder connector
- `services/api` — FastAPI service, guarded estimate upload, provenance, and parser
- `packages/shared` — shared TypeScript schemas and product language
- `supabase` — PostgreSQL schema, private Storage policy, RLS, and isolation tests
- `docs` — architecture, security, privacy, legal, AI safety, retention, OEM rights, and incident response

## Local setup

Prerequisites: Node 24+, npm 11+, Python 3.12+, `uv`, .NET 8 SDK, and a hosted Supabase development project. Docker is not used.

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

The Stage 6 connector is Windows-only. After the API is running and an authorized Mitchell EMS export folder is available, start it with:

```powershell
npm run dev:connector
```

The setup window signs in through Supabase, registers the workstation and selected location, and stores session tokens encrypted for the current Windows user. The login password is never stored.

Both the web app and API require a real Supabase user session. Configure the URL and publishable key in `.env.local`. The Stage 4 API additionally needs server-only Supabase and OpenAI secrets; never expose them through `NEXT_PUBLIC_...` or `EXPO_PUBLIC_...` variables. Paid AI calls remain disabled unless `NEXAIQ_PAID_AI_ENABLED=true` is deliberately configured. See [the Stage 4 runbook](docs/ai-safety/STAGE_4_RUNBOOK.md).

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

Implemented and sealed through Stage 5: workspace foundation, dashboard, auth clients, tenant schema, RBAC model, append-oriented audit events, private media, AI job/result/model provenance, legal acceptance and retention records, secure PDF validation, deterministic estimate parsing, immutable source lines, superseding human line reviews, derived estimate verification status, and cross-tenant tests. Stage 3 includes a mobile repair-order list, privacy-aware photo batches and optional voice capture, local image compression, metadata minimization, a durable offline retry queue, authenticated uploads, and idempotent tenant-scoped persistence.

Stage 4 adds fail-closed readiness, server-side private-evidence retrieval, structured vision observations, deterministic verified-estimate comparison, evidence-linked candidate records, AI job/result logs, and append-only human evaluation history. Clear coat is always excluded from missing-operation candidates. External AI remains disabled until an authorized owner approves the provider policy, a pinned model passes evaluation, and server-only credentials are configured.

Stage 5 adds append-only estimator candidate reviews, mandatory OEM/source consideration, immutable versioned review-package snapshots, explicit estimator attestation, print/PDF-ready reports, and Stage 5 audit history. Package generation and approval are service-only writes; browser roles cannot fabricate report packages. Linked-database tests verify tenant isolation, append-only attribution, package snapshots, approval audit events, and denial of cross-tenant package creation. See [the Stage 5 architecture note](docs/architecture/STAGE_5_SUPPLEMENT_REVIEW.md).

Stage 6 is underway with a Windows tray application, authenticated workstation registration, current-user encrypted session storage, folder scanning, an on-disk retry queue, idempotent private EMS file sync, privacy-minimized dBASE parsing, repair-order matching, review-required estimate versioning, audit history, and tenant-isolation tests. Customer, insurer, vendor, and memo tables are never extracted. See [the Stage 6 architecture note](docs/architecture/STAGE_6_WINDOWS_EMS_CONNECTOR.md).

Not implemented: automatic Mitchell write-back, insurer submission, repair approval, calibration approval, or any autonomous safety-critical decision.

Legal drafts and checklists in this repository are internal product-development material and are **not lawyer-approved**. Review [LEGAL_REVIEW_REQUIRED.md](LEGAL_REVIEW_REQUIRED.md) before any external commercial launch.
