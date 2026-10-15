import Stripe from "npm:stripe@18.0.0";
import { createClient } from "npm:@supabase/supabase-js@2";

export const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!);

/** Service-role client: bypasses RLS. Never expose to the app. */
export const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

export const PRICES: Record<string, string> = {
  monthly: Deno.env.get("STRIPE_PRICE_MONTHLY")!,
  annual: Deno.env.get("STRIPE_PRICE_ANNUAL")!,
};

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

/** Resolves the calling user from the request's Supabase JWT. */
export async function requireUser(req: Request) {
  const token = req.headers.get("Authorization")?.replace("Bearer ", "");
  if (!token) return null;
  const { data, error } = await admin.auth.getUser(token);
  return error ? null : data.user;
}

/** Returns the user's Stripe customer id, creating the customer on first use. */
export async function customerFor(user: { id: string; email?: string }) {
  const { data: row } = await admin
    .from("subscriptions")
    .select("stripe_customer_id")
    .eq("user_id", user.id)
    .maybeSingle();
  if (row?.stripe_customer_id) return row.stripe_customer_id as string;

  const customer = await stripe.customers.create({
    email: user.email,
    metadata: { user_id: user.id },
  });
  await admin.from("subscriptions").upsert({
    user_id: user.id,
    stripe_customer_id: customer.id,
  });
  return customer.id;
}
