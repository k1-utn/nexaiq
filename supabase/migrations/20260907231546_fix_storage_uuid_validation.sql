-- Accept every PostgreSQL UUID shape used by tenant identifiers, including
-- deterministic development/test UUIDs whose version nibble is zero.
create or replace function private.storage_organization_id(object_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when (storage.foldername(object_name))[1]
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then ((storage.foldername(object_name))[1])::uuid
    else null
  end;
$$;

revoke all on function private.storage_organization_id(text) from public, anon;
grant execute on function private.storage_organization_id(text) to authenticated;
