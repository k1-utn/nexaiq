begin;

create policy estimate_line_reviews_writer_insert
on public.estimate_line_reviews
for insert
to authenticated
with check (
  reviewer_id = (select auth.uid())
  and (select private.has_org_permission(organization_id, 'records:write'))
);

grant insert on table public.estimate_line_reviews to authenticated;

create or replace function private.prepare_estimate_line_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  line_organization_id uuid;
  line_estimate_version_id uuid;
  prior_review_id uuid;
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if new.decision not in ('confirmed', 'corrected', 'excluded', 'needs_review') then
    raise exception 'invalid estimate line review decision' using errcode = '22023';
  end if;

  new.corrected_description := nullif(btrim(new.corrected_description), '');
  new.note := nullif(btrim(new.note), '');

  if new.decision = 'corrected' and new.corrected_description is null then
    raise exception 'a corrected description is required' using errcode = '22023';
  end if;

  if new.decision <> 'corrected'
     and (new.corrected_description is not null or new.corrected_amount is not null) then
    raise exception 'corrected values are only accepted for a corrected decision'
      using errcode = '22023';
  end if;

  if new.corrected_amount is not null and new.corrected_amount < 0 then
    raise exception 'corrected amount cannot be negative' using errcode = '22023';
  end if;

  if new.decision <> 'confirmed' and new.note is null then
    raise exception 'a review note is required for this decision' using errcode = '22023';
  end if;

  select el.organization_id, el.estimate_version_id
    into line_organization_id, line_estimate_version_id
    from public.estimate_lines el
    join public.estimate_versions ev on ev.id = el.estimate_version_id
    where el.id = new.estimate_line_id
      and ev.organization_id = el.organization_id;

  if line_organization_id is null
     or not (select private.has_org_permission(line_organization_id, 'records:write')) then
    raise exception 'estimate line review access denied' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(line_estimate_version_id::text, 0));

  select r.id
    into prior_review_id
    from public.estimate_line_reviews r
    where r.estimate_line_id = new.estimate_line_id
      and not exists (
        select 1
        from public.estimate_line_reviews successor
        where successor.supersedes_review_id = r.id
      )
    limit 1;

  new.id := coalesce(new.id, gen_random_uuid());
  new.organization_id := line_organization_id;
  new.estimate_version_id := line_estimate_version_id;
  new.reviewer_id := caller_id;
  new.supersedes_review_id := prior_review_id;
  new.reviewed_at := clock_timestamp();
  return new;
end;
$$;

revoke all on function private.prepare_estimate_line_review()
  from public, anon, authenticated;

create or replace function private.finish_estimate_line_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  line_repair_order_id uuid;
  prior_verification_status text;
  new_verification_status text;
  total_line_count integer;
  final_review_count integer;
begin
  select ev.repair_order_id, ev.parse_status
    into line_repair_order_id, prior_verification_status
    from public.estimate_versions ev
    where ev.id = new.estimate_version_id;

  select count(*)
    into total_line_count
    from public.estimate_lines el
    where el.estimate_version_id = new.estimate_version_id;

  select count(*)
    into final_review_count
    from public.estimate_line_reviews r
    where r.estimate_version_id = new.estimate_version_id
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
        verified_by = case when new_verification_status = 'verified' then new.reviewer_id else null end,
        verified_at = case when new_verification_status = 'verified' then new.reviewed_at else null end
    where ev.id = new.estimate_version_id
      and (
        ev.parse_status is distinct from new_verification_status
        or (new_verification_status = 'verified' and ev.verified_by is distinct from new.reviewer_id)
      );

  insert into public.audit_events (
    organization_id, repair_order_id, actor_id, event_type, entity_type,
    entity_id, authentication_context, payload
  ) values (
    new.organization_id, line_repair_order_id, new.reviewer_id,
    'estimate_line_review_recorded', 'estimate_line', new.estimate_line_id,
    jsonb_build_object('provider', 'supabase_auth', 'workflow', 'human_estimate_verification'),
    jsonb_strip_nulls(jsonb_build_object(
      'review_id', new.id,
      'estimate_version_id', new.estimate_version_id,
      'decision', new.decision,
      'corrected_description', new.corrected_description,
      'corrected_amount', new.corrected_amount,
      'note', new.note,
      'supersedes_review_id', new.supersedes_review_id
    ))
  );

  if prior_verification_status is distinct from new_verification_status then
    insert into public.audit_events (
      organization_id, repair_order_id, actor_id, event_type, entity_type,
      entity_id, authentication_context, payload
    ) values (
      new.organization_id, line_repair_order_id, new.reviewer_id,
      case
        when new_verification_status = 'verified' then 'estimate_verification_completed'
        else 'estimate_verification_reopened'
      end,
      'estimate_version', new.estimate_version_id,
      jsonb_build_object('provider', 'supabase_auth', 'workflow', 'human_estimate_verification'),
      jsonb_build_object(
        'previous_status', prior_verification_status,
        'verification_status', new_verification_status,
        'total_lines', total_line_count,
        'final_reviews', final_review_count
      )
    );
  end if;

  return new;
end;
$$;

revoke all on function private.finish_estimate_line_review()
  from public, anon, authenticated;

create trigger estimate_line_reviews_prepare
  before insert on public.estimate_line_reviews
  for each row execute function private.prepare_estimate_line_review();

create trigger estimate_line_reviews_finish
  after insert on public.estimate_line_reviews
  for each row execute function private.finish_estimate_line_review();

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
security invoker
set search_path = ''
as $$
declare
  inserted_review_id uuid;
  inserted_estimate_version_id uuid;
  inserted_reviewed_at timestamptz;
  resulting_status text;
begin
  insert into public.estimate_line_reviews as review (
    estimate_line_id, decision, corrected_description, corrected_amount, note
  ) values (
    p_estimate_line_id, p_decision, p_corrected_description, p_corrected_amount, p_note
  )
  returning review.id, review.estimate_version_id, review.reviewed_at
    into inserted_review_id, inserted_estimate_version_id, inserted_reviewed_at;

  select ev.parse_status
    into resulting_status
    from public.estimate_versions ev
    where ev.id = inserted_estimate_version_id;

  return query
  select inserted_review_id, inserted_estimate_version_id, resulting_status, inserted_reviewed_at;
end;
$$;

revoke all on function public.record_estimate_line_review(uuid, text, text, numeric, text)
  from public, anon;
grant execute on function public.record_estimate_line_review(uuid, text, text, numeric, text)
  to authenticated;

alter function public.persist_estimate_parse(
  uuid, uuid, uuid, text, text, text, bigint, text, text, text, jsonb
) security invoker;

grant insert on table public.estimate_versions, public.estimate_lines to authenticated;

commit;
