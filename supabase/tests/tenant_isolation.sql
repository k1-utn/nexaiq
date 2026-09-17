begin;

do $$
declare
  missing_table text;
  rls_disabled_table text;
begin
  select required.table_name
    into missing_table
    from unnest(array[
      'organizations', 'repair_orders', 'audit_events', 'media',
      'estimate_line_reviews', 'scan_session_media', 'finding_evidence',
      'ai_evaluation_events'
    ])
      as required(table_name)
    where to_regclass('public.' || required.table_name) is null
    limit 1;

  if missing_table is not null then
    raise exception 'required table public.% is missing', missing_table;
  end if;

  select required.table_name
    into rls_disabled_table
    from unnest(array[
      'organizations', 'repair_orders', 'audit_events', 'media',
      'estimate_line_reviews', 'scan_session_media', 'finding_evidence',
      'ai_evaluation_events'
    ])
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
  if has_table_privilege('authenticated', 'public.findings', 'INSERT')
     or has_table_privilege('authenticated', 'public.ai_results', 'INSERT')
     or has_table_privilege('authenticated', 'public.supplement_candidates', 'INSERT') then
    raise exception 'authenticated clients can fabricate Stage 4 AI or review records';
  end if;

  if not has_table_privilege('authenticated', 'public.ai_evaluation_events', 'INSERT') then
    raise exception 'authenticated reviewers cannot append controlled evaluation events';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.get_supplement_analysis_readiness(uuid,uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'authenticated role cannot execute readiness check';
  end if;

  if has_function_privilege(
    'anon',
    'public.record_finding_review(uuid,text,text)',
    'EXECUTE'
  ) then
    raise exception 'anonymous role can execute finding review';
  end if;

  if has_function_privilege(
       'authenticated',
       'public.begin_supplement_analysis(uuid,uuid,uuid,text,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.complete_supplement_analysis(uuid,uuid,text,jsonb,integer,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.fail_supplement_analysis(uuid,uuid,text)',
       'EXECUTE'
     ) then
    raise exception 'browser roles can execute server-only analysis lifecycle functions';
  end if;

  if not has_function_privilege(
       'service_role',
       'public.begin_supplement_analysis(uuid,uuid,uuid,text,text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'public.complete_supplement_analysis(uuid,uuid,text,jsonb,integer,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'public.fail_supplement_analysis(uuid,uuid,text)',
       'EXECUTE'
     ) then
    raise exception 'service role cannot execute the controlled analysis lifecycle';
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
