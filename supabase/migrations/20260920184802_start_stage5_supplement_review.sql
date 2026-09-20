begin;

alter table public.supplement_candidates
  add column review_note text,
  add column oem_consideration_status text not null default 'not_reviewed',
  add column oem_source_document_id uuid,
  add column oem_source_note text,
  add column reviewed_by uuid references public.users(id) on delete set null,
  add column reviewed_at timestamptz,
  add column updated_at timestamptz not null default now(),
  add constraint supplement_candidates_oem_status_check check (
    oem_consideration_status in (
      'not_reviewed', 'review_recommended', 'source_reviewed',
      'source_unavailable', 'not_applicable'
    )
  );

create unique index documents_id_organization_unique
  on public.documents (id, organization_id);
create unique index supplement_candidates_id_organization_unique
  on public.supplement_candidates (id, organization_id);

alter table public.supplement_candidates
  add constraint supplement_candidates_oem_document_tenant_fk
    foreign key (oem_source_document_id, organization_id)
    references public.documents (id, organization_id) on delete restrict;

create index supplement_candidates_org_ro_review_idx
  on public.supplement_candidates (organization_id, repair_order_id, status, updated_at desc);
create index supplement_candidates_oem_document_idx
  on public.supplement_candidates (oem_source_document_id)
  where oem_source_document_id is not null;
create index supplement_candidates_reviewed_by_idx
  on public.supplement_candidates (reviewed_by)
  where reviewed_by is not null;

create table public.supplement_candidate_review_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id) on delete cascade,
  supplement_candidate_id uuid not null references public.supplement_candidates(id) on delete restrict,
  actor_id uuid not null references public.users(id) on delete restrict,
  decision text not null check (
    decision in ('ready_for_package', 'needs_changes', 'excluded')
  ),
  review_reason text,
  oem_consideration_status text not null check (
    oem_consideration_status in (
      'review_recommended', 'source_reviewed', 'source_unavailable', 'not_applicable'
    )
  ),
  oem_source_document_id uuid,
  oem_source_note text,
  supersedes_event_id uuid references public.supplement_candidate_review_events(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint supplement_candidate_review_reason_check check (
    decision = 'ready_for_package'
    or (review_reason is not null and length(btrim(review_reason)) >= 3)
  ),
  constraint supplement_candidate_review_source_check check (
    oem_consideration_status <> 'source_reviewed'
    or oem_source_document_id is not null
  ),
  constraint supplement_candidate_review_unavailable_note_check check (
    oem_consideration_status <> 'source_unavailable'
    or (oem_source_note is not null and length(btrim(oem_source_note)) >= 3)
  ),
  constraint supplement_candidate_review_not_self_superseding_check check (
    supersedes_event_id is null or supersedes_event_id <> id
  ),
  unique (supersedes_event_id)
);

comment on table public.supplement_candidate_review_events is
  'Append-only estimator review history for confirmed supplement candidates.';

create index supplement_candidate_reviews_org_ro_time_idx
  on public.supplement_candidate_review_events
  (organization_id, repair_order_id, created_at desc);
create index supplement_candidate_reviews_candidate_time_idx
  on public.supplement_candidate_review_events
  (supplement_candidate_id, created_at desc);
create index supplement_candidate_reviews_actor_idx
  on public.supplement_candidate_review_events (actor_id);
create index supplement_candidate_reviews_oem_document_idx
  on public.supplement_candidate_review_events (oem_source_document_id)
  where oem_source_document_id is not null;

alter table public.supplement_candidate_review_events
  add constraint supplement_candidate_reviews_candidate_tenant_fk
    foreign key (supplement_candidate_id, organization_id)
    references public.supplement_candidates (id, organization_id) on delete restrict,
  add constraint supplement_candidate_reviews_repair_order_tenant_fk
    foreign key (repair_order_id, organization_id)
    references public.repair_orders (id, organization_id) on delete cascade,
  add constraint supplement_candidate_reviews_oem_document_tenant_fk
    foreign key (oem_source_document_id, organization_id)
    references public.documents (id, organization_id) on delete restrict;

