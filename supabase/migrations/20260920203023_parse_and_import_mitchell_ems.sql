begin;

alter table public.connector_sync_files
  drop constraint connector_sync_files_parse_status_check;

alter table public.connector_sync_files
  add column extracted_payload jsonb not null default '{}'::jsonb,
  add constraint connector_sync_files_parse_status_check check (
    parse_status in ('parsed', 'withheld_by_minimization', 'unsupported', 'failed')
  ),
  add constraint connector_sync_files_extracted_payload_object_check check (
    jsonb_typeof(extracted_payload) = 'object'
    and pg_column_size(extracted_payload) <= 1048576
  );

alter table public.connector_sync_batches
  add column repair_order_id uuid,
  add column estimate_version_id uuid,
  add column normalized_summary jsonb not null default '{}'::jsonb,
  add constraint connector_sync_batches_repair_order_tenant_fk
    foreign key (repair_order_id, organization_id)
    references public.repair_orders (id, organization_id) on delete restrict,
  add constraint connector_sync_batches_estimate_version_tenant_fk
    foreign key (estimate_version_id, organization_id)
    references public.estimate_versions (id, organization_id) on delete restrict,
  add constraint connector_sync_batches_normalized_summary_object_check check (
    jsonb_typeof(normalized_summary) = 'object'
  );

create index connector_sync_batches_repair_order_idx
  on public.connector_sync_batches (organization_id, repair_order_id)
  where repair_order_id is not null;

drop function if exists public.persist_connector_sync_file(
  uuid, uuid, uuid, uuid, uuid, uuid, text, text, text, bigint,
  text, text, text, timestamptz
);

