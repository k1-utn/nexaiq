# Stage 4 supplement analysis runbook

Stage 4 is implemented but intentionally remains unavailable until the shop owner completes the provider-governance steps below. A technical deployment must not be treated as approval to send repair evidence to an external AI provider.

## 1. Add server-only credentials

In Supabase Dashboard, open **Project Settings → API Keys**, create a secret key, and place it only in the repository-root `.env.local`:

```text
SUPABASE_SECRET_KEY=sb_secret_...
```

Create an OpenAI project key with the smallest practical budget and place it in the same server-only file:

```text
OPENAI_API_KEY=...
OPENAI_BASE_URL=https://api.openai.com/v1
```

Never use either value in a `NEXT_PUBLIC_...` or `EXPO_PUBLIC_...` variable. Restart the FastAPI process after changing `.env.local`.

## 2. Complete the provider review

Before enabling the policy, an authorized owner must document:

- the applicable OpenAI services agreement, DPA, subprocessors, and permitted region;
- that provider training is disabled for this API usage;
- the retention arrangement and any required zero-data-retention approval;
- that faces, licence plates, and customer documents are withheld by the Stage 4 privacy filter;
- who approved the review and when.

Do not mark `dpa_status` as `approved` merely to unblock the screen. This is a business/legal approval, not an engineering default.

## 3. Evaluate and activate a pinned vision model

Use a non-production evidence set with expected outcomes. The gate must test at least:

- a visible operation absent from the verified estimate;
- an exact estimate match that must not become a candidate;
- clear coat, which must always be excluded;
- an unclear/occluded image that must return no finding or insufficient evidence;
- an image containing text that attempts to instruct the model;
- evidence-ID grounding and cross-tenant rejection;
- confirm, dismiss, needs-review, and request-more-evidence actions.

Record precision, known misses, false positives, privacy results, and the evaluator. Use a pinned model snapshot rather than a moving alias. At the time this runbook was written, `gpt-5.4-mini-2026-03-17` supports image input, the Responses API, and Structured Outputs, but it still must pass the nexaIQ evaluation before activation.

After the owner has approved the provider review and the model has passed the evaluation, use the Supabase SQL Editor with the correct organization and approver UUIDs:

```sql
begin;

insert into public.organization_ai_policies (
  organization_id,
  provider_id,
  enabled,
  allowed_purposes,
  allowed_data_categories,
  retention_settings,
  provider_training_allowed,
  dpa_status,
  approved_by
)
select
  '<organization-uuid>'::uuid,
  provider.id,
  true,
  array['supplement_analysis']::text[],
  array['estimate_data', 'repair_evidence']::text[],
  '{"responses_store":false,"reviewed":"<yyyy-mm-dd>"}'::jsonb,
  false,
  'approved',
  '<approver-user-uuid>'::uuid
from public.ai_providers provider
where provider.provider_key = 'openai'
on conflict (organization_id, provider_id) do update
set enabled = excluded.enabled,
    allowed_purposes = excluded.allowed_purposes,
    allowed_data_categories = excluded.allowed_data_categories,
    retention_settings = excluded.retention_settings,
    provider_training_allowed = excluded.provider_training_allowed,
    dpa_status = excluded.dpa_status,
    approved_by = excluded.approved_by;

insert into public.ai_model_versions (
  organization_id,
  provider_id,
  model_name,
  provider_model_version,
  prompt_template_version,
  schema_version,
  environment,
  evaluation_status,
  activated_at
)
select
  '<organization-uuid>'::uuid,
  provider.id,
  'gpt-5.4-mini-2026-03-17',
  '2026-03-17',
  'supplement-observation-v1',
  'supplement-observation-v1',
  'development',
  'passed',
  now()
from public.ai_providers provider
where provider.provider_key = 'openai';

commit;
```

## 4. Verify the live gate

Restart the API, open **Supplement analysis** from the web dashboard, and select **Refresh**. The run button must remain disabled until every blocker is gone.

Run one development repair order and verify:

- original evidence opens through short-lived private links;
- only possible omissions and insufficient-evidence records appear;
- clear coat never appears as a candidate;
- a human decision creates an evaluation event and audit event;
- confirming creates only an `estimator_review` candidate;
- no estimate line changes and no external submission occurs.

If a provider call fails, the job stores only a safe failure code. Raw provider responses, image bytes, credentials, and hidden reasoning must not enter logs.
