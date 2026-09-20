begin;

-- Some Mitchell exports use a zero-filled RO_ID when the shop has not assigned
-- an RO number. Correct already imported batches to the non-empty estimate file
-- reference, without overwriting an existing repair-order identifier.
create temporary table ems_ro_reference_corrections on commit drop as
select distinct on (batch.id)
  batch.id as connector_sync_batch_id,
  batch.organization_id,
  batch.location_id,
  batch.connector_version,
  batch.repair_order_id,
  device.registered_by as actor_id,
  left(btrim(file.extracted_payload ->> 'estimate_file_reference'), 120)
    as corrected_reference
from public.connector_sync_batches batch
join public.connector_sync_files file
  on file.connector_sync_batch_id = batch.id
 and file.organization_id = batch.organization_id
join public.repair_orders repair_order
  on repair_order.id = batch.repair_order_id
 and repair_order.organization_id = batch.organization_id
join public.connector_devices device
  on device.id = batch.connector_device_id
 and device.organization_id = batch.organization_id
where file.parse_status = 'parsed'
  and file.extracted_payload ->> 'table' = 'env'
  and btrim(coalesce(file.extracted_payload ->> 'repair_order_reference', '')) ~ '^0+$'
  and nullif(btrim(file.extracted_payload ->> 'estimate_file_reference'), '') is not null
  and repair_order.ro_number ~ '^0+$'
  and not exists (
    select 1
    from public.repair_orders existing
    where existing.organization_id = batch.organization_id
      and existing.id <> repair_order.id
      and existing.ro_number = left(
        btrim(file.extracted_payload ->> 'estimate_file_reference'), 120
      )
  )
order by batch.id, file.created_at desc;

insert into public.audit_events (
  organization_id, location_id, repair_order_id, actor_id,
  event_type, entity_type, entity_id, authentication_context,
  software_version, payload
)
select
  correction.organization_id,
  correction.location_id,
  correction.repair_order_id,
  correction.actor_id,
  'connector_ems_repair_order_reference_corrected',
  'repair_order',
  correction.repair_order_id,
  jsonb_build_object(
    'provider', 'supabase_auth',
    'workflow', 'windows_ems_connector'
  ),
  correction.connector_version,
  jsonb_build_object(
    'connector_sync_batch_id', correction.connector_sync_batch_id,
    'previous_reference', '0',
    'corrected_reference', correction.corrected_reference,
    'reason', 'zero_filled_ems_ro_reference'
  )
from ems_ro_reference_corrections correction;

update public.repair_orders repair_order
set ro_number = correction.corrected_reference,
    updated_at = clock_timestamp()
from ems_ro_reference_corrections correction
where repair_order.id = correction.repair_order_id
  and repair_order.organization_id = correction.organization_id;

update public.connector_sync_batches batch
set normalized_summary = jsonb_set(
      batch.normalized_summary,
      '{repair_order_reference}',
      to_jsonb(correction.corrected_reference),
      true
    ),
    updated_at = clock_timestamp()
from ems_ro_reference_corrections correction
where batch.id = correction.connector_sync_batch_id
  and batch.organization_id = correction.organization_id;

update public.connector_sync_files file
set extracted_payload = jsonb_set(
  file.extracted_payload,
  '{repair_order_reference}',
  'null'::jsonb,
  true
)
where file.parse_status = 'parsed'
  and file.extracted_payload ->> 'table' = 'env'
  and btrim(coalesce(file.extracted_payload ->> 'repair_order_reference', '')) ~ '^0+$';

commit;