create table public.supplement_review_packages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id) on delete cascade,
  package_number integer not null check (package_number > 0),
  status text not null default 'draft' check (
    status in ('draft', 'approved', 'changes_requested')
  ),
  created_by uuid not null references public.users(id) on delete restrict,
  approval_note text,
  approval_attestation text,
  approved_by uuid references public.users(id) on delete restrict,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (repair_order_id, package_number),
  constraint supplement_review_package_approval_check check (
    status <> 'approved'
    or (
      approved_by is not null
      and approved_at is not null
      and approval_attestation is not null
      and length(btrim(approval_attestation)) > 0
    )
  ),
  constraint supplement_review_package_changes_note_check check (
    status <> 'changes_requested'
    or (approval_note is not null and length(btrim(approval_note)) >= 3)
  )
);

create unique index supplement_review_packages_id_organization_unique
  on public.supplement_review_packages (id, organization_id);
create index supplement_review_packages_org_ro_time_idx
  on public.supplement_review_packages
  (organization_id, repair_order_id, created_at desc);
create index supplement_review_packages_created_by_idx
  on public.supplement_review_packages (created_by);
create index supplement_review_packages_approved_by_idx
  on public.supplement_review_packages (approved_by)
  where approved_by is not null;

alter table public.supplement_review_packages
  add constraint supplement_review_packages_repair_order_tenant_fk
    foreign key (repair_order_id, organization_id)
    references public.repair_orders (id, organization_id) on delete cascade;

create table public.supplement_review_package_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  package_id uuid not null references public.supplement_review_packages(id) on delete cascade,
  supplement_candidate_id uuid not null references public.supplement_candidates(id) on delete restrict,
  sequence_number integer not null check (sequence_number > 0),
  proposed_operation text not null,
  reason text not null,
  review_note text,
  oem_consideration_status text not null,
  oem_source_document_id uuid,
  oem_source_note text,
  evidence_references jsonb not null default '[]'::jsonb check (
    jsonb_typeof(evidence_references) = 'array'
  ),
  source_snapshot jsonb not null default '{}'::jsonb check (
    jsonb_typeof(source_snapshot) = 'object'
  ),
  created_at timestamptz not null default now(),
  unique (package_id, supplement_candidate_id),
  unique (package_id, sequence_number)
);

comment on table public.supplement_review_package_items is
  'Immutable report snapshots; later candidate reviews do not silently rewrite prior packages.';

create index supplement_review_package_items_org_package_idx
  on public.supplement_review_package_items (organization_id, package_id, sequence_number);
create index supplement_review_package_items_candidate_idx
  on public.supplement_review_package_items (supplement_candidate_id);
create index supplement_review_package_items_oem_document_idx
  on public.supplement_review_package_items (oem_source_document_id)
  where oem_source_document_id is not null;

alter table public.supplement_review_package_items
  add constraint supplement_review_package_items_package_tenant_fk
    foreign key (package_id, organization_id)
    references public.supplement_review_packages (id, organization_id) on delete cascade,
  add constraint supplement_review_package_items_candidate_tenant_fk
    foreign key (supplement_candidate_id, organization_id)
    references public.supplement_candidates (id, organization_id) on delete restrict,
  add constraint supplement_review_package_items_oem_document_tenant_fk
    foreign key (oem_source_document_id, organization_id)
    references public.documents (id, organization_id) on delete restrict;

alter table public.supplement_candidate_review_events enable row level security;
alter table public.supplement_candidate_review_events force row level security;
alter table public.supplement_review_packages enable row level security;
alter table public.supplement_review_packages force row level security;
alter table public.supplement_review_package_items enable row level security;
alter table public.supplement_review_package_items force row level security;

revoke all on table
  public.supplement_candidate_review_events,
  public.supplement_review_packages,
  public.supplement_review_package_items
from public, anon, authenticated;

grant select on table
  public.supplement_candidate_review_events,
  public.supplement_review_packages,
  public.supplement_review_package_items
to authenticated;
grant insert on table public.supplement_candidate_review_events to authenticated;

create policy supplement_candidate_review_events_member_read
on public.supplement_candidate_review_events
for select
to authenticated
using ((select private.is_org_member(organization_id)));

create policy supplement_candidate_review_events_controlled_insert
on public.supplement_candidate_review_events
for insert
to authenticated
with check ((select private.has_org_permission(organization_id, 'records:write')));

create policy supplement_review_packages_member_read
on public.supplement_review_packages
for select
to authenticated
using ((select private.is_org_member(organization_id)));

create policy supplement_review_package_items_member_read
on public.supplement_review_package_items
for select
to authenticated
using ((select private.is_org_member(organization_id)));

create or replace function private.prevent_supplement_review_history_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'supplement review history is append-only; create a superseding event'
    using errcode = '55000';
end;
$$;

