begin;

do $$
declare
  missing_table text;
  rls_disabled_table text;
begin
  select required.table_name
    into missing_table
    from unnest(array['organizations', 'repair_orders', 'audit_events', 'media', 'estimate_line_reviews', 'scan_session_media'])
      as required(table_name)
    where to_regclass('public.' || required.table_name) is null
    limit 1;

  if missing_table is not null then
    raise exception 'required table public.% is missing', missing_table;
  end if;

  select required.table_name
    into rls_disabled_table
    from unnest(array['organizations', 'repair_orders', 'audit_events', 'media', 'estimate_line_reviews', 'scan_session_media'])
      as required(table_name)
    join pg_class c on c.oid = to_regclass('public.' || required.table_name)
    where not c.relrowsecurity
    limit 1;

  if rls_disabled_table is not null then
    raise exception 'RLS is disabled on public.%', rls_disabled_table;
  end if;
end;
$$;

do $$
begin
  if private.storage_organization_id(
    '00000000-0000-0000-0000-000000000001/repair-order/evidence.pdf'
  ) is distinct from '00000000-0000-0000-0000-000000000001'::uuid then
    raise exception 'storage tenant parsing rejected a valid deterministic UUID';
  end if;

  if private.storage_organization_id('not-an-organization/evidence.pdf') is not null then
    raise exception 'storage tenant parsing accepted an invalid UUID';
  end if;
end;
$$;

select 'tenant isolation schema checks passed' as result;

rollback;
