begin;

alter table public.scan_sessions
  add column client_session_id uuid,
  add column privacy_mode text not null default 'minimized',
  add column last_activity_at timestamptz not null default now(),
  add constraint scan_sessions_status_check
    check (status in ('capturing', 'uploading', 'ready_for_analysis', 'completed', 'cancelled')),
  add constraint scan_sessions_privacy_mode_check
    check (privacy_mode in ('minimized', 'standard'));

create unique index scan_sessions_org_client_session_idx
  on public.scan_sessions (organization_id, client_session_id)
  where client_session_id is not null;
create index scan_sessions_org_repair_order_activity_idx
  on public.scan_sessions (organization_id, repair_order_id, last_activity_at desc);
create index scan_sessions_started_by_idx
  on public.scan_sessions (started_by);

create table public.scan_session_media (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  scan_session_id uuid not null references public.scan_sessions(id) on delete cascade,
  media_id uuid not null references public.media(id) on delete cascade,
  client_capture_id uuid not null,
  capture_kind text not null check (capture_kind in ('photo', 'voice_note')),
  sequence_number integer not null check (sequence_number >= 0),
  privacy_flags jsonb not null default '{}'::jsonb check (jsonb_typeof(privacy_flags) = 'object'),
  captured_at timestamptz not null,
  uploaded_at timestamptz not null default now(),
  unique (organization_id, client_capture_id),
  unique (media_id),
  unique (scan_session_id, sequence_number)
);

comment on table public.scan_session_media is
  'Server-accepted photo and voice captures. Client capture IDs make offline retries idempotent.';
comment on column public.scan_session_media.privacy_flags is
  'User-entered minimization flags only; the app does not claim that faces, plates, or documents were automatically redacted.';

create index scan_session_media_org_session_sequence_idx
  on public.scan_session_media (organization_id, scan_session_id, sequence_number);

alter table public.scan_session_media enable row level security;
alter table public.scan_session_media force row level security;
revoke all on table public.scan_session_media from public, anon, authenticated;
grant select, insert on table public.scan_session_media to authenticated;

create policy scan_session_media_member_read
on public.scan_session_media
for select
to authenticated
using ((select private.is_org_member(organization_id)));

create policy scan_session_media_writer_insert
on public.scan_session_media
for insert
to authenticated
with check ((select private.has_org_permission(organization_id, 'records:write')));

-- A capture is immutable evidence. Identical bytes can legitimately occur in more
-- than one repair order, so retain a lookup index without collapsing the records.
alter table public.media
  drop constraint media_organization_id_content_sha256_purpose_key;
create index media_org_hash_purpose_idx
  on public.media (organization_id, content_sha256, purpose);

