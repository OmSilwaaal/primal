# Friends / profiles backend

1. Run `migrations/20261016000000_social.sql` in the Supabase SQL editor (creates tables, RLS,
   search functions and the public `avatars` storage bucket).
2. Deploy the account deletion function (needs the same Stripe secrets as billing):
   `supabase functions deploy delete-account`
3. Profiles are created automatically the first time a signed-in user opens the app.

Privacy model
- `is_private`: non-friends can only see name, username and photo (needed to send a request).
- `meal_visibility`: `friends` (default), `everyone` (hidden from non-friends while private) or `nobody`.
- Enforced by row level security, not by the app.
