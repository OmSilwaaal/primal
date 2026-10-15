-- One row per user. Written only by edge functions (service role); users can read their own row.
create table if not exists public.subscriptions (
  user_id                uuid primary key references auth.users (id) on delete cascade,
  stripe_customer_id     text unique,
  stripe_subscription_id text unique,
  status                 text not null default 'none',   -- Stripe status: active, trialing, past_due, canceled, ...
  plan                   text,                           -- 'monthly' | 'annual'
  current_period_end     timestamptz,
  cancel_at_period_end   boolean not null default false,
  updated_at             timestamptz not null default now()
);

alter table public.subscriptions enable row level security;

create policy "Users read own subscription"
  on public.subscriptions for select
  using (auth.uid() = user_id);
-- No insert/update/delete policies: clients cannot grant themselves access.
