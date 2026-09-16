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
insert into public.media (
  id, organization_id, repair_order_id, uploader_id, object_path,
  original_filename, mime_type, byte_size, content_sha256, purpose
) values (
  'b5000000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000002',
  'b4000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000002/b4000000-0000-4000-8000-000000000002/b5000000-0000-4000-8000-000000000002/b.pdf',
  'b.pdf', 'application/pdf', 128, repeat('b', 64), 'estimate_source'
);
insert into public.estimate_versions (
  id, organization_id, repair_order_id, version_number, source_media_id,
  source_sha256, parser_name, parser_version
) values (
  'b6000000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000002',
  'b4000000-0000-4000-8000-000000000002', 1,
  'b5000000-0000-4000-8000-000000000002', repeat('b', 64),
  'nexaiq_test_parser', '1.0'
);
insert into public.estimate_lines (
  id, organization_id, estimate_version_id, source_line_number,
  operation_code, description, amount, raw_text, parse_confidence
) values (
  'b7000000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000002',
  'b6000000-0000-4000-8000-000000000002', 1,
  'R&I', 'Tenant B line', 50.00, '1 R&I Tenant B line 50.00', 0.9000
);

set local role anon;
do $$
begin
  begin
    perform 1 from public.estimate_line_reviews;
    raise exception 'anonymous role read estimate review history';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.record_estimate_line_review(
      'b7000000-0000-4000-8000-000000000002', 'confirmed', null, null, null
    );
    raise exception 'anonymous role recorded an estimate review';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;
