import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { SupplementReview } from "@/components/supplement-review";
import { createClient } from "@/lib/supabase/server";

export default async function SupplementReviewPage({ params }: { params: Promise<{ repairOrderId: string }> }) {
  await connection();
  const { repairOrderId } = await params;
  const supabase = await createClient();
  const { data: authData } = await supabase.auth.getClaims();
  if (!authData?.claims?.sub) redirect("/login");

  const { data: memberships } = await supabase.from("organization_members").select("organization_id").eq("status", "active").limit(1);
  const organizationId = memberships?.[0]?.organization_id;
  if (!organizationId) redirect("/login?error=no_organization");

  const { data: repairOrder } = await supabase.from("repair_orders").select("id, ro_number, vehicle_id").eq("id", repairOrderId).eq("organization_id", organizationId).maybeSingle();
  if (!repairOrder) notFound();

  const [{ data: organization }, { data: vehicle }, { data: candidates }, { data: packages }, { data: documents }, { data: auditEvents }] = await Promise.all([
    supabase.from("organizations").select("name").eq("id", organizationId).single(),
    supabase.from("vehicles").select("year, make, model, vin").eq("id", repairOrder.vehicle_id).single(),
    supabase.from("supplement_candidates").select("id, finding_id, proposed_operation, reason, status, review_note, oem_consideration_status, oem_source_document_id, oem_source_note, reviewed_at, created_at").eq("organization_id", organizationId).eq("repair_order_id", repairOrderId).order("created_at", { ascending: true }),
    supabase.from("supplement_review_packages").select("id, package_number, status, approval_note, approved_at, created_at").eq("organization_id", organizationId).eq("repair_order_id", repairOrderId).order("package_number", { ascending: false }),
    supabase.from("documents").select("id, title, revision, applicability").eq("organization_id", organizationId).eq("repair_order_id", repairOrderId).order("created_at", { ascending: false }),
    supabase.from("audit_events").select("id, event_type, occurred_at, payload").eq("organization_id", organizationId).eq("repair_order_id", repairOrderId).in("event_type", ["supplement_candidate_review_recorded", "supplement_review_package_created", "supplement_review_package_approved", "supplement_review_package_changes_requested"]).order("occurred_at", { ascending: false }).limit(50),
  ]);

  const findingIds = [...new Set((candidates ?? []).map((candidate) => candidate.finding_id))];
  const packageIds = (packages ?? []).map((item) => item.id);
  const documentIds = (documents ?? []).map((item) => item.id);
  const [{ data: findings }, { data: evidenceLinks }, { data: packageItems }, { data: documentSources }] = await Promise.all([
    findingIds.length ? supabase.from("findings").select("id, component, condition, confidence, source_quality, comparison_status, limitations").in("id", findingIds) : Promise.resolve({ data: [] }),
    findingIds.length ? supabase.from("finding_evidence").select("finding_id, media_id, evidence_role").in("finding_id", findingIds) : Promise.resolve({ data: [] }),
    packageIds.length ? supabase.from("supplement_review_package_items").select("package_id").in("package_id", packageIds) : Promise.resolve({ data: [] }),
    documentIds.length ? supabase.from("document_sources").select("document_id, source_name, section_reference").in("document_id", documentIds) : Promise.resolve({ data: [] }),
  ]);

  const mediaIds = [...new Set((evidenceLinks ?? []).map((link) => link.media_id))];
  const { data: media } = mediaIds.length ? await supabase.from("media").select("id, object_path, original_filename, content_sha256").in("id", mediaIds) : { data: [] };
  const mediaById = new Map(await Promise.all((media ?? []).map(async (item) => {
    const { data } = await supabase.storage.from("repair-evidence").createSignedUrl(item.object_path, 300);
    return [item.id, { ...item, signedUrl: data?.signedUrl ?? null }] as const;
  })));
  const packageCounts = new Map<string, number>();
  for (const item of packageItems ?? []) packageCounts.set(item.package_id, (packageCounts.get(item.package_id) ?? 0) + 1);

  return <SupplementReview
    organizationId={organizationId}
    organizationName={organization?.name ?? "Current organization"}
    repairOrder={{ id: repairOrder.id, number: repairOrder.ro_number, vehicle: [vehicle?.year, vehicle?.make, vehicle?.model].filter(Boolean).join(" ") || "Vehicle not recorded", vin: vehicle?.vin ?? null }}
    candidates={candidates ?? []}
    findings={findings ?? []}
    evidence={(evidenceLinks ?? []).map((link) => ({ ...link, original_filename: mediaById.get(link.media_id)?.original_filename ?? link.media_id, content_sha256: mediaById.get(link.media_id)?.content_sha256 ?? "", signedUrl: mediaById.get(link.media_id)?.signedUrl ?? null }))}
    documents={(documents ?? []).map((document) => { const source = (documentSources ?? []).find((item) => item.document_id === document.id); return { ...document, sourceName: source?.source_name ?? null, sectionReference: source?.section_reference ?? null }; })}
    packages={(packages ?? []).map((item) => ({ ...item, itemCount: packageCounts.get(item.id) ?? 0 }))}
    auditEvents={auditEvents ?? []}
  />;
}