revoke all on function private.prevent_supplement_review_history_mutation()
  from public, anon, authenticated;

create trigger supplement_candidate_review_events_append_only
  before update or delete on public.supplement_candidate_review_events
  for each row execute function private.prevent_supplement_review_history_mutation();

create or replace function private.prepare_supplement_candidate_review_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  candidate_organization_id uuid;
  candidate_repair_order_id uuid;
  prior_event_id uuid;
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  if new.decision not in ('ready_for_package', 'needs_changes', 'excluded') then
    raise exception 'invalid supplement candidate review decision' using errcode = '22023';
  end if;

  new.review_reason := nullif(btrim(new.review_reason), '');
  new.oem_source_note := nullif(btrim(new.oem_source_note), '');

  if new.decision <> 'ready_for_package'
     and (new.review_reason is null or length(new.review_reason) < 3) then
    raise exception 'a review reason is required for this decision' using errcode = '22023';
  end if;

  if new.oem_consideration_status not in (
    'review_recommended', 'source_reviewed', 'source_unavailable', 'not_applicable'
  ) then
    raise exception 'record an OEM/source consideration status' using errcode = '22023';
  end if;

  if new.decision = 'ready_for_package'
     and new.oem_consideration_status = 'review_recommended' then
    raise exception 'resolve the OEM/source consideration before package approval'
      using errcode = '22023';
  end if;

  if new.oem_consideration_status = 'source_reviewed'
     and new.oem_source_document_id is null then
    raise exception 'select the reviewed OEM/source document' using errcode = '22023';
  end if;

  if new.oem_consideration_status = 'source_unavailable'
     and (new.oem_source_note is null or length(new.oem_source_note) < 3) then
    raise exception 'explain why the source is unavailable' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(new.supplement_candidate_id::text, 0));

  select candidate.organization_id, candidate.repair_order_id
    into candidate_organization_id, candidate_repair_order_id
    from public.supplement_candidates candidate
    where candidate.id = new.supplement_candidate_id;

  if candidate_organization_id is null
     or not (select private.has_org_permission(candidate_organization_id, 'records:write')) then
    raise exception 'supplement candidate review access denied' using errcode = '42501';
  end if;

  if new.oem_source_document_id is not null and not exists (
    select 1
    from public.documents document
    where document.id = new.oem_source_document_id
      and document.organization_id = candidate_organization_id
      and document.repair_order_id = candidate_repair_order_id
  ) then
    raise exception 'OEM/source document does not belong to this repair order'
      using errcode = '22023';
  end if;

  select event.id
    into prior_event_id
    from public.supplement_candidate_review_events event
    where event.supplement_candidate_id = new.supplement_candidate_id
      and not exists (
        select 1
        from public.supplement_candidate_review_events successor
        where successor.supersedes_event_id = event.id
      )
    limit 1;

  new.id := gen_random_uuid();
  new.organization_id := candidate_organization_id;
  new.repair_order_id := candidate_repair_order_id;
  new.actor_id := caller_id;
  new.supersedes_event_id := prior_event_id;
  new.created_at := clock_timestamp();
  return new;
end;
$$;

revoke all on function private.prepare_supplement_candidate_review_event()
  from public, anon, authenticated;

create or replace function private.finish_supplement_candidate_review_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  resulting_status text;
begin
  resulting_status := case new.decision
    when 'ready_for_package' then 'confirmed'
    when 'excluded' then 'dismissed'
    else 'review_reopened'
  end;

  update public.supplement_candidates
    set status = resulting_status,
        review_note = new.review_reason,
        oem_consideration_status = new.oem_consideration_status,
        oem_source_document_id = new.oem_source_document_id,
        oem_source_note = new.oem_source_note,
        reviewed_by = new.actor_id,
        reviewed_at = new.created_at,
        updated_at = new.created_at
    where id = new.supplement_candidate_id
      and organization_id = new.organization_id;

  insert into public.audit_events (
    organization_id, repair_order_id, actor_id, event_type,
    entity_type, entity_id, authentication_context, payload
  ) values (
    new.organization_id, new.repair_order_id, new.actor_id,
    'supplement_candidate_review_recorded', 'supplement_candidate',
    new.supplement_candidate_id,
    jsonb_build_object('provider', 'supabase_auth', 'workflow', 'supplement_review'),
    jsonb_strip_nulls(jsonb_build_object(
      'review_event_id', new.id,
      'decision', new.decision,
      'resulting_status', resulting_status,
      'review_reason', new.review_reason,
      'oem_consideration_status', new.oem_consideration_status,
      'oem_source_document_id', new.oem_source_document_id,
      'oem_source_note', new.oem_source_note,
      'supersedes_event_id', new.supersedes_event_id
    ))
  );

  return new;
