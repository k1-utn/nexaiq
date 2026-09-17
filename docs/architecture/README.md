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

## Sealed Phase 3 mobile evidence capture

The Expo client lists only repair orders visible through the signed-in user's active organization. Camera and microphone permissions are requested only when the user starts the corresponding capture. Photos are stripped of EXIF data, resized, and compressed locally; voice notes are optional and background recording is disabled. Precise location is never collected. Users can flag unavoidable faces, licence plates, or customer documents before capture.

Captured files are copied into the native app's durable document directory and queued with a client-generated capture identity. Uploads use the user's Supabase access token plus an explicit organization header. Failed or offline uploads remain on-device with bounded exponential retry; local files are deleted only after the API confirms durable server persistence. The server validates declared MIME type against file signatures, hashes the bytes, writes to private tenant-prefixed Storage paths, and calls an idempotent database function that links the media to a scan session and appends an audit event. Browser preview is presentation-only because it cannot provide the native durable-filesystem guarantee.

Stage 3 captures are evidence, not findings or decisions. They do not approve repairs, establish OEM compliance, certify repair quality, or determine vehicle safety.

## Sealed Phase 4 supplement analysis

The Stage 4 control plane fails closed unless the repair order has a human-verified estimate, photo evidence, an organization-approved provider policy, and an evaluated active model version. Provider training must be disabled and the policy must explicitly permit both estimate data and repair evidence for supplement analysis.

Vision observations require evidence IDs, confidence, source quality, a reason, limitations, and `human_review_required=true`. Deterministic comparison marks only exact description matches—or an exact operation-code plus description match—as already present. Generic codes such as `R&I` never suppress a candidate by themselves. Clear coat is always classified as an automatic-operation exclusion and cannot become a supplement candidate.

Candidate records and human evaluation events are tenant-scoped. Browser clients cannot fabricate AI output; human evaluation inserts pass through RLS and database triggers that derive the tenant, actor, source result, supersession chain, and audit event. A permitted reviewer can confirm, dismiss, defer, escalate, or request more evidence through a narrow audited command. Confirmation creates an estimator-review candidate only; it does not alter the verified estimate or submit anything externally.

The API retrieves privacy-eligible originals from private Storage with a server-only Supabase secret and sends bounded image inputs to the approved OpenAI Responses API model with response storage disabled. Structured output is schema-validated, evidence IDs must belong to the job, and all observations pass through deterministic estimate comparison before persistence. Browser clients receive no provider or Supabase secret. Jobs are idempotent and record only safe failure codes; raw evidence and provider error bodies are not logged.

## Scale

Stateless APIs can scale horizontally. PostgreSQL indexes lead with `organization_id` for tenant-filtered workloads. Blob bytes remain in private storage while relational metadata stays queryable. AI jobs are explicit, idempotency-ready records instead of unbounded background agents.