reset role;

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
  persisted_estimate_id uuid;
  persisted_line_id uuid;
  first_review_id uuid;
  latest_review_id uuid;
  direct_review_id uuid;
  returned_status text;
  persisted_scan_session_id uuid;
  persisted_scan_media_id uuid;
  persisted_scan_link_id uuid;
  duplicate_scan_session_id uuid;
  duplicate_scan_media_id uuid;
  duplicate_scan_link_id uuid;
  duplicate_capture boolean;
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

  select result.source_media_id, result.estimate_version_id
    into persisted_media_id, persisted_estimate_id
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
      jsonb_build_array(jsonb_build_object(
        'source_line_number', 12,
        'operation_code', 'RPL',
        'description', 'Replace bumper cover',
        'amount', 125.00,
        'raw_text', '12 RPL Replace bumper cover 125.00',
        'confidence', 0.9100
      ))
    ) as result;
  if persisted_media_id is distinct from 'a6000000-0000-4000-8000-000000000001'::uuid
     or not exists (
       select 1 from public.media
       where id = 'a6000000-0000-4000-8000-000000000001'
         and object_path like '%/a6000000-0000-4000-8000-000000000001/%'
     ) then
    raise exception 'estimate source media identity was not preserved';
  end if;

  select id into persisted_line_id
    from public.estimate_lines
    where estimate_version_id = persisted_estimate_id;

  select result.review_id, result.verification_status
    into first_review_id, returned_status
    from public.record_estimate_line_review(
      persisted_line_id, 'confirmed', null, null, null
    ) as result;
  if returned_status <> 'verified'
     or not exists (
       select 1 from public.estimate_line_reviews r
       where r.id = first_review_id
         and r.reviewer_id = '10000000-0000-4000-8000-000000000001'
         and r.organization_id = 'a0000000-0000-4000-8000-000000000001'
         and r.decision = 'confirmed'
     ) then
    raise exception 'confirmed review attribution or completion status failed';
  end if;

  select result.verification_status
    into returned_status
    from public.record_estimate_line_review(
      persisted_line_id, 'needs_review', null, null,
      'Confirm the operation against the source page.'
    ) as result;
  if returned_status <> 'requires_human_verification' then
    raise exception 'needs-review decision did not reopen verification';
  end if;

  select result.review_id, result.verification_status
    into latest_review_id, returned_status
    from public.record_estimate_line_review(
      persisted_line_id, 'corrected', 'Replace front bumper cover', 135.00,
      'The PDF identifies the front bumper and a revised amount.'
    ) as result;
  if returned_status <> 'verified'
     or not exists (
       select 1 from public.estimate_line_reviews r
       where r.id = latest_review_id
         and r.supersedes_review_id is not null
         and r.decision = 'corrected'
         and r.corrected_description = 'Replace front bumper cover'
         and r.corrected_amount = 135.00
     ) then
    raise exception 'corrected review chain or completion status failed';
  end if;

  if not exists (
    select 1 from public.estimate_lines el
    where el.id = persisted_line_id
      and el.description = 'Replace bumper cover'
      and el.amount = 125.00
      and el.raw_text = '12 RPL Replace bumper cover 125.00'
  ) then
    raise exception 'parsed estimate source line was mutated by human review';
  end if;

  if (
    select count(*)
    from public.audit_events ae
    where ae.entity_id in (persisted_line_id, persisted_estimate_id)
      and ae.event_type in (
        'estimate_line_review_recorded',
        'estimate_verification_completed',
        'estimate_verification_reopened'
      )
  ) <> 6 then
    raise exception 'estimate review audit trail is incomplete';
  end if;

  begin
    perform public.record_estimate_line_review(
      'b7000000-0000-4000-8000-000000000002',
      'confirmed', null, null, null
    );
    raise exception 'tenant A reviewed a tenant B estimate line';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.estimate_line_reviews (
    organization_id, estimate_version_id, estimate_line_id, reviewer_id, decision
  ) values (
    'b0000000-0000-4000-8000-000000000002',
    'b6000000-0000-4000-8000-000000000002',
    persisted_line_id,
    '20000000-0000-4000-8000-000000000002',
    'confirmed'
  ) returning id into direct_review_id;
  if not exists (
    select 1 from public.estimate_line_reviews r
    where r.id = direct_review_id
      and r.organization_id = 'a0000000-0000-4000-8000-000000000001'
      and r.estimate_version_id = persisted_estimate_id
      and r.reviewer_id = '10000000-0000-4000-8000-000000000001'
      and r.supersedes_review_id = latest_review_id
  ) then
    raise exception 'direct insert bypassed review derivation and attribution';
  end if;

  begin
    update public.estimate_line_reviews set note = 'hidden rewrite'
    where id = latest_review_id;
    raise exception 'authenticated role mutated append-only review history';
  exception
    when insufficient_privilege then null;
  end;

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

  select result.scan_session_id, result.media_id, result.scan_session_media_id,
         result.already_persisted
    into persisted_scan_session_id, persisted_scan_media_id,
         persisted_scan_link_id, duplicate_capture
    from public.persist_scan_capture(
      'a0000000-0000-4000-8000-000000000001',
      'a4000000-0000-4000-8000-000000000001',
      'a8000000-0000-4000-8000-000000000001',
      'a9000000-0000-4000-8000-000000000001',
      'aa000000-0000-4000-8000-000000000001',
      'a0000000-0000-4000-8000-000000000001/a4000000-0000-4000-8000-000000000001/scans/a8000000-0000-4000-8000-000000000001/a9000000-0000-4000-8000-000000000001/aa000000-0000-4000-8000-000000000001/photo.jpg',
      'photo.jpg', 'image/jpeg', 128, repeat('a', 64),
      'photo', 0, clock_timestamp(),
      '{"may_contain_face":false,"precise_location_collected":false}'::jsonb,
      '{"width":2048,"height":1536}'::jsonb
    ) as result;
  if duplicate_capture
     or not exists (
       select 1 from public.scan_session_media ssm
       where ssm.id = persisted_scan_link_id
         and ssm.scan_session_id = persisted_scan_session_id
         and ssm.media_id = persisted_scan_media_id
         and ssm.organization_id = 'a0000000-0000-4000-8000-000000000001'
         and ssm.privacy_flags ->> 'precise_location_collected' = 'false'
     ) then
    raise exception 'mobile capture was not persisted with tenant and privacy metadata';
  end if;

  select result.scan_session_id, result.media_id, result.scan_session_media_id,
         result.already_persisted
    into duplicate_scan_session_id, duplicate_scan_media_id,
         duplicate_scan_link_id, duplicate_capture
    from public.persist_scan_capture(
      'a0000000-0000-4000-8000-000000000001',
      'a4000000-0000-4000-8000-000000000001',
      'a8000000-0000-4000-8000-000000000001',
      'a9000000-0000-4000-8000-000000000001',
      'aa000000-0000-4000-8000-000000000001',
      'a0000000-0000-4000-8000-000000000001/a4000000-0000-4000-8000-000000000001/scans/a8000000-0000-4000-8000-000000000001/a9000000-0000-4000-8000-000000000001/aa000000-0000-4000-8000-000000000001/photo.jpg',
      'photo.jpg', 'image/jpeg', 128, repeat('a', 64),
      'photo', 0, clock_timestamp(), '{}'::jsonb, '{}'::jsonb
    ) as result;
  if not duplicate_capture
     or duplicate_scan_session_id is distinct from persisted_scan_session_id
     or duplicate_scan_media_id is distinct from persisted_scan_media_id
     or duplicate_scan_link_id is distinct from persisted_scan_link_id then
    raise exception 'mobile capture retry was not idempotent';
  end if;

  if not exists (
    select 1 from public.audit_events ae
    where ae.event_type = 'scan_capture_uploaded'
      and ae.entity_id = persisted_scan_media_id
      and ae.actor_id = '10000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'mobile capture audit event is missing';
  end if;

  begin
    perform public.persist_scan_capture(
      'b0000000-0000-4000-8000-000000000002',
      'b4000000-0000-4000-8000-000000000002',
      'b8000000-0000-4000-8000-000000000002',
      'b9000000-0000-4000-8000-000000000002',
      'bb000000-0000-4000-8000-000000000002',
      'b0000000-0000-4000-8000-000000000002/attack/photo.jpg',
      'photo.jpg', 'image/jpeg', 128, repeat('b', 64),
      'photo', 0, clock_timestamp(), '{}'::jsonb, '{}'::jsonb
    );
    raise exception 'tenant A persisted a capture into tenant B';
  exception
    when insufficient_privilege then null;
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
