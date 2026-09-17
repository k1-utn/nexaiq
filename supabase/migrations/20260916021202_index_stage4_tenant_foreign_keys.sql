-- Cover composite tenant foreign keys in their declared column order. These
-- indexes keep parent updates/deletes and integrity checks from scanning the
-- child tables as Stage 4 records grow.
create index findings_ai_result_tenant_idx
  on public.findings (ai_result_id, organization_id);
create index findings_estimate_version_tenant_idx
  on public.findings (estimate_version_id, organization_id);
create index findings_estimate_line_tenant_idx
  on public.findings (matched_estimate_line_id, organization_id);

create index finding_evidence_finding_tenant_idx
  on public.finding_evidence (finding_id, organization_id);
create index finding_evidence_media_tenant_idx
  on public.finding_evidence (media_id, organization_id);

create index ai_evaluation_events_repair_order_tenant_idx
  on public.ai_evaluation_events (repair_order_id, organization_id);
create index ai_evaluation_events_job_tenant_idx
  on public.ai_evaluation_events (ai_job_id, organization_id);
create index ai_evaluation_events_result_tenant_idx
  on public.ai_evaluation_events (ai_result_id, organization_id);
create index ai_evaluation_events_finding_tenant_idx
  on public.ai_evaluation_events (finding_id, organization_id);

create index supplement_candidates_finding_tenant_idx
  on public.supplement_candidates (finding_id, organization_id);
