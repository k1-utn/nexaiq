begin;

create extension if not exists pgcrypto;
create schema if not exists private;
revoke all on schema private from public, anon;

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  locale text not null default 'en-CA',
  timezone text not null default 'America/Vancouver',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  beta_mode boolean not null default true,
  status text not null default 'active' check (status in ('active','suspended','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  province_or_state text,
  country_code text not null default 'CA',
  timezone text not null default 'America/Vancouver',
  status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, name)
);

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text not null
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  description text,
  system_key text,
  created_at timestamptz not null default now(),
  unique (organization_id, name)
);

create table public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  default_location_id uuid references public.locations(id) on delete set null,
  status text not null default 'active' check (status in ('invited','active','suspended','removed')),
  joined_at timestamptz,
  created_at timestamptz not null default now(),
  unique (organization_id, user_id)
);

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (id, display_name)
  values (new.id, nullif(new.raw_user_meta_data ->> 'display_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function private.handle_new_auth_user() from public, anon, authenticated;
create trigger create_public_user_after_auth_signup
  after insert on auth.users
  for each row execute function private.handle_new_auth_user();

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  location_id uuid references public.locations(id) on delete cascade,
  granted_by uuid references public.users(id) on delete set null,
  granted_at timestamptz not null default now(),
  unique (organization_id, user_id, role_id, location_id)
);

create or replace function private.is_org_member(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1 from public.organization_members m
    where m.organization_id = target_organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
  );
$$;

create or replace function private.has_org_permission(target_organization_id uuid, permission_code text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null and exists (
    select 1
    from public.organization_members m
    join public.user_roles ur on ur.organization_id = m.organization_id and ur.user_id = m.user_id
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where m.organization_id = target_organization_id
      and m.user_id = (select auth.uid())
      and m.status = 'active'
      and p.code = permission_code
  );
$$;

revoke all on function private.is_org_member(uuid) from public, anon;
revoke all on function private.has_org_permission(uuid, text) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.is_org_member(uuid) to authenticated;
grant execute on function private.has_org_permission(uuid, text) to authenticated;

create table public.vehicles (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  vin text, year smallint, make text, model text, trim text, created_at timestamptz not null default now(),
  unique (organization_id, vin)
);

create table public.repair_orders (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id), vehicle_id uuid not null references public.vehicles(id),
  ro_number text not null, workflow_status text not null default 'intake', assigned_estimator_id uuid references public.users(id),
  opened_at timestamptz not null default now(), closed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id, ro_number)
);

create table public.claims (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id) on delete cascade, payer_name text, claim_reference text,
  loss_date date, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

create table public.estimate_versions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id) on delete cascade, version_number integer not null,
  source_media_id uuid, source_system text not null default 'mitchell_pdf', source_sha256 text not null check (source_sha256 ~ '^[a-f0-9]{64}$'),
  parse_status text not null default 'requires_human_verification' check (parse_status in ('processing','requires_human_verification','verified','rejected')),
  parser_name text not null, parser_version text not null, verified_by uuid references public.users(id), verified_at timestamptz,
  created_at timestamptz not null default now(), unique (repair_order_id, version_number)
);

create table public.estimate_lines (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  estimate_version_id uuid not null references public.estimate_versions(id) on delete cascade, source_line_number integer,
  operation_code text, description text not null, amount numeric(12,2), raw_text text not null, parse_confidence numeric(5,4),
  human_verified boolean not null default false, verified_by uuid references public.users(id), verified_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.media (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid references public.repair_orders(id) on delete cascade, uploader_id uuid references public.users(id),
  bucket_id text not null default 'repair-evidence', object_path text not null, original_filename text not null, mime_type text not null,
  byte_size bigint not null check (byte_size >= 0), content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  original_metadata jsonb not null default '{}'::jsonb, purpose text not null, captured_at timestamptz,
  created_at timestamptz not null default now(), unique (bucket_id, object_path), unique (organization_id, content_sha256, purpose)
);

alter table public.estimate_versions add constraint estimate_versions_source_media_fk foreign key (source_media_id) references public.media(id);

create table public.media_derivatives (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  source_media_id uuid not null references public.media(id) on delete cascade, derivative_media_id uuid not null references public.media(id) on delete cascade,
  derivative_type text not null, generator_version text not null, created_at timestamptz not null default now(),
  check (source_media_id <> derivative_media_id)
);

create table public.media_analysis (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  media_id uuid not null references public.media(id) on delete cascade, ai_job_id uuid, status text not null default 'queued',
  result jsonb, created_at timestamptz not null default now()
);

create table public.scan_sessions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id) on delete cascade, scan_type text not null,
  started_by uuid references public.users(id), started_at timestamptz not null default now(), completed_at timestamptz,
  status text not null default 'capturing'
);

