-- Social: profiles, friendships, shared meals, avatars.

create table if not exists public.public_profiles (
  user_id         uuid primary key references auth.users (id) on delete cascade,
  username        text not null unique check (username ~ '^[a-z0-9_]{3,20}$'),
  display_name    text not null default '',
  bio             text not null default '' check (char_length(bio) <= 160),
  avatar_url      text,
  is_private      boolean not null default false,          -- hides details + activity from non-friends
  meal_visibility text not null default 'friends'
                  check (meal_visibility in ('everyone', 'friends', 'nobody')),
  updated_at      timestamptz not null default now()
);

create table if not exists public.friendships (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users (id) on delete cascade,
  addressee_id uuid not null references auth.users (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at   timestamptz not null default now(),
  check (requester_id <> addressee_id)
);
-- One friendship per pair, regardless of who asked first.
create unique index if not exists friendships_pair_idx
  on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

create table if not exists public.shared_meals (
  id            uuid primary key,                           -- same id as the local MealEntry
  user_id       uuid not null references auth.users (id) on delete cascade,
  food_name     text not null,
  calories      double precision not null default 0,
  protein       double precision not null default 0,
  carbohydrates double precision not null default 0,
  total_fat     double precision not null default 0,
  serving_size  double precision not null default 0,
  source        text not null default '',
  eaten_at      timestamptz not null
);
create index if not exists shared_meals_user_time_idx on public.shared_meals (user_id, eaten_at desc);

-- ── Helpers (security definer so policies don't recurse) ────────────────────
create or replace function public.are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.friendships
    where status = 'accepted'
      and ((requester_id = a and addressee_id = b) or (requester_id = b and addressee_id = a))
  );
$$;

create or replace function public.can_view_meals(owner uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select owner = auth.uid() or exists (
    select 1 from public.public_profiles p
    where p.user_id = owner
      and (
        (p.meal_visibility = 'friends' and public.are_friends(auth.uid(), owner))
        or (p.meal_visibility = 'everyone' and (not p.is_private or public.are_friends(auth.uid(), owner)))
      )
  );
$$;

-- ── Row level security ──────────────────────────────────────────────────────
alter table public.public_profiles enable row level security;
alter table public.friendships     enable row level security;
alter table public.shared_meals    enable row level security;

-- Full profile rows: yourself, friends, or anyone if the profile isn't private.
create policy "read profiles" on public.public_profiles for select
  using (user_id = auth.uid() or not is_private or public.are_friends(auth.uid(), user_id));
create policy "insert own profile" on public.public_profiles for insert
  with check (user_id = auth.uid());
create policy "update own profile" on public.public_profiles for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "read own friendships" on public.friendships for select
  using (auth.uid() in (requester_id, addressee_id));
create policy "send request" on public.friendships for insert
  with check (requester_id = auth.uid() and status = 'pending');
create policy "accept request" on public.friendships for update
  using (addressee_id = auth.uid()) with check (addressee_id = auth.uid() and status = 'accepted');
create policy "remove friendship" on public.friendships for delete
  using (auth.uid() in (requester_id, addressee_id));

create policy "read visible meals" on public.shared_meals for select
  using (public.can_view_meals(user_id));
create policy "write own meals" on public.shared_meals for insert
  with check (user_id = auth.uid());
create policy "update own meals" on public.shared_meals for update
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "delete own meals" on public.shared_meals for delete
  using (user_id = auth.uid());

-- ── Discovery: only the basic card, even for private profiles ───────────────
create or replace function public.search_profiles(q text)
returns table (user_id uuid, username text, display_name text, avatar_url text, is_private boolean)
language sql stable security definer set search_path = public as $$
  select p.user_id, p.username, p.display_name, p.avatar_url, p.is_private
  from public.public_profiles p
  where length(trim(q)) >= 2
    and p.user_id <> auth.uid()
    and (p.username ilike replace(replace(trim(q), '%', ''), '_', '\_') || '%'
         or p.display_name ilike '%' || replace(trim(q), '%', '') || '%')
  order by p.username
  limit 20;
$$;

create or replace function public.profiles_basic(ids uuid[])
returns table (user_id uuid, username text, display_name text, avatar_url text, is_private boolean)
language sql stable security definer set search_path = public as $$
  select p.user_id, p.username, p.display_name, p.avatar_url, p.is_private
  from public.public_profiles p
  where p.user_id = any(ids)
    and (p.user_id = auth.uid()
         or exists (select 1 from public.friendships f
                    where auth.uid() in (f.requester_id, f.addressee_id)
                      and p.user_id in (f.requester_id, f.addressee_id)));
$$;

grant execute on function public.search_profiles(text) to authenticated;
grant execute on function public.profiles_basic(uuid[]) to authenticated;

-- ── Avatars ─────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true)
  on conflict (id) do nothing;

create policy "avatars are public" on storage.objects for select
  using (bucket_id = 'avatars');
create policy "upload own avatar" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "replace own avatar" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "delete own avatar" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
