// POST { action: "scan", image, entitlement? }            -> { items, remaining }
// POST { action: "ask", question, log, entitlement? }       -> { answer, remaining }
// Errors: { error: code, message } with 400 invalid | 401 unauthorized | 403 pro_required |
//         413 too_large | 422 off_topic / crisis / no_food | 429 quota / slow_down | 503 busy | 502 error
//
// The only place the Claude API key exists. Order of checks, cheapest first, so an abusive request costs nothing:
//   size -> method -> signed-in user -> schema -> content rules -> plan (verified with Apple) -> every rate limit
//   (one transaction) -> Claude, with a capped answer in a fixed shape -> cleaned reply.

import Anthropic from "npm:@anthropic-ai/sdk@1.3.0";
import { zodOutputFormat } from "npm:@anthropic-ai/sdk@1.3.0/helpers/zod";
import { admin, requireUser } from "../_shared/supabase.ts";
import { verifyPro } from "../_shared/apple_entitlement.ts";
import {
  AIRequest, ASK_SYSTEM, AskReply, buckets, checkQuestion, cleanAnswer, cleanLog, cleanScan, dailyLimit,
  decodeJpeg, type Kind, MAX_BODY_BYTES, MODEL, type Plan, REFUSALS, SCAN_SYSTEM, ScanReply,
} from "../_shared/ai_rules.ts";

const claude = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY"), maxRetries: 1, timeout: 25_000 });

// A native app calls this, not a browser: no CORS headers, so no website can call it with someone's session.
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const fail = (status: number, error: string, message: string, extra: Record<string, unknown> = {}) =>
  json({ error, message, ...extra }, status);

