begin;

alter table public.findings
  add column ai_result_id uuid references public.ai_results(id) on delete restrict,
  add column estimate_version_id uuid references public.estimate_versions(id) on delete restrict,
  add column matched_estimate_line_id uuid references public.estimate_lines(id) on delete restrict,
  add column candidate_key text,
  add column proposed_operation text,
  add column comparison_status text not null default 'not_compared',
  add column match_method text not null default 'none',
  add column source_references jsonb not null default '[]'::jsonb,
  add column updated_at timestamptz not null default now();

alter table public.findings
  drop constraint if exists findings_status_check,
  add constraint findings_status_check check (
    status in (
      'candidate', 'confirmed', 'dismissed', 'needs_review',
      'escalated', 'more_evidence_requested'
    )
  ),
  add constraint findings_confidence_range_check check (
    confidence is null or (confidence >= 0 and confidence <= 1)
  ),
  add constraint findings_source_quality_check check (
    source_quality in ('source_document', 'camera_only', 'mixed', 'unknown')
  ),
  add constraint findings_comparison_status_check check (
    comparison_status in (
      'not_compared', 'already_in_verified_estimate',
      'possible_missing_operation', 'automatic_operation_excluded',
      'insufficient_evidence'
    )
  ),
  add constraint findings_match_method_check check (
    match_method in ('none', 'operation_code_exact', 'description_exact', 'human_linked')
  ),
  add constraint findings_candidate_key_check check (
    candidate_key is null or length(btrim(candidate_key)) > 0
  ),
  add constraint findings_limitations_array_check check (
    jsonb_typeof(limitations) = 'array'
  ),
  add constraint findings_source_references_array_check check (
    jsonb_typeof(source_references) = 'array'
  );

create unique index findings_org_ro_candidate_key_idx
  on public.findings (organization_id, repair_order_id, candidate_key)
  where candidate_key is not null;
create index findings_ai_result_idx on public.findings (ai_result_id);
create index findings_estimate_version_idx on public.findings (estimate_version_id);
create index findings_matched_estimate_line_idx on public.findings (matched_estimate_line_id);

-- Composite references make the organization boundary part of the relationship,
-- preventing service-side code from linking otherwise valid IDs across tenants.
create unique index findings_id_organization_unique
  on public.findings (id, organization_id);
create unique index ai_results_id_organization_unique
  on public.ai_results (id, organization_id);
create unique index estimate_versions_id_organization_unique
  on public.estimate_versions (id, organization_id);
create unique index estimate_lines_id_organization_unique
  on public.estimate_lines (id, organization_id);
create unique index media_id_organization_unique
  on public.media (id, organization_id);
create unique index repair_orders_id_organization_unique
  on public.repair_orders (id, organization_id);
create unique index ai_jobs_id_organization_unique
  on public.ai_jobs (id, organization_id);

alter table public.findings
  add constraint findings_ai_result_tenant_fk
    foreign key (ai_result_id, organization_id)
    references public.ai_results (id, organization_id) on delete restrict,
  add constraint findings_estimate_version_tenant_fk
    foreign key (estimate_version_id, organization_id)
    references public.estimate_versions (id, organization_id) on delete restrict,
  add constraint findings_estimate_line_tenant_fk
    foreign key (matched_estimate_line_id, organization_id)
    references public.estimate_lines (id, organization_id) on delete restrict;

create table public.finding_evidence (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  finding_id uuid not null references public.findings(id) on delete cascade,
  media_id uuid not null references public.media(id) on delete restrict,
  evidence_role text not null default 'supporting' check (
    evidence_role in ('primary', 'supporting', 'context')
  ),
  created_at timestamptz not null default now(),
  unique (finding_id, media_id)
);

comment on table public.finding_evidence is
  'Evidence references for AI-generated candidates. Source media remains immutable and private.';

create index finding_evidence_org_finding_idx
  on public.finding_evidence (organization_id, finding_id);
create index finding_evidence_media_idx on public.finding_evidence (media_id);

alter table public.finding_evidence
  add constraint finding_evidence_finding_tenant_fk
    foreign key (finding_id, organization_id)
    references public.findings (id, organization_id) on delete cascade,
  add constraint finding_evidence_media_tenant_fk
    foreign key (media_id, organization_id)
    references public.media (id, organization_id) on delete restrict;

