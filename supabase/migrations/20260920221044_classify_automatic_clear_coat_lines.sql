begin;

alter table public.estimate_lines
  add column line_role text not null default 'estimate_operation',
  add constraint estimate_lines_line_role_check check (
    line_role in ('estimate_operation', 'automatic_refinish_calculation')
  );

comment on column public.estimate_lines.line_role is
  'Source-line classification. Clear coat is preserved as an automatic refinish calculation and is not a separately editable estimate operation.';

insert into public.audit_events (
  organization_id, repair_order_id, event_type, entity_type, entity_id,
  authentication_context, payload
)
select
  line.organization_id,
  estimate.repair_order_id,
  'estimate_line_automatic_refinish_classified',
  'estimate_line',
  line.id,
  jsonb_build_object('provider', 'system_migration'),
  jsonb_build_object(
    'estimate_version_id', line.estimate_version_id,
    'line_role', 'automatic_refinish_calculation',
    'reason', 'clear_coat_is_automatically_derived_from_refinish_operations'
  )
from public.estimate_lines line
join public.estimate_versions estimate
  on estimate.id = line.estimate_version_id
 and estimate.organization_id = line.organization_id
where line.description ~* '\mclear[ -]?coat\M';

update public.estimate_lines line
set line_role = 'automatic_refinish_calculation'
where line.description ~* '\mclear[ -]?coat\M';

create function private.classify_estimate_line_role()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.line_role := case
    when new.description ~* '\mclear[ -]?coat\M'
      then 'automatic_refinish_calculation'
    else 'estimate_operation'
  end;
  return new;
end;
$$;

revoke all on function private.classify_estimate_line_role()
  from public, anon, authenticated;

create trigger estimate_lines_classify_role
  before insert or update of description on public.estimate_lines
  for each row execute function private.classify_estimate_line_role();

create function private.prevent_automatic_estimate_line_review()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.estimate_lines line
    where line.id = new.estimate_line_id
      and line.line_role = 'automatic_refinish_calculation'
  ) then
    raise exception 'automatic refinish calculations do not accept separate review decisions'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function private.prevent_automatic_estimate_line_review()
  from public, anon, authenticated;

create trigger estimate_line_reviews_automatic_guard
  before insert on public.estimate_line_reviews
  for each row execute function private.prevent_automatic_estimate_line_review();

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
    where el.estimate_version_id = new.estimate_version_id
      and el.line_role = 'estimate_operation';

  select count(*)
    into final_review_count
    from public.estimate_line_reviews r
    join public.estimate_lines el
      on el.id = r.estimate_line_id
     and el.estimate_version_id = r.estimate_version_id
    where r.estimate_version_id = new.estimate_version_id
      and el.line_role = 'estimate_operation'
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
        verified_by = case
          when new_verification_status = 'verified' then new.reviewer_id
          else null
        end,
        verified_at = case
          when new_verification_status = 'verified' then new.reviewed_at
          else null
        end
    where ev.id = new.estimate_version_id
      and (
        ev.parse_status is distinct from new_verification_status
        or (
          new_verification_status = 'verified'
          and ev.verified_by is distinct from new.reviewer_id
        )
      );

  insert into public.audit_events (
    organization_id, repair_order_id, actor_id, event_type, entity_type,
    entity_id, authentication_context, payload
  ) values (
    new.organization_id, line_repair_order_id, new.reviewer_id,
    'estimate_line_review_recorded', 'estimate_line', new.estimate_line_id,
    jsonb_build_object(
      'provider', 'supabase_auth',
      'workflow', 'human_estimate_verification'
    ),
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
        when new_verification_status = 'verified'
          then 'estimate_verification_completed'
        else 'estimate_verification_reopened'
      end,
      'estimate_version', new.estimate_version_id,
      jsonb_build_object(
        'provider', 'supabase_auth',
        'workflow', 'human_estimate_verification'
      ),
      jsonb_build_object(
        'previous_status', prior_verification_status,
        'verification_status', new_verification_status,
        'total_lines', total_line_count,
        'final_reviews', final_review_count,
        'automatic_lines_excluded', true
      )
    );
  end if;

  return new;
end;
$$;

revoke all on function private.finish_estimate_line_review()
  from public, anon, authenticated;

commit;