create table public.map_pins (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  scan_session_id uuid not null references public.scan_sessions(id) on delete cascade, media_id uuid references public.media(id),
  normalized_x numeric(7,6), normalized_y numeric(7,6), label text, created_at timestamptz not null default now()
);

create table public.findings (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id) on delete cascade, finding_type text not null,
  component text, condition text, status text not null default 'candidate' check (status in ('candidate','confirmed','dismissed','needs_review','escalated')),
  confidence numeric(5,4), source_quality text not null default 'unknown', human_review_required boolean not null default true,
  reason text not null, limitations jsonb not null default '[]'::jsonb, created_at timestamptz not null default now(),
  check (human_review_required = true)
);

create table public.supplement_candidates (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id) on delete cascade, finding_id uuid not null references public.findings(id),
  proposed_operation text, reason text not null, status text not null default 'estimator_review',
  confirmed_by uuid references public.users(id), confirmed_at timestamptz, created_at timestamptz not null default now()
);

create table public.supplements (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id) on delete cascade, supplement_number integer not null,
  status text not null default 'draft', estimator_approved_by uuid references public.users(id), estimator_approved_at timestamptz,
  submitted_externally_at timestamptz, created_at timestamptz not null default now(), unique (repair_order_id, supplement_number)
);

create table public.voice_notes (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id) on delete cascade, media_id uuid not null references public.media(id),
  transcript text, transcript_status text not null default 'pending', created_at timestamptz not null default now()
);

create table public.documents (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid references public.repair_orders(id), media_id uuid not null references public.media(id), document_type text not null,
  title text not null, revision text, applicability text, access_basis text, created_at timestamptz not null default now()
);

create table public.document_sources (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade, source_name text not null, source_locator text,
  section_reference text, retrieved_at timestamptz, content_sha256 text not null, created_at timestamptz not null default now()
);

create table public.repair_procedures (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid references public.repair_orders(id), document_source_id uuid not null references public.document_sources(id),
  title text not null, summary text, applicability_status text not null default 'review_required', created_at timestamptz not null default now()
);

create table public.repair_steps (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_procedure_id uuid not null references public.repair_procedures(id) on delete cascade, sequence integer not null,
  title text not null, instructions_summary text, human_review_required boolean not null default true, unique (repair_procedure_id, sequence)
);

create table public.qc_gates (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id) on delete cascade, repair_step_id uuid references public.repair_steps(id),
  title text not null, criticality text not null default 'standard', status text not null default 'incomplete',
  qualified_signoff_required boolean not null default false, created_at timestamptz not null default now()
);

create table public.qc_evidence (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  qc_gate_id uuid not null references public.qc_gates(id) on delete cascade, media_id uuid not null references public.media(id),
  added_by uuid references public.users(id), comment text, created_at timestamptz not null default now()
);

create table public.signoffs (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id), repair_order_id uuid not null references public.repair_orders(id),
  qc_gate_id uuid references public.qc_gates(id), signer_id uuid not null references public.users(id), signer_role_snapshot text not null,
  attestation_text text not null, record_version text not null, authentication_context jsonb not null,
  device_session_id text, evidence_snapshot jsonb not null default '[]'::jsonb, signed_at timestamptz not null default now(),
  supervisor_signoff_id uuid references public.signoffs(id), created_at timestamptz not null default now()
);

create table public.overrides (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id), qc_gate_id uuid references public.qc_gates(id),
  performed_by uuid not null references public.users(id), reason text not null check (length(trim(reason)) >= 10),
  second_approval_required boolean not null default false, second_approved_by uuid references public.users(id), second_approved_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.technician_profiles (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.users(id), employee_reference text, privacy_visibility text not null default 'role_limited',
  created_at timestamptz not null default now(), unique (organization_id, user_id)
);

