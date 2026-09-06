begin;

do $$
declare
  missing_table text;
  rls_disabled_table text;
begin
  select required.table_name
    into missing_table
    from unnest(array['organizations', 'repair_orders', 'audit_events', 'media'])
      as required(table_name)
    where to_regclass('public.' || required.table_name) is null
    limit 1;

  if missing_table is not null then
    raise exception 'required table public.% is missing', missing_table;
  end if;

  select required.table_name
    into rls_disabled_table
    from unnest(array['organizations', 'repair_orders', 'audit_events', 'media'])
      as required(table_name)
    join pg_class c on c.oid = to_regclass('public.' || required.table_name)
    where not c.relrowsecurity
    limit 1;

  if rls_disabled_table is not null then
    raise exception 'RLS is disabled on public.%', rls_disabled_table;
  end if;
end;
$$;

select 'tenant isolation schema checks passed' as result;

rollback;
