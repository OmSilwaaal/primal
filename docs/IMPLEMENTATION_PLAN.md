# Vitalis — functionality implementation plan

The design pass is largely done (Home, Map, Scan, Data, Profile, Settings, Payment). This plan covers making the app
*work* end to end. Phases are ordered by what blocks a real release first. Each item says what exists today, what's
missing, and what "done" means.

---

## Launch check — 4 Nov 2026

Checked live against the real services, plus a read of every service and 16 new unit tests (`NutriCoreTests`).

| Area | Status | Notes |
|---|---|---|
| USDA food search | ✅ Works | Live search returns results (e.g. 1,161 hits for "beef liver") |
| Barcode (Open Food Facts) | ✅ Works | Live lookup returns the product |
| Food → meal nutrients | ✅ Fixed | Foundation raw beef cuts logged **0 kcal** (no 1008 Energy; they use 2047/2048). Now falls back. Folate now prefers DFE (1190) |
| Core maths | ✅ Tested | Targets (Mifflin–St Jeor), per-100 g scaling, scores, on-target range, streak, 7-day averages, seasons, water from food |
| Apple Health | ✅ Fixed | Deleting a meal left its kcal/protein in Health (double counting). Samples are now tagged with the meal and removed with it |
| Subscriptions (StoreKit 2) | ✅ Code sound | Verified transactions, `Transaction.updates`, refresh on launch. Products still need creating in App Store Connect |
| **Supabase** (sign-in, delete account, Friends) | ❌ **Down** | `ggxpqswpambvbnliopfv.supabase.co` doesn't resolve (NXDOMAIN on 1.1.1.1 and 8.8.8.8): the project is deleted or gone. Email / Google sign-in and Delete account cannot work. Guest mode works |
| **Sign in with Apple** | ❌ Off | Entitlement and button commented out ("TEMP", personal-device signing) while Google sign-in is offered: App Review guideline 4.8 rejects that |
| Photo scan (Gemini) | ❌ Off | No key; shows "Add your Gemini API key". Should go through a server function (0.1) |
| Friends meal upload | ✅ Fixed | Signed-in users' meals were uploaded to `shared_meals` for a hidden feature with no way to turn it off. Off while Friends is hidden (`SocialService.isEnabled`) |
| Delete account | ⚠️ | Edge function is correct, but local SwiftData data stays on the phone afterwards (0.4) |
| **Diet fit** | ⚠️ | Targets are generic: protein 15%, carbs 50%, fat 30%, fibre 25–38 g. A raw animal-based day always reads "Low" on carbs and fibre. Next: diet-aware targets (personalisation) |

### To launch by Friday (in order)
1. Recreate (or restore) the Supabase project; put its URL and anon key in `Constants.swift`; run `supabase/migrations/…_social.sql`; deploy `delete-account`; turn on the Email, Apple and Google providers with the bundle's redirect URL.
2. Paid Apple Developer team: restore the Sign in with Apple entitlement and button (`project.yml`, `NutriCore.entitlements`, `OnboardingView`), or remove Google sign-in.
3. Create the two subscriptions in App Store Connect (`…pro.monthly`, `…pro.annual`) and decide what Pro unlocks (0.2).
4. Gemini behind a server function, or hide photo scan for v1 (barcode and search work).
5. Privacy manifest (0.4).
6. Diet-aware targets so the raw/animal-based diet isn't scored as deficient.

 — Release blockers

### 0.1 API keys off the device
- **Today:** `Constants.swift` ships a real USDA key in the binary and in git; the Gemini key is the placeholder, so
  photo scanning shows "Add your Gemini API key". Anyone can pull keys out of an app binary.
- **Do:** two Supabase Edge Functions — `food-search` (USDA proxy) and `analyze-photo` (Gemini proxy) — that check the
  caller's Supabase session and rate-limit per user. The app calls them with `supabase.functions.invoke`. Rotate the
  USDA key afterwards, since it's in git history.
