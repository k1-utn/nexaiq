"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { loginCredentialsSchema } from "@nexaiq/shared";

function credentials(formData: FormData) {
  return loginCredentialsSchema.safeParse({
    email: String(formData.get("email") ?? ""),
    password: String(formData.get("password") ?? ""),
  });
}

export async function login(formData: FormData) {
  const parsed = credentials(formData);
  if (!parsed.success) redirect("/login?error=invalid_credentials");
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  if (error) redirect("/login?error=invalid_credentials");
  redirect("/");
}