create table public.technician_qualifications (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  technician_profile_id uuid not null references public.technician_profiles(id) on delete cascade, credential text not null, issuer text,
  issued_on date, expires_on date, verification_status text not null default 'pending_verification' check (verification_status in ('verified','self_reported','expired','pending_verification')),
  evidence_document_id uuid references public.documents(id), verified_by uuid references public.users(id), created_at timestamptz not null default now()
);

create table public.equipment (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id), name text not null, model text, serial_number text, status text not null default 'recorded',
  created_at timestamptz not null default now()
);

create table public.equipment_service_records (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  equipment_id uuid not null references public.equipment(id) on delete cascade, service_type text not null, serviced_at timestamptz not null,
  next_due_at timestamptz, provider text, document_id uuid references public.documents(id), created_at timestamptz not null default now()
);

create table public.scan_reports (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id), scan_type text not null, media_id uuid references public.media(id),
  status text not null default 'diagnostic_review_required', reviewed_by uuid references public.users(id), created_at timestamptz not null default now()
);

create table public.diagnostic_codes (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  scan_report_id uuid not null references public.scan_reports(id) on delete cascade, code text not null, system text,
  ai_category text check (ai_category in ('resolved','remaining','potentially_repair_related','unknown_review')),
  technician_disposition text, reviewed_by uuid references public.users(id), created_at timestamptz not null default now()
);

create table public.calibrations (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid not null references public.repair_orders(id), system text not null, vendor text, reported_result text,
  vin_match boolean, report_media_id uuid references public.media(id), status text not null default 'review_required',
  verified_by uuid references public.users(id), verified_at timestamptz, created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.users(id), category text not null, title text not null, body text not null,
  read_at timestamptz, created_at timestamptz not null default now()
);

create table public.integrations (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  provider text not null, integration_type text not null, status text not null default 'disabled', authorization_basis text,
  secret_reference text, settings jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

create table public.connector_devices (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  location_id uuid not null references public.locations(id), device_name text not null, public_key_fingerprint text,
  version text, last_seen_at timestamptz, status text not null default 'pending', created_at timestamptz not null default now()
);

create table public.ai_providers (
  id uuid primary key default gen_random_uuid(), provider_key text not null unique, display_name text not null,
  subprocessor_information_url text, created_at timestamptz not null default now()
);

create table public.organization_ai_policies (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_id uuid not null references public.ai_providers(id), enabled boolean not null default false, allowed_purposes text[] not null default '{}',
  allowed_data_categories text[] not null default '{}', required_region text, retention_settings jsonb not null default '{}'::jsonb,
  provider_training_allowed boolean not null default false, dpa_status text not null default 'not_reviewed', approved_by uuid references public.users(id),
  created_at timestamptz not null default now(), unique (organization_id, provider_id)
);

create table public.ai_model_versions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_id uuid references public.ai_providers(id), model_name text not null, provider_model_version text,
  prompt_template_version text not null, schema_version text not null, environment text not null check (environment in ('development','staging','production')),
  evaluation_status text not null default 'not_run', activated_at timestamptz, retired_at timestamptz, created_at timestamptz not null default now()
);

create table public.ai_jobs (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  repair_order_id uuid references public.repair_orders(id), job_type text not null, model_version_id uuid references public.ai_model_versions(id),
  purpose text not null, data_categories text[] not null default '{}', status text not null default 'queued', idempotency_key text not null,
  requested_by uuid references public.users(id), input_references jsonb not null default '[]'::jsonb,
  started_at timestamptz, completed_at timestamptz, created_at timestamptz not null default now(), unique (organization_id, idempotency_key)
);

create table public.ai_results (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  ai_job_id uuid not null references public.ai_jobs(id) on delete cascade, result_type text not null, structured_output jsonb not null,
  confidence numeric(5,4), source_quality text not null default 'unknown', human_review_required boolean not null default true,
  evidence_references jsonb not null default '[]'::jsonb, concise_rationale text not null, limitations jsonb not null default '[]'::jsonb,
  human_decision text, decided_by uuid references public.users(id), decided_at timestamptz,
  input_tokens integer, output_tokens integer, cost_cad numeric(12,6), latency_ms integer, created_at timestamptz not null default now(),
  check (human_review_required = true)
);

