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

Use only publishable keys in the web, mobile, and API app configuration. The API forwards each authenticated user's bearer token so PostgreSQL RLS remains the authorization boundary.

Estimate source versions and parsed lines are not updateable or deleteable by browser roles. Human verification is stored as an append-only review chain. Client inserts pass through database-controlled derivation and RLS, while the public review function runs with the caller's normal privileges.
