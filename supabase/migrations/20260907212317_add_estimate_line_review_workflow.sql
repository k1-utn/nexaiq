begin;

create table public.estimate_line_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  estimate_version_id uuid not null references public.estimate_versions(id) on delete cascade,
  estimate_line_id uuid not null references public.estimate_lines(id) on delete cascade,
  reviewer_id uuid not null references public.users(id),
  decision text not null check (
    decision in ('confirmed', 'corrected', 'excluded', 'needs_review')
  ),
  corrected_description text,
  corrected_amount numeric(12,2),
  note text,
  supersedes_review_id uuid references public.estimate_line_reviews(id),
  reviewed_at timestamptz not null default now(),
  constraint estimate_line_reviews_corrected_fields_check check (
    (
      decision = 'corrected'
      and corrected_description is not null
      and length(btrim(corrected_description)) > 0
    )
    or (
      decision <> 'corrected'
      and corrected_description is null
      and corrected_amount is null
    )
  ),
  constraint estimate_line_reviews_reason_check check (
    decision = 'confirmed'
    or (note is not null and length(btrim(note)) > 0)
  ),
  constraint estimate_line_reviews_amount_check check (
    corrected_amount is null or corrected_amount >= 0
  ),
  constraint estimate_line_reviews_not_self_superseding_check check (
    supersedes_review_id is null or supersedes_review_id <> id
  ),
  unique (supersedes_review_id)
);

comment on table public.estimate_line_reviews is
  'Append-only human decisions over immutable parser output. The latest review in a line chain is authoritative.';
comment on column public.estimate_line_reviews.corrected_description is
  'Human-provided replacement description. The parsed estimate_lines.description remains unchanged.';

create unique index estimate_line_reviews_one_root_per_line_idx
  on public.estimate_line_reviews (estimate_line_id)
  where supersedes_review_id is null;
create index estimate_line_reviews_line_time_idx
  on public.estimate_line_reviews (estimate_line_id, reviewed_at desc);
create index estimate_line_reviews_version_time_idx
  on public.estimate_line_reviews (estimate_version_id, reviewed_at desc);
create index estimate_line_reviews_organization_version_time_idx
  on public.estimate_line_reviews (organization_id, estimate_version_id, reviewed_at desc);
create index estimate_line_reviews_reviewer_idx
  on public.estimate_line_reviews (reviewer_id);

alter table public.estimate_line_reviews enable row level security;
alter table public.estimate_line_reviews force row level security;

revoke all on table public.estimate_line_reviews from public, anon, authenticated;
grant select on table public.estimate_line_reviews to authenticated;

create policy estimate_line_reviews_member_read
on public.estimate_line_reviews
for select
to authenticated
using ((select private.is_org_member(organization_id)));

create or replace function private.prevent_estimate_line_review_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'estimate line reviews are append-only; create a superseding review'
    using errcode = '55000';
end;
$$;

revoke all on function private.prevent_estimate_line_review_mutation()
  from public, anon, authenticated;

create trigger estimate_line_reviews_append_only
  before update or delete on public.estimate_line_reviews
  for each row execute function private.prevent_estimate_line_review_mutation();

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
  review_time timestamptz := now();
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

  select el.organization_id, el.estimate_version_id, ev.repair_order_id,
         ev.parse_status
    into line_organization_id, line_estimate_version_id, line_repair_order_id,
         prior_verification_status
    from public.estimate_lines el
    join public.estimate_versions ev on ev.id = el.estimate_version_id
    where el.id = p_estimate_line_id
      and ev.organization_id = el.organization_id;

  if line_organization_id is null
     or not (select private.has_org_permission(line_organization_id, 'records:write')) then
    raise exception 'estimate line review access denied' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_estimate_line_id::text, 0));

  select r.id
    into prior_review_id
    from public.estimate_line_reviews r
    where r.estimate_line_id = p_estimate_line_id
    order by r.reviewed_at desc, r.id desc
    limit 1;

  insert into public.estimate_line_reviews (
    id,
    organization_id,
    estimate_version_id,
    estimate_line_id,
    reviewer_id,
    decision,
    corrected_description,
    corrected_amount,
    note,
    supersedes_review_id,
    reviewed_at
  ) values (
    new_review_id,
    line_organization_id,
    line_estimate_version_id,
    p_estimate_line_id,
    caller_id,
    p_decision,
    case when p_decision = 'corrected' then normalized_description else null end,
    case when p_decision = 'corrected' then p_corrected_amount else null end,
    normalized_note,
    prior_review_id,
    review_time
  );

  select count(*)
    into total_line_count
    from public.estimate_lines el
    where el.estimate_version_id = line_estimate_version_id;

  select count(*)
    into final_review_count
    from (
      select distinct on (r.estimate_line_id)
        r.estimate_line_id,
        r.decision
      from public.estimate_line_reviews r
      where r.estimate_version_id = line_estimate_version_id
      order by r.estimate_line_id, r.reviewed_at desc, r.id desc
    ) latest
    where latest.decision in ('confirmed', 'corrected', 'excluded');

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
    organization_id,
    repair_order_id,
    actor_id,
    event_type,
    entity_type,
    entity_id,
    authentication_context,
    payload
  ) values (
    line_organization_id,
    line_repair_order_id,
    caller_id,
    'estimate_line_review_recorded',
    'estimate_line',
    p_estimate_line_id,
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
      organization_id,
      repair_order_id,
      actor_id,
      event_type,
      entity_type,
      entity_id,
      authentication_context,
      payload
    ) values (
      line_organization_id,
      line_repair_order_id,
      caller_id,
      case
        when new_verification_status = 'verified' then 'estimate_verification_completed'
        else 'estimate_verification_reopened'
      end,
      'estimate_version',
      line_estimate_version_id,
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

-- Import persistence remains callable by authenticated writers, but it now owns
-- its inserts so source estimate records do not need browser-write privileges.
alter function public.persist_estimate_parse(
  uuid, uuid, uuid, text, text, text, bigint, text, text, text, jsonb
) security definer;

revoke insert, update, delete on table public.estimate_versions from authenticated;
revoke insert, update, delete on table public.estimate_lines from authenticated;
grant select on table public.estimate_versions, public.estimate_lines to authenticated;

commit;