alter table public.media_analysis add constraint media_analysis_ai_job_fk foreign key (ai_job_id) references public.ai_jobs(id);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  location_id uuid references public.locations(id), repair_order_id uuid references public.repair_orders(id), actor_id uuid references public.users(id),
  event_type text not null, entity_type text not null, entity_id uuid, occurred_at timestamptz not null default now(),
  authentication_context jsonb not null default '{}'::jsonb, request_id text, software_version text,
  payload jsonb not null default '{}'::jsonb, previous_event_hash text, event_hash text,
  correction_of_event_id uuid references public.audit_events(id)
);

create or replace function private.prevent_audit_event_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'audit events are append-only; create a correction event' using errcode = '55000';
end;
$$;
revoke all on function private.prevent_audit_event_mutation() from public, anon, authenticated;
create trigger audit_events_append_only
  before update or delete on public.audit_events
  for each row execute function private.prevent_audit_event_mutation();

create table public.retention_policies (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  data_category text not null, retention_days integer check (retention_days is null or retention_days > 0), action text not null default 'delete',
  legal_review_status text not null default 'required', created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id, data_category)
);

create table public.retention_holds (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  record_type text not null, record_id uuid not null, reason text not null, placed_by uuid not null references public.users(id),
  released_by uuid references public.users(id), placed_at timestamptz not null default now(), released_at timestamptz
);

create table public.legal_documents (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  document_type text not null, version text not null, jurisdiction text, status text not null default 'draft' check (status in ('draft','counsel_review','approved','retired')),
  effective_at timestamptz, content_sha256 text, source_media_id uuid references public.media(id), counsel_approved boolean not null default false,
  approved_by uuid references public.users(id), created_at timestamptz not null default now(), unique (organization_id, document_type, version)
);

create table public.legal_acceptances (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  legal_document_id uuid not null references public.legal_documents(id), user_id uuid not null references public.users(id),
  intent text not null, attestation_text text not null, authentication_context jsonb not null, accepted_at timestamptz not null default now(),
  unique (legal_document_id, user_id)
);

create table public.data_export_requests (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  requested_by uuid not null references public.users(id), scope jsonb not null, status text not null default 'requested',
  approved_by uuid references public.users(id), export_media_id uuid references public.media(id), created_at timestamptz not null default now(), completed_at timestamptz
);

create table public.deletion_requests (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  requested_by uuid not null references public.users(id), scope jsonb not null, status text not null default 'requested',
  retention_hold_detected boolean not null default false, decision_reason text, approved_by uuid references public.users(id),
  created_at timestamptz not null default now(), completed_at timestamptz
);

create table public.security_events (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  event_type text not null, severity text not null check (severity in ('low','medium','high','critical')),
  actor_id uuid references public.users(id), source_ip inet, details jsonb not null default '{}'::jsonb,
  detected_at timestamptz not null default now(), resolved_at timestamptz, resolution_summary text
);

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  provider text not null default 'stripe', external_customer_reference text, external_subscription_reference text,
  status text not null default 'beta_free', amount_cad numeric(12,2), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id)
);

create table public.brand_configs (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id) on delete cascade,
  product_name text not null default 'nexaIQ', legal_entity_name text, logo_media_id uuid references public.media(id),
  primary_colour text not null default '#67e8f9', privacy_contact text, security_contact text, support_contact text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique (organization_id)
);

create index organization_members_lookup_idx on public.organization_members (organization_id, user_id) where status = 'active';
create index user_roles_lookup_idx on public.user_roles (organization_id, user_id, role_id);
create index repair_orders_org_status_idx on public.repair_orders (organization_id, workflow_status, updated_at desc);
create index estimate_versions_org_ro_idx on public.estimate_versions (organization_id, repair_order_id, version_number desc);
create index media_org_ro_idx on public.media (organization_id, repair_order_id, created_at desc);
create index findings_org_ro_idx on public.findings (organization_id, repair_order_id, status);
create index ai_jobs_org_status_idx on public.ai_jobs (organization_id, status, created_at);
create index audit_events_org_ro_time_idx on public.audit_events (organization_id, repair_order_id, occurred_at desc);
create index security_events_org_time_idx on public.security_events (organization_id, detected_at desc);

revoke all on all tables in schema public from anon, authenticated;
grant select, update on public.users to authenticated;
grant select on public.permissions, public.ai_providers to authenticated;

alter table public.users enable row level security;
create policy users_select_self on public.users for select to authenticated using ((select auth.uid()) = id);
create policy users_update_self on public.users for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

