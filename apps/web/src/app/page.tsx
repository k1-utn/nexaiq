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
  const [{ data: organization }, { data: repairOrders }] = await Promise.all([
    supabase.from("organizations").select("name").eq("id", organizationId).single(),
    supabase
      .from("repair_orders")
      .select("id")
      .eq("organization_id", organizationId)
      .order("updated_at", { ascending: false })
      .limit(1),
  ]);
  const repairOrderId = repairOrders?.[0]?.id ?? null;
  const { data: estimateVersions } = repairOrderId
    ? await supabase
        .from("estimate_versions")
        .select("id")
        .eq("repair_order_id", repairOrderId)
        .order("version_number", { ascending: false })
        .limit(1)
    : { data: null };
  return (
    <Dashboard
      organizationId={organizationId}
      organizationName={organization?.name ?? "Current organization"}
      repairOrderId={repairOrderId}
      latestEstimateVersionId={estimateVersions?.[0]?.id ?? null}
    />
  );
}
