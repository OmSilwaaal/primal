// POST {} -> { ok: true }. Cancels billing and permanently deletes the caller's account and data.
// Required by App Store guideline 5.1.1(v) for apps that let people create accounts.
import { admin, cors, json, requireUser, stripe } from "../_shared/stripe.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const user = await requireUser(req);
  if (!user) return json({ error: "Unauthorized" }, 401);

  try {
    // Stop billing first so a deleted user is never charged again.
    const { data: row } = await admin
      .from("subscriptions").select("stripe_customer_id").eq("user_id", user.id).maybeSingle();
    if (row?.stripe_customer_id) {
      const subs = await stripe.subscriptions.list({ customer: row.stripe_customer_id, status: "all" });
      for (const s of subs.data) {
        if (s.status !== "canceled") await stripe.subscriptions.cancel(s.id);
      }
      await stripe.customers.del(row.stripe_customer_id);
    }

    // Avatar files live in storage, not in a table with a cascade.
    const { data: files } = await admin.storage.from("avatars").list(user.id);
    if (files?.length) {
      await admin.storage.from("avatars").remove(files.map((f) => `${user.id}/${f.name}`));
    }

    // Cascades to public_profiles, friendships, shared_meals and subscriptions.
    const { error } = await admin.auth.admin.deleteUser(user.id);
    if (error) throw error;
    return json({ ok: true });
  } catch (e) {
    console.error(e);
    return json({ error: "Could not delete account" }, 500);
  }
});
