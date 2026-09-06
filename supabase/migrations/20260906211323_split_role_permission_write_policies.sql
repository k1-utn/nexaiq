begin;

drop policy role_permissions_admin_write on public.role_permissions;

create policy role_permissions_admin_insert
on public.role_permissions
for insert
to authenticated
with check (
  exists (
    select 1
    from public.roles r
    where r.id = role_id
      and (select private.has_org_permission(r.organization_id, 'organization:admin'))
  )
);

create policy role_permissions_admin_update
on public.role_permissions
for update
to authenticated
using (
  exists (
    select 1
    from public.roles r
    where r.id = role_id
      and (select private.has_org_permission(r.organization_id, 'organization:admin'))
  )
)
with check (
  exists (
    select 1
    from public.roles r
    where r.id = role_id
      and (select private.has_org_permission(r.organization_id, 'organization:admin'))
  )
);

create policy role_permissions_admin_delete
on public.role_permissions
for delete
to authenticated
using (
  exists (
    select 1
    from public.roles r
    where r.id = role_id
      and (select private.has_org_permission(r.organization_id, 'organization:admin'))
  )
);

commit;