create or replace function public.persist_scan_capture(
  p_organization_id uuid,
  p_repair_order_id uuid,
  p_client_session_id uuid,
  p_client_capture_id uuid,
  p_media_id uuid,
  p_object_path text,
  p_original_filename text,
  p_mime_type text,
  p_byte_size bigint,
  p_content_sha256 text,
  p_capture_kind text,
  p_sequence_number integer,
  p_captured_at timestamptz,
  p_privacy_flags jsonb default '{}'::jsonb,
  p_original_metadata jsonb default '{}'::jsonb
)
returns table (
  scan_session_id uuid,
  media_id uuid,
  scan_session_media_id uuid,
  already_persisted boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  session_id uuid;
  link_id uuid;
  existing_media_id uuid;
  expected_purpose text;
begin
  if caller_id is null
     or not (select private.has_org_permission(p_organization_id, 'records:write')) then
    raise exception 'organization write access denied' using errcode = '42501';
  end if;

  if p_capture_kind not in ('photo', 'voice_note') then
    raise exception 'unsupported capture kind' using errcode = '22023';
  end if;
  if p_sequence_number < 0 or p_byte_size <= 0 then
    raise exception 'invalid capture metadata' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_privacy_flags, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_original_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'capture metadata must be JSON objects' using errcode = '22023';
  end if;
  if private.storage_organization_id(p_object_path) is distinct from p_organization_id then
    raise exception 'storage path organization mismatch' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.repair_orders ro
    where ro.id = p_repair_order_id
      and ro.organization_id = p_organization_id
  ) then
    raise exception 'repair order not found' using errcode = 'P0002';
  end if;

  select ssm.scan_session_id, ssm.media_id, ssm.id
    into session_id, existing_media_id, link_id
  from public.scan_session_media ssm
  where ssm.organization_id = p_organization_id
    and ssm.client_capture_id = p_client_capture_id;

  if link_id is not null then
    return query select session_id, existing_media_id, link_id, true;
    return;
  end if;

  insert into public.scan_sessions (
    organization_id, repair_order_id, scan_type, started_by,
    client_session_id, privacy_mode, status, last_activity_at
  ) values (
    p_organization_id, p_repair_order_id, 'supplement_teardown', caller_id,
    p_client_session_id, 'minimized', 'capturing', clock_timestamp()
  )
  on conflict (organization_id, client_session_id) where client_session_id is not null
  do update set last_activity_at = excluded.last_activity_at
  returning id into session_id;

  if not exists (
    select 1 from public.scan_sessions ss
    where ss.id = session_id
      and ss.organization_id = p_organization_id
      and ss.repair_order_id = p_repair_order_id
      and ss.started_by = caller_id
  ) then
    raise exception 'capture session does not match repair order or user' using errcode = '42501';
  end if;

  expected_purpose := case
    when p_capture_kind = 'photo' then 'teardown_photo'
    else 'teardown_voice_note'
  end;

  insert into public.media (
    id, organization_id, repair_order_id, uploader_id, bucket_id,
    object_path, original_filename, mime_type, byte_size, content_sha256,
    original_metadata, purpose, captured_at
  ) values (
    p_media_id, p_organization_id, p_repair_order_id, caller_id, 'repair-evidence',
    p_object_path, p_original_filename, p_mime_type, p_byte_size, p_content_sha256,
    coalesce(p_original_metadata, '{}'::jsonb), expected_purpose, p_captured_at
  );

  insert into public.scan_session_media (
    organization_id, scan_session_id, media_id, client_capture_id,
    capture_kind, sequence_number, privacy_flags, captured_at
  ) values (
    p_organization_id, session_id, p_media_id, p_client_capture_id,
    p_capture_kind, p_sequence_number, coalesce(p_privacy_flags, '{}'::jsonb), p_captured_at
  ) returning id into link_id;

  if p_capture_kind = 'voice_note' then
    insert into public.voice_notes (
      organization_id, repair_order_id, media_id, transcript_status
    ) values (
      p_organization_id, p_repair_order_id, p_media_id, 'pending'
    );
  end if;

  insert into public.audit_events (
    organization_id, repair_order_id, actor_id, event_type,
    entity_type, entity_id, payload
  ) values (
    p_organization_id, p_repair_order_id, caller_id, 'scan_capture_uploaded',
    'media', p_media_id,
    jsonb_build_object(
      'scan_session_id', session_id,
      'scan_session_media_id', link_id,
      'capture_kind', p_capture_kind,
      'client_capture_id', p_client_capture_id,
      'content_sha256', p_content_sha256,
      'privacy_flags', coalesce(p_privacy_flags, '{}'::jsonb)
    )
  );

  return query select session_id, p_media_id, link_id, false;
end;
$$;

revoke all on function public.persist_scan_capture(
  uuid, uuid, uuid, uuid, uuid, text, text, text, bigint, text,
  text, integer, timestamptz, jsonb, jsonb
) from public, anon;
grant execute on function public.persist_scan_capture(
  uuid, uuid, uuid, uuid, uuid, text, text, text, bigint, text,
  text, integer, timestamptz, jsonb, jsonb
) to authenticated;

commit;
