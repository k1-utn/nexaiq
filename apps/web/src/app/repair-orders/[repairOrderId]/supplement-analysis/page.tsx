import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { SupplementAnalysis } from "@/components/supplement-analysis";
import { createClient } from "@/lib/supabase/server";

export default async function SupplementAnalysisPage({
  params,
}: {
  params: Promise<{ repairOrderId: string }>;
}) {
  await connection();
  const { repairOrderId } = await params;
  const supabase = await createClient();
  const { data: authData } = await supabase.auth.getClaims();
  if (!authData?.claims?.sub) redirect("/login");

  const { data: memberships } = await supabase
    .from("organization_members")
    .select("organization_id")
    .eq("status", "active")
    .limit(1);
  const organizationId = memberships?.[0]?.organization_id;
  if (!organizationId) redirect("/login?error=no_organization");

  const { data: repairOrder } = await supabase
    .from("repair_orders")
    .select("id, ro_number, vehicle_id")
    .eq("id", repairOrderId)
    .eq("organization_id", organizationId)
    .maybeSingle();
  if (!repairOrder) notFound();

  const [{ data: organization }, { data: vehicle }, { data: findings }, { data: jobs }] =
    await Promise.all([
      supabase.from("organizations").select("name").eq("id", organizationId).single(),
      supabase
        .from("vehicles")
        .select("year, make, model, vin")
        .eq("id", repairOrder.vehicle_id)
        .single(),
      supabase
        .from("findings")
        .select(
          "id, finding_type, component, condition, status, confidence, source_quality, reason, limitations, proposed_operation, comparison_status, match_method, created_at",
        )
        .eq("organization_id", organizationId)
        .eq("repair_order_id", repairOrderId)
        .order("created_at", { ascending: false }),
      supabase
        .from("ai_jobs")
        .select("id, status, failure_code, started_at, completed_at, created_at")
        .eq("organization_id", organizationId)
        .eq("repair_order_id", repairOrderId)
        .eq("job_type", "supplement_analysis")
        .order("created_at", { ascending: false })
        .limit(5),
    ]);

  const findingIds = (findings ?? []).map((finding) => finding.id);
  const { data: evidenceLinks } = findingIds.length
    ? await supabase
        .from("finding_evidence")
        .select("finding_id, media_id, evidence_role")
        .in("finding_id", findingIds)
    : { data: [] };
  const mediaIds = [...new Set((evidenceLinks ?? []).map((link) => link.media_id))];
  const { data: media } = mediaIds.length
    ? await supabase
        .from("media")
        .select("id, object_path, original_filename, mime_type, content_sha256")
        .in("id", mediaIds)
    : { data: [] };
  const mediaWithUrls = await Promise.all(
    (media ?? []).map(async (item) => {
      const { data } = await supabase.storage
        .from("repair-evidence")
        .createSignedUrl(item.object_path, 300);
      return { ...item, signedUrl: data?.signedUrl ?? null };
    }),
  );

  return (
    <SupplementAnalysis
      organizationId={organizationId}
      organizationName={organization?.name ?? "Current organization"}
      repairOrder={{
        id: repairOrder.id,
        number: repairOrder.ro_number,
        vehicle:
          [vehicle?.year, vehicle?.make, vehicle?.model].filter(Boolean).join(" ") ||
          "Vehicle not recorded",
        vin: vehicle?.vin ?? null,
      }}
      findings={findings ?? []}
      jobs={jobs ?? []}
      evidenceLinks={evidenceLinks ?? []}
      media={mediaWithUrls}
    />
  );
}