create table public.ai_evaluation_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id) on delete cascade,
  ai_job_id uuid references public.ai_jobs(id) on delete restrict,
  ai_result_id uuid references public.ai_results(id) on delete restrict,
  finding_id uuid references public.findings(id) on delete restrict,
  actor_id uuid references public.users(id),
  event_type text not null check (
    event_type in ('candidate_created', 'human_decision', 'known_miss', 'quality_note')
  ),
  decision text check (
    decision is null or decision in (
      'confirmed', 'dismissed', 'needs_review',
      'escalated', 'more_evidence_requested'
    )
  ),
  reason text,
  metrics jsonb not null default '{}'::jsonb check (jsonb_typeof(metrics) = 'object'),
  supersedes_event_id uuid references public.ai_evaluation_events(id),
  created_at timestamptz not null default now(),
  constraint ai_evaluation_events_human_decision_check check (
    event_type <> 'human_decision' or decision is not null
  ),
  constraint ai_evaluation_events_reason_check check (
    decision not in ('dismissed', 'needs_review', 'escalated', 'more_evidence_requested')
    or (reason is not null and length(btrim(reason)) >= 3)
  ),
  constraint ai_evaluation_events_not_self_superseding_check check (
    supersedes_event_id is null or supersedes_event_id <> id
  ),
  unique (supersedes_event_id)
);

comment on table public.ai_evaluation_events is
  'Append-only AI evaluation and human feedback events. No hidden model reasoning is stored.';

create index ai_evaluation_events_org_ro_time_idx
  on public.ai_evaluation_events (organization_id, repair_order_id, created_at desc);
create index ai_evaluation_events_job_idx on public.ai_evaluation_events (ai_job_id);
create index ai_evaluation_events_result_idx on public.ai_evaluation_events (ai_result_id);
create index ai_evaluation_events_finding_time_idx
  on public.ai_evaluation_events (finding_id, created_at desc);
create index ai_evaluation_events_actor_idx on public.ai_evaluation_events (actor_id);

alter table public.ai_evaluation_events
  add constraint ai_evaluation_events_repair_order_tenant_fk
    foreign key (repair_order_id, organization_id)
    references public.repair_orders (id, organization_id) on delete cascade,
  add constraint ai_evaluation_events_job_tenant_fk
    foreign key (ai_job_id, organization_id)
    references public.ai_jobs (id, organization_id) on delete restrict,
  add constraint ai_evaluation_events_result_tenant_fk
    foreign key (ai_result_id, organization_id)
    references public.ai_results (id, organization_id) on delete restrict,
  add constraint ai_evaluation_events_finding_tenant_fk
    foreign key (finding_id, organization_id)
    references public.findings (id, organization_id) on delete restrict;

alter table public.supplement_candidates
  add constraint supplement_candidates_finding_unique unique (finding_id),
  add constraint supplement_candidates_finding_tenant_fk
    foreign key (finding_id, organization_id)
    references public.findings (id, organization_id) on delete restrict,
  add constraint supplement_candidates_status_check check (
    status in ('estimator_review', 'confirmed', 'dismissed', 'review_reopened')
  );

alter table public.ai_results
  add constraint ai_results_confidence_range_check check (
    confidence is null or (confidence >= 0 and confidence <= 1)
  ),
  add constraint ai_results_human_decision_check check (
    human_decision is null or human_decision in (
      'confirmed', 'dismissed', 'needs_review',
      'escalated', 'more_evidence_requested'
    )
  ),
  add constraint ai_results_evidence_references_array_check check (
    jsonb_typeof(evidence_references) = 'array'
  ),
  add constraint ai_results_limitations_array_check check (
    jsonb_typeof(limitations) = 'array'
  );

alter table public.finding_evidence enable row level security;
alter table public.finding_evidence force row level security;
alter table public.ai_evaluation_events enable row level security;
alter table public.ai_evaluation_events force row level security;

revoke all on table public.finding_evidence, public.ai_evaluation_events
  from public, anon, authenticated;
grant select on table public.finding_evidence, public.ai_evaluation_events
  to authenticated;

create policy finding_evidence_member_read
on public.finding_evidence
for select
to authenticated
using ((select private.is_org_member(organization_id)));

