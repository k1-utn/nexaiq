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
insert into public.findings (
  id, organization_id, repair_order_id, finding_type, component, condition,
  confidence, source_quality, reason, proposed_operation, candidate_key
) values
  (
    'a4500000-0000-4000-8000-000000000001',
    'a0000000-0000-4000-8000-000000000001',
    'a4000000-0000-4000-8000-000000000001',
    'possible_missing_operation', 'front bumper', 'removed', 0.8500, 'mixed',
    'Photo and estimate comparison require estimator review.',
    'R&I front bumper cover', 'test-a-front-bumper'
  ),
  (
    'b4500000-0000-4000-8000-000000000002',
    'b0000000-0000-4000-8000-000000000002',
    'b4000000-0000-4000-8000-000000000002',
    'possible_missing_operation', 'rear bumper', 'removed', 0.8500, 'mixed',
    'Photo and estimate comparison require estimator review.',
    'R&I rear bumper cover', 'test-b-rear-bumper'
  );
insert into public.supplement_candidates (
  id, organization_id, repair_order_id, finding_id, proposed_operation,
  reason, status, confirmed_by, confirmed_at
) values (
  'b4600000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000002',
  'b4000000-0000-4000-8000-000000000002',
  'b4500000-0000-4000-8000-000000000002',
  'R&I rear bumper cover',
  'Photo and estimate comparison require estimator review.',
  'estimator_review',
  '20000000-0000-4000-8000-000000000002',
  clock_timestamp()
);
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
insert into public.connector_devices (
  id, organization_id, location_id, device_identifier, device_name,
  registered_by, platform, version, watch_path_hash, status
) values (
  'b7100000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000002',
  'b1000000-0000-4000-8000-000000000002',
  'b7200000-0000-4000-8000-000000000002',
  'Tenant B connector',
  '20000000-0000-4000-8000-000000000002',
  'windows', '0.1.0', repeat('b', 64), 'active'
);
insert into public.connector_sync_batches (
  id, organization_id, location_id, connector_device_id,
  client_batch_id, connector_version, status, file_count,
  total_bytes, discovered_at
) values (
  'b7300000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000002',
  'b1000000-0000-4000-8000-000000000002',
  'b7100000-0000-4000-8000-000000000002',
  'b7400000-0000-4000-8000-000000000002',
  '0.1.0', 'format_review_required', 1, 16, clock_timestamp()
);
insert into public.connector_sync_files (
  id, organization_id, connector_sync_batch_id, client_file_id,
  source_filename, file_extension, mime_type, byte_size,
  content_sha256, storage_object_path
) values (
  'b7500000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000002',
  'b7300000-0000-4000-8000-000000000002',
  'b7600000-0000-4000-8000-000000000002',
  'tenant-b.ad1', '.ad1', 'application/octet-stream', 16,
  repeat('c', 64),
  'b0000000-0000-4000-8000-000000000002/b7200000-0000-4000-8000-000000000002/b7400000-0000-4000-8000-000000000002/b7600000-0000-4000-8000-000000000002/tenant-b.ad1'
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

  begin
    perform public.record_finding_review(
      'b4500000-0000-4000-8000-000000000002', 'confirmed', null
    );
    raise exception 'anonymous role reviewed a finding';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform public.get_supplement_analysis_readiness(
      'b0000000-0000-4000-8000-000000000002',
      'b4000000-0000-4000-8000-000000000002',
      'development'
    );
    raise exception 'tenant A checked supplement readiness for tenant B';
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
  stage5_candidate_id uuid;
  stage5_review_event_id uuid;
begin
  select array_agg(ro_number order by ro_number)
    into visible_repairs
    from public.repair_orders;
  if visible_repairs is distinct from array['A-100']::text[] then
    raise exception 'tenant A repair-order visibility failed: %', visible_repairs;
  end if;

  if exists (
    select 1 from public.connector_devices
    where organization_id = 'b0000000-0000-4000-8000-000000000002'
  ) or exists (
    select 1 from public.connector_sync_batches
    where organization_id = 'b0000000-0000-4000-8000-000000000002'
  ) or exists (
    select 1 from public.connector_sync_files
    where organization_id = 'b0000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'tenant A can read tenant B connector records';
  end if;

  begin
    insert into public.connector_devices (
      organization_id, location_id, device_identifier, device_name
    ) values (
      'a0000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000001',
      'a7200000-0000-4000-8000-000000000001',
      'Fabricated connector'
    );
    raise exception 'tenant A directly created a connector device';
  exception
    when insufficient_privilege then null;
  end;

  if exists (
    select 1 from public.repair_orders
    where organization_id = 'b0000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'tenant A can read tenant B repair orders';
  end if;

  begin
    perform public.record_finding_review(
      'b4500000-0000-4000-8000-000000000002', 'confirmed', null
    );
    raise exception 'tenant A reviewed a tenant B finding';
  exception
    when insufficient_privilege then null;
  end;

  perform public.record_finding_review(
    'a4500000-0000-4000-8000-000000000001', 'confirmed', null
  );
  if not exists (
    select 1
    from public.supplement_candidates candidate
    where candidate.finding_id = 'a4500000-0000-4000-8000-000000000001'
      and candidate.organization_id = 'a0000000-0000-4000-8000-000000000001'
      and candidate.status = 'estimator_review'
  ) then
    raise exception 'confirmed finding did not create an estimator-review candidate';
  end if;

  if not exists (
    select 1
    from public.ai_evaluation_events event
    where event.finding_id = 'a4500000-0000-4000-8000-000000000001'
      and event.actor_id = '10000000-0000-4000-8000-000000000001'
      and event.decision = 'confirmed'
  ) then
    raise exception 'finding review evaluation event was not attributed';
  end if;

  select candidate.id
    into stage5_candidate_id
    from public.supplement_candidates candidate
    where candidate.finding_id = 'a4500000-0000-4000-8000-000000000001';

  insert into public.supplement_candidate_review_events (
    supplement_candidate_id, decision, review_reason,
    oem_consideration_status
  ) values (
    stage5_candidate_id, 'ready_for_package',
    'Estimator verified the operation and linked evidence.',
    'not_applicable'
  ) returning id into stage5_review_event_id;

  if not exists (
    select 1
    from public.supplement_candidate_review_events event
    where event.id = stage5_review_event_id
      and event.organization_id = 'a0000000-0000-4000-8000-000000000001'
      and event.repair_order_id = 'a4000000-0000-4000-8000-000000000001'
      and event.actor_id = '10000000-0000-4000-8000-000000000001'
      and event.decision = 'ready_for_package'
  ) or not exists (
    select 1
    from public.supplement_candidates candidate
    where candidate.id = stage5_candidate_id
      and candidate.status = 'confirmed'
      and candidate.oem_consideration_status = 'not_applicable'
      and candidate.reviewed_by = '10000000-0000-4000-8000-000000000001'
  ) or not exists (
    select 1
    from public.audit_events event
    where event.entity_id = stage5_candidate_id
      and event.event_type = 'supplement_candidate_review_recorded'
      and event.actor_id = '10000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'Stage 5 candidate review was not derived and audited correctly';
  end if;

  begin
    insert into public.supplement_candidate_review_events (
      supplement_candidate_id, decision, review_reason,
      oem_consideration_status
    ) values (
      'b4600000-0000-4000-8000-000000000002',
      'ready_for_package', 'Cross-tenant attempt.', 'not_applicable'
    );
    raise exception 'tenant A reviewed a tenant B supplement candidate';
  exception
    when insufficient_privilege then null;
  end;

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

  if not exists (
    select 1
    from public.get_supplement_analysis_readiness(
      'a0000000-0000-4000-8000-000000000001',
      'a4000000-0000-4000-8000-000000000001',
      'development'
    ) readiness
    where readiness.verified_estimate_version_id = persisted_estimate_id
      and readiness.photo_count = 1
      and readiness.eligible_photo_count = 1
      and readiness.withheld_photo_count = 0
      and readiness.voice_note_count = 0
      and readiness.approved_provider_policy_count = 0
      and readiness.eligible_model_version_count = 0
  ) then
    raise exception 'supplement readiness did not report fail-closed live prerequisites';
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

reset role;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

do $$
declare
  provider_id uuid;
  job_id uuid;
  result_id uuid;
  finding_count integer;
  review_package_id uuid;
  review_package_number integer;
  review_package_item_count integer;
  review_package_status text;
  package_decision_time timestamptz;
  connector_device_id uuid;
  connector_device_status text;
  connector_batch_id uuid;
  connector_file_id uuid;
  connector_duplicate boolean;
begin
  select registered.connector_device_id, registered.device_status
    into connector_device_id, connector_device_status
    from public.register_connector_device(
      '10000000-0000-4000-8000-000000000001',
      'a0000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000001',
      'a7200000-0000-4000-8000-000000000001',
      'Tenant A connector', '0.1.0', repeat('a', 64)
    ) registered;

  if connector_device_status <> 'active'
     or not exists (
       select 1 from public.connector_devices device
       where device.id = connector_device_id
         and device.organization_id = 'a0000000-0000-4000-8000-000000000001'
         and device.registered_by = '10000000-0000-4000-8000-000000000001'
         and device.watch_path_hash = repeat('a', 64)
     )
     or not exists (
       select 1 from public.audit_events event
       where event.entity_id = connector_device_id
         and event.event_type = 'connector_device_registered'
     ) then
    raise exception 'Stage 6 connector registration was not derived and audited';
  end if;

  select persisted.connector_sync_batch_id,
         persisted.connector_sync_file_id,
         persisted.already_persisted
    into connector_batch_id, connector_file_id, connector_duplicate
    from public.persist_connector_sync_file(
      '10000000-0000-4000-8000-000000000001',
      'a0000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000001',
      'a7200000-0000-4000-8000-000000000001',
      'a7400000-0000-4000-8000-000000000001',
      'a7600000-0000-4000-8000-000000000001',
      'tenant-a.ad1', '.ad1', 'application/octet-stream', 16,
      repeat('d', 64),
      'a0000000-0000-4000-8000-000000000001/a7200000-0000-4000-8000-000000000001/a7400000-0000-4000-8000-000000000001/a7600000-0000-4000-8000-000000000001/tenant-a.ad1',
      '0.1.0', clock_timestamp()
    ) persisted;

  if connector_duplicate
     or not exists (
       select 1 from public.connector_sync_batches batch
       where batch.id = connector_batch_id
         and batch.file_count = 1
         and batch.total_bytes = 16
         and batch.status = 'format_review_required'
     )
     or not exists (
       select 1 from public.connector_sync_files file
       where file.id = connector_file_id
         and file.content_sha256 = repeat('d', 64)
         and file.parse_status = 'awaiting_format_validation'
     )
     or not exists (
       select 1 from public.audit_events event
       where event.entity_id = connector_file_id
         and event.event_type = 'connector_ems_file_received'
     ) then
    raise exception 'Stage 6 EMS file persistence was not idempotent and audited';
  end if;

  select persisted.already_persisted
    into connector_duplicate
    from public.persist_connector_sync_file(
      '10000000-0000-4000-8000-000000000001',
      'a0000000-0000-4000-8000-000000000001',
      'a1000000-0000-4000-8000-000000000001',
      'a7200000-0000-4000-8000-000000000001',
      'a7400000-0000-4000-8000-000000000001',
      'a7600000-0000-4000-8000-000000000001',
      'tenant-a.ad1', '.ad1', 'application/octet-stream', 16,
      repeat('d', 64),
      'a0000000-0000-4000-8000-000000000001/a7200000-0000-4000-8000-000000000001/a7400000-0000-4000-8000-000000000001/a7600000-0000-4000-8000-000000000001/tenant-a.ad1',
      '0.1.0', clock_timestamp()
    ) persisted;
  if not connector_duplicate then
    raise exception 'Stage 6 EMS file retry created a duplicate record';
  end if;

  begin
    perform public.register_connector_device(
      '10000000-0000-4000-8000-000000000001',
      'b0000000-0000-4000-8000-000000000002',
      'b1000000-0000-4000-8000-000000000002',
      'b7700000-0000-4000-8000-000000000002',
      'Cross-tenant connector', '0.1.0', repeat('e', 64)
    );
    raise exception 'tenant A registered a connector for tenant B';
  exception
    when insufficient_privilege then null;
  end;

  select package.package_id, package.package_number,
         package.item_count, package.package_status
    into review_package_id, review_package_number,
         review_package_item_count, review_package_status
    from public.create_supplement_review_package(
      '10000000-0000-4000-8000-000000000001',
      'a0000000-0000-4000-8000-000000000001',
      'a4000000-0000-4000-8000-000000000001'
    ) package;

  if review_package_number <> 1
     or review_package_item_count <> 1
     or review_package_status <> 'draft'
     or not exists (
       select 1
       from public.supplement_review_package_items item
       where item.package_id = review_package_id
         and item.organization_id = 'a0000000-0000-4000-8000-000000000001'
         and item.supplement_candidate_id in (
           select candidate.id
           from public.supplement_candidates candidate
           where candidate.finding_id = 'a4500000-0000-4000-8000-000000000001'
         )
         and item.oem_consideration_status = 'not_applicable'
     ) then
    raise exception 'Stage 5 package snapshot was not created correctly';
  end if;

  select decision.package_status, decision.decided_at
    into review_package_status, package_decision_time
    from public.record_supplement_review_package_decision(
      '10000000-0000-4000-8000-000000000001',
      'a0000000-0000-4000-8000-000000000001',
      review_package_id,
      'approved',
      null,
      'I confirm that I reviewed this supplement package and its linked evidence. This is an estimator decision and does not certify repair safety or insurer payment.'
    ) decision;

  if review_package_status <> 'approved'
     or package_decision_time is null
     or not exists (
       select 1
       from public.supplement_review_packages package
       where package.id = review_package_id
         and package.status = 'approved'
         and package.approved_by = '10000000-0000-4000-8000-000000000001'
         and package.approved_at is not null
     )
     or (
       select count(*)
       from public.audit_events event
       where event.entity_id = review_package_id
         and event.event_type in (
           'supplement_review_package_created',
           'supplement_review_package_approved'
         )
     ) <> 2 then
    raise exception 'Stage 5 package approval or audit history is incomplete';
  end if;

  begin
    perform public.create_supplement_review_package(
      '10000000-0000-4000-8000-000000000001',
      'b0000000-0000-4000-8000-000000000002',
      'b4000000-0000-4000-8000-000000000002'
    );
    raise exception 'tenant A created a Stage 5 package for tenant B';
  exception
    when insufficient_privilege then null;
  end;

  select id into provider_id
    from public.ai_providers
    where provider_key = 'openai';

  insert into public.organization_ai_policies (
    organization_id, provider_id, enabled, allowed_purposes,
    allowed_data_categories, provider_training_allowed, dpa_status, approved_by
  ) values (
    'a0000000-0000-4000-8000-000000000001', provider_id, true,
    array['supplement_analysis']::text[],
    array['estimate_data', 'repair_evidence']::text[],
    false, 'approved', '10000000-0000-4000-8000-000000000001'
  );

  insert into public.ai_model_versions (
    organization_id, provider_id, model_name, provider_model_version,
    prompt_template_version, schema_version, environment,
    evaluation_status, activated_at
  ) values (
    'a0000000-0000-4000-8000-000000000001', provider_id,
    'test-vision-model', 'test-snapshot', 'test-prompt-v1', 'test-schema-v1',
    'development', 'passed', clock_timestamp()
  );

  select analysis.ai_job_id
    into job_id
    from public.begin_supplement_analysis(
      '10000000-0000-4000-8000-000000000001',
      'a0000000-0000-4000-8000-000000000001',
      'a4000000-0000-4000-8000-000000000001',
      'development',
      'stage4-lifecycle-test'
    ) analysis;

  select completion.ai_result_id, completion.created_finding_count
    into result_id, finding_count
    from public.complete_supplement_analysis(
      job_id,
      '10000000-0000-4000-8000-000000000001',
      'provider-response-test',
      jsonb_build_array(
        jsonb_build_object(
          'finding_type', 'possible_missing_operation',
          'component', 'front bumper',
          'condition', 'removed',
          'proposed_operation', 'R&I front bumper cover',
          'confidence', 0.85,
          'source_quality', 'camera_only',
          'evidence_ids', jsonb_build_array(
            'aa000000-0000-4000-8000-000000000001'::uuid
          ),
          'reason', 'No exact verified-estimate match was found.',
          'limitations', jsonb_build_array('Human inspection is required.'),
          'comparison_status', 'possible_missing_operation',
          'match_method', 'none',
          'matched_estimate_line_id', null,
          'human_review_required', true
        ),
        jsonb_build_object(
          'finding_type', 'paint_operation',
          'component', 'front bumper',
          'condition', 'refinished',
          'proposed_operation', 'Add clear coat',
          'confidence', 0.90,
          'source_quality', 'camera_only',
          'evidence_ids', jsonb_build_array(
            'aa000000-0000-4000-8000-000000000001'::uuid
          ),
          'reason', 'Clear coat is automatic.',
          'limitations', '[]'::jsonb,
          'comparison_status', 'automatic_operation_excluded',
          'match_method', 'none',
          'matched_estimate_line_id', null,
          'human_review_required', true
        )
      ),
      100,
      50,
      250
    ) completion;

  if finding_count <> 1
     or not exists (
       select 1 from public.findings finding
       where finding.ai_result_id = result_id
         and finding.proposed_operation = 'R&I front bumper cover'
         and finding.human_review_required
     )
     or exists (
       select 1 from public.findings finding
       where finding.ai_result_id = result_id
         and finding.proposed_operation ~* '\mclear[ -]?coat\M'
     ) then
    raise exception 'controlled Stage 4 lifecycle did not preserve candidate safety rules';
  end if;

  if not exists (
    select 1 from public.ai_jobs job
    where job.id = job_id
      and job.status = 'completed'
      and job.provider_response_id = 'provider-response-test'
  ) then
    raise exception 'Stage 4 lifecycle did not complete its governed AI job';
  end if;
end;
$$;

select 'cross-tenant RLS checks passed' as result;

rollback;