- **Done when:** no third-party key in `Sources/`, search and photo scan work for a signed-in user and a guest.

### 0.2 Decide what Pro is, and make the gate consistent
- **Today:** nothing inside the app checks `isSubscribed`. The only gate is at launch: signed-in users can't get in
  at all without Pro, while guests can tap "Not now" and use everything.
- **Do:** pick the free tier (suggestion: manual logging, Home, Map free; photo scan, Data history, Trends, Ask and
  Seasonal behind Pro). Add one `ProGate` view modifier that shows the Payment page, and drop the launch-time hard wall
  for signed-in users.
- **Done when:** guests and signed-in users get the same free tier, and every Pro feature goes through one gate.

### 0.3 StoreKit for real
- **Today:** StoreKit 2 with the local `Vitalis.storekit`. Entitlement is cached in `UserDefaults`.
- **Do:** create the products in App Store Connect with the same IDs as `SubscriptionManager.Plan`. Listen to
  `Transaction.updates` for renewals, refunds and revocations, and recheck `currentEntitlements` on launch and when
  the app comes back to the foreground. Treat the cache as a hint only.
- **Done when:** sandbox purchase, restore, cancel, refund and expiry are all reflected in the app within one launch.

### 0.4 Privacy manifest and review requirements
- **Do:** add `PrivacyInfo.xcprivacy` (UserDefaults and file timestamp required-reason APIs, data collected: health,
  location, photos, email). Check the Health and location purpose strings against what ships. When account deletion
  succeeds, also wipe the local SwiftData store and the widget snapshot.

---

## Phase 1 — Logging works end to end

| Item | Today | Do |
|---|---|---|
| Photo meal scan | Built, disabled (no key) | Route through `analyze-photo` (0.1); always show the editable result before logging |
| Edit a logged meal | Delete only (Home context menu) | Edit serving size, time and slot; re-sync HealthKit totals |
| Quick re-log | None | Recents and favourites at the top of Search; "log again" on History rows |
| Custom foods | None | Create a food with per-100 g nutrients; store in SwiftData |
| Barcode not found | Error only | Offer "add it" (prefilled custom food) or search by name |
| Units | Metric everywhere after setup | Imperial option (lb, ft/in, fl oz) in Preferences; store metric, convert at display |
| Time outside | Manual only | Fill from Health's time in daylight (`dailyDaylightMinutes` exists), manual adds on top |

---

## Phase 2 — Data, insights and the Seasonal tab

### 2.1 Seasonal eating (the Data tab's fourth card)
- **Today:** a placeholder: the season name and "Seasonal eating guides are on the way".
- **Do:** a bundled, versioned dataset `seasonal.json`: for each season and hemisphere (later, region), foods with
  peak months, key nutrients and a one-line why. `Season(date:latitude:)` already exists; feed it the location from
  `LocationManager`. Card: the season's top foods as bars or pills, scored by how many you've eaten in the last 14
  days. Sheet: the full list, what you've had, what's missing, and links to Map categories (for example "Farm").
- **Done when:** the card has real content in all four seasons in both hemispheres, with no network needed.

### 2.2 Data for other days
- **Today:** the wheel shows today only.
- **Do:** reuse Home's date wheel (or a compact day picker) above the cards, so the scores, bars and sheet follow the
  chosen day. Streak and Trends stay as they are.

### 2.3 Explain the score
- **Do:** an info button on the Data header opening a short "How the score works" sheet (average share of each target,
  capped at 100%; Met ≥ 90%, Low < 50%; targets from NIH DRIs).

### 2.4 Ask
- **Today:** keyword matching over the last 30 days of your own log ("What has the most iron?").
- **Do:** keep the local answers. For anything it can't match, send the question plus a compact summary of the log to
  an `ask` Edge Function (Pro). Show where every answer came from.

---

## Phase 3 — Accounts and sync

- **Today:** everything lives in local SwiftData. A new phone or a reinstall loses all meals. Supabase holds only auth
  and the (hidden) social profile.
