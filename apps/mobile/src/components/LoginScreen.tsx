import { useState } from "react";
import { ActivityIndicator, Alert, KeyboardAvoidingView, Platform, StyleSheet, Text, TextInput, TouchableOpacity, View } from "react-native";

import { supabase } from "../lib/supabase";

export function LoginScreen() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);

  async function signIn() {
    const normalizedPassword = password.trim();
    if (!email.trim() || !normalizedPassword) return;
    setLoading(true);
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password: normalizedPassword });
    setLoading(false);
    if (error) Alert.alert("Sign-in failed", error.message);
  }

  return (
    <KeyboardAvoidingView style={styles.page} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <View style={styles.brandRow}><View style={styles.mark}><Text style={styles.markText}>N</Text></View><Text style={styles.brand}>nexa<Text style={styles.accent}>IQ</Text></Text></View>
      <Text style={styles.eyebrow}>MOBILE EVIDENCE CAPTURE</Text>
      <Text style={styles.title}>Sign in to your workspace</Text>
      <Text style={styles.body}>Your repair photos and voice notes stay organization-scoped and private.</Text>
      <TextInput style={styles.input} value={email} onChangeText={setEmail} autoCapitalize="none" keyboardType="email-address" placeholder="Email" placeholderTextColor="#526071" />
      <View style={styles.passwordRow}>
        <TextInput
          style={styles.passwordInput}
          value={password}
          onChangeText={setPassword}
          secureTextEntry={!showPassword}
          autoCapitalize="none"
          autoCorrect={false}
          spellCheck={false}
          autoComplete="password"
          textContentType="password"
          placeholder="Password"
          placeholderTextColor="#526071"
          onSubmitEditing={() => void signIn()}
        />
        <TouchableOpacity onPress={() => setShowPassword((visible) => !visible)} style={styles.passwordToggle} accessibilityRole="button" accessibilityLabel={showPassword ? "Hide password" : "Show password"}>
          <Text style={styles.passwordToggleText}>{showPassword ? "HIDE" : "SHOW"}</Text>
        </TouchableOpacity>
      </View>
      <TouchableOpacity disabled={loading || !email.trim() || !password} onPress={() => void signIn()} style={[styles.button, (loading || !email.trim() || !password) && styles.buttonDisabled]}>
        {loading ? <ActivityIndicator color="#071018" /> : <Text style={styles.buttonText}>SIGN IN</Text>}
      </TouchableOpacity>
      <Text style={styles.notice}>Accounts are provisioned by an administrator. Captured evidence is never treated as an automatic repair decision.</Text>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  page: { flex: 1, justifyContent: "center", padding: 24 },
  brandRow: { flexDirection: "row", alignItems: "center", marginBottom: 42 },
  mark: { width: 42, height: 42, borderRadius: 12, backgroundColor: "rgba(103,232,249,.12)", borderWidth: 1, borderColor: "rgba(103,232,249,.25)", alignItems: "center", justifyContent: "center" },
  markText: { color: "#67e8f9", fontWeight: "900" }, brand: { color: "#f2f7fa", fontSize: 25, fontWeight: "900", marginLeft: 10 }, accent: { color: "#67e8f9" },
  eyebrow: { color: "#67e8f9", fontSize: 11, fontWeight: "900", letterSpacing: 1.4 }, title: { color: "#f8fafc", fontSize: 29, lineHeight: 35, fontWeight: "900", marginTop: 10 },
  body: { color: "#94a3b8", fontSize: 14, lineHeight: 21, marginTop: 9, marginBottom: 24 }, input: { color: "#f8fafc", backgroundColor: "#0d1925", borderWidth: 1, borderColor: "rgba(255,255,255,.1)", borderRadius: 13, paddingHorizontal: 16, minHeight: 54, marginBottom: 12, fontSize: 16 },
  passwordRow: { flexDirection: "row", alignItems: "center", backgroundColor: "#0d1925", borderWidth: 1, borderColor: "rgba(255,255,255,.1)", borderRadius: 13, minHeight: 54, marginBottom: 12 },
  passwordInput: { flex: 1, color: "#f8fafc", paddingHorizontal: 16, minHeight: 52, fontSize: 16 },
  passwordToggle: { alignSelf: "stretch", justifyContent: "center", paddingHorizontal: 16 }, passwordToggleText: { color: "#67e8f9", fontSize: 11, fontWeight: "900", letterSpacing: .7 },
  button: { minHeight: 56, borderRadius: 13, backgroundColor: "#67e8f9", alignItems: "center", justifyContent: "center", marginTop: 4 }, buttonDisabled: { opacity: .45 }, buttonText: { color: "#071018", fontWeight: "900", letterSpacing: .8 },
  notice: { color: "#64748b", fontSize: 12, lineHeight: 18, marginTop: 22, textAlign: "center" },
});
