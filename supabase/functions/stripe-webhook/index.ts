// Stripe -> Supabase. Deploy with --no-verify-jwt; authenticity comes from the Stripe signature.
import { admin, stripe } from "../_shared/stripe.ts";

const PLAN_BY_PRICE: Record<string, string> = {
  [Deno.env.get("STRIPE_PRICE_MONTHLY") ?? "_"]: "monthly",
  [Deno.env.get("STRIPE_PRICE_ANNUAL") ?? "_"]: "annual",
};

Deno.serve(async (req) => {
  const signature = req.headers.get("stripe-signature");
  if (!signature) return new Response("Missing signature", { status: 400 });

  let event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      await req.text(),
      signature,
      Deno.env.get("STRIPE_WEBHOOK_SECRET")!,
    );
  } catch {
    return new Response("Invalid signature", { status: 400 });
  }

  if (event.type.startsWith("customer.subscription.")) {
    const sub = event.data.object as any;
    const item = sub.items?.data?.[0];
    // current_period_end moved onto the subscription item in newer API versions.
    const periodEnd = item?.current_period_end ?? sub.current_period_end;

    // Prefer metadata; fall back to the customer link we stored at checkout.
    let userId = sub.metadata?.user_id as string | undefined;
    if (!userId) {
      const { data } = await admin.from("subscriptions")
        .select("user_id").eq("stripe_customer_id", sub.customer).maybeSingle();
      userId = data?.user_id;
    }
    if (!userId) return new Response("No matching user", { status: 200 }); // don't make Stripe retry forever

    const { error } = await admin.from("subscriptions").upsert({
      user_id: userId,
      stripe_customer_id: sub.customer,
      stripe_subscription_id: sub.id,
      status: sub.status,
      plan: sub.metadata?.plan ?? PLAN_BY_PRICE[item?.price?.id] ?? null,
      current_period_end: periodEnd ? new Date(periodEnd * 1000).toISOString() : null,
      cancel_at_period_end: sub.cancel_at_period_end ?? false,
      updated_at: new Date().toISOString(),
    });
    if (error) {
      console.error(error);
      return new Response("DB error", { status: 500 }); // let Stripe retry
    }
  }

  return new Response("ok", { status: 200 });
});
