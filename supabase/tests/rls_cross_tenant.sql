begin;

select pg_advisory_xact_lock(hashtext('nexaiq-rls-cross-tenant-test'));

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, email_change, email_change_token_new, recovery_token
) values
  ('00000000-0000-0000-0000-000000000000','10000000-0000-4000-8000-000000000001','authenticated','authenticated','tenant-a@example.test','',now(),'{}','{}',now(),now(),'','','',''),
  ('00000000-0000-0000-0000-000000000000','20000000-0000-4000-8000-000000000002','authenticated','authenticated','tenant-b@example.test','',now(),'{}','{}',now(),now(),'','','','');

insert into public.organizations (id, name, slug) values
  ('a0000000-0000-4000-8000-000000000001','Tenant A','tenant-a-test'),
  ('b0000000-0000-4000-8000-000000000002','Tenant B','tenant-b-test');
insert into public.locations (id, organization_id, name) values
  ('a1000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','Location A'),
  ('b1000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','Location B');
insert into public.organization_members (organization_id, user_id, status) values
  ('a0000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','active'),
  ('b0000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','active');
insert into public.roles (id, organization_id, name) values
  ('a2000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','Estimator'),
  ('b2000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','Estimator');
insert into public.role_permissions (role_id, permission_id)
  select 'a2000000-0000-4000-8000-000000000001'::uuid, id from public.permissions where code = 'records:write'
  union all
  select 'b2000000-0000-4000-8000-000000000002'::uuid, id from public.permissions where code = 'records:write';
insert into public.user_roles (organization_id, user_id, role_id) values
  ('a0000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000001'),
  ('b0000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','b2000000-0000-4000-8000-000000000002');
insert into public.vehicles (id, organization_id, vin, year, make, model) values
  ('a3000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','TESTVIN00000000001',2025,'Toyota','RAV4'),
  ('b3000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','TESTVIN00000000002',2024,'Ford','F-150');
insert into public.repair_orders (id, organization_id, location_id, vehicle_id, ro_number) values
  ('a4000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001','A-100'),
  ('b4000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000002','b3000000-0000-4000-8000-000000000002','B-200');
insert into storage.objects (id, bucket_id, name, owner_id) values
  ('a5000000-0000-4000-8000-000000000001','repair-evidence','a0000000-0000-4000-8000-000000000001/a4000000-0000-4000-8000-000000000001/a5000000-0000-4000-8000-000000000001/a.pdf','10000000-0000-4000-8000-000000000001'),
  ('b5000000-0000-4000-8000-000000000002','repair-evidence','b0000000-0000-4000-8000-000000000002/b4000000-0000-4000-8000-000000000002/b5000000-0000-4000-8000-000000000002/b.pdf','20000000-0000-4000-8000-000000000002');

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  visible_repairs text[];
  visible_objects text[];
  persisted_media_id uuid;
begin
  select array_agg(ro_number order by ro_number)
    into visible_repairs
    from public.repair_orders;
  if visible_repairs is distinct from array['A-100']::text[] then
    raise exception 'tenant A repair-order visibility failed: %', visible_repairs;
  end if;

  if exists (
    select 1 from public.repair_orders
    where organization_id = 'b0000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'tenant A can read tenant B repair orders';
  end if;

  insert into public.repair_orders (
    organization_id, location_id, vehicle_id, ro_number
  ) values (
    'a0000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000001',
    'a3000000-0000-4000-8000-000000000001',
    'A-ALLOWED'
  );

  select result.source_media_id
    into persisted_media_id
    from public.persist_estimate_parse(
      'a0000000-0000-4000-8000-000000000001',
      'a4000000-0000-4000-8000-000000000001',
      'a6000000-0000-4000-8000-000000000001',
      'a0000000-0000-4000-8000-000000000001/a4000000-0000-4000-8000-000000000001/a6000000-0000-4000-8000-000000000001/estimate.pdf',
      'estimate.pdf',
      'application/pdf',
      128,
      repeat('0', 64),
      'nexaiq_test_parser',
      '1.0',
      '[]'::jsonb
    ) as result;
  if persisted_media_id is distinct from 'a6000000-0000-4000-8000-000000000001'::uuid
     or not exists (
       select 1 from public.media
       where id = 'a6000000-0000-4000-8000-000000000001'
         and object_path like '%/a6000000-0000-4000-8000-000000000001/%'
     ) then
    raise exception 'estimate source media identity was not preserved';
  end if;

  begin
    perform public.persist_estimate_parse(
      'a0000000-0000-4000-8000-000000000001',
      'a4000000-0000-4000-8000-000000000001',
      'a7000000-0000-4000-8000-000000000001',
      'b0000000-0000-4000-8000-000000000002/wrong/path.pdf',
      'estimate.pdf',
      'application/pdf',
      128,
      repeat('1', 64),
      'nexaiq_test_parser',
      '1.0',
      '[]'::jsonb
    );
    raise exception 'mismatched source object path was accepted';
  exception
    when invalid_parameter_value then null;
  end;

  begin
    insert into public.repair_orders (
      organization_id, location_id, vehicle_id, ro_number
    ) values (
      'b0000000-0000-4000-8000-000000000002',
      'b1000000-0000-4000-8000-000000000002',
      'b3000000-0000-4000-8000-000000000002',
      'ATTACK-1'
    );
    raise exception 'tenant A inserted a repair order into tenant B';
  exception
    when insufficient_privilege then null;
  end;

  select array_agg(name order by name)
    into visible_objects
    from storage.objects
    where bucket_id = 'repair-evidence';
  if visible_objects is distinct from array[
    'a0000000-0000-4000-8000-000000000001/a4000000-0000-4000-8000-000000000001/a5000000-0000-4000-8000-000000000001/a.pdf'
  ]::text[] then
    raise exception 'tenant A storage visibility failed: %', visible_objects;
  end if;
end;
$$;

select 'cross-tenant RLS checks passed' as result;

rollback;
