// POST { plan: "monthly" | "annual" }
// -> { clientSecret, customerId, ephemeralKey, publishableKey }
import { cors, customerFor, json, PRICES, requireUser, stripe } from "../_shared/stripe.ts";
import { admin } from "../_shared/stripe.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const user = await requireUser(req);
  if (!user) return json({ error: "Unauthorized" }, 401);

  const { plan } = await req.json().catch(() => ({}));
  const price = PRICES[plan];
  if (!price) return json({ error: "Unknown plan" }, 400);

  try {
    // Don't create a second subscription for someone who already has one.
    const { data: existing } = await admin
      .from("subscriptions").select("status").eq("user_id", user.id).maybeSingle();
    if (existing && ["active", "trialing"].includes(existing.status)) {
      return json({ error: "Already subscribed" }, 409);
    }

    const customerId = await customerFor(user);

    // Version must match the one stripe-ios uses, or PaymentSheet rejects the key.
    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion: "2020-08-27" },
    );

    const subscription = await stripe.subscriptions.create({
      customer: customerId,
      items: [{ price }],
      payment_behavior: "default_incomplete",
      payment_settings: { save_default_payment_method: "on_subscription" },
      expand: ["latest_invoice.confirmation_secret", "latest_invoice.payment_intent"],
      metadata: { user_id: user.id, plan },
    });

    // Newer API versions expose confirmation_secret; older ones payment_intent.
    const invoice = subscription.latest_invoice as any;
    const clientSecret = invoice?.confirmation_secret?.client_secret ??
      invoice?.payment_intent?.client_secret;
    if (!clientSecret) return json({ error: "No payment required or missing client secret" }, 500);

    return json({
      clientSecret,
      customerId,
      ephemeralKey: ephemeralKey.secret,
      publishableKey: Deno.env.get("STRIPE_PUBLISHABLE_KEY"),
    });
  } catch (e) {
    console.error(e);
    return json({ error: "Could not start checkout" }, 500);
  }
});