create function public.persist_connector_sync_file(
  p_actor_id uuid,
  p_organization_id uuid,
  p_location_id uuid,
  p_device_identifier uuid,
  p_client_batch_id uuid,
  p_client_file_id uuid,
  p_source_filename text,
  p_file_extension text,
  p_mime_type text,
  p_byte_size bigint,
  p_content_sha256 text,
  p_storage_object_path text,
  p_connector_version text,
  p_discovered_at timestamptz,
  p_parse_status text,
  p_extracted_payload jsonb
)
returns table (
  connector_device_id uuid,
  connector_sync_batch_id uuid,
  connector_sync_file_id uuid,
  already_persisted boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved_device_id uuid;
  saved_device_status text;
  saved_device_location_id uuid;
  saved_batch_id uuid;
  saved_file_id uuid;
  existing_file_hash text;
  existing_file_size bigint;
  existing_parse_status text;
  existing_payload jsonb;
  inserted_now boolean := false;
  expected_prefix text;
  normalized_filename text := nullif(btrim(p_source_filename), '');
  normalized_extension text := lower(nullif(btrim(p_file_extension), ''));
  normalized_hash text := lower(nullif(btrim(p_content_sha256), ''));
  normalized_version text := nullif(btrim(p_connector_version), '');
begin
  if p_actor_id is null or p_organization_id is null then
    raise exception 'authenticated actor and organization are required' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.organization_members member
    join public.user_roles user_role
      on user_role.organization_id = member.organization_id
     and user_role.user_id = member.user_id
    join public.role_permissions role_permission
      on role_permission.role_id = user_role.role_id
    join public.permissions permission
      on permission.id = role_permission.permission_id
    where member.organization_id = p_organization_id
      and member.user_id = p_actor_id
      and member.status = 'active'
      and permission.code = 'records:write'
  ) then
    raise exception 'connector synchronization access denied' using errcode = '42501';
  end if;

  if normalized_filename is null or length(normalized_filename) > 180
     or normalized_filename ~ '[\\/]' then
    raise exception 'invalid connector source filename' using errcode = '22023';
  end if;

  if normalized_extension is null or normalized_extension !~ '^\.[a-z0-9]{1,8}$' then
    raise exception 'invalid connector file extension' using errcode = '22023';
  end if;

  if p_byte_size <= 0 or p_byte_size > 5242880 then
    raise exception 'connector file size is outside the allowed range' using errcode = '22023';
  end if;

  if normalized_hash is null or normalized_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'connector file hash must be a lowercase SHA-256 value'
      using errcode = '22023';
  end if;

  if p_parse_status not in ('parsed', 'withheld_by_minimization', 'unsupported')
     or jsonb_typeof(p_extracted_payload) is distinct from 'object'
     or pg_column_size(p_extracted_payload) > 1048576 then
    raise exception 'invalid connector parse result' using errcode = '22023';
  end if;

  select device.id, device.status, device.location_id
    into saved_device_id, saved_device_status, saved_device_location_id
    from public.connector_devices device
    where device.organization_id = p_organization_id
      and device.device_identifier = p_device_identifier;

  if saved_device_id is null or saved_device_status <> 'active' then
    raise exception 'active connector device not found' using errcode = '42501';
  end if;

  if saved_device_location_id is distinct from p_location_id then
    raise exception 'connector location does not match the registered device'
      using errcode = '42501';
  end if;

  expected_prefix := p_organization_id::text || '/' || p_device_identifier::text || '/'
    || p_client_batch_id::text || '/' || p_client_file_id::text || '/';
  if p_storage_object_path not like expected_prefix || '%' then
    raise exception 'connector storage path is outside the expected tenant scope'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    saved_device_id::text || ':' || p_client_batch_id::text, 7
  ));

  insert into public.connector_sync_batches (
    organization_id, location_id, connector_device_id, client_batch_id,
    connector_version, status, discovered_at
  ) values (
    p_organization_id, p_location_id, saved_device_id, p_client_batch_id,
    normalized_version, 'received', p_discovered_at
  )
  on conflict on constraint connector_sync_batches_connector_device_id_client_batch_id_key
  do update set updated_at = clock_timestamp()
  returning id into saved_batch_id;

  insert into public.connector_sync_files (
    organization_id, connector_sync_batch_id, client_file_id,
    source_filename, file_extension, mime_type, byte_size,
    content_sha256, storage_object_path, parse_status, extracted_payload
  ) values (
    p_organization_id, saved_batch_id, p_client_file_id,
    normalized_filename, normalized_extension, p_mime_type, p_byte_size,
    normalized_hash, p_storage_object_path, p_parse_status, p_extracted_payload
  )
  on conflict on constraint connector_sync_files_connector_sync_batch_id_client_file_id_key
  do nothing
  returning id into saved_file_id;

  if saved_file_id is null then
    select file.id, file.content_sha256, file.byte_size,
           file.parse_status, file.extracted_payload
      into saved_file_id, existing_file_hash, existing_file_size,
           existing_parse_status, existing_payload
      from public.connector_sync_files file
      where file.connector_sync_batch_id = saved_batch_id
        and file.client_file_id = p_client_file_id;

    if existing_file_hash is distinct from normalized_hash
       or existing_file_size is distinct from p_byte_size
       or existing_parse_status is distinct from p_parse_status
       or existing_payload is distinct from p_extracted_payload then
      raise exception 'connector idempotency key was reused for different content'
        using errcode = '23505';
    end if;
  else
    inserted_now := true;

    update public.connector_sync_batches
      set file_count = file_count + 1,
          total_bytes = total_bytes + p_byte_size,
          status = 'format_review_required',
          updated_at = clock_timestamp()
      where id = saved_batch_id
        and organization_id = p_organization_id;

    insert into public.audit_events (
      organization_id, location_id, actor_id, event_type,
      entity_type, entity_id, authentication_context, software_version, payload
    ) values (
      p_organization_id, p_location_id, p_actor_id,
      'connector_ems_file_received', 'connector_sync_file', saved_file_id,
      jsonb_build_object('provider', 'supabase_auth', 'workflow', 'windows_ems_connector'),
      normalized_version,
      jsonb_build_object(
        'connector_device_id', saved_device_id,
        'connector_sync_batch_id', saved_batch_id,
        'client_file_id', p_client_file_id,
        'source_filename', normalized_filename,
        'byte_size', p_byte_size,
        'content_sha256', normalized_hash,
        'parse_status', p_parse_status
      )
    );
  end if;

  update public.connector_devices
    set version = normalized_version,
        last_seen_at = clock_timestamp(),
        last_sync_at = clock_timestamp(),
        last_error_code = null,
        updated_at = clock_timestamp()
    where id = saved_device_id
      and organization_id = p_organization_id;

  return query
  select saved_device_id, saved_batch_id, saved_file_id, not inserted_now;
