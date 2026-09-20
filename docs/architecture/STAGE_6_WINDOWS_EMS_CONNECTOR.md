# Stage 6 — Windows EMS Connector

Stage 6 provides an authorized, human-configured Windows path from Mitchell EMS exports to nexaIQ. It does not automate Mitchell's private interface, collect Mitchell credentials, bypass access controls, or write changes back to an estimating system.

## Implemented foundation

1. The user signs in through Supabase with the browser-safe publishable key.
2. The login password is discarded; access and refresh tokens are encrypted with Windows DPAPI for the current Windows user.
3. The workstation registers through FastAPI with an organization, location, stable device identifier, connector version, and a SHA-256 fingerprint of the watched path. The raw Windows path remains local.
4. A Windows tray process scans the authorized folder and waits for files to become stable.
5. A durable local queue records file and batch identities before upload and retries failures with bounded exponential backoff.
6. FastAPI validates filename, extension, MIME type, size, and blocked executable/archive signatures, then writes the unmodified source to the private `connector-imports` bucket.
7. The API parses only the approved dBASE tables and withholds sensitive side tables from extraction.
8. Service-only database functions persist idempotent tenant-scoped records, create review-required estimate versions, and append audit events.

## Security boundary

- No Supabase secret/service key is shipped in the Windows application.
- Browser and desktop roles cannot directly create or modify connector database records.
- Stage 6 tables use forced RLS and tenant-scoped foreign keys.
- Device registration and file persistence independently validate the initiating user's active `records:write` permission.
- Storage paths include organization, device, client batch, and client file identifiers.
- Retries reuse stable identifiers; reused identifiers with different content are rejected.

## Parser and import boundary

The parser was built from an authorized Mitchell EMS export and backed by synthetic dBASE fixtures. It imports only ENV estimate metadata, VEH vehicle data, LIN estimate lines, and TTL totals. AD1, AD2, VEN, and DBT data are never extracted because those tables can contain customer, insurer, vendor, address, email, claim, or memo content. Profile tables remain unsupported because they are not required for the initial estimate import.

Once ENV, VEH, and LIN are present in one connector batch, the service idempotently creates or matches the repair order, creates a new estimate version, and imports its lines. Every imported version is marked `requires_human_verification`; no estimate is approved, submitted, or written back automatically.