alter table public.permissions enable row level security;
create policy permissions_authenticated_read on public.permissions for select to authenticated using ((select auth.uid()) is not null);
alter table public.ai_providers enable row level security;
create policy ai_providers_authenticated_read on public.ai_providers for select to authenticated using ((select auth.uid()) is not null);

alter table public.organizations enable row level security;
grant select, update on public.organizations to authenticated;
create policy organizations_member_read on public.organizations for select to authenticated using ((select private.is_org_member(id)));
create policy organizations_admin_update on public.organizations for update to authenticated using ((select private.has_org_permission(id, 'organization:admin'))) with check ((select private.has_org_permission(id, 'organization:admin')));

alter table public.organization_members enable row level security;
grant select, insert, update, delete on public.organization_members to authenticated;
create policy organization_members_member_read on public.organization_members for select to authenticated using ((select private.is_org_member(organization_id)));
create policy organization_members_admin_insert on public.organization_members for insert to authenticated with check ((select private.has_org_permission(organization_id, 'organization:admin')));
create policy organization_members_admin_update on public.organization_members for update to authenticated using ((select private.has_org_permission(organization_id, 'organization:admin'))) with check ((select private.has_org_permission(organization_id, 'organization:admin')));
create policy organization_members_admin_delete on public.organization_members for delete to authenticated using ((select private.has_org_permission(organization_id, 'organization:admin')));

do $$
declare table_name text;
begin
  foreach table_name in array array['locations','roles','user_roles'] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('grant select, insert, update, delete on public.%I to authenticated', table_name);
    execute format('create policy %I on public.%I for select to authenticated using ((select private.is_org_member(organization_id)))', table_name || '_member_read', table_name);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select private.has_org_permission(organization_id, ''organization:admin'')))', table_name || '_admin_insert', table_name);
    execute format('create policy %I on public.%I for update to authenticated using ((select private.has_org_permission(organization_id, ''organization:admin''))) with check ((select private.has_org_permission(organization_id, ''organization:admin'')))', table_name || '_admin_update', table_name);
    execute format('create policy %I on public.%I for delete to authenticated using ((select private.has_org_permission(organization_id, ''organization:admin'')))', table_name || '_admin_delete', table_name);
  end loop;
end $$;

alter table public.role_permissions enable row level security;
grant select, insert, update, delete on public.role_permissions to authenticated;
create policy role_permissions_member_read on public.role_permissions for select to authenticated using (exists (select 1 from public.roles r where r.id = role_id and (select private.is_org_member(r.organization_id))));
create policy role_permissions_admin_write on public.role_permissions for all to authenticated using (exists (select 1 from public.roles r where r.id = role_id and (select private.has_org_permission(r.organization_id, 'organization:admin')))) with check (exists (select 1 from public.roles r where r.id = role_id and (select private.has_org_permission(r.organization_id, 'organization:admin'))));

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'vehicles','repair_orders','claims','estimate_versions','estimate_lines','media','media_derivatives','media_analysis',
    'scan_sessions','map_pins','findings','supplement_candidates','supplements','voice_notes','documents','document_sources',
    'repair_procedures','repair_steps','qc_gates','qc_evidence','signoffs','overrides','technician_profiles',
    'technician_qualifications','equipment','equipment_service_records','scan_reports','diagnostic_codes','calibrations',
    'notifications','integrations','connector_devices','organization_ai_policies','ai_model_versions','ai_jobs','ai_results',
    'retention_policies','retention_holds','legal_documents','legal_acceptances','data_export_requests','deletion_requests','subscriptions','brand_configs'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('grant select, insert, update, delete on public.%I to authenticated', table_name);
    execute format('create policy %I on public.%I for select to authenticated using ((select private.is_org_member(organization_id)))', table_name || '_member_read', table_name);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select private.has_org_permission(organization_id, ''records:write'')))', table_name || '_writer_insert', table_name);
    execute format('create policy %I on public.%I for update to authenticated using ((select private.has_org_permission(organization_id, ''records:write''))) with check ((select private.has_org_permission(organization_id, ''records:write'')))', table_name || '_writer_update', table_name);
    execute format('create policy %I on public.%I for delete to authenticated using ((select private.has_org_permission(organization_id, ''records:write'')))', table_name || '_writer_delete', table_name);
  end loop;
end $$;

