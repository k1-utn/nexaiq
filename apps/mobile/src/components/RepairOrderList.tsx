import { useEffect, useState } from "react";
import { ActivityIndicator, Alert, RefreshControl, ScrollView, StyleSheet, Text, TouchableOpacity, View } from "react-native";

import { supabase } from "../lib/supabase";
import type { OrganizationContext, RepairOrder } from "../types";

type OrganizationRow = { id: string; name: string };
type MembershipRow = { organization_id: string; organizations: OrganizationRow | OrganizationRow[] | null };
type RepairOrderRow = Omit<RepairOrder, "vehicle"> & { vehicles: RepairOrder["vehicle"] | RepairOrder["vehicle"][] };

function oneRelation<T>(value: T | T[] | null): T | null {
  return Array.isArray(value) ? value[0] ?? null : value;
}

export function RepairOrderList({ onOrganizationLoaded, onSelectRepairOrder }: { onOrganizationLoaded: (organization: OrganizationContext) => void; onSelectRepairOrder: (repairOrder: RepairOrder) => void }) {
  const [organization, setOrganization] = useState<OrganizationContext | null>(null);
  const [repairOrders, setRepairOrders] = useState<RepairOrder[]>([]);
  const [loading, setLoading] = useState(true);

  async function load() {
    setLoading(true);
    const { data: memberships, error: membershipError } = await supabase.from("organization_members").select("organization_id, organizations(id, name)").eq("status", "active").limit(1);
    if (membershipError || !memberships?.length) {
      setLoading(false);
      Alert.alert("Workspace unavailable", membershipError?.message ?? "No active nexaIQ workspace was found.");
      return;
    }
    const membership = memberships[0] as unknown as MembershipRow;
    const nextOrganization = oneRelation(membership.organizations) ?? { id: membership.organization_id, name: "nexaIQ workspace" };
    setOrganization(nextOrganization);
    onOrganizationLoaded(nextOrganization);
    const { data, error } = await supabase.from("repair_orders").select("id, ro_number, workflow_status, updated_at, vehicles(year, make, model, vin)").eq("organization_id", nextOrganization.id).is("closed_at", null).order("updated_at", { ascending: false });
    setLoading(false);
    if (error) {
      Alert.alert("Repair orders unavailable", error.message);
      return;
    }
    setRepairOrders((data as unknown as RepairOrderRow[]).map(({ vehicles, ...row }) => ({ ...row, vehicle: oneRelation(vehicles) })));
  }

  useEffect(() => { void load(); }, []);

  return (
    <ScrollView contentContainerStyle={styles.page} refreshControl={<RefreshControl refreshing={loading} onRefresh={() => void load()} tintColor="#67e8f9" />}>
      <View style={styles.header}><View><Text style={styles.eyebrow}>STAGE 3 · MOBILE CAMERA</Text><Text style={styles.title}>Repair orders</Text><Text style={styles.subtitle}>{organization?.name ?? "Loading workspace…"}</Text></View><TouchableOpacity onPress={() => void supabase.auth.signOut()}><Text style={styles.signOut}>SIGN OUT</Text></TouchableOpacity></View>
      <View style={styles.notice}><Text style={styles.noticeTitle}>PRIVATE EVIDENCE WORKFLOW</Text><Text style={styles.noticeBody}>Choose the repair order before capturing. Files are compressed locally, queued safely, and uploaded only to its organization-scoped record.</Text></View>
      {loading && !repairOrders.length ? <ActivityIndicator style={styles.loader} color="#67e8f9" size="large" /> : null}
      {!loading && !repairOrders.length ? <Text style={styles.empty}>No open repair orders.</Text> : null}
      {repairOrders.map((repairOrder) => {
        const vehicle = repairOrder.vehicle;
        const vehicleLabel = [vehicle?.year, vehicle?.make, vehicle?.model].filter(Boolean).join(" ") || "Vehicle details pending";
        return <TouchableOpacity key={repairOrder.id} style={styles.card} onPress={() => onSelectRepairOrder(repairOrder)}><View style={styles.cardTop}><Text style={styles.ro}>RO #{repairOrder.ro_number}</Text><Text style={styles.chevron}>›</Text></View><Text style={styles.vehicle}>{vehicleLabel}</Text><View style={styles.cardBottom}><Text style={styles.status}>{repairOrder.workflow_status.replaceAll("_", " ")}</Text><Text style={styles.updated}>Updated {new Date(repairOrder.updated_at).toLocaleDateString("en-CA")}</Text></View></TouchableOpacity>;
      })}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  page: { padding: 22, paddingTop: 30, paddingBottom: 48 }, header: { flexDirection: "row", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 22 },
  eyebrow: { color: "#67e8f9", fontSize: 10, fontWeight: "900", letterSpacing: 1.3 }, title: { color: "#f8fafc", fontSize: 32, fontWeight: "900", marginTop: 6 }, subtitle: { color: "#64748b", fontSize: 13, marginTop: 4 }, signOut: { color: "#94a3b8", fontSize: 11, fontWeight: "800", marginTop: 4 },
  notice: { borderLeftWidth: 3, borderLeftColor: "#67e8f9", backgroundColor: "rgba(103,232,249,.06)", padding: 15, borderRadius: 5, marginBottom: 16 }, noticeTitle: { color: "#a5f3fc", fontSize: 10, fontWeight: "900", letterSpacing: 1 }, noticeBody: { color: "#94a3b8", fontSize: 13, lineHeight: 19, marginTop: 5 },
  loader: { marginTop: 50 }, empty: { color: "#64748b", textAlign: "center", marginTop: 50 }, card: { backgroundColor: "#0d1925", borderWidth: 1, borderColor: "rgba(255,255,255,.08)", borderRadius: 16, padding: 18, marginBottom: 12 },
  cardTop: { flexDirection: "row", alignItems: "center", justifyContent: "space-between" }, ro: { color: "#f8fafc", fontSize: 20, fontWeight: "900" }, chevron: { color: "#67e8f9", fontSize: 30, lineHeight: 30 }, vehicle: { color: "#cbd5e1", fontSize: 15, marginTop: 6 }, cardBottom: { flexDirection: "row", justifyContent: "space-between", marginTop: 16 }, status: { color: "#a5f3fc", fontSize: 10, fontWeight: "800", textTransform: "uppercase", letterSpacing: .8 }, updated: { color: "#526071", fontSize: 10 },
});
