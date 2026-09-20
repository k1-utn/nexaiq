begin;

insert into storage.buckets (id, name, public, file_size_limit)
values ('connector-imports', 'connector-imports', false, 5242880)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit;

create unique index if not exists locations_id_organization_unique
  on public.locations (id, organization_id);

alter table public.connector_devices
  add column device_identifier uuid,
  add column registered_by uuid references public.users(id) on delete restrict,
  add column platform text not null default 'windows',
  add column watch_path_hash text,
  add column last_sync_at timestamptz,
  add column last_error_code text,
  add column updated_at timestamptz not null default now();

update public.connector_devices
set device_identifier = gen_random_uuid()
where device_identifier is null;

alter table public.connector_devices
  alter column device_identifier set not null,
  add constraint connector_devices_status_check check (
    status in ('pending', 'active', 'disabled', 'revoked')
  ),
  add constraint connector_devices_platform_check check (platform = 'windows'),
  add constraint connector_devices_watch_path_hash_check check (
    watch_path_hash is null or watch_path_hash ~ '^[0-9a-f]{64}$'
  ),
  add constraint connector_devices_location_tenant_fk
    foreign key (location_id, organization_id)
    references public.locations (id, organization_id) on delete restrict;

create unique index connector_devices_org_identifier_unique
  on public.connector_devices (organization_id, device_identifier);
create unique index connector_devices_id_organization_unique
  on public.connector_devices (id, organization_id);
create index connector_devices_org_location_status_idx
  on public.connector_devices (organization_id, location_id, status, updated_at desc);
create index connector_devices_registered_by_idx
  on public.connector_devices (registered_by)
  where registered_by is not null;

drop policy if exists connector_devices_writer_insert on public.connector_devices;
drop policy if exists connector_devices_writer_update on public.connector_devices;
drop policy if exists connector_devices_writer_delete on public.connector_devices;
revoke insert, update, delete on public.connector_devices from authenticated;
alter table public.connector_devices force row level security;

create table public.connector_sync_batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null,
  connector_device_id uuid not null,
  client_batch_id uuid not null,
  source_system text not null default 'mitchell_ems' check (
    source_system = 'mitchell_ems'
  ),
  connector_version text not null,
  status text not null default 'received' check (
    status in ('received', 'format_review_required', 'parsed', 'failed')
  ),
  file_count integer not null default 0 check (file_count >= 0),
  total_bytes bigint not null default 0 check (total_bytes >= 0),
  discovered_at timestamptz not null,
  received_at timestamptz not null default now(),
  completed_at timestamptz,
  failure_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (connector_device_id, client_batch_id),
  constraint connector_sync_batches_location_tenant_fk
    foreign key (location_id, organization_id)
    references public.locations (id, organization_id) on delete restrict,
  constraint connector_sync_batches_device_tenant_fk
    foreign key (connector_device_id, organization_id)
    references public.connector_devices (id, organization_id) on delete restrict
);

create unique index connector_sync_batches_id_organization_unique
  on public.connector_sync_batches (id, organization_id);
create index connector_sync_batches_org_location_time_idx
  on public.connector_sync_batches
  (organization_id, location_id, received_at desc);
create index connector_sync_batches_device_status_idx
  on public.connector_sync_batches
  (connector_device_id, status, updated_at desc);

create table public.connector_sync_files (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  connector_sync_batch_id uuid not null,
  client_file_id uuid not null,
  source_filename text not null,
  file_extension text not null,
  mime_type text not null,
  byte_size bigint not null check (byte_size > 0 and byte_size <= 5242880),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  storage_object_path text not null unique,
  parse_status text not null default 'awaiting_format_validation' check (
    parse_status in ('awaiting_format_validation', 'parsed', 'unsupported', 'failed')
  ),
  created_at timestamptz not null default now(),
  unique (connector_sync_batch_id, client_file_id),
  constraint connector_sync_files_batch_tenant_fk
    foreign key (connector_sync_batch_id, organization_id)
    references public.connector_sync_batches (id, organization_id) on delete cascade
);

create index connector_sync_files_org_batch_idx
  on public.connector_sync_files (organization_id, connector_sync_batch_id, created_at);
create index connector_sync_files_content_hash_idx
  on public.connector_sync_files (organization_id, content_sha256);

alter table public.connector_sync_batches enable row level security;
alter table public.connector_sync_batches force row level security;
alter table public.connector_sync_files enable row level security;
alter table public.connector_sync_files force row level security;

revoke all on table
  public.connector_sync_batches,
  public.connector_sync_files
