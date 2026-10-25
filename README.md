# Royale Connect — school app for Royale Concorde International School

One codebase (Flutter) for Android, iOS and web; one database (Supabase, project `upgvxhsxmdihmfmzknlq`,
Mumbai). Everything here is already wired to the school's live project. Nothing in this folder contains a secret:
the only key inside the app is the **publishable** key, which is designed to be public — the row-level
rules in the database decide what each login may see.

## What is here

```
supabase/
  migrations/0001_schema.sql        49 tables                                     ✅ loaded live
  migrations/0002_access_rules.sql  80 row-level security rules + helper functions ✅ loaded live
  migrations/0003_auth_columns.sql  password hashes, OTP codes, app sessions        ✅ loaded live
  migrations/0004_storage.sql       private "files" bucket + folder rules            ⬜ run next (step 1 below)
  seed_sample.sql                   sample data (Aarav, Diya, VIII-B, Route 7 …)   ✅ loaded live
  functions/
    _shared/lib.ts                  token minting, password hashing, phone/admission normalising, audit
    _shared/fee_engine.ts           late-fee + bucket logic (same as engine/)
    login-student/                  admission number + password → session token (+ sibling linking)
    login-otp/                      mobile OTP → all children on that number; bus crew → crew token
    password/                       change · reset (office / class teacher) · sign out all phones
    nightly-fees/                   adds late-fee rows, queues fee reminders (−3/0/+3/+6/+10 days)
    send-notifications/             FCM push with quiet hours 21:00–06:00 IST, Urgent bypass
    razorpay-order/                 validates the selection (fee engine) → Razorpay order (app) or payment link (web)
    razorpay-webhook/               Razorpay webhook + in-app confirmation → marks paid, issues receipt no.
engine/
  fee_engine.js + fee_engine.test.js   8 tests — node fee_engine.test.js
app/                                Flutter app (see "Running the app")
  pubspec.yaml
  lib/main.dart                     Supabase.initialize + theme + router
  lib/router.dart                   all routes; redirects for signed-out / set-password / pick-student / crew
  lib/shell.dart                    bottom tabs (Bus tab only for transport students)
  lib/core/config.dart              project URL + publishable key + school constants
  lib/core/theme.dart               brand tokens (crimson / gold / Manrope / Playfair), light + dark
  lib/core/data.dart                fees, announcements, diary, unread, transport providers
  lib/auth/session.dart             login / OTP / sibling / change-password / sign-out, secure storage
  lib/auth/login_screen.dart        Splash, Login (Admission number | Mobile OTP), Set password
  lib/screens/                      Home, Fees, Pay, Receipts, Diary, Announcements, Messages + Chat, Timetable, Exams,
                                    Monthly plan, Worksheets, Star, Calendar, Report cards, Gallery, Leave, Profile,
                                    Feedback, Bus (stops / live map / alerts), Driver (start / end trip), Settings
  assets/images                     logo, monogram, app icon
docs/decisions.md                   every product decision, in one place
```

## Step 1 — storage bucket (SQL Editor, 1 minute)

Supabase → SQL Editor → New query → paste `supabase/migrations/0004_storage.sql` → **Run**.
Creates the private `files` bucket (PDF/images up to 10 MB) and the rules for who may upload where.

## Automatic builds (no software needed) — `.github/workflows/build.yml`

Once this folder is in the GitHub repo **with its folders intact**, every push builds the app by itself:
* **Web**: Settings → Pages → Source = "GitHub Actions" (one-time). The app is then live at
  `https://royaleconnect.github.io/royaleconnect/` within ~10 minutes of each push.
* **Android**: Releases → "latest" → download `app-release.apk` and open it on any Android phone.
* iOS needs Apple's signing and is done from a Mac at store time.

## Step 2 — deploy the server functions (IT person's laptop, ~15 minutes, once)

```bash
npm i -g supabase                       # Supabase CLI
supabase login                          # opens the browser; sign in as rciskit@gmail.com
cd <repo>/supabase
supabase link --project-ref upgvxhsxmdihmfmzknlq

# secrets — paste values, never commit them
supabase secrets set SUPABASE_JWT_SECRET="<Project Settings → API → JWT Secret>"
supabase secrets set MSG91_AUTHKEY="" MSG91_TEMPLATE_ID=""        # leave empty until the SMS account exists → OTP is logged, not sent
supabase secrets set FCM_SERVICE_ACCOUNT_JSON=''                   # from Firebase later; empty = notifications only queued

supabase functions deploy login-student login-otp password nightly-fees send-notifications razorpay-order razorpay-webhook --no-verify-jwt
```

