begin;

drop function public.create_supplement_review_package(uuid);
drop function public.record_supplement_review_package_decision(uuid, text, text, text);

create function public.create_supplement_review_package(
  p_actor_id uuid,
  p_organization_id uuid,
  p_repair_order_id uuid
)
returns table (
  package_id uuid,
  package_number integer,
  item_count integer,
  package_status text
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  next_package_number integer;
  created_package_id uuid := gen_random_uuid();
  created_item_count integer;
  created_at_time timestamptz := clock_timestamp();
begin
  if p_actor_id is null or p_organization_id is null then
    raise exception 'authenticated actor and organization are required' using errcode = '42501';
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
    raise exception 'supplement package access denied' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.repair_orders repair_order
    where repair_order.id = p_repair_order_id
      and repair_order.organization_id = p_organization_id
  ) then
    raise exception 'repair order not found' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_repair_order_id::text, 1));

  if not exists (
    select 1
    from public.supplement_candidates candidate
    where candidate.organization_id = p_organization_id
      and candidate.repair_order_id = p_repair_order_id
      and candidate.status = 'confirmed'
  ) then
    raise exception 'at least one package-ready candidate is required' using errcode = '22023';
  end if;

  select coalesce(max(package.package_number), 0) + 1
    into next_package_number
    from public.supplement_review_packages package
    where package.repair_order_id = p_repair_order_id
      and package.organization_id = p_organization_id;

  insert into public.supplement_review_packages (
    id, organization_id, repair_order_id, package_number,
    status, created_by, created_at, updated_at
  ) values (
    created_package_id, p_organization_id, p_repair_order_id,
    next_package_number, 'draft', p_actor_id, created_at_time, created_at_time
  );

  insert into public.supplement_review_package_items (
    organization_id, package_id, supplement_candidate_id, sequence_number,
    proposed_operation, reason, review_note, oem_consideration_status,
    oem_source_document_id, oem_source_note, evidence_references,
    source_snapshot, created_at
  )
  select
    candidate.organization_id,
    created_package_id,
    candidate.id,
    row_number() over (order by candidate.confirmed_at, candidate.created_at, candidate.id),
    coalesce(nullif(btrim(candidate.proposed_operation), ''), 'Operation requires estimator entry'),
    candidate.reason,
    candidate.review_note,
    candidate.oem_consideration_status,
    candidate.oem_source_document_id,
    candidate.oem_source_note,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'media_id', evidence.media_id,
        'evidence_role', evidence.evidence_role,
        'original_filename', media.original_filename,
        'mime_type', media.mime_type,
        'content_sha256', media.content_sha256
      ) order by evidence.created_at, evidence.id)
      from public.finding_evidence evidence
      join public.media media
        on media.id = evidence.media_id
       and media.organization_id = evidence.organization_id
      where evidence.finding_id = candidate.finding_id
        and evidence.organization_id = candidate.organization_id
    ), '[]'::jsonb),
    jsonb_build_object(
      'finding_id', finding.id,
      'finding_type', finding.finding_type,
      'component', finding.component,
      'condition', finding.condition,
      'confidence', finding.confidence,
      'source_quality', finding.source_quality,
      'comparison_status', finding.comparison_status,
      'limitations', finding.limitations,
      'reviewed_by', candidate.reviewed_by,
      'reviewed_at', candidate.reviewed_at
    ),
    created_at_time
  from public.supplement_candidates candidate
  join public.findings finding
    on finding.id = candidate.finding_id
   and finding.organization_id = candidate.organization_id
  where candidate.organization_id = p_organization_id
    and candidate.repair_order_id = p_repair_order_id
    and candidate.status = 'confirmed';

  get diagnostics created_item_count = row_count;

  insert into public.audit_events (
    organization_id, repair_order_id, actor_id, event_type,
    entity_type, entity_id, authentication_context, payload
  ) values (
    p_organization_id, p_repair_order_id, p_actor_id,
    'supplement_review_package_created', 'supplement_review_package',
    created_package_id,
    jsonb_build_object('provider', 'supabase_auth', 'workflow', 'supplement_review'),
    jsonb_build_object(
      'package_number', next_package_number,
      'item_count', created_item_count,
      'status', 'draft'
    )
  );

  return query
  select created_package_id, next_package_number, created_item_count, 'draft'::text;
end;
$$;

revoke all on function public.create_supplement_review_package(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.create_supplement_review_package(uuid, uuid, uuid)
  to service_role;

create function public.record_supplement_review_package_decision(
  p_actor_id uuid,
  p_organization_id uuid,
  p_package_id uuid,
  p_decision text,
  p_note text default null,
  p_attestation text default null
)
returns table (
  package_id uuid,
  package_status text,
  decided_at timestamptz
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  package_repair_order_id uuid;
  package_number_value integer;
  decision_time timestamptz := clock_timestamp();
  normalized_note text := nullif(btrim(p_note), '');
  normalized_attestation text := nullif(btrim(p_attestation), '');
  required_attestation constant text :=
    'I confirm that I reviewed this supplement package and its linked evidence. This is an estimator decision and does not certify repair safety or insurer payment.';
begin
  if p_actor_id is null or p_organization_id is null then
    raise exception 'authenticated actor and organization are required' using errcode = '42501';
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
    raise exception 'supplement package decision access denied' using errcode = '42501';
  end if;

  if p_decision not in ('approved', 'changes_requested') then
    raise exception 'invalid supplement package decision' using errcode = '22023';
  end if;

  if p_decision = 'approved' and normalized_attestation is distinct from required_attestation then
    raise exception 'the approval attestation must be accepted exactly as shown'
      using errcode = '22023';
  end if;

  if p_decision = 'changes_requested'
     and (normalized_note is null or length(normalized_note) < 3) then
    raise exception 'a change-request reason is required' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_package_id::text, 2));

  select package.repair_order_id, package.package_number
    into package_repair_order_id, package_number_value
    from public.supplement_review_packages package
    where package.id = p_package_id
      and package.organization_id = p_organization_id;

  if package_repair_order_id is null then
    raise exception 'supplement package not found' using errcode = 'P0002';
  end if;

  update public.supplement_review_packages
    set status = p_decision,
        approval_note = normalized_note,
        approval_attestation = case
          when p_decision = 'approved' then normalized_attestation
          else null
        end,
        approved_by = case when p_decision = 'approved' then p_actor_id else null end,
        approved_at = case when p_decision = 'approved' then decision_time else null end,
        updated_at = decision_time
    where id = p_package_id
      and organization_id = p_organization_id;

  insert into public.audit_events (
    organization_id, repair_order_id, actor_id, event_type,
    entity_type, entity_id, authentication_context, payload
  ) values (
    p_organization_id, package_repair_order_id, p_actor_id,
    case
      when p_decision = 'approved' then 'supplement_review_package_approved'
      else 'supplement_review_package_changes_requested'
    end,
    'supplement_review_package', p_package_id,
    jsonb_build_object('provider', 'supabase_auth', 'workflow', 'supplement_review'),
    jsonb_strip_nulls(jsonb_build_object(
      'package_number', package_number_value,
      'decision', p_decision,
      'note', normalized_note,
      'attestation', normalized_attestation
    ))
  );

  return query select p_package_id, p_decision, decision_time;
end;
$$;

revoke all on function public.record_supplement_review_package_decision(
  uuid, uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.record_supplement_review_package_decision(
  uuid, uuid, uuid, text, text, text
) to service_role;

commit;
