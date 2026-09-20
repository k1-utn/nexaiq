# nexaIQ Windows EMS Connector

The connector watches an authorized Mitchell EMS export folder and sends unmodified source files to the nexaIQ API. The API imports ENV, VEH, LIN, and TTL data into a human-verification-required estimate version. It does not scrape Mitchell, reuse Mitchell credentials, modify an estimate, or write back to Mitchell.

## Run in development

Start the FastAPI service on port 8001, then run:

```powershell
npm run dev:connector
```

On first launch, the setup window requests the browser-safe Supabase project URL and publishable key, the nexaIQ login, organization/location identifiers, and an EMS export folder. The password is used once for Supabase sign-in and is never stored. Access and refresh tokens are encrypted with Windows DPAPI for the current Windows user.

The tray menu provides **Sync now**, **Open EMS folder**, **Settings**, and **Exit**. The connector scans every 15 seconds, waits for files to stop changing, skips executable/archive formats, maintains an on-disk retry queue, and retries failures with bounded exponential backoff.

## Privacy and Stage 6 boundary

Files are validated, hashed, privately stored, parsed with fixture-backed dBASE tests, and matched to a repair order using the EMS repair-order reference. Imported estimates always require human verification. Customer, insurer, vendor, address, email, and memo tables (`AD1`, `AD2`, `VEN`, and `DBT`) are stored privately for source provenance but deliberately not extracted. No absolute Windows path is sent to the server.

Local state and logs are stored under `%LOCALAPPDATA%\nexaIQ\Connector`.
