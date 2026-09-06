begin;

drop function public.persist_estimate_parse(
  uuid, uuid, text, text, text, bigint, text, text, text, jsonb
);

create function public.persist_estimate_parse(
  p_organization_id uuid,
  p_repair_order_id uuid,
  p_source_media_id uuid,
  p_object_path text,
  p_original_filename text,
  p_mime_type text,
  p_byte_size bigint,
  p_content_sha256 text,
  p_parser_name text,
  p_parser_version text,
  p_lines jsonb
)
returns table (estimate_version_id uuid, source_media_id uuid)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  new_estimate_id uuid := gen_random_uuid();
  next_version integer;
  item jsonb;
begin
  if (select auth.uid()) is null
     or not (select private.has_org_permission(p_organization_id, 'records:write')) then
    raise exception 'organization write access denied' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.repair_orders ro
    where ro.id = p_repair_order_id and ro.organization_id = p_organization_id
  ) then
    raise exception 'repair order not found in organization' using errcode = 'P0002';
  end if;

  if p_source_media_id is null
     or p_object_path not like (
       p_organization_id::text || '/' || p_repair_order_id::text || '/'
       || p_source_media_id::text || '/%'
     ) then
    raise exception 'source object path does not match its organization, repair order, and media id'
      using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_repair_order_id::text, 0));
  select coalesce(max(ev.version_number), 0) + 1
    into next_version
    from public.estimate_versions ev
    where ev.repair_order_id = p_repair_order_id;

  insert into public.media (
    id, organization_id, repair_order_id, uploader_id, bucket_id, object_path,
    original_filename, mime_type, byte_size, content_sha256, purpose
  ) values (
    p_source_media_id, p_organization_id, p_repair_order_id, (select auth.uid()),
    'repair-evidence', p_object_path, p_original_filename, p_mime_type,
    p_byte_size, p_content_sha256, 'estimate_source'
  );

  insert into public.estimate_versions (
    id, organization_id, repair_order_id, version_number, source_media_id,
    source_system, source_sha256, parse_status, parser_name, parser_version
  ) values (
    new_estimate_id, p_organization_id, p_repair_order_id, next_version,
    p_source_media_id, 'mitchell_pdf', p_content_sha256,
    'requires_human_verification', p_parser_name, p_parser_version
  );

  for item in select value from jsonb_array_elements(p_lines)
  loop
    insert into public.estimate_lines (
      organization_id, estimate_version_id, source_line_number, operation_code,
      description, amount, raw_text, parse_confidence, human_verified
    ) values (
      p_organization_id,
      new_estimate_id,
      nullif(item ->> 'source_line_number', '')::integer,
      nullif(item ->> 'operation_code', ''),
      item ->> 'description',
      nullif(item ->> 'amount', '')::numeric,
      item ->> 'raw_text',
      nullif(item ->> 'confidence', '')::numeric,
      false
    );
  end loop;

  insert into public.audit_events (
    organization_id, repair_order_id, actor_id, event_type, entity_type,
    entity_id, authentication_context, payload
  ) values (
    p_organization_id, p_repair_order_id, (select auth.uid()),
    'estimate_imported', 'estimate_version', new_estimate_id,
    jsonb_build_object('provider', 'supabase_auth'),
    jsonb_build_object(
      'source_media_id', p_source_media_id,
      'content_sha256', p_content_sha256,
      'parser_name', p_parser_name,
      'parser_version', p_parser_version,
      'verification_status', 'requires_human_verification'
    )
  );

  return query select new_estimate_id, p_source_media_id;
end;
$$;

revoke all on function public.persist_estimate_parse(
  uuid, uuid, uuid, text, text, text, bigint, text, text, text, jsonb
) from public, anon;
grant execute on function public.persist_estimate_parse(
  uuid, uuid, uuid, text, text, text, bigint, text, text, text, jsonb
) to authenticated;

commit;
