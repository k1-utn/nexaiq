import { StatusBar } from "expo-status-bar";
import { SafeAreaView, ScrollView, StyleSheet, Text, TouchableOpacity, View } from "react-native";

const secondaryActions = ["VIEW ESTIMATE", "VIEW FINDINGS", "REPAIR WORKFLOW", "EVIDENCE"];

export default function App() {
  return (
    <SafeAreaView style={styles.safe}>
      <StatusBar style="light" />
      <ScrollView contentContainerStyle={styles.page}>
        <View style={styles.brandRow}><View style={styles.mark}><Text style={styles.markText}>N</Text></View><Text style={styles.brand}>nexa<Text style={styles.accent}>IQ</Text></Text><View style={styles.beta}><Text style={styles.betaText}>BETA</Text></View></View>
        <View style={styles.eyebrowRow}><Text style={styles.eyebrow}>ACTIVE REPAIR ORDER</Text><Text style={styles.synced}>● Synced 10:42 AM</Text></View>
        <Text style={styles.ro}>RO #18472</Text>
        <Text style={styles.vehicle}>2025 Toyota RAV4</Text>

        <View style={styles.summary}>
          <View><Text style={styles.label}>CURRENT ESTIMATE</Text><Text style={styles.value}>Supplement 1</Text></View>
          <View style={styles.divider} />
          <View><Text style={styles.label}>WORKFLOW</Text><Text style={styles.value}>96% documented</Text></View>
        </View>

        <TouchableOpacity accessibilityRole="button" style={styles.primary}><Text style={styles.primaryIcon}>⌗</Text><View><Text style={styles.primaryText}>SCAN FOR SUPPLEMENT</Text><Text style={styles.primarySub}>Capture teardown evidence</Text></View></TouchableOpacity>

        <View style={styles.grid}>{secondaryActions.map((action) => <TouchableOpacity accessibilityRole="button" key={action} style={styles.secondary}><Text style={styles.secondaryIcon}>{action === "VIEW ESTIMATE" ? "≡" : action === "VIEW FINDINGS" ? "◎" : action === "REPAIR WORKFLOW" ? "✓" : "▧"}</Text><Text style={styles.secondaryText}>{action}</Text></TouchableOpacity>)}</View>

        <View style={styles.notice}><Text style={styles.noticeTitle}>HUMAN REVIEW REQUIRED</Text><Text style={styles.noticeBody}>AI output remains a candidate until confirmed by a qualified repair professional.</Text></View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: "#071018" }, page: { padding: 22, paddingTop: 30 },
  brandRow: { flexDirection: "row", alignItems: "center", marginBottom: 42 }, mark: { width: 38, height: 38, borderRadius: 11, backgroundColor: "rgba(103,232,249,.12)", borderWidth: 1, borderColor: "rgba(103,232,249,.25)", alignItems: "center", justifyContent: "center" }, markText: { color: "#67e8f9", fontWeight: "900" }, brand: { color: "#f2f7fa", fontSize: 24, fontWeight: "900", marginLeft: 10 }, accent: { color: "#67e8f9" }, beta: { marginLeft: "auto", backgroundColor: "rgba(103,232,249,.1)", paddingHorizontal: 9, paddingVertical: 5, borderRadius: 99 }, betaText: { color: "#a5f3fc", fontSize: 11, fontWeight: "800", letterSpacing: 1 },
  eyebrowRow: { flexDirection: "row", justifyContent: "space-between", marginBottom: 10 }, eyebrow: { color: "#67e8f9", fontSize: 11, fontWeight: "800", letterSpacing: 1.4 }, synced: { color: "#64748b", fontSize: 11 }, ro: { color: "#f8fafc", fontSize: 34, lineHeight: 40, fontWeight: "900" }, vehicle: { color: "#94a3b8", fontSize: 18, marginTop: 3, marginBottom: 26 },
  summary: { flexDirection: "row", backgroundColor: "#0d1925", borderWidth: 1, borderColor: "rgba(255,255,255,.08)", borderRadius: 16, padding: 18, marginBottom: 18 }, divider: { width: 1, backgroundColor: "rgba(255,255,255,.08)", marginHorizontal: 18 }, label: { color: "#64748b", fontSize: 10, letterSpacing: 1.2, fontWeight: "800", marginBottom: 7 }, value: { color: "#e2e8f0", fontSize: 15, fontWeight: "700" },
  primary: { minHeight: 92, backgroundColor: "#67e8f9", borderRadius: 17, padding: 20, flexDirection: "row", alignItems: "center", marginBottom: 12 }, primaryIcon: { color: "#071018", fontSize: 34, fontWeight: "300", marginRight: 15 }, primaryText: { color: "#071018", fontSize: 17, fontWeight: "900", letterSpacing: .4 }, primarySub: { color: "#164e63", fontSize: 13, marginTop: 4 },
  grid: { flexDirection: "row", flexWrap: "wrap", gap: 10 }, secondary: { width: "48.5%", minHeight: 105, backgroundColor: "#0d1925", borderWidth: 1, borderColor: "rgba(255,255,255,.08)", borderRadius: 15, padding: 16, justifyContent: "space-between" }, secondaryIcon: { color: "#67e8f9", fontSize: 23 }, secondaryText: { color: "#cbd5e1", fontSize: 12, fontWeight: "800", lineHeight: 17 },
  notice: { borderLeftWidth: 3, borderLeftColor: "#fbbf24", backgroundColor: "rgba(251,191,36,.06)", padding: 15, marginTop: 18, borderRadius: 4 }, noticeTitle: { color: "#fde68a", fontSize: 11, fontWeight: "900", letterSpacing: 1 }, noticeBody: { color: "#94a3b8", fontSize: 13, lineHeight: 19, marginTop: 5 },
});