async function ipHash(req: Request): Promise<string> {
  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || "unknown";
  const salt = Deno.env.get("AI_IP_SALT") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${salt}:${ip}`));
  return Array.from(new Uint8Array(digest).slice(0, 12), (b) => b.toString(16).padStart(2, "0")).join("");
}

async function log(userId: string, kind: Kind, plan: Plan, outcome: string, usage?: Anthropic.Usage) {
  await admin.from("ai_log").insert({
    user_id: userId, kind, plan, outcome,
    input_tokens: usage?.input_tokens ?? 0, output_tokens: usage?.output_tokens ?? 0,
  });
  if (Math.random() < 0.01) await admin.rpc("ai_prune");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return fail(405, "invalid", "POST only.");
  if (!Deno.env.get("ANTHROPIC_API_KEY")) return fail(503, "busy", "AI isn't set up yet.");

  // Size before reading: a huge body is refused without being buffered.
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_BYTES) return fail(413, "too_large", "That photo is too large.");
  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) return fail(413, "too_large", "That photo is too large.");

  const user = await requireUser(req);
  if (!user) return fail(401, "unauthorized", "Sign in to use this.");

  let body: AIRequest;
  try {
    const parsed = AIRequest.safeParse(JSON.parse(raw));
    if (!parsed.success) return fail(400, "invalid", "That request isn't valid.");
    body = parsed.data;
  } catch {
    return fail(400, "invalid", "That request isn't valid.");
  }
  const kind: Kind = body.action;

  // Content rules before anything is counted or sent.
  let image: Uint8Array | null = null;
  let question = "";
  if (body.action === "scan") {
    image = decodeJpeg(body.image);
    if (!image) return fail(400, "invalid", "That photo couldn't be read.");
  } else {
    const check = checkQuestion(body.question);
    if (!check.ok) return fail(check.code === "invalid" ? 400 : 422, check.code, REFUSALS[check.code]);
    question = check.question;
  }

  // Plan: only Apple's signed record counts, and one subscription belongs to one account.
  let plan: Plan = "free";
  const pro = await verifyPro(body.entitlement, user.id);
  if (pro) {
    const { data: claimed } = await admin.rpc("ai_claim_entitlement", {
      p_user: user.id, p_original: pro.originalTransactionId, p_product: pro.productId,
      p_expires: pro.expiresAt.toISOString(), p_environment: pro.environment,
    });
    if (claimed === true) plan = "pro";
  }
  if (dailyLimit(kind, plan) === 0) {
    await log(user.id, kind, plan, "pro_required");
    return fail(403, "pro_required", "Ask is part of Vitalis Pro.");
  }

  // Every limit at once, atomically.
  const now = new Date();
  const bs = buckets(user.id, await ipHash(req), kind, plan, now);
  const take = { p_buckets: bs.map((b) => b.bucket), p_windows: bs.map((b) => b.window.toISOString()) };
  const { data: full, error: takeError } = await admin.rpc("ai_take", { ...take, p_limits: bs.map((b) => b.limit) });
  if (takeError) return fail(503, "busy", "Try again in a moment.");
  if (full !== 0) {
    const hit = bs[(full as number) - 1];
    await log(user.id, kind, plan, hit.reason);
    const message = hit.reason === "busy" ? "AI is busy right now. Try again later."
      : hit.reason === "slow_down" ? "Slow down a little and try again in a minute."
      : kind === "scan" && plan === "free" ? "You've used today's 4 free photo scans. Get Vitalis Pro for more, or log by barcode or search."
      : "You've reached today's limit. It resets at midnight UTC.";
    return fail(hit.reason === "busy" ? 503 : 429, hit.reason, message);
  }
  const userBucket = bs[2];
  const used = (await admin.rpc("ai_used_today", { p_bucket: userBucket.bucket, p_day: userBucket.window.toISOString() })).data ?? 0;
  const remaining = Math.max(0, userBucket.limit - (used as number));

  try {
    if (body.action === "scan") {
      const response = await claude.messages.parse({
        model: MODEL,
        max_tokens: 1500,
        output_config: { effort: "low", format: zodOutputFormat(ScanReply) },
        system: SCAN_SYSTEM,
        messages: [{
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: "image/jpeg", data: body.image } },
            { type: "text", text: "List the foods in this photo." },
          ],
        }],
      });
      if (response.stop_reason === "refusal" || !response.parsed_output) {
        await log(user.id, kind, plan, "refused", response.usage);
        return fail(422, "no_food", "No food recognised. Try again with the plate centred.");
      }
      const items = cleanScan(response.parsed_output);
      await log(user.id, kind, plan, items.length ? "ok" : "no_food", response.usage);
      if (!items.length) return fail(422, "no_food", "No food recognised. Try again with the plate centred.");
      return json({ items, remaining, plan });
    } else {
      const response = await claude.messages.parse({
        model: MODEL,
        max_tokens: 600,
        output_config: { effort: "low", format: zodOutputFormat(AskReply) },
        system: ASK_SYSTEM,
        messages: [{
          role: "user",
          content: `<food_log>\n${cleanLog(body.log)}\n</food_log>\n\nQuestion: ${question}`,
        }],
      });
      const reply = response.parsed_output;
      if (response.stop_reason === "refusal" || !reply || !reply.on_topic || !cleanAnswer(reply.answer)) {
        await log(user.id, kind, plan, "off_topic", response.usage);
        return fail(422, "off_topic", REFUSALS.off_topic, { remaining });
      }
      await log(user.id, kind, plan, "ok", response.usage);
      return json({ answer: cleanAnswer(reply.answer), remaining, plan });
    }
  } catch (error) {
    // The model call failed: give the units back so an outage doesn't cost anyone their quota.
    await admin.rpc("ai_give_back", take);
    await log(user.id, kind, plan, "error");
    if (error instanceof Anthropic.RateLimitError) return fail(503, "busy", "AI is busy right now. Try again shortly.");
    console.error("ai", error instanceof Anthropic.APIError ? `${error.status} ${error.message}` : error);
    return fail(502, "error", "That didn't work. Try again.");
  }
});
