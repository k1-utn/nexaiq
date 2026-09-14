begin;

alter table public.estimate_line_reviews
  alter column reviewed_at set default clock_timestamp();

create or replace function public.record_estimate_line_review(
  p_estimate_line_id uuid,
  p_decision text,
  p_corrected_description text default null,
  p_corrected_amount numeric default null,
  p_note text default null
)
returns table (
  review_id uuid,
  estimate_version_id uuid,
  verification_status text,
  reviewed_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  line_organization_id uuid;
  line_estimate_version_id uuid;
  line_repair_order_id uuid;
  prior_review_id uuid;
  new_review_id uuid := gen_random_uuid();
  review_time timestamptz := clock_timestamp();
  prior_verification_status text;
  new_verification_status text;
  total_line_count integer;
  final_review_count integer;
  normalized_description text := nullif(btrim(p_corrected_description), '');
  normalized_note text := nullif(btrim(p_note), '');
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if p_decision not in ('confirmed', 'corrected', 'excluded', 'needs_review') then
    raise exception 'invalid estimate line review decision' using errcode = '22023';
  end if;

  if p_decision = 'corrected' and normalized_description is null then
    raise exception 'a corrected description is required' using errcode = '22023';
  end if;

  if p_decision <> 'corrected'
     and (p_corrected_description is not null or p_corrected_amount is not null) then
    raise exception 'corrected values are only accepted for a corrected decision'
      using errcode = '22023';
  end if;

  if p_corrected_amount is not null and p_corrected_amount < 0 then
    raise exception 'corrected amount cannot be negative' using errcode = '22023';
  end if;

  if p_decision <> 'confirmed' and normalized_note is null then
    raise exception 'a review note is required for this decision' using errcode = '22023';
  end if;

  select el.organization_id, el.estimate_version_id, ev.repair_order_id
    into line_organization_id, line_estimate_version_id, line_repair_order_id
    from public.estimate_lines el
    join public.estimate_versions ev on ev.id = el.estimate_version_id
    where el.id = p_estimate_line_id
      and ev.organization_id = el.organization_id;

  if line_organization_id is null
     or not (select private.has_org_permission(line_organization_id, 'records:write')) then
    raise exception 'estimate line review access denied' using errcode = '42501';
  end if;

  -- One version-level lock serializes line reviews and completion-state changes.
  perform pg_advisory_xact_lock(hashtextextended(line_estimate_version_id::text, 0));

  select ev.parse_status
    into prior_verification_status
    from public.estimate_versions ev
    where ev.id = line_estimate_version_id;

  -- The current review is the leaf of the append-only supersession chain.
  select r.id
    into prior_review_id
    from public.estimate_line_reviews r
    where r.estimate_line_id = p_estimate_line_id
      and not exists (
        select 1
        from public.estimate_line_reviews successor
        where successor.supersedes_review_id = r.id
      )
    limit 1;

  insert into public.estimate_line_reviews (
    id, organization_id, estimate_version_id, estimate_line_id, reviewer_id,
    decision, corrected_description, corrected_amount, note,
    supersedes_review_id, reviewed_at
  ) values (
    new_review_id, line_organization_id, line_estimate_version_id,
    p_estimate_line_id, caller_id, p_decision,
    case when p_decision = 'corrected' then normalized_description else null end,
    case when p_decision = 'corrected' then p_corrected_amount else null end,
    normalized_note, prior_review_id, review_time
  );

  select count(*)
    into total_line_count
    from public.estimate_lines el
    where el.estimate_version_id = line_estimate_version_id;

  select count(*)
    into final_review_count
    from public.estimate_line_reviews r
    where r.estimate_version_id = line_estimate_version_id
      and r.decision in ('confirmed', 'corrected', 'excluded')
      and not exists (
        select 1
        from public.estimate_line_reviews successor
        where successor.supersedes_review_id = r.id
      );

  new_verification_status := case
    when total_line_count > 0 and final_review_count = total_line_count then 'verified'
    else 'requires_human_verification'
  end;

  update public.estimate_versions ev
    set parse_status = new_verification_status,
        verified_by = case when new_verification_status = 'verified' then caller_id else null end,
        verified_at = case when new_verification_status = 'verified' then review_time else null end
    where ev.id = line_estimate_version_id
      and (
        ev.parse_status is distinct from new_verification_status
        or (new_verification_status = 'verified' and ev.verified_by is distinct from caller_id)
      );

  insert into public.audit_events (
    organization_id, repair_order_id, actor_id, event_type, entity_type,
    entity_id, authentication_context, payload
  ) values (
    line_organization_id, line_repair_order_id, caller_id,
    'estimate_line_review_recorded', 'estimate_line', p_estimate_line_id,
    jsonb_build_object('provider', 'supabase_auth', 'workflow', 'human_estimate_verification'),
    jsonb_strip_nulls(jsonb_build_object(
      'review_id', new_review_id,
      'estimate_version_id', line_estimate_version_id,
      'decision', p_decision,
      'corrected_description', case when p_decision = 'corrected' then normalized_description else null end,
      'corrected_amount', case when p_decision = 'corrected' then p_corrected_amount else null end,
      'note', normalized_note,
      'supersedes_review_id', prior_review_id
    ))
  );

  if prior_verification_status is distinct from new_verification_status then
    insert into public.audit_events (
      organization_id, repair_order_id, actor_id, event_type, entity_type,
      entity_id, authentication_context, payload
    ) values (
      line_organization_id, line_repair_order_id, caller_id,
      case
        when new_verification_status = 'verified' then 'estimate_verification_completed'
        else 'estimate_verification_reopened'
      end,
      'estimate_version', line_estimate_version_id,
      jsonb_build_object('provider', 'supabase_auth', 'workflow', 'human_estimate_verification'),
      jsonb_build_object(
        'previous_status', prior_verification_status,
        'verification_status', new_verification_status,
        'total_lines', total_line_count,
        'final_reviews', final_review_count
      )
    );
  end if;

  return query
  select new_review_id, line_estimate_version_id, new_verification_status, review_time;
end;
$$;

revoke all on function public.record_estimate_line_review(uuid, text, text, numeric, text)
  from public, anon;
grant execute on function public.record_estimate_line_review(uuid, text, text, numeric, text)
  to authenticated;

commit;
