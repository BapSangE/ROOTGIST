"use server";
import { redirect } from "next/navigation";
import { resolveEnvironment } from "./environment";
import { sessionClient } from "@/lib/supabase/server";
export async function login(form: FormData) {
  const environment = resolveEnvironment(process.env);
  if (environment.mode !== "supabase") redirect("/admin");
  const client = await sessionClient(environment);
  const email = String(form.get("email") ?? "").trim();
  const password = String(form.get("password") ?? "");
  if (email.length > 254 || password.length > 1024 || !email || !password)
    redirect("/login?error=credentials");
  const { data, error } = await client.auth.signInWithPassword({
    email,
    password,
  });
  if (error) redirect("/login?error=credentials");
  if (data.user?.id !== environment.adminUserId) {
    await client.auth.signOut();
    redirect("/login?error=admin");
  }
  redirect("/admin");
}
export async function logout() {
  const environment = resolveEnvironment(process.env);
  if (environment.mode === "supabase")
    await (await sessionClient(environment)).auth.signOut();
  redirect("/login");
}
