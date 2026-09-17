begin;

alter table public.ai_jobs
  add column provider_response_id text,
  add column failure_code text,
  alter column input_references set default '{}'::jsonb;

update public.ai_jobs
  set input_references = '{}'::jsonb
  where input_references = '[]'::jsonb;

alter table public.ai_jobs
  add constraint ai_jobs_status_check check (
    status in ('queued', 'running', 'completed', 'failed')
  ),
  add constraint ai_jobs_input_references_object_check check (
    jsonb_typeof(input_references) = 'object'
  );

create index ai_jobs_model_version_idx on public.ai_jobs (model_version_id);
create index ai_jobs_repair_order_idx on public.ai_jobs (repair_order_id);
create index ai_jobs_requested_by_idx on public.ai_jobs (requested_by);
create index ai_results_ai_job_idx on public.ai_results (ai_job_id);

drop function public.get_supplement_analysis_readiness(uuid, uuid, text);

create function public.get_supplement_analysis_readiness(
  p_organization_id uuid,
  p_repair_order_id uuid,
  p_environment text default 'development'
)
returns table (
  verified_estimate_version_id uuid,
  photo_count bigint,
  eligible_photo_count bigint,
  withheld_photo_count bigint,
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
  eligible_photos bigint;
  withheld_photos bigint;
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
    count(*) filter (
      where ssm.capture_kind = 'photo'
        and not coalesce((ssm.privacy_flags ->> 'may_contain_face')::boolean, false)
        and not coalesce((ssm.privacy_flags ->> 'may_contain_plate')::boolean, false)
        and not coalesce((ssm.privacy_flags ->> 'may_contain_customer_document')::boolean, false)
    ),
    count(*) filter (
      where ssm.capture_kind = 'photo'
        and (
          coalesce((ssm.privacy_flags ->> 'may_contain_face')::boolean, false)
          or coalesce((ssm.privacy_flags ->> 'may_contain_plate')::boolean, false)
          or coalesce((ssm.privacy_flags ->> 'may_contain_customer_document')::boolean, false)
        )
    ),
    count(*) filter (where ssm.capture_kind = 'voice_note')
    into photos, eligible_photos, withheld_photos, voice_notes
    from public.scan_session_media ssm
    join public.scan_sessions ss
      on ss.id = ssm.scan_session_id
     and ss.organization_id = ssm.organization_id
    where ssm.organization_id = p_organization_id
      and ss.repair_order_id = p_repair_order_id;

  select count(*)
    into approved_policies
    from public.organization_ai_policies policy
    join public.ai_providers provider on provider.id = policy.provider_id
    where policy.organization_id = p_organization_id
      and provider.provider_key = 'openai'
      and policy.enabled
      and 'supplement_analysis' = any(policy.allowed_purposes)
      and policy.allowed_data_categories @> array['estimate_data', 'repair_evidence']::text[]
      and not policy.provider_training_allowed
      and policy.dpa_status = 'approved';

  select count(*)
    into eligible_models
    from public.ai_model_versions model
    join public.ai_providers provider on provider.id = model.provider_id
    join public.organization_ai_policies policy
      on policy.organization_id = model.organization_id
     and policy.provider_id = model.provider_id
    where model.organization_id = p_organization_id
      and model.environment = p_environment
      and provider.provider_key = 'openai'
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
    coalesce(eligible_photos, 0),
    coalesce(withheld_photos, 0),
    coalesce(voice_notes, 0),
    coalesce(approved_policies, 0),
    coalesce(eligible_models, 0);
end;
$$;

revoke all on function public.get_supplement_analysis_readiness(uuid, uuid, text)
  from public, anon;
grant execute on function public.get_supplement_analysis_readiness(uuid, uuid, text)
  to authenticated;

create or replace function public.begin_supplement_analysis(
  p_actor_id uuid,
  p_organization_id uuid,
  p_repair_order_id uuid,
  p_environment text,
  p_idempotency_key text
)
returns table (
  ai_job_id uuid,
  job_status text,
  estimate_version_id uuid,
  provider_key text,
  model_name text,
  provider_model_version text,
  prompt_template_version text,
  schema_version text,
  estimate_lines jsonb,
  evidence jsonb
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  selected_estimate_id uuid;
  selected_model_id uuid;
  selected_provider_key text;
  selected_model_name text;
  selected_provider_model_version text;
  selected_prompt_version text;
  selected_schema_version text;
  selected_lines jsonb;
  selected_evidence jsonb;
  selected_evidence_ids jsonb;
  job_id uuid;
  resulting_status text;
begin
  if p_environment not in ('development', 'staging', 'production')
     or length(btrim(p_idempotency_key)) < 8 then
    raise exception 'invalid supplement analysis request' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.organization_members member
    join public.user_roles user_role
      on user_role.organization_id = member.organization_id
     and user_role.user_id = member.user_id
    join public.role_permissions role_permission
      on role_permission.role_id = user_role.role_id
    join public.permissions permission
      on permission.id = role_permission.permission_id
    where member.organization_id = p_organization_id
      and member.user_id = p_actor_id
      and member.status = 'active'
      and permission.code = 'records:write'
  ) then
    raise exception 'supplement analysis access denied' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.repair_orders ro
    where ro.id = p_repair_order_id
      and ro.organization_id = p_organization_id
  ) then
    raise exception 'repair order not found' using errcode = 'P0002';
  end if;

  select estimate.id
    into selected_estimate_id
    from public.estimate_versions estimate
    where estimate.organization_id = p_organization_id
      and estimate.repair_order_id = p_repair_order_id
      and estimate.parse_status = 'verified'
    order by estimate.version_number desc, estimate.created_at desc
    limit 1;

  if selected_estimate_id is null then
    raise exception 'a verified estimate is required' using errcode = '22023';
  end if;

  select
    model.id,
    provider.provider_key,
    model.model_name,
    model.provider_model_version,
    model.prompt_template_version,
    model.schema_version
    into
      selected_model_id,
      selected_provider_key,
      selected_model_name,
      selected_provider_model_version,
      selected_prompt_version,
      selected_schema_version
    from public.ai_model_versions model
    join public.ai_providers provider on provider.id = model.provider_id
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
      and policy.dpa_status = 'approved'
      and provider.provider_key = 'openai'
    order by model.activated_at desc, model.created_at desc
    limit 1;

  if selected_model_id is null then
    raise exception 'no approved evaluated model is available' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', line.id,
      'source_line_number', line.source_line_number,
      'operation_code', line.operation_code,
      'description', line.description,
      'amount', line.amount
    ) order by line.source_line_number nulls last, line.created_at), '[]'::jsonb)
    into selected_lines
    from public.estimate_lines line
    where line.organization_id = p_organization_id
      and line.estimate_version_id = selected_estimate_id;

  select
    coalesce(jsonb_agg(jsonb_build_object(
      'media_id', evidence.media_id,
      'object_path', evidence.object_path,
      'mime_type', evidence.mime_type,
      'content_sha256', evidence.content_sha256,
      'captured_at', evidence.captured_at
    ) order by evidence.sequence_number, evidence.captured_at), '[]'::jsonb),
    coalesce(jsonb_agg(to_jsonb(evidence.media_id)
      order by evidence.sequence_number, evidence.captured_at), '[]'::jsonb)
    into selected_evidence, selected_evidence_ids
    from (
      select
        media.id as media_id,
        media.object_path,
        media.mime_type,
        media.content_sha256,
        link.captured_at,
        link.sequence_number
      from public.scan_session_media link
      join public.scan_sessions session
        on session.id = link.scan_session_id
       and session.organization_id = link.organization_id
      join public.media media
        on media.id = link.media_id
       and media.organization_id = link.organization_id
      where link.organization_id = p_organization_id
        and session.repair_order_id = p_repair_order_id
        and link.capture_kind = 'photo'
        and not coalesce((link.privacy_flags ->> 'may_contain_face')::boolean, false)
        and not coalesce((link.privacy_flags ->> 'may_contain_plate')::boolean, false)
        and not coalesce((link.privacy_flags ->> 'may_contain_customer_document')::boolean, false)
      order by link.captured_at desc
      limit 12
    ) evidence;

  if jsonb_array_length(selected_evidence) = 0 then
    raise exception 'at least one privacy-eligible photo is required' using errcode = '22023';
  end if;

  insert into public.ai_jobs (
    organization_id,
    repair_order_id,
    job_type,
    model_version_id,
    purpose,
    data_categories,
    status,
    idempotency_key,
    requested_by,
    input_references,
    started_at
  ) values (
    p_organization_id,
    p_repair_order_id,
    'supplement_analysis',
    selected_model_id,
    'supplement_analysis',
    array['estimate_data', 'repair_evidence']::text[],
    'running',
    p_idempotency_key,
    p_actor_id,
    jsonb_build_object(
      'estimate_version_id', selected_estimate_id,
      'evidence_ids', selected_evidence_ids
    ),
    clock_timestamp()
  )
  on conflict (organization_id, idempotency_key) do update
    set idempotency_key = excluded.idempotency_key
  returning id, status into job_id, resulting_status;

  insert into public.audit_events (
    organization_id, repair_order_id, actor_id, event_type,
    entity_type, entity_id, authentication_context, payload
  ) values (
    p_organization_id, p_repair_order_id, p_actor_id,
    'supplement_analysis_started', 'ai_job', job_id,
    jsonb_build_object('provider', 'supabase_auth', 'workflow', 'supplement_analysis'),
    jsonb_build_object(
      'estimate_version_id', selected_estimate_id,
      'model_version_id', selected_model_id,
      'evidence_count', jsonb_array_length(selected_evidence)
    )
  );

  return query select
    job_id,
    resulting_status,
    selected_estimate_id,
    selected_provider_key,
    selected_model_name,
    selected_provider_model_version,
    selected_prompt_version,
    selected_schema_version,
    selected_lines,
    selected_evidence;
