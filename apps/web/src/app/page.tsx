import { Dashboard } from "@/components/dashboard";
import { redirect } from "next/navigation";
import { connection } from "next/server";
import { createClient } from "@/lib/supabase/server";

export default async function Home() {
  await connection();
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  if (!data?.claims?.sub) redirect("/login");
  const { data: memberships } = await supabase
    .from("organization_members")
    .select("organization_id")
    .eq("status", "active")
    .limit(1);
  const organizationId = memberships?.[0]?.organization_id;
  if (!organizationId) redirect("/login?error=no_organization");
  const [
    { data: organization },
    { data: repairOrders, count: repairOrderCount },
  ] = await Promise.all([
    supabase.from("organizations").select("name").eq("id", organizationId).single(),
    supabase
      .from("repair_orders")
      .select(
        "id, ro_number, workflow_status, updated_at, vehicles(year, make, model)",
        { count: "exact" },
      )
      .eq("organization_id", organizationId)
      .order("updated_at", { ascending: false })
      .limit(20),
  ]);
  const repairOrderId = repairOrders?.[0]?.id ?? null;
  const repairOrderIds = repairOrders?.map((repairOrder) => repairOrder.id) ?? [];
  const { data: estimateVersions } = repairOrderIds.length
    ? await supabase
        .from("estimate_versions")
        .select(
          "id, repair_order_id, version_number, source_system, parse_status, created_at",
        )
        .in("repair_order_id", repairOrderIds)
        .order("version_number", { ascending: false })
    : { data: null };
  const latestEstimateByRepairOrder = new Map<
    string,
    NonNullable<typeof estimateVersions>[number]
  >();
  for (const estimate of estimateVersions ?? []) {
    if (!latestEstimateByRepairOrder.has(estimate.repair_order_id)) {
      latestEstimateByRepairOrder.set(estimate.repair_order_id, estimate);
    }
  }
  const recentRepairOrders = (repairOrders ?? []).map((repairOrder) => {
    const vehicle = Array.isArray(repairOrder.vehicles)
      ? repairOrder.vehicles[0]
      : repairOrder.vehicles;
    const estimate = latestEstimateByRepairOrder.get(repairOrder.id);
    return {
      id: repairOrder.id,
      roNumber: repairOrder.ro_number,
      vehicle: [vehicle?.year, vehicle?.make, vehicle?.model]
        .filter(Boolean)
        .join(" ") || "Vehicle details pending",
      workflowStatus: repairOrder.workflow_status,
      estimateLabel: estimate
        ? `${estimate.source_system === "mitchell_ems" ? "Mitchell EMS" : "Estimate"} · v${estimate.version_number}`
        : "No estimate",
      estimateStatus: estimate?.parse_status ?? null,
      updatedLabel: new Intl.DateTimeFormat("en-CA", {
        month: "short",
        day: "numeric",
        year: "numeric",
      }).format(new Date(repairOrder.updated_at)),
    };
  });
  const latestEstimateVersionId = repairOrderId
    ? latestEstimateByRepairOrder.get(repairOrderId)?.id ?? null
    : null;
  return (
    <Dashboard
      organizationId={organizationId}
      organizationName={organization?.name ?? "Current organization"}
      repairOrderId={repairOrderId}
      latestEstimateVersionId={latestEstimateVersionId}
      repairOrders={recentRepairOrders}
      repairOrderCount={repairOrderCount ?? recentRepairOrders.length}
    />
  );
}