end;
$$;

create function public.finalize_connector_ems_batch(
  p_actor_id uuid,
  p_organization_id uuid,
  p_connector_sync_batch_id uuid
)
returns table (
  import_status text,
  repair_order_id uuid,
  estimate_version_id uuid,
  imported_line_count integer
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  saved_batch public.connector_sync_batches%rowtype;
  env_payload jsonb;
  vehicle_payload jsonb;
  line_payload jsonb;
  totals_payload jsonb;
  normalized_ro_number text;
  normalized_vin text;
  saved_vehicle_id uuid;
  saved_repair_order_id uuid;
  saved_estimate_version_id uuid;
  existing_estimate_version_id uuid;
  next_version integer;
  combined_source_hash text;
  line_count integer := 0;
begin
  if not exists (
    select 1
    from public.organization_members member
    join public.user_roles user_role
      on user_role.organization_id = member.organization_id
     and user_role.user_id = member.user_id
    join public.role_permissions role_permission
      on role_permission.role_id = user_role.role_id
    join public.permissions permission
      on permission.id = role_permission.permission_id
    where member.organization_id = p_organization_id
      and member.user_id = p_actor_id
      and member.status = 'active'
      and permission.code = 'records:write'
  ) then
    raise exception 'connector import access denied' using errcode = '42501';
  end if;

  select batch.* into saved_batch
    from public.connector_sync_batches batch
    where batch.id = p_connector_sync_batch_id
      and batch.organization_id = p_organization_id
    for update;

  if saved_batch.id is null then
    raise exception 'connector batch not found' using errcode = '42501';
  end if;

  if saved_batch.estimate_version_id is not null then
    return query select 'already_imported'::text, saved_batch.repair_order_id,
      saved_batch.estimate_version_id,
      (select count(*)::integer from public.estimate_lines line
       where line.estimate_version_id = saved_batch.estimate_version_id
         and line.organization_id = p_organization_id);
    return;
  end if;

  select file.extracted_payload into env_payload
    from public.connector_sync_files file
    where file.connector_sync_batch_id = saved_batch.id
      and file.organization_id = p_organization_id
      and file.parse_status = 'parsed'
      and file.extracted_payload ->> 'table' = 'env'
    order by file.created_at desc limit 1;
  select file.extracted_payload into vehicle_payload
    from public.connector_sync_files file
    where file.connector_sync_batch_id = saved_batch.id
      and file.organization_id = p_organization_id
      and file.parse_status = 'parsed'
      and file.extracted_payload ->> 'table' = 'veh'
    order by file.created_at desc limit 1;
  select file.extracted_payload into line_payload
    from public.connector_sync_files file
    where file.connector_sync_batch_id = saved_batch.id
      and file.organization_id = p_organization_id
      and file.parse_status = 'parsed'
      and file.extracted_payload ->> 'table' = 'lin'
    order by file.created_at desc limit 1;
  select file.extracted_payload into totals_payload
    from public.connector_sync_files file
    where file.connector_sync_batch_id = saved_batch.id
      and file.organization_id = p_organization_id
      and file.parse_status = 'parsed'
      and file.extracted_payload ->> 'table' = 'ttl'
    order by file.created_at desc limit 1;

  if env_payload is null or vehicle_payload is null or line_payload is null then
    return query select 'waiting_for_core_files'::text, null::uuid, null::uuid, 0;
    return;
  end if;

  normalized_ro_number := left(coalesce(
    nullif(btrim(env_payload ->> 'repair_order_reference'), ''),
    nullif(btrim(env_payload ->> 'estimate_file_reference'), '')
  ), 120);
  normalized_vin := upper(left(nullif(btrim(vehicle_payload ->> 'vin'), ''), 32));
  if normalized_ro_number is null then
    raise exception 'EMS estimate does not contain a repair-order reference'
      using errcode = '22023';
  end if;
  if jsonb_typeof(line_payload -> 'lines') is distinct from 'array'
     or jsonb_array_length(line_payload -> 'lines') = 0 then
    raise exception 'EMS estimate does not contain importable lines'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':' || normalized_ro_number, 11
  ));

  select repair_order.id, repair_order.vehicle_id
    into saved_repair_order_id, saved_vehicle_id
    from public.repair_orders repair_order
    where repair_order.organization_id = p_organization_id
      and repair_order.ro_number = normalized_ro_number;

  if saved_repair_order_id is null then
    if normalized_vin is not null then
      insert into public.vehicles (
        organization_id, vin, year, make, model, trim
      ) values (
        p_organization_id,
        normalized_vin,
        case when (vehicle_payload ->> 'year') ~ '^[0-9]{4}$'
          then (vehicle_payload ->> 'year')::smallint else null end,
        nullif(left(btrim(vehicle_payload ->> 'make'), 120), ''),
        nullif(left(btrim(vehicle_payload ->> 'model'), 120), ''),
        nullif(left(btrim(vehicle_payload ->> 'trim'), 120), '')
      )
      on conflict (organization_id, vin) do update set
        year = coalesce(excluded.year, public.vehicles.year),
        make = coalesce(excluded.make, public.vehicles.make),
        model = coalesce(excluded.model, public.vehicles.model),
        trim = coalesce(excluded.trim, public.vehicles.trim)
      returning id into saved_vehicle_id;
    else
      insert into public.vehicles (organization_id, year, make, model, trim)
      values (
        p_organization_id,
        case when (vehicle_payload ->> 'year') ~ '^[0-9]{4}$'
          then (vehicle_payload ->> 'year')::smallint else null end,
        nullif(left(btrim(vehicle_payload ->> 'make'), 120), ''),
        nullif(left(btrim(vehicle_payload ->> 'model'), 120), ''),
        nullif(left(btrim(vehicle_payload ->> 'trim'), 120), '')
      ) returning id into saved_vehicle_id;
    end if;

    insert into public.repair_orders (
      organization_id, location_id, vehicle_id, ro_number, workflow_status
    ) values (
      p_organization_id, saved_batch.location_id, saved_vehicle_id,
      normalized_ro_number, 'intake'
    ) returning id into saved_repair_order_id;
  end if;

  select pg_catalog.encode(
      extensions.digest(
        string_agg(file.content_sha256, '' order by file.source_filename),
        'sha256'
      ),
      'hex'
    ) into combined_source_hash
    from public.connector_sync_files file
    where file.connector_sync_batch_id = saved_batch.id
      and file.organization_id = p_organization_id;

  select estimate.id into existing_estimate_version_id
    from public.estimate_versions estimate
    where estimate.organization_id = p_organization_id
      and estimate.repair_order_id = saved_repair_order_id
      and estimate.source_system = 'mitchell_ems'
      and estimate.source_sha256 = combined_source_hash
    order by estimate.created_at desc limit 1;

  if existing_estimate_version_id is not null then
    update public.connector_sync_batches
      set status = 'parsed', repair_order_id = saved_repair_order_id,
          estimate_version_id = existing_estimate_version_id,
          normalized_summary = jsonb_build_object(
            'repair_order_reference', normalized_ro_number,
            'line_count', jsonb_array_length(line_payload -> 'lines'),
            'totals', coalesce(totals_payload, '{}'::jsonb)
          ),
          completed_at = clock_timestamp(), updated_at = clock_timestamp()
      where id = saved_batch.id and organization_id = p_organization_id;
    return query select 'already_imported'::text, saved_repair_order_id,
      existing_estimate_version_id,
      (select count(*)::integer from public.estimate_lines line
       where line.estimate_version_id = existing_estimate_version_id
         and line.organization_id = p_organization_id);
    return;
  end if;

  select coalesce(max(estimate.version_number), 0) + 1 into next_version
    from public.estimate_versions estimate
    where estimate.organization_id = p_organization_id
      and estimate.repair_order_id = saved_repair_order_id;

  insert into public.estimate_versions (
    organization_id, repair_order_id, version_number, source_system,
    source_sha256, parse_status, parser_name, parser_version
  ) values (
    p_organization_id, saved_repair_order_id, next_version, 'mitchell_ems',
    combined_source_hash, 'requires_human_verification',
    'nexaiq_ems_dbf', '0.1.0'
  ) returning id into saved_estimate_version_id;

  insert into public.estimate_lines (
    organization_id, estimate_version_id, source_line_number,
    operation_code, description, amount, raw_text, parse_confidence
  )
  select
    p_organization_id,
    saved_estimate_version_id,
    case when (item ->> 'source_line_number') ~ '^[0-9]+$'
      then (item ->> 'source_line_number')::integer else null end,
    nullif(left(btrim(item ->> 'operation_code'), 80), ''),
    left(btrim(item ->> 'description'), 500),
    case when (item ->> 'amount') ~ '^-?[0-9]+(\.[0-9]+)?$'
      then (item ->> 'amount')::numeric(12,2) else null end,
    left(coalesce(nullif(btrim(item ->> 'normalized_source_text'), ''),
      btrim(item ->> 'description')), 2000),
    0.9900
  from jsonb_array_elements(line_payload -> 'lines') item
  where nullif(btrim(item ->> 'description'), '') is not null;
  get diagnostics line_count = row_count;

  update public.connector_sync_batches
    set status = 'parsed', repair_order_id = saved_repair_order_id,
        estimate_version_id = saved_estimate_version_id,
        normalized_summary = jsonb_build_object(
          'repair_order_reference', normalized_ro_number,
          'line_count', line_count,
          'totals', coalesce(totals_payload, '{}'::jsonb)
        ),
        completed_at = clock_timestamp(), failure_code = null,
        updated_at = clock_timestamp()
    where id = saved_batch.id and organization_id = p_organization_id;

  insert into public.audit_events (
    organization_id, location_id, repair_order_id, actor_id,
    event_type, entity_type, entity_id, authentication_context,
    software_version, payload
  ) values (
    p_organization_id, saved_batch.location_id, saved_repair_order_id, p_actor_id,
    'connector_ems_estimate_imported', 'estimate_version', saved_estimate_version_id,
    jsonb_build_object('provider', 'supabase_auth', 'workflow', 'windows_ems_connector'),
    saved_batch.connector_version,
    jsonb_build_object(
      'connector_sync_batch_id', saved_batch.id,
      'source_system', 'mitchell_ems',
      'source_sha256', combined_source_hash,
      'parser_name', 'nexaiq_ems_dbf',
      'parser_version', '0.1.0',
      'line_count', line_count,
      'human_verification_required', true,
      'privacy_minimization', jsonb_build_array('ad1', 'ad2', 'ven', 'dbt')
    )
  );

  return query select 'imported'::text, saved_repair_order_id,
    saved_estimate_version_id, line_count;
end;
$$;

revoke all on function public.persist_connector_sync_file(
  uuid, uuid, uuid, uuid, uuid, uuid, text, text, text, bigint,
  text, text, text, timestamptz, text, jsonb
) from public, anon, authenticated;
grant execute on function public.persist_connector_sync_file(
  uuid, uuid, uuid, uuid, uuid, uuid, text, text, text, bigint,
  text, text, text, timestamptz, text, jsonb
) to service_role;

revoke all on function public.finalize_connector_ems_batch(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.finalize_connector_ems_batch(uuid, uuid, uuid)
  to service_role;

commit;
