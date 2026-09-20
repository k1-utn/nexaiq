# nexaIQ Windows EMS Connector

The connector watches an authorized Mitchell EMS export folder and sends unmodified source files to the nexaIQ API. It does not scrape Mitchell, reuse Mitchell credentials, modify an estimate, or write back to Mitchell.

## Run in development

Start the FastAPI service on port 8001, then run:

```powershell
npm run dev:connector
```

On first launch, the setup window requests the browser-safe Supabase project URL and publishable key, the nexaIQ login, organization/location identifiers, and an EMS export folder. The password is used once for Supabase sign-in and is never stored. Access and refresh tokens are encrypted with Windows DPAPI for the current Windows user.

The tray menu provides **Sync now**, **Open EMS folder**, **Settings**, and **Exit**. The connector scans every 15 seconds, waits for files to stop changing, skips executable/archive formats, maintains an on-disk retry queue, and retries failures with bounded exponential backoff.

## Current Stage 6 boundary

Files are validated, hashed, privately stored, and marked `awaiting_format_validation`. Parsing and repair-order matching stay off until the team inspects an authorized real EMS sample and adds fixture-backed parser tests. No absolute Windows path is sent to the server.

Local state and logs are stored under `%LOCALAPPDATA%\nexaIQ\Connector`.
