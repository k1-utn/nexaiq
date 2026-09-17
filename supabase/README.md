# Supabase hosted development

The migrations create the nexaIQ tenant schema, RLS policies, append-only audit controls, and the private `repair-evidence` bucket. Object keys use this structure:

`{organization_id}/{repair_order_id}/{media_id}/{sanitized_filename}`

Docker and the local Supabase stack are not used. Authenticate and link the repository to a dedicated hosted development project:

```powershell
npm exec supabase -- login
npm exec supabase -- link --project-ref <your-project-ref>
npm exec supabase -- migration list --linked
```

Create migrations with the pinned CLI before editing them, then review and apply them:

```powershell
npm exec supabase -- migration new <descriptive-name>
npm exec supabase -- db push --linked --dry-run
npm exec supabase -- db push --linked
```

Run the hosted verification gate only against development or staging. Both SQL files use transactions and roll back their test data:

```powershell
npm run db:test:linked
npm exec supabase -- db lint --linked --level warning
```

For optional GitHub-hosted database checks, configure `SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_ID` as repository secrets and set the repository variable `RUN_HOSTED_SUPABASE_TESTS` to `true`.

Use only publishable keys in web and mobile configuration. Normal API operations forward each authenticated user's bearer token so PostgreSQL RLS remains the authorization boundary. Stage 4 analysis uses a server-only Supabase secret exclusively for its narrow lifecycle RPCs and private evidence download; it must never be exposed to a browser or mobile bundle.

Estimate source versions and parsed lines are not updateable or deleteable by browser roles. Human verification is stored as an append-only review chain. Client inserts pass through database-controlled derivation and RLS, while the public review function runs with the caller's normal privileges.

Stage 4 AI findings, evidence links, and supplement candidates are read-only to browser table APIs. Human evaluation inserts pass through RLS and protected triggers that derive the tenant, actor, source result, supersession chain, and audit event. The public review function uses the caller's normal privileges and requires `records:write`. Confirmation creates an estimator-review candidate; no database function modifies an estimate or submits a supplement.

The analysis begin/complete/fail functions are executable only by `service_role`. They independently validate the initiating actor's active membership and permissions, bind inputs to the verified estimate and privacy-eligible media, and maintain job/audit state. Provider policy and evaluated-model activation remain explicit organization governance steps; see [`docs/ai-safety/STAGE_4_RUNBOOK.md`](../docs/ai-safety/STAGE_4_RUNBOOK.md).
