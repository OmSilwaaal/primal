# Stripe subscription backend

1. **Stripe dashboard** (test mode first): create a product "Primal Pro" with two recurring prices
   (monthly, yearly). Copy both price IDs (`price_...`). Enable the Customer Portal
   (Settings → Billing → Customer portal).
2. **Database**: run `migrations/20261015000000_subscriptions.sql` in the Supabase SQL editor.
3. **Secrets** (`supabase secrets set ...`):
   `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_ANNUAL`,
   `STRIPE_WEBHOOK_SECRET` (from step 5).
4. **Deploy**:
   ```
   supabase functions deploy create-subscription
   supabase functions deploy create-portal-session
   supabase functions deploy stripe-webhook --no-verify-jwt
   ```
5. **Webhook**: Stripe → Developers → Webhooks → add endpoint
   `https://<project-ref>.supabase.co/functions/v1/stripe-webhook` with events
   `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`.
   Copy its signing secret into `STRIPE_WEBHOOK_SECRET`.
6. Test with card `4242 4242 4242 4242`, any future date/CVC.

The app never sees a secret key. Access is granted only by the webhook writing to `subscriptions`.