alter table public.audit_events enable row level security;
grant select, insert on public.audit_events to authenticated;
create policy audit_events_member_read on public.audit_events for select to authenticated using ((select private.is_org_member(organization_id)));
create policy audit_events_member_append on public.audit_events for insert to authenticated with check ((select private.is_org_member(organization_id)) and (actor_id is null or actor_id = (select auth.uid())));

alter table public.security_events enable row level security;
grant select on public.security_events to authenticated;
create policy security_events_authorized_read on public.security_events for select to authenticated using ((select private.has_org_permission(organization_id, 'security:read')));

alter table public.role_permissions force row level security;
alter table public.audit_events force row level security;
alter table public.security_events force row level security;

insert into public.permissions (code, description) values
  ('organization:admin', 'Manage organization, roles, and memberships'),
  ('records:write', 'Create and update organization-scoped repair records'),
  ('security:read', 'Review organization security events'),
  ('legal:manage', 'Manage legal documents and acceptance workflows'),
  ('ai:manage', 'Manage organization AI provider policy')
on conflict (code) do nothing;

insert into public.ai_providers (provider_key, display_name) values
  ('openai','OpenAI'), ('anthropic','Anthropic'), ('google','Google'), ('nexaiq','nexaIQ models')
on conflict (provider_key) do nothing;

create or replace function public.persist_estimate_parse(
  p_organization_id uuid,
  p_repair_order_id uuid,
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
  new_media_id uuid := gen_random_uuid();
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

  perform pg_advisory_xact_lock(hashtextextended(p_repair_order_id::text, 0));
  select coalesce(max(ev.version_number), 0) + 1
    into next_version
    from public.estimate_versions ev
    where ev.repair_order_id = p_repair_order_id;

  insert into public.media (
    id, organization_id, repair_order_id, uploader_id, bucket_id, object_path,
    original_filename, mime_type, byte_size, content_sha256, purpose
  ) values (
    new_media_id, p_organization_id, p_repair_order_id, (select auth.uid()),
    'repair-evidence', p_object_path, p_original_filename, p_mime_type,
    p_byte_size, p_content_sha256, 'estimate_source'
  );

  insert into public.estimate_versions (
    id, organization_id, repair_order_id, version_number, source_media_id,
    source_system, source_sha256, parse_status, parser_name, parser_version
  ) values (
    new_estimate_id, p_organization_id, p_repair_order_id, next_version,
    new_media_id, 'mitchell_pdf', p_content_sha256,
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
      'source_media_id', new_media_id,
      'content_sha256', p_content_sha256,
      'parser_name', p_parser_name,
      'parser_version', p_parser_version,
      'verification_status', 'requires_human_verification'
    )
  );

  return query select new_estimate_id, new_media_id;
end;
$$;
revoke all on function public.persist_estimate_parse(uuid, uuid, text, text, text, bigint, text, text, text, jsonb) from public, anon;
grant execute on function public.persist_estimate_parse(uuid, uuid, text, text, text, bigint, text, text, text, jsonb) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'repair-evidence', 'repair-evidence', false, 52428800,
  array['application/pdf','image/jpeg','image/png','image/heic','image/webp','audio/m4a','audio/mpeg','video/mp4']
)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function private.storage_organization_id(object_name text)
returns uuid
language sql
immutable
security invoker
set search_path = ''
as $$
  select case
    when (storage.foldername(object_name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    then ((storage.foldername(object_name))[1])::uuid
    else null
  end;
$$;
grant execute on function private.storage_organization_id(text) to authenticated;

create policy repair_evidence_member_read on storage.objects for select to authenticated
using (bucket_id = 'repair-evidence' and (select private.is_org_member(private.storage_organization_id(name))));
create policy repair_evidence_member_insert on storage.objects for insert to authenticated
with check (bucket_id = 'repair-evidence' and (select private.has_org_permission(private.storage_organization_id(name), 'records:write')));
create policy repair_evidence_member_update on storage.objects for update to authenticated
using (bucket_id = 'repair-evidence' and (select private.has_org_permission(private.storage_organization_id(name), 'records:write')))
with check (bucket_id = 'repair-evidence' and (select private.has_org_permission(private.storage_organization_id(name), 'records:write')));
create policy repair_evidence_member_delete on storage.objects for delete to authenticated
using (bucket_id = 'repair-evidence' and (select private.has_org_permission(private.storage_organization_id(name), 'records:write')));

alter default privileges in schema public revoke all on tables from anon, authenticated;

commit;
