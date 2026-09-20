begin;

create or replace function public.persist_connector_sync_file(
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
  p_discovered_at timestamptz
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
    content_sha256, storage_object_path
  ) values (
    p_organization_id, saved_batch_id, p_client_file_id,
    normalized_filename, normalized_extension, p_mime_type, p_byte_size,
    normalized_hash, p_storage_object_path
  )
  on conflict on constraint connector_sync_files_connector_sync_batch_id_client_file_id_key
  do nothing
  returning id into saved_file_id;

  if saved_file_id is null then
    select file.id, file.content_sha256, file.byte_size
      into saved_file_id, existing_file_hash, existing_file_size
      from public.connector_sync_files file
      where file.connector_sync_batch_id = saved_batch_id
        and file.client_file_id = p_client_file_id;

    if existing_file_hash is distinct from normalized_hash
       or existing_file_size is distinct from p_byte_size then
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
        'parse_status', 'awaiting_format_validation'
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

commit;