end;
$$;

revoke all on function private.finish_supplement_candidate_review_event()
  from public, anon, authenticated;

create trigger supplement_candidate_review_prepare
  before insert on public.supplement_candidate_review_events
  for each row execute function private.prepare_supplement_candidate_review_event();

create trigger supplement_candidate_review_finish
  after insert on public.supplement_candidate_review_events
  for each row execute function private.finish_supplement_candidate_review_event();

create or replace function public.create_supplement_review_package(
  p_repair_order_id uuid
)
returns table (
  package_id uuid,
  package_number integer,
  item_count integer,
  package_status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  package_organization_id uuid;
  next_package_number integer;
  created_package_id uuid := gen_random_uuid();
  created_item_count integer;
  created_at_time timestamptz := clock_timestamp();
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_repair_order_id::text, 1));

  select repair_order.organization_id
    into package_organization_id
    from public.repair_orders repair_order
    where repair_order.id = p_repair_order_id;

  if package_organization_id is null
     or not (select private.has_org_permission(package_organization_id, 'records:write')) then
    raise exception 'supplement package access denied' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.supplement_candidates candidate
    where candidate.organization_id = package_organization_id
      and candidate.repair_order_id = p_repair_order_id
      and candidate.status = 'confirmed'
  ) then
    raise exception 'at least one package-ready candidate is required' using errcode = '22023';
  end if;

  select coalesce(max(package.package_number), 0) + 1
    into next_package_number
    from public.supplement_review_packages package
    where package.repair_order_id = p_repair_order_id
      and package.organization_id = package_organization_id;

  insert into public.supplement_review_packages (
    id, organization_id, repair_order_id, package_number,
    status, created_by, created_at, updated_at
  ) values (
    created_package_id, package_organization_id, p_repair_order_id,
    next_package_number, 'draft', caller_id, created_at_time, created_at_time
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
  where candidate.organization_id = package_organization_id
    and candidate.repair_order_id = p_repair_order_id
    and candidate.status = 'confirmed';

  get diagnostics created_item_count = row_count;

  insert into public.audit_events (
    organization_id, repair_order_id, actor_id, event_type,
    entity_type, entity_id, authentication_context, payload
  ) values (
    package_organization_id, p_repair_order_id, caller_id,
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

revoke all on function public.create_supplement_review_package(uuid)
  from public, anon;
grant execute on function public.create_supplement_review_package(uuid)
  to authenticated;

create or replace function public.record_supplement_review_package_decision(
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
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  package_organization_id uuid;
  package_repair_order_id uuid;
  package_number_value integer;
  decision_time timestamptz := clock_timestamp();
  normalized_note text := nullif(btrim(p_note), '');
  normalized_attestation text := nullif(btrim(p_attestation), '');
  required_attestation constant text :=
    'I confirm that I reviewed this supplement package and its linked evidence. This is an estimator decision and does not certify repair safety or insurer payment.';
begin
  if caller_id is null then
    raise exception 'authentication required' using errcode = '42501';
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

  select package.organization_id, package.repair_order_id, package.package_number
    into package_organization_id, package_repair_order_id, package_number_value
    from public.supplement_review_packages package
    where package.id = p_package_id;

  if package_organization_id is null
     or not (select private.has_org_permission(package_organization_id, 'records:write')) then
    raise exception 'supplement package decision access denied' using errcode = '42501';
  end if;

  update public.supplement_review_packages
    set status = p_decision,
        approval_note = normalized_note,
        approval_attestation = case
          when p_decision = 'approved' then normalized_attestation
          else null
        end,
        approved_by = case when p_decision = 'approved' then caller_id else null end,
        approved_at = case when p_decision = 'approved' then decision_time else null end,
        updated_at = decision_time
    where id = p_package_id
      and organization_id = package_organization_id;

  insert into public.audit_events (
    organization_id, repair_order_id, actor_id, event_type,
    entity_type, entity_id, authentication_context, payload
  ) values (
    package_organization_id, package_repair_order_id, caller_id,
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

revoke all on function public.record_supplement_review_package_decision(uuid, text, text, text)
  from public, anon;
grant execute on function public.record_supplement_review_package_decision(uuid, text, text, text)
  to authenticated;

commit;