- **Do (recommended):** CloudKit-backed SwiftData (`ModelConfiguration(cloudKitDatabase: .private(...))`) for meals,
  hydration, sun sessions, readings and profile: private, free and no server code. Audit models for CloudKit rules
  (optional or defaulted properties, no unique constraints).
- **Guest → account:** when a guest signs in, keep their local data (it's the same store) and create the Supabase
  profile.
- **Done when:** logging on one device shows on a second device signed into the same Apple Account.

---

## Phase 4 — Platform

- **Widgets:** the snapshot is only written when Home appears. Write it from `MealLogger.log/delete`, water and sun
  adds, and on day change, then reload timelines.
- **Reminders:** skip the evening reminder when today already has meals; skip the morning one when Health already
  shows daylight minutes.
- **HealthKit writes:** today it writes energy, protein and water. Add carbs, fat, fibre and the main vitamins and
  minerals that HealthKit supports, and remove samples when a meal is deleted or edited.

---

## Phase 5 — Hidden features (kept in code, not reachable)

- **Friends:** the backend is ready (`supabase/migrations/…_social.sql`, RLS, `delete-account`). The UI is unreachable,
  and Settings' Privacy section is off via `SettingsView.showsSocial`. To ship: run the migration, add an entry point
  (Profile header), then block, report and content rules (App Store user-generated-content requirements), and turn
  `showsSocial` on.
- **Raw hub** (raw log, batches, biomarkers, diet rater, sourcing) and **Sun**: decide per piece. Biomarkers could join
  Profile's More info, sourcing could join Map, and the rest could be deleted. Nothing links to them today (the
  `pushed: SecondaryScreen?` state in Home and Profile is never set).

---

## Phase 6 — Quality

- **Tests (none today):**
  - unit tests for `NutrientGoals`, `buildNutrientList`, `DataGroupSummary.score`, `StreakSummary`, `DayGoal`,
    `Season`, `ProfileView.dailyAverage` and `FoodWater`;
  - a launch smoke test per tab that fails on a crash.
- **Warnings (Swift 6):** `AIService.prompt` actor isolation, the unused `event` in `AuthManager`, and the Sendable
  closure in `EditProfileView`.
- **Accessibility pass:** VoiceOver order on Home, Dynamic Type on the bento tiles, and Reduce Motion on the Data wheel
  and Vitalis card.
- **Crash reporting:** privacy-friendly crash reporting (for example MetricKit diagnostics) before TestFlight.
- **App Store:** screenshots, description and review notes (demo account, what Health is used for).

---

## Redundancy removed in this pass

| Where | What was repeated | Now |
|---|---|---|
| Home header | Profile button (same as the Profile tab) | Removed; Weather and Share remain |
| Map header | "0 × BUTCHER WITHIN 20 KM" repeated the selected chip | "0 PLACES WITHIN 20 KM" |
| Data, Seasonal card | "coming soon" three times (card, pill, caption) | Once, under the wheel; the card shows the season |
| Profile, Daily tile | Today's calories (same as Home's ring) | **Week**: 7-day average a day against the target |
| Profile, Daily energy panel | Today's total and today's meals (Home) | **This week**: a bar per day, days on target, how the target is worked out |
| Profile, Today tile | Today's meals (Home) | **History**: every meal from the last 7 days, by day |
| Profile, Info panel | Today's energy, water, sun and lowest nutrients (Home and Data) | **Trends**: 7-day averages and the nutrients lowest across the week |
| Settings, Body & goals | Weight, height, age, goal, activity (all editable on Profile) | Row and `BodyGoalsView` removed |
| Settings, Privacy | Friends visibility for a hidden feature | Hidden with `showsSocial` |
| Code | Unused `ArcWheel`, `ProgressRing`, `GlassSegmented`, `OptionChip`, `SegmentBackground`, `RuleLabel`, `SmoothLine`, `OnboardingFeatureRow`, `PaywallFeatureRow`, `ChipFlow` | Deleted |
