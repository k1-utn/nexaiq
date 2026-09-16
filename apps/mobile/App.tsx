import type { Session } from "@supabase/supabase-js";
import { StatusBar } from "expo-status-bar";
import { useEffect, useState } from "react";
import { ActivityIndicator, SafeAreaView, StyleSheet, Text, View } from "react-native";

import { LoginScreen } from "./src/components/LoginScreen";
import { RepairOrderList } from "./src/components/RepairOrderList";
import { ScanCaptureScreen } from "./src/components/ScanCaptureScreen";
import { isMobileConfigured, supabase } from "./src/lib/supabase";
import type { OrganizationContext, RepairOrder } from "./src/types";

export default function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [loadingSession, setLoadingSession] = useState(true);
  const [organization, setOrganization] = useState<OrganizationContext | null>(null);
  const [selectedRepairOrder, setSelectedRepairOrder] = useState<RepairOrder | null>(null);

  useEffect(() => {
    if (!isMobileConfigured) {
      setLoadingSession(false);
      return;
    }
    void supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setLoadingSession(false);
    });
    const { data } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession);
      if (!nextSession) {
        setOrganization(null);
        setSelectedRepairOrder(null);
      }
    });
    return () => data.subscription.unsubscribe();
  }, []);

  if (!isMobileConfigured) {
    return <Shell><View style={styles.centered}><Text style={styles.title}>Mobile setup required</Text><Text style={styles.body}>Add EXPO_PUBLIC_SUPABASE_URL, EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY, and EXPO_PUBLIC_API_URL to apps/mobile/.env.local, then restart Expo.</Text></View></Shell>;
  }
  if (loadingSession) {
    return <Shell><View style={styles.centered}><ActivityIndicator color="#67e8f9" size="large" /></View></Shell>;
  }
  if (!session) return <Shell><LoginScreen /></Shell>;
  if (selectedRepairOrder && organization) {
    return <Shell><ScanCaptureScreen repairOrder={selectedRepairOrder} organization={organization} session={session} onBack={() => setSelectedRepairOrder(null)} /></Shell>;
  }
  return <Shell><RepairOrderList onOrganizationLoaded={setOrganization} onSelectRepairOrder={setSelectedRepairOrder} /></Shell>;
}

function Shell({ children }: { children: React.ReactNode }) {
  return <SafeAreaView style={styles.safe}><StatusBar style="light" />{children}</SafeAreaView>;
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: "#071018" },
  centered: { flex: 1, alignItems: "center", justifyContent: "center", padding: 28 },
  title: { color: "#f8fafc", fontSize: 24, fontWeight: "900", textAlign: "center" },
  body: { color: "#94a3b8", fontSize: 15, lineHeight: 23, marginTop: 12, textAlign: "center" },
});
