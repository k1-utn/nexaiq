# Stage 6 — Windows EMS Connector

Stage 6 provides an authorized, human-configured Windows path from Mitchell EMS exports to nexaIQ. It does not automate Mitchell's private interface, collect Mitchell credentials, bypass access controls, or write changes back to an estimating system.

## Implemented foundation

1. The user signs in through Supabase with the browser-safe publishable key.
2. The login password is discarded; access and refresh tokens are encrypted with Windows DPAPI for the current Windows user.
3. The workstation registers through FastAPI with an organization, location, stable device identifier, connector version, and a SHA-256 fingerprint of the watched path. The raw Windows path remains local.
4. A Windows tray process scans the authorized folder and waits for files to become stable.
5. A durable local queue records file and batch identities before upload and retries failures with bounded exponential backoff.
6. FastAPI validates filename, extension, MIME type, size, and blocked executable/archive signatures, then writes the unmodified source to the private `connector-imports` bucket.
7. Service-only database functions persist idempotent tenant-scoped device, batch, and file records and append audit events.

## Security boundary

- No Supabase secret/service key is shipped in the Windows application.
- Browser and desktop roles cannot directly create or modify connector database records.
- Stage 6 tables use forced RLS and tenant-scoped foreign keys.
- Device registration and file persistence independently validate the initiating user's active `records:write` permission.
- Storage paths include organization, device, client batch, and client file identifiers.
- Retries reuse stable identifiers; reused identifiers with different content are rejected.

## Required real sample

EMS parsing and repair-order matching are not implemented from assumptions. The next Stage 6 increment requires one authorized Mitchell EMS export with all generated files kept together. The sample should use a test repair order or be de-identified before development use. Fixture-backed parsing, version handling, and update detection will be built from that sample.