create policy ai_evaluation_events_member_read
on public.ai_evaluation_events
for select
to authenticated
using ((select private.is_org_member(organization_id)));

-- Stage 4 writes are owned by narrow RPCs. Browser clients can read the
-- tenant-scoped records but cannot fabricate AI output or review history.
revoke insert, update, delete on table
  public.ai_jobs,
  public.ai_results,
  public.findings,
  public.finding_evidence,
  public.ai_evaluation_events,
  public.supplement_candidates
from authenticated;
grant select on table
  public.ai_jobs,
  public.ai_results,
  public.findings,
  public.finding_evidence,
  public.ai_evaluation_events,
  public.supplement_candidates
to authenticated;

create or replace function private.prevent_ai_evaluation_event_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'AI evaluation events are append-only; create a superseding event'
    using errcode = '55000';
end;
$$;

revoke all on function private.prevent_ai_evaluation_event_mutation()
  from public, anon, authenticated;

create trigger ai_evaluation_events_append_only
  before update or delete on public.ai_evaluation_events
  for each row execute function private.prevent_ai_evaluation_event_mutation();

create or replace function public.get_supplement_analysis_readiness(
  p_organization_id uuid,
  p_repair_order_id uuid,
  p_environment text default 'development'
)
returns table (
  verified_estimate_version_id uuid,
  photo_count bigint,
  voice_note_count bigint,
  approved_provider_policy_count bigint,
  eligible_model_version_count bigint
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  verified_version_id uuid;
  photos bigint;
  voice_notes bigint;
  approved_policies bigint;
  eligible_models bigint;
begin
  if caller_id is null
     or not (select private.is_org_member(p_organization_id)) then
    raise exception 'supplement analysis access denied' using errcode = '42501';
  end if;

  if p_environment not in ('development', 'staging', 'production') then
    raise exception 'invalid AI environment' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.repair_orders ro
    where ro.id = p_repair_order_id
      and ro.organization_id = p_organization_id
  ) then
    raise exception 'repair order not found' using errcode = 'P0002';
  end if;

  select ev.id
    into verified_version_id
    from public.estimate_versions ev
    where ev.organization_id = p_organization_id
      and ev.repair_order_id = p_repair_order_id
      and ev.parse_status = 'verified'
    order by ev.version_number desc, ev.created_at desc
    limit 1;

  select
    count(*) filter (where ssm.capture_kind = 'photo'),
    count(*) filter (where ssm.capture_kind = 'voice_note')
    into photos, voice_notes
    from public.scan_session_media ssm
    join public.scan_sessions ss
      on ss.id = ssm.scan_session_id
     and ss.organization_id = ssm.organization_id
    where ssm.organization_id = p_organization_id
      and ss.repair_order_id = p_repair_order_id;

  select count(*)
    into approved_policies
    from public.organization_ai_policies policy
    where policy.organization_id = p_organization_id
      and policy.enabled
      and 'supplement_analysis' = any(policy.allowed_purposes)
      and policy.allowed_data_categories @> array['estimate_data', 'repair_evidence']::text[]
      and not policy.provider_training_allowed
      and policy.dpa_status = 'approved';

  select count(*)
    into eligible_models
    from public.ai_model_versions model
    join public.organization_ai_policies policy
      on policy.organization_id = model.organization_id
     and policy.provider_id = model.provider_id
    where model.organization_id = p_organization_id
      and model.environment = p_environment
      and model.evaluation_status = 'passed'
      and model.activated_at is not null
      and model.retired_at is null
      and policy.enabled
      and 'supplement_analysis' = any(policy.allowed_purposes)
      and policy.allowed_data_categories @> array['estimate_data', 'repair_evidence']::text[]
      and not policy.provider_training_allowed
      and policy.dpa_status = 'approved';

  return query
  select
    verified_version_id,
    coalesce(photos, 0),
    coalesce(voice_notes, 0),
    coalesce(approved_policies, 0),
    coalesce(eligible_models, 0);
end;
$$;

revoke all on function public.get_supplement_analysis_readiness(uuid, uuid, text)
  from public, anon;
grant execute on function public.get_supplement_analysis_readiness(uuid, uuid, text)
  to authenticated;