from public, anon, authenticated;

grant select on table
  public.connector_sync_batches,
  public.connector_sync_files
to authenticated;

grant select, insert, update, delete on table
  public.connector_devices,
  public.connector_sync_batches,
  public.connector_sync_files
to service_role;

create policy connector_sync_batches_member_read
on public.connector_sync_batches
for select
to authenticated
using ((select private.is_org_member(organization_id)));

create policy connector_sync_files_member_read
on public.connector_sync_files
for select
to authenticated
using ((select private.is_org_member(organization_id)));

create or replace function public.register_connector_device(
  p_actor_id uuid,
  p_organization_id uuid,
  p_location_id uuid,
  p_device_identifier uuid,
  p_device_name text,
  p_connector_version text,
  p_watch_path_hash text
)
returns table (
  connector_device_id uuid,
  device_status text
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  existing_device_id uuid;
  existing_status text;
  saved_device_id uuid;
  normalized_name text := nullif(btrim(p_device_name), '');
  normalized_version text := nullif(btrim(p_connector_version), '');
  normalized_path_hash text := nullif(lower(btrim(p_watch_path_hash)), '');
begin
  if p_actor_id is null or p_organization_id is null then
    raise exception 'authenticated actor and organization are required' using errcode = '42501';
  end if;

  if normalized_name is null or length(normalized_name) > 120 then
    raise exception 'device name is required and must be 120 characters or fewer'
      using errcode = '22023';
  end if;

  if normalized_version is null or length(normalized_version) > 40 then
    raise exception 'connector version is required and must be 40 characters or fewer'
      using errcode = '22023';
  end if;

  if normalized_path_hash is null or normalized_path_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'watch path fingerprint must be a lowercase SHA-256 value'
      using errcode = '22023';
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
    raise exception 'connector registration access denied' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.locations location
    where location.id = p_location_id
      and location.organization_id = p_organization_id
      and location.status = 'active'
  ) then
    raise exception 'active connector location not found' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_device_identifier::text, 6));

  select device.id, device.status
    into existing_device_id, existing_status
    from public.connector_devices device
    where device.organization_id = p_organization_id
      and device.device_identifier = p_device_identifier;

  if existing_status = 'revoked' then
    raise exception 'connector device is revoked' using errcode = '42501';
  end if;

  if existing_device_id is null then
    insert into public.connector_devices (
      organization_id, location_id, device_identifier, device_name,
      registered_by, platform, version, watch_path_hash, status,
      last_seen_at, updated_at
    ) values (
      p_organization_id, p_location_id, p_device_identifier, normalized_name,
      p_actor_id, 'windows', normalized_version, normalized_path_hash, 'active',
      clock_timestamp(), clock_timestamp()
    ) returning id into saved_device_id;

    insert into public.audit_events (
      organization_id, location_id, actor_id, event_type,
      entity_type, entity_id, authentication_context, software_version, payload
    ) values (
      p_organization_id, p_location_id, p_actor_id,
      'connector_device_registered', 'connector_device', saved_device_id,
      jsonb_build_object('provider', 'supabase_auth', 'workflow', 'windows_ems_connector'),
      normalized_version,
      jsonb_build_object(
        'device_identifier', p_device_identifier,
        'platform', 'windows',
        'watch_path_hash', normalized_path_hash
      )
    );
  else
    update public.connector_devices
      set location_id = p_location_id,
          device_name = normalized_name,
          registered_by = p_actor_id,
          version = normalized_version,
          watch_path_hash = normalized_path_hash,
          status = 'active',
          last_seen_at = clock_timestamp(),
          updated_at = clock_timestamp()
      where id = existing_device_id
        and organization_id = p_organization_id
      returning id into saved_device_id;
  end if;

  return query select saved_device_id, 'active'::text;
end;
$$;

revoke all on function public.register_connector_device(
  uuid, uuid, uuid, uuid, text, text, text
) from public, anon, authenticated;
grant execute on function public.register_connector_device(
  uuid, uuid, uuid, uuid, text, text, text
) to service_role;

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
  on conflict (connector_device_id, client_batch_id) do update
    set updated_at = clock_timestamp()
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
  on conflict (connector_sync_batch_id, client_file_id) do nothing
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

revoke all on function public.persist_connector_sync_file(
  uuid, uuid, uuid, uuid, uuid, uuid, text, text, text,
  bigint, text, text, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.persist_connector_sync_file(
  uuid, uuid, uuid, uuid, uuid, uuid, text, text, text,
  bigint, text, text, text, timestamptz
) to service_role;

commit;
