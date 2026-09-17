create index findings_repair_order_idx
  on public.findings (repair_order_id);

create index supplement_candidates_organization_idx
  on public.supplement_candidates (organization_id);
create index supplement_candidates_repair_order_idx
  on public.supplement_candidates (repair_order_id);
create index supplement_candidates_confirmed_by_idx
  on public.supplement_candidates (confirmed_by);