create or replace function public.record_finding_review(
  p_finding_id uuid,
  p_decision text,
  p_reason text default null
)
returns table (
  evaluation_event_id uuid,
  finding_status text,
  supplement_candidate_id uuid,
  reviewed_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  finding_organization_id uuid;
  finding_repair_order_id uuid;
  finding_ai_result_id uuid;
  finding_reason text;
  finding_operation text;
  prior_event_id uuid;
  new_event_id uuid := gen_random_uuid();
  candidate_id uuid;
  review_time timestamptz := clock_timestamp();
  normalized_reason text := nullif(btrim(p_reason), '');
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if p_decision not in (
    'confirmed', 'dismissed', 'needs_review',
    'escalated', 'more_evidence_requested'
  ) then
    raise exception 'invalid finding review decision' using errcode = '22023';
  end if;

  if p_decision in ('dismissed', 'needs_review', 'escalated', 'more_evidence_requested')
     and (normalized_reason is null or length(normalized_reason) < 3) then
    raise exception 'a review reason is required for this decision'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_finding_id::text, 0));

  select
    f.organization_id,
    f.repair_order_id,
    f.ai_result_id,
    f.reason,
    f.proposed_operation
    into
      finding_organization_id,
      finding_repair_order_id,
      finding_ai_result_id,
      finding_reason,
      finding_operation
    from public.findings f
    where f.id = p_finding_id;

  if finding_organization_id is null
     or not (select private.has_org_permission(finding_organization_id, 'records:write')) then
    raise exception 'finding review access denied' using errcode = '42501';
  end if;

  select event.id
    into prior_event_id
    from public.ai_evaluation_events event
    where event.finding_id = p_finding_id
      and event.event_type = 'human_decision'
    order by event.created_at desc, event.id desc
    limit 1;

  insert into public.ai_evaluation_events (
    id,
    organization_id,
    repair_order_id,
    ai_result_id,
    finding_id,
    actor_id,
    event_type,
    decision,
    reason,
    supersedes_event_id,
    created_at
  ) values (
    new_event_id,
    finding_organization_id,
    finding_repair_order_id,
    finding_ai_result_id,
    p_finding_id,
    caller_id,
    'human_decision',
    p_decision,
    normalized_reason,
    prior_event_id,
    review_time
  );

  update public.findings
    set status = p_decision,
        updated_at = review_time
    where id = p_finding_id;

  if finding_ai_result_id is not null then
    update public.ai_results
      set human_decision = p_decision,
          decided_by = caller_id,
          decided_at = review_time
      where id = finding_ai_result_id
        and organization_id = finding_organization_id;
  end if;

  if p_decision = 'confirmed' then
    insert into public.supplement_candidates (
      organization_id,
      repair_order_id,
      finding_id,
      proposed_operation,
      reason,
      status,
      confirmed_by,
      confirmed_at
    ) values (
      finding_organization_id,
      finding_repair_order_id,
      p_finding_id,
      finding_operation,
      finding_reason,
      'estimator_review',
      caller_id,
      review_time
    )
    on conflict (finding_id) do update
      set status = 'estimator_review',
          confirmed_by = excluded.confirmed_by,
          confirmed_at = excluded.confirmed_at
    returning id into candidate_id;
  else
    update public.supplement_candidates
      set status = case
        when p_decision = 'dismissed' then 'dismissed'
        else 'review_reopened'
      end
      where finding_id = p_finding_id
    returning id into candidate_id;
  end if;

  insert into public.audit_events (
    organization_id,
    repair_order_id,
    actor_id,
    event_type,
    entity_type,
    entity_id,
    authentication_context,
    payload
  ) values (
    finding_organization_id,
    finding_repair_order_id,
    caller_id,
    'finding_human_decision_recorded',
    'finding',
    p_finding_id,
    jsonb_build_object('provider', 'supabase_auth', 'workflow', 'supplement_analysis'),
    jsonb_strip_nulls(jsonb_build_object(
      'evaluation_event_id', new_event_id,
      'decision', p_decision,
      'reason', normalized_reason,
      'supplement_candidate_id', candidate_id,
      'supersedes_event_id', prior_event_id
    ))
  );

  return query
  select new_event_id, p_decision, candidate_id, review_time;
end;
$$;

revoke all on function public.record_finding_review(uuid, text, text)
  from public, anon;
grant execute on function public.record_finding_review(uuid, text, text)
  to authenticated;

commit;
