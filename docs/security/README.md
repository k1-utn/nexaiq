# Security baseline

## Controls implemented in the foundation

- RLS enabled on every application table in the exposed `public` schema.
- Explicit grants and operation-specific policies; authentication alone is never treated as tenant authorization.
- Membership lookups use `auth.uid()` and database records, never user-editable JWT metadata.
- Private media bucket with organization-prefixed object paths and membership policies.
- Browser code has publishable credentials only; secret/service-role and AI keys are server-only.
- Original evidence is separate from derivatives and identified by SHA-256.
- Audit rows are append-oriented; client update/delete grants are revoked.
- Estimate uploads validate content type, signature, size, encryption, and page count.
- Uploaded content is data, never instructions.

## Required before pilot

1. Configure MFA and short session lifetime appropriate to risk; require MFA for administrators once the workflow is validated.
2. Put rate limiting and abuse controls at the edge and API.
3. Enable malware scanning and quarantine before an uploaded object becomes available downstream.
4. Run dependency, secret, static-analysis, and tenant-isolation checks in CI.
5. Establish managed backup/restore testing and incident contacts.
6. Run an independent penetration test before enterprise rollout.
7. Enable Supabase leaked-password protection on a supported plan before external pilot access. It is intentionally recorded as unavailable in the current hosted development project, not treated as an active control.

See `docs/incident-response` and `LEGAL_REVIEW_REQUIRED.md`.
