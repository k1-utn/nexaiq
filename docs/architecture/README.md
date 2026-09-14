# Architecture

Status: engineering design, not a claim of certification or regulatory approval.

## Boundaries

```text
Next.js web ─┐
Expo mobile ─┼─ HTTPS + Supabase user JWT ─ FastAPI ─ controlled AI tools
             └─ Supabase Data API ─ PostgreSQL/RLS ─ private Storage
```

The web and mobile clients receive only publishable Supabase credentials. Secret/service-role keys are server-only. Every durable record is tenant-scoped with `organization_id`; location-scoped workflows add `location_id`. API handlers establish tenant context before touching data, while RLS is the final enforcement boundary.

## Human-control boundary

AI services create versioned results and candidate records only. They cannot call tools that approve repairs, edit estimates, submit supplements, sign QC, or release vehicles. High-impact writes are separate application commands requiring authenticated intent, current role/permission checks, and an audit event.

## Phase 1 modules

- Identity: Supabase Auth, user profile, organization membership, roles, permissions.
- Operations: locations, vehicles, repair orders.
- Evidence: immutable source metadata, private object paths, content hashes, derivatives separated from originals.
- Governance: legal documents/acceptances, retention policies and holds, security events.
- AI control plane: providers, organization policy, model versions, jobs, results, structured rationale, sources, cost/latency, human decision.
- Audit: append-oriented events; corrections create additional events.

## Phase 2 ingestion

The FastAPI endpoint validates MIME, magic bytes, size, encryption, and page count. It preserves a SHA-256 source identity, extracts text locally, and uses deterministic parsing before any model routing. Parsed versions remain `requires_human_verification`; the original source takes precedence.

The web verification workspace displays the preserved PDF beside its structured lines. A reviewer can confirm, correct, exclude, or defer each line. Decisions append to `estimate_line_reviews`; a new decision supersedes the prior decision without rewriting or deleting history. Database triggers derive tenant, version, reviewer identity, timestamps, completion state, and audit events. An estimate becomes `verified` only when every parsed line has a final human decision. This status documents source verification only and does not approve repair work or release a vehicle.

Domain rule: clear-coat operations are automatically added by the estimating workflow. nexaIQ must preserve them when present for provenance, but downstream supplement detection must not report clear coat as a missing operation or proposed supplement.

## Scale

Stateless APIs can scale horizontally. PostgreSQL indexes lead with `organization_id` for tenant-filtered workloads. Blob bytes remain in private storage while relational metadata stays queryable. AI jobs are explicit, idempotency-ready records instead of unbounded background agents.
