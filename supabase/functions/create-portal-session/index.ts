// POST {} -> { url }  (Stripe billing portal: update card, cancel, view invoices)
import { cors, json, requireUser, stripe, admin } from "../_shared/stripe.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const user = await requireUser(req);
  if (!user) return json({ error: "Unauthorized" }, 401);

  const { data: row } = await admin
    .from("subscriptions").select("stripe_customer_id").eq("user_id", user.id).maybeSingle();
  if (!row?.stripe_customer_id) return json({ error: "No subscription found" }, 404);

  try {
    const session = await stripe.billingPortal.sessions.create({
      customer: row.stripe_customer_id,
      return_url: "com.omsilwal.NutriCorePrimal://billing-return",
    });
    return json({ url: session.url });
  } catch (e) {
    console.error(e);
    return json({ error: "Could not open billing portal" }, 500);
  }
});
