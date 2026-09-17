begin;

create policy ai_evaluation_events_writer_insert
on public.ai_evaluation_events
for insert
to authenticated
with check (
  event_type = 'human_decision'
  and actor_id = (select auth.uid())
  and (select private.has_org_permission(organization_id, 'records:write'))
);

grant insert on table public.ai_evaluation_events to authenticated;

create or replace function private.prepare_finding_review_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  finding_organization_id uuid;
  finding_repair_order_id uuid;
  finding_ai_result_id uuid;
  prior_event_id uuid;
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if new.event_type is distinct from 'human_decision'
     or new.decision not in (
       'confirmed', 'dismissed', 'needs_review',
       'escalated', 'more_evidence_requested'
     ) then
    raise exception 'invalid finding review decision' using errcode = '22023';
  end if;

  new.reason := nullif(btrim(new.reason), '');
  if new.decision in ('dismissed', 'needs_review', 'escalated', 'more_evidence_requested')
     and (new.reason is null or length(new.reason) < 3) then
    raise exception 'a review reason is required for this decision'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(new.finding_id::text, 0));

  select f.organization_id, f.repair_order_id, f.ai_result_id
    into finding_organization_id, finding_repair_order_id, finding_ai_result_id
    from public.findings f
    where f.id = new.finding_id;

  if finding_organization_id is null
     or not (select private.has_org_permission(finding_organization_id, 'records:write')) then
    raise exception 'finding review access denied' using errcode = '42501';
  end if;

  select event.id
    into prior_event_id
    from public.ai_evaluation_events event
    where event.finding_id = new.finding_id
      and event.event_type = 'human_decision'
      and not exists (
        select 1
        from public.ai_evaluation_events successor
        where successor.supersedes_event_id = event.id
      )
    limit 1;

  new.id := gen_random_uuid();
  new.organization_id := finding_organization_id;
  new.repair_order_id := finding_repair_order_id;
  new.ai_job_id := null;
  new.ai_result_id := finding_ai_result_id;
  new.actor_id := caller_id;
  new.event_type := 'human_decision';
  new.metrics := '{}'::jsonb;
  new.supersedes_event_id := prior_event_id;
  new.created_at := clock_timestamp();
  return new;
end;
$$;

revoke all on function private.prepare_finding_review_event()
  from public, anon, authenticated;

create or replace function private.finish_finding_review_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  finding_reason text;
  finding_operation text;
  candidate_id uuid;
begin
  select f.reason, f.proposed_operation
    into finding_reason, finding_operation
    from public.findings f
    where f.id = new.finding_id
      and f.organization_id = new.organization_id;

  update public.findings
    set status = new.decision,
        updated_at = new.created_at
    where id = new.finding_id
      and organization_id = new.organization_id;

  if new.ai_result_id is not null then
    update public.ai_results
      set human_decision = new.decision,
          decided_by = new.actor_id,
          decided_at = new.created_at
      where id = new.ai_result_id
        and organization_id = new.organization_id;
  end if;

  if new.decision = 'confirmed' then
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
      new.organization_id,
      new.repair_order_id,
      new.finding_id,
      finding_operation,
      finding_reason,
      'estimator_review',
      new.actor_id,
      new.created_at
    )
    on conflict (finding_id) do update
      set status = 'estimator_review',
          confirmed_by = excluded.confirmed_by,
          confirmed_at = excluded.confirmed_at
    returning id into candidate_id;
  else
    update public.supplement_candidates
      set status = case
        when new.decision = 'dismissed' then 'dismissed'
        else 'review_reopened'
      end
      where finding_id = new.finding_id
        and organization_id = new.organization_id
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
    new.organization_id,
    new.repair_order_id,
    new.actor_id,
    'finding_human_decision_recorded',
    'finding',
    new.finding_id,
    jsonb_build_object('provider', 'supabase_auth', 'workflow', 'supplement_analysis'),
    jsonb_strip_nulls(jsonb_build_object(
      'evaluation_event_id', new.id,
      'decision', new.decision,
      'reason', new.reason,
      'supplement_candidate_id', candidate_id,
      'supersedes_event_id', new.supersedes_event_id
    ))
  );

  return new;
end;
$$;

revoke all on function private.finish_finding_review_event()
  from public, anon, authenticated;

create trigger ai_evaluation_events_prepare_finding_review
  before insert on public.ai_evaluation_events
  for each row execute function private.prepare_finding_review_event();

create trigger ai_evaluation_events_finish_finding_review
  after insert on public.ai_evaluation_events
  for each row execute function private.finish_finding_review_event();

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
security invoker
set search_path = ''
as $$
declare
  inserted_event_id uuid;
  inserted_status text;
  inserted_reviewed_at timestamptz;
  resulting_candidate_id uuid;
begin
  insert into public.ai_evaluation_events (
    finding_id,
    event_type,
    decision,
    reason
  ) values (
    p_finding_id,
    'human_decision',
    p_decision,
    p_reason
  )
  returning id, decision, created_at
    into inserted_event_id, inserted_status, inserted_reviewed_at;

  select candidate.id
    into resulting_candidate_id
    from public.supplement_candidates candidate
    where candidate.finding_id = p_finding_id;

  return query
  select
    inserted_event_id,
    inserted_status,
    resulting_candidate_id,
    inserted_reviewed_at;
end;
$$;

revoke all on function public.record_finding_review(uuid, text, text)
  from public, anon;
grant execute on function public.record_finding_review(uuid, text, text)
  to authenticated;

commit;
