# Stage 5 — Supplement Review

Stage 5 turns human-confirmed Stage 4 findings into an estimator-controlled review package. It does not modify an estimate, submit a supplement, guarantee reimbursement, or certify a repair.

## Workflow

1. A Stage 4 finding is confirmed by a human and becomes an estimator-review candidate.
2. The estimator opens the Supplement Review workspace.
3. The estimator reviews the linked original evidence and records an OEM/source consideration.
4. The estimator marks the candidate ready, requests changes, or excludes it. Each decision is append-only and supersedes the prior review event.
5. Package-ready candidates can be frozen into a versioned review package.
6. The estimator explicitly accepts the displayed attestation before approving a package.
7. The package can be opened as a print-friendly report and saved as PDF through the browser.

## Integrity and authorization

- `supplement_candidate_review_events` is append-only.
- `supplement_review_package_items` stores immutable snapshots, including evidence hashes and source-review metadata.
- All Stage 5 tables use forced RLS and tenant-scoped foreign keys.
- Authenticated browsers can append controlled candidate-review events through trigger validation.
- Package creation and approval run through FastAPI and service-only `SECURITY INVOKER` database functions.
- Audit events record candidate reviews, package creation, package approval, and requested changes.

## Human-control boundary

An approved package means an authenticated estimator reviewed the recorded candidates and evidence. It is not a vehicle-safety sign-off, OEM-compliance certification, insurer submission, or promise of payment.

## Seal evidence

Stage 5 is sealed for its defined development scope. The linked-database suite verifies forced RLS, least-privilege grants, append-only review attribution, candidate-state derivation, immutable package snapshots, exact approval attestation, audit events, and denial of cross-tenant review/package attempts. Web and API checks cover the review workspace, service-only package routes, and paid-AI fail-closed behavior.

This seal does not authorize an external pilot. The pre-pilot controls and legal approvals remain tracked in the security and legal checklists.
