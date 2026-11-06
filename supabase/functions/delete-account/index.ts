// POST {} -> { ok: true }. Permanently deletes the caller's account and data.
// Required by App Store guideline 5.1.1(v) for apps that let people create accounts.
// Subscriptions are App Store purchases tied to the Apple ID; the user cancels them in Apple ID settings.
import { admin, cors, json, requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const user = await requireUser(req);
  if (!user) return json({ error: "Unauthorized" }, 401);

  try {
    // Avatar files live in storage, not in a table with a cascade.
    const { data: files } = await admin.storage.from("avatars").list(user.id);
    if (files?.length) {
      await admin.storage.from("avatars").remove(files.map((f) => `${user.id}/${f.name}`));
    }

    // AI usage counts and logs aren't keyed to auth.users, so remove them explicitly.
    await admin.from("ai_log").delete().eq("user_id", user.id);
    await admin.from("ai_usage").delete().or(`bucket.like.user:${user.id}:%,bucket.eq.minute:${user.id}`);

    // Cascades to public_profiles, friendships, shared_meals and ai_entitlements.
    const { error } = await admin.auth.admin.deleteUser(user.id);
    if (error) throw error;
    return json({ ok: true });
  } catch (e) {
    console.error(e);
    return json({ error: "Could not delete account" }, 500);
  }
});