end;
$$;

revoke all on function public.begin_supplement_analysis(uuid, uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.begin_supplement_analysis(uuid, uuid, uuid, text, text)
  to service_role;

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
  if new.event_type = 'candidate_created' and caller_id is null then
    if new.actor_id is not null or new.decision is not null or new.finding_id is null
       or new.ai_job_id is null or new.ai_result_id is null then
      raise exception 'invalid candidate evaluation event' using errcode = '22023';
    end if;
    new.id := coalesce(new.id, gen_random_uuid());
    new.reason := null;
    new.metrics := coalesce(new.metrics, '{}'::jsonb);
    new.supersedes_event_id := null;
    new.created_at := coalesce(new.created_at, clock_timestamp());
    return new;
  end if;

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
        select 1 from public.ai_evaluation_events successor
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
  if new.event_type <> 'human_decision' then
    return new;
  end if;

  select f.reason, f.proposed_operation
    into finding_reason, finding_operation
    from public.findings f
    where f.id = new.finding_id
      and f.organization_id = new.organization_id;

  update public.findings
    set status = new.decision, updated_at = new.created_at
    where id = new.finding_id and organization_id = new.organization_id;

  if new.ai_result_id is not null then
    update public.ai_results
      set human_decision = new.decision,
          decided_by = new.actor_id,
          decided_at = new.created_at
      where id = new.ai_result_id
        and organization_id = new.organization_id
        and result_type <> 'supplement_analysis_candidates';
  end if;

  if new.decision = 'confirmed' then
    insert into public.supplement_candidates (
      organization_id, repair_order_id, finding_id, proposed_operation,
      reason, status, confirmed_by, confirmed_at
    ) values (
      new.organization_id, new.repair_order_id, new.finding_id, finding_operation,
      finding_reason, 'estimator_review', new.actor_id, new.created_at
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
    organization_id, repair_order_id, actor_id, event_type, entity_type,
    entity_id, authentication_context, payload
  ) values (
    new.organization_id, new.repair_order_id, new.actor_id,
    'finding_human_decision_recorded', 'finding', new.finding_id,
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

create or replace function public.complete_supplement_analysis(
  p_ai_job_id uuid,
  p_actor_id uuid,
  p_provider_response_id text,
  p_candidates jsonb,
  p_input_tokens integer,
  p_output_tokens integer,
  p_latency_ms integer
)
returns table (
  ai_result_id uuid,
  created_finding_count integer,
  completed_at timestamptz
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  job_record public.ai_jobs%rowtype;
  estimate_id uuid;
  allowed_evidence_ids jsonb;
  result_id uuid := gen_random_uuid();
  completion_time timestamptz := clock_timestamp();
  candidate jsonb;
  candidate_index integer := 0;
  new_finding_id uuid;
  evidence_value jsonb;
  evidence_id uuid;
  finding_count integer := 0;
  average_confidence numeric(5,4);
begin
  if jsonb_typeof(p_candidates) <> 'array' or jsonb_array_length(p_candidates) > 100 then
    raise exception 'invalid candidate output' using errcode = '22023';
  end if;

  select * into job_record
    from public.ai_jobs job
    where job.id = p_ai_job_id
    for update;

  if job_record.id is null
     or job_record.requested_by <> p_actor_id
     or job_record.job_type <> 'supplement_analysis'
     or job_record.status <> 'running' then
    raise exception 'analysis job cannot be completed' using errcode = '42501';
  end if;

  estimate_id := (job_record.input_references ->> 'estimate_version_id')::uuid;
  allowed_evidence_ids := job_record.input_references -> 'evidence_ids';

  select avg((item ->> 'confidence')::numeric)
    into average_confidence
    from jsonb_array_elements(p_candidates) item;

  insert into public.ai_results (
    id, organization_id, ai_job_id, result_type, structured_output,
    confidence, source_quality, human_review_required, evidence_references,
    concise_rationale, limitations, input_tokens, output_tokens, latency_ms
  ) values (
    result_id, job_record.organization_id, job_record.id,
    'supplement_analysis_candidates',
    jsonb_build_object(
      'provider_response_id', nullif(btrim(p_provider_response_id), ''),
      'candidates', p_candidates
    ),
    average_confidence,
    'mixed',
    true,
    allowed_evidence_ids,
    case when jsonb_array_length(p_candidates) = 0
      then 'No supplement candidates were generated.'
      else 'Vision observations were compared with the human-verified estimate.'
    end,
    jsonb_build_array(
      'Image analysis cannot establish hidden damage or repair requirements.',
      'Every possible omission requires qualified estimator review.'
    ),
    greatest(coalesce(p_input_tokens, 0), 0),
    greatest(coalesce(p_output_tokens, 0), 0),
    greatest(coalesce(p_latency_ms, 0), 0)
  );

  for candidate in select value from jsonb_array_elements(p_candidates)
  loop
    candidate_index := candidate_index + 1;

    if jsonb_typeof(candidate) <> 'object'
       or candidate ->> 'comparison_status' is null
       or candidate ->> 'comparison_status' not in (
         'already_in_verified_estimate', 'possible_missing_operation',
         'automatic_operation_excluded', 'insufficient_evidence'
       )
       or candidate ->> 'proposed_operation' is null
       or length(btrim(candidate ->> 'proposed_operation')) = 0
       or candidate ->> 'confidence' is null
       or candidate ->> 'confidence' !~ '^(0(\.[0-9]+)?|1(\.0+)?)$'
       or candidate ->> 'source_quality' is null
       or candidate ->> 'source_quality' not in (
         'source_document', 'camera_only', 'mixed', 'unknown'
       )
       or candidate ->> 'match_method' is null
       or candidate ->> 'match_method' not in (
         'none', 'operation_code_exact', 'description_exact'
       ) then
      raise exception 'candidate output failed validation' using errcode = '22023';
    end if;

    if candidate ->> 'comparison_status' not in (
         'possible_missing_operation', 'insufficient_evidence'
       ) then
      continue;
    end if;

    if (candidate ->> 'proposed_operation') ~* '\mclear[ -]?coat\M' then
      continue;
    end if;

    if jsonb_typeof(candidate -> 'evidence_ids') <> 'array'
       or jsonb_array_length(candidate -> 'evidence_ids') = 0
       or jsonb_typeof(candidate -> 'limitations') <> 'array'
       or candidate ->> 'finding_type' is null
       or length(btrim(candidate ->> 'finding_type')) = 0
       or candidate ->> 'reason' is null
       or length(btrim(candidate ->> 'reason')) = 0
       or (candidate ->> 'confidence')::numeric < 0
       or (candidate ->> 'confidence')::numeric > 1
       then
      raise exception 'candidate output failed validation' using errcode = '22023';
    end if;

    for evidence_value in select value from jsonb_array_elements(candidate -> 'evidence_ids')
    loop
      evidence_id := trim(both '"' from evidence_value::text)::uuid;
      if not (allowed_evidence_ids @> jsonb_build_array(evidence_id)) then
        raise exception 'candidate referenced evidence outside the job' using errcode = '22023';
      end if;
    end loop;

    insert into public.findings (
      organization_id, repair_order_id, finding_type, component, condition,
      status, confidence, source_quality, human_review_required, reason,
      limitations, ai_result_id, estimate_version_id, matched_estimate_line_id,
      candidate_key, proposed_operation, comparison_status, match_method,
      source_references
    ) values (
      job_record.organization_id,
      job_record.repair_order_id,
      left(candidate ->> 'finding_type', 100),
      nullif(left(candidate ->> 'component', 200), ''),
      nullif(left(candidate ->> 'condition', 200), ''),
      case when candidate ->> 'comparison_status' = 'insufficient_evidence'
        then 'needs_review' else 'candidate' end,
      (candidate ->> 'confidence')::numeric,
      candidate ->> 'source_quality',
      true,
      left(candidate ->> 'reason', 2000),
      candidate -> 'limitations',
      result_id,
      estimate_id,
      nullif(candidate ->> 'matched_estimate_line_id', '')::uuid,
      md5(job_record.id::text || ':' || candidate_index::text),
      left(candidate ->> 'proposed_operation', 500),
      candidate ->> 'comparison_status',
      candidate ->> 'match_method',
      candidate -> 'evidence_ids'
    ) returning id into new_finding_id;

    for evidence_value in select value from jsonb_array_elements(candidate -> 'evidence_ids')
    loop
      evidence_id := trim(both '"' from evidence_value::text)::uuid;
      insert into public.finding_evidence (
        organization_id, finding_id, media_id, evidence_role
      ) values (
        job_record.organization_id, new_finding_id, evidence_id, 'supporting'
      );
    end loop;

    insert into public.ai_evaluation_events (
      organization_id, repair_order_id, ai_job_id, ai_result_id,
      finding_id, actor_id, event_type, metrics
    ) values (
      job_record.organization_id, job_record.repair_order_id, job_record.id,
      result_id, new_finding_id, null, 'candidate_created',
      jsonb_build_object(
        'confidence', (candidate ->> 'confidence')::numeric,
        'comparison_status', candidate ->> 'comparison_status'
      )
    );
    finding_count := finding_count + 1;
  end loop;

  update public.ai_jobs
    set status = 'completed',
        provider_response_id = nullif(btrim(p_provider_response_id), ''),
        completed_at = completion_time
    where id = job_record.id;

  insert into public.audit_events (
    organization_id, repair_order_id, actor_id, event_type,
    entity_type, entity_id, authentication_context, payload
  ) values (
    job_record.organization_id, job_record.repair_order_id, p_actor_id,
    'supplement_analysis_completed', 'ai_job', job_record.id,
    jsonb_build_object('provider', 'supabase_auth', 'workflow', 'supplement_analysis'),
    jsonb_build_object(
      'ai_result_id', result_id,
      'candidate_count', finding_count,
      'provider_response_id', nullif(btrim(p_provider_response_id), '')
    )
  );

  return query select result_id, finding_count, completion_time;
end;
$$;

revoke all on function public.complete_supplement_analysis(
  uuid, uuid, text, jsonb, integer, integer, integer
) from public, anon, authenticated;
grant execute on function public.complete_supplement_analysis(
  uuid, uuid, text, jsonb, integer, integer, integer
) to service_role;

create or replace function public.fail_supplement_analysis(
  p_ai_job_id uuid,
  p_actor_id uuid,
  p_failure_code text
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  job_record public.ai_jobs%rowtype;
begin
  select * into job_record
    from public.ai_jobs job
    where job.id = p_ai_job_id
    for update;

  if job_record.id is null
     or job_record.requested_by <> p_actor_id
     or job_record.job_type <> 'supplement_analysis'
     or job_record.status <> 'running' then
    raise exception 'analysis job cannot be failed' using errcode = '42501';
  end if;

  update public.ai_jobs
    set status = 'failed',
        failure_code = left(coalesce(nullif(btrim(p_failure_code), ''), 'provider_error'), 100),
        completed_at = clock_timestamp()
    where id = job_record.id;

  insert into public.audit_events (
    organization_id, repair_order_id, actor_id, event_type,
    entity_type, entity_id, authentication_context, payload
  ) values (
    job_record.organization_id, job_record.repair_order_id, p_actor_id,
    'supplement_analysis_failed', 'ai_job', job_record.id,
    jsonb_build_object('provider', 'supabase_auth', 'workflow', 'supplement_analysis'),
    jsonb_build_object('failure_code', left(coalesce(p_failure_code, 'provider_error'), 100))
  );
end;
$$;

revoke all on function public.fail_supplement_analysis(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.fail_supplement_analysis(uuid, uuid, text)
  to service_role;

commit;
