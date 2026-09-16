import "react-native-url-polyfill/auto";
import "expo-sqlite/localStorage/install";

import { createClient } from "@supabase/supabase-js";

const url = process.env.EXPO_PUBLIC_SUPABASE_URL ?? "";
const publishableKey = process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "";
export const isMobileConfigured = Boolean(url && publishableKey);

export const supabase = createClient(url || "https://configuration.invalid", publishableKey || "missing", {
  auth: { storage: localStorage, autoRefreshToken: true, persistSession: true, detectSessionInUrl: false },
});
