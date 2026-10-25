# Product decisions — Royale Concorde school app (as of 25 Oct 2026)

Working name: Royale Class Board (final name pending). Replaces MyClassBoard (MCB).

## Users and login
- One account per **student**, identified by the **admission number** on the ID card (e.g. LK/10/2014).
- Parents and the student use the **same login** on their own phones; no separate roles.
- **Siblings** have their own admission numbers; add from the student list screen; switch from Home.
- **Mobile OTP** is the alternative: any registered parent number signs in and links every child on that number.
- **First sign-in** forces a password change from the school-issued first-use password.
- Stay signed in on the device; Settings → sign out; office can **reset password** and **sign out all phones** per student.
- **Staff**: school email (`name@rcis.in`) + password. Roles: teacher, class teacher, coordinator, VP, principal, accounts, office, IT admin, transport in-charge, driver, conductor.
- **Bus crew**: same OTP tab; a registered crew number opens the trip screen only. No visible "bus staff" option.
- After a TC: read-only for 12 months (report cards, receipts), then closed.

## Divisions (for messaging and coordinators)
Pre-primary (Mont–UKG) · Primary (I–V) · Middle (VI–VIII) · High & Senior Secondary (IX–XII, one division).

## Fees
- Installments with due dates; late fee ₹100/day after due date (grace days and cap configurable; currently none).
- Late fee is a separate line that **rides with its installment** and is paid together with it; freezes on payment.
- No partial payments. Future installments may be paid early. Overdue items are mandatory in any payment.
- Home card shows the **overdue** amount; Fees screen splits Overdue / Due soon / Upcoming.
- Office payments (cash/cheque) are **not** accepted/recorded in the app (school's answer: not possible) — to be re-confirmed.
- Payment gateway: Razorpay (school's own merchant account in the trust's name, set up by us with the signatory). Gateway charge policy: TBD (prototype shows "paid by school").
- Receipts: official PDF with school receipt number; downloadable/shareable. Numbering series: TBD.
- Reminders: 3 days before, on the day, 3/6/10 days after. No SMS fallback (cost).

## Announcements
- Categories: General, Holiday, Field trip, Exams, Fees, **Urgent**.
- Audience: whole school, selected grades, or specific sections.
- Teachers may post to their own sections without approval; beyond that needs office approval.
- **Urgent**: office / VP / principal / IT only; bypasses quiet hours; distinct sound; pinned on Home until read; logged with sender; emergencies only.
- No acknowledgements/"Noted"; consents stay on Google Forms. No polls for now.

## Class diary
- Subject teachers and class teacher post per section: Homework, To bring, Reminder, Test, Notice, Project.
- **No submission by default.** Optional "needs a file submission by [date]" switch; when on, students get Submit and the file lands in their private conversation with that teacher, tagged with the note.

## Messages
- Private 1-to-1 conversation per (student, teacher). Visible to student, their parents (same login) and that teacher; office can review. Nothing can be deleted.
- Student may message: teachers who teach them, class teacher, division coordinator, VP. Teacher may message any student they teach; coordinators/VP any student in division.
- Files: PDF, images (camera), Word, PowerPoint, Excel; up to 25 MB.
- Push with sender + first line; badges; seen ticks. **Quiet hours 9 pm – 6 am** (queued, delivered at 6 am).
- Teacher inbox: grouped by class, filters, saved replies, mark done, "post this answer to class diary".

## Academics
- Exams: exam cell sets dates; subject teachers fill portions; lock a week before; one Publish per grade.
- Monthly plan (macro plan) per grade per month; published on the 1st.
- Worksheets / revision PDFs per subject, per section or whole grade; optional answer key with release date.
- Marks entry grid per subject; grades auto from school scale (same scale all grades, to confirm). Report cards visible only after the class teacher **publishes**; locked after; edits audited.
- Co-scholastic, attendance, height/weight entered by class teacher.
- Report card terms: Term I, Term II, Overall.

## Other modules (Stage 1)
- Timetable: set once a year by office; click-a-cell edit; publish notifies section. "Carry kit" tags.
- Leave application: parent applies; class teacher approves/declines in one tap; recorded (attendance itself is not marked online).
- Star of the month: one per section per month, with photo (consent on file) and reason.
- Class moments: class teacher posts photos for the section's families; ♥ only, no comments.
- Gallery: school-wide albums by event (RoMUN 2026 first), audience by grade.
- Calendar: holidays, events, exam and fee dates.
- Student profile: student, academic (subjects), transport tabs. Aadhaar/APAAR/PEN never shown in the app.
- Feedback & suggestions: category, subject, message, optional anonymous; office inbox with reply/forward.
- Morning card ("Your day") on Home: periods & kit, diary notes, next exam, next fee, bus status.
- Transport: routes/stops/crew managed by transport in-charge; **bus tab only for transport students**; stop list + **live map** with moving marker; ETA alerts (trip started, 10 min, 2 stops, at stop, trip ended) per student's own stop; driver/conductor phones send GPS every 5 s in background; alerts to in-charge if trip not started 10 min after schedule or GPS silent 3 min. No school phones per bus for now.
- Birthdays on class teacher's dashboard.

## Explicitly out (for now)
Hall of Fame / toppers, achievements page, PTM slot booking, certificate requests, SMS fallback, translations (English only), polls/forms, badges, alumni, online exams, LMS, student wall/chat, school store, library.

## Platforms
One Flutter codebase → Android, iOS, web (parents and staff). Staff panel also as a browser site. Everything available on every device — teachers can do all tasks from a phone.

## Costs
Google Play $25 once; Apple Developer $99/yr; Supabase free→~₹2,000/mo; Firebase push free; OTP SMS ~₹0.20 each; maps within free tier (bus students only, ~500); gateway 1.5–2% per online payment (policy TBD). Yearly rebuild for OS updates.

## Payments (25 Oct 2026)
- Gateway: Razorpay, account in the school's name; app uses Razorpay SDK on Android/iOS and a hosted payment link on web (same server function decides by `channel`).
- Selection rules enforced server-side by the fee engine: overdue items always included, late fee rides with its instalment, no partial amounts, paying ahead allowed.
- Receipt numbers: `RCIS/<yy-yy>/<5 digits>` from a per-year sequence, issued only on confirmed capture (webhook or signed in-app confirmation; idempotent).
- Failed/abandoned payments stay as `failed`/`created` rows and never touch the ledger.