Then schedule the two jobs (Supabase → Integrations → Cron, or SQL):
`nightly-fees` daily at 00:30 IST, `send-notifications` every 5 minutes. Both must be called with the
`service_role` key in the `Authorization` header — the cron UI does this for you.

Quick test from any terminal (uses the publishable key only):

```bash
curl -X POST https://upgvxhsxmdihmfmzknlq.supabase.co/functions/v1/login-student \
  -H "apikey: sb_publishable_8mtHFfZ9Fk3p1YdG6gwydw_IXlULRxR" -H "content-type: application/json" \
  -d '{"admission_no":"LK/10/2014","password":"Welcome1"}'
```

Expected: a JSON with `token`, `students` (Aarav) and `must_change_password: true`.

## Step 3 — running the app (any laptop with Flutter installed)

Install Flutter once: https://docs.flutter.dev/get-started/install (Android Studio for Android; a Mac with
Xcode for iOS). Then:

```bash
cd app
flutter create . --org in.rcis --project-name royale_connect   # generates android/ ios/ web/ folders; keeps lib/
flutter pub get
dart run flutter_launcher_icons                                   # app icon on both platforms
flutter run -d chrome                                             # web, instantly
flutter run                                                      # phone/emulator
```

Sign in with `LK/10/2014` / `Welcome1` (sample data). First build on a new machine takes a few minutes;
afterwards changes hot-reload in a second.

Builds for the stores: `flutter build appbundle` (Play) · `flutter build ipa` (App Store, Mac only) ·
`flutter build web` (host anywhere — Supabase, Vercel or the school's website).

### Online fee payment (Razorpay)
The school opens a Razorpay account in its own name (free; needs PAN, bank account, school registration). Then:
1. Razorpay Dashboard → Settings → API Keys → Generate. `supabase secrets set RAZORPAY_KEY_ID=rzp_live_… RAZORPAY_KEY_SECRET=…`
2. Settings → Webhooks → Add: URL `https://upgvxhsxmdihmfmzknlq.supabase.co/functions/v1/razorpay-webhook`,
   events `payment.captured` and `payment.failed`, choose a secret → `supabase secrets set RAZORPAY_WEBHOOK_SECRET=…`
3. `supabase secrets set APP_WEB_URL=https://<where the web build is hosted>` (return page for payments made on the web).
Until the keys exist the Pay screen shows "Could not start the payment" — everything else works. Test mode keys (`rzp_test_…`) work the same way for rehearsals.

### Push notifications
Create a Firebase project (free) → add Android + iOS apps → download `google-services.json` into
`android/app/` and `GoogleService-Info.plist` into `ios/Runner/`. Paste the service-account JSON into the
`FCM_SERVICE_ACCOUNT_JSON` secret (step 2). Until then the app works fully; alerts simply queue.

## Login model

* **Student / parent** — admission number (e.g. `LK/10/2014`) + password. `login-student` checks the PBKDF2
  hash, then mints a token carrying `student_ids: [...]` — the signed-in student plus any siblings added on this
  phone. First sign-in forces a new password. 5 wrong attempts → 15-minute lock.
* **Mobile OTP** — either parent's number → one token with every child on that number. A driver's or
  conductor's number opens the trip screen instead.
* **Staff** — school email + password → token with `staff_id` and `roles` (next pass, with the web panel).
* Office / IT (or the class teacher, own section only) can reset a password; the student gets a one-time
  password and must change it. "Sign out all phones" invalidates every session for that student.

## Verified so far

* All three migrations + seed apply on PostgreSQL 16; 0001/0002/seed confirmed in the live project
  (anonymous REST call returns `[]` — rules in force).
* Access rules tested as four users (student, sibling-linked student, teacher, office).
* Fee engine: 8/8 tests. Edge functions type-check (tsc) clean.
* Flutter code is written against the live schema; first `flutter run` will surface any analyzer nits — they
  are quick fixes, not design changes.

## What comes next (in order)

1. Import scripts for the school's Excel sheets (students + phones, fee plan, timetable, routes).
2. Receipt PDF generation + email copy to the parent.
3. Staff web panel (same Flutter code, web build) + teacher phone mode.
4. Street-map tiles for the live bus map (optional), diary file submissions table.
5. Spec + demo script, store listings, launch.

## Moving to the school's own accounts later

Supabase: Organization settings → Transfer project. GitHub: repository Settings → Transfer ownership.
Both keep every URL and key unchanged.
