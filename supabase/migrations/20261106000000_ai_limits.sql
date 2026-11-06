-- AI usage limits, verified Pro entitlements, and a usage log for the `ai` Edge Function.
-- Row-level security is on with NO policies: only the service role (inside the Edge Function) can read or write.
-- The app can never see or change its own counters.

-- ── Counters ─────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.ai_usage (
  bucket       text        not null,   -- 'global' | 'ip:<hash>' | 'user:<uuid>:<kind>' | 'minute:<uuid>'
  window_start timestamptz not null,   -- the UTC day, or the minute, the count belongs to
  count        integer     not null default 0,
  primary key (bucket, window_start)
);
alter table public.ai_usage enable row level security;

-- Takes one unit from every bucket, or from none: returns 0 when all were under their limit (and counts them),
-- else the 1-based index of the first bucket that is full (and counts nothing). One transaction, rows locked in
-- the caller's fixed order, so concurrent requests can't both slip past a limit.
create or replace function public.ai_take(p_buckets text[], p_windows timestamptz[], p_limits integer[])
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  i integer;
  c integer;
begin
  if array_length(p_buckets, 1) is distinct from array_length(p_windows, 1)
     or array_length(p_buckets, 1) is distinct from array_length(p_limits, 1) then
    raise exception 'ai_take: mismatched arrays';
  end if;
  for i in 1 .. array_length(p_buckets, 1) loop
    insert into ai_usage (bucket, window_start, count) values (p_buckets[i], p_windows[i], 0)
      on conflict (bucket, window_start) do nothing;
    select count into c from ai_usage where bucket = p_buckets[i] and window_start = p_windows[i] for update;
    if c >= p_limits[i] then
      return i;
    end if;
  end loop;
  for i in 1 .. array_length(p_buckets, 1) loop
    update ai_usage set count = count + 1 where bucket = p_buckets[i] and window_start = p_windows[i];
  end loop;
  return 0;
end;
$$;

-- Gives the units back when the model call itself failed (so an outage doesn't eat anyone's quota).
create or replace function public.ai_give_back(p_buckets text[], p_windows timestamptz[])
returns void
language sql
security definer
set search_path = public
as $$
  update ai_usage u set count = greatest(u.count - 1, 0)
  from unnest(p_buckets, p_windows) as b(bucket, window_start)
  where u.bucket = b.bucket and u.window_start = b.window_start;
$$;

-- How many of a user's daily units are left (for the app's "3 of 4 free scans left" line).
create or replace function public.ai_used_today(p_bucket text, p_day timestamptz)
returns integer
language sql
security definer
set search_path = public
as $$
  select coalesce((select count from ai_usage where bucket = p_bucket and window_start = p_day), 0);
$$;

-- ── Verified Pro entitlements ────────────────────────────────────────────────────────────────────────────
-- One App Store subscription (original_transaction_id) unlocks one account: the first one to present it.
create table if not exists public.ai_entitlements (
  original_transaction_id text primary key,
  user_id     uuid        not null references auth.users (id) on delete cascade,
  product_id  text        not null,
  expires_at  timestamptz not null,
  environment text        not null,
  updated_at  timestamptz not null default now()
);
create index if not exists ai_entitlements_user on public.ai_entitlements (user_id);
alter table public.ai_entitlements enable row level security;

-- Records a verified entitlement for a user. False when that subscription already belongs to another account.
create or replace function public.ai_claim_entitlement(
  p_user uuid, p_original text, p_product text, p_expires timestamptz, p_environment text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid;
begin
  insert into ai_entitlements (original_transaction_id, user_id, product_id, expires_at, environment)
  values (p_original, p_user, p_product, p_expires, p_environment)
  on conflict (original_transaction_id) do nothing;
  select user_id into owner from ai_entitlements where original_transaction_id = p_original for update;
  if owner <> p_user then
    return false;
  end if;
  update ai_entitlements set product_id = p_product, expires_at = greatest(expires_at, p_expires),
    environment = p_environment, updated_at = now()
  where original_transaction_id = p_original;
  return true;
end;
$$;

-- ── Log ──────────────────────────────────────────────────────────────────────────────────────────────────
-- What each call cost and how it ended; no photos, questions or answers are stored.
create table if not exists public.ai_log (
  id            bigint generated always as identity primary key,
  user_id       uuid        not null,
  kind          text        not null,
  plan          text        not null,
  outcome       text        not null,   -- ok | quota | busy | slow_down | pro_required | off_topic | refused | error
  input_tokens  integer     not null default 0,
  output_tokens integer     not null default 0,
  created_at    timestamptz not null default now()
);
create index if not exists ai_log_created on public.ai_log (created_at);
alter table public.ai_log enable row level security;

-- Keeps the tables small: counters older than three days and logs older than 90.
create or replace function public.ai_prune()
returns void
language sql
security definer
set search_path = public
as $$
  delete from ai_usage where window_start < now() - interval '3 days';
  delete from ai_log where created_at < now() - interval '90 days';
$$;

-- Only the service role may call these.
revoke all on function public.ai_take(text[], timestamptz[], integer[]) from public, anon, authenticated;
revoke all on function public.ai_give_back(text[], timestamptz[]) from public, anon, authenticated;
revoke all on function public.ai_used_today(text, timestamptz) from public, anon, authenticated;
revoke all on function public.ai_claim_entitlement(uuid, text, text, timestamptz, text) from public, anon, authenticated;
revoke all on function public.ai_prune() from public, anon, authenticated;
