-- Royale Concorde International School — school app
-- Migration 0001: core schema
-- Target: Supabase (PostgreSQL 15+). Run in the SQL editor or via `supabase db push`.
-- Conventions: snake_case, uuid primary keys, created_at/updated_at on every table,
-- soft-delete via `archived_at` where records must never be lost (students, staff, payments, messages).

create extension if not exists "pgcrypto";
create extension if not exists "citext";

-- ---------------------------------------------------------------------------
-- 0. Enums
-- ---------------------------------------------------------------------------
create type division as enum ('pre_primary','primary','middle','high_senior');
create type staff_role as enum ('teacher','class_teacher','coordinator','vice_principal','principal','accounts','office','it_admin','transport_incharge','driver','conductor');
create type fee_head_kind as enum ('tuition','transport','misc','late_fee','other');
create type ledger_status as enum ('pending','paid','waived','cancelled');
create type payment_mode as enum ('upi','card','netbanking','wallet','cash','cheque','neft','other');
create type payment_status as enum ('created','pending','success','failed','refunded');
create type announcement_category as enum ('general','holiday','field_trip','exams','fees','urgent');
create type diary_kind as enum ('homework','to_bring','reminder','test','notice','project');
create type leave_status as enum ('pending','approved','declined');
create type report_status as enum ('draft','ready','published','locked');
create type trip_kind as enum ('morning_pickup','afternoon_drop');
create type trip_status as enum ('running','ended','aborted');
create type notif_kind as enum ('announcement','diary','fee_reminder','fee_overdue','message','report_card','leave','bus','moment','worksheet','exam','system');

-- ---------------------------------------------------------------------------
-- 1. Academic structure
-- ---------------------------------------------------------------------------
create table academic_year (
  id uuid primary key default gen_random_uuid(),
  label text not null unique,            -- '2026-27'
  starts_on date not null,
  ends_on date not null,
  is_current boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index one_current_year on academic_year (is_current) where is_current;

create table grade (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,             -- 'VIII', 'LKG', 'XI'
  name text not null,                    -- 'Grade VIII'
  division division not null,
  sort_order int not null
);

create table section (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_year(id),
  grade_id uuid not null references grade(id),
  name text not null,                    -- 'B', 'Sci', 'Com'
  class_teacher_id uuid,                 -- fk added after staff table
  unique (academic_year_id, grade_id, name)
);

create table subject (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,             -- 'Mathematics'
  short text not null                    -- 'MA'
);

-- ---------------------------------------------------------------------------
-- 2. People: staff, students, families
-- ---------------------------------------------------------------------------
create table staff (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique,              -- supabase auth.users.id (email login)
  email citext not null unique,          -- name@rcis.in
  full_name text not null,
  display_name text not null,            -- 'Ms. Kavitha R.'
  phone text,
  roles staff_role[] not null default '{teacher}',
  division division,                     -- for coordinators
  photo_path text,
  active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table section add constraint section_class_teacher_fk foreign key (class_teacher_id) references staff(id);

-- which teacher teaches which subject to which section (drives timetable, messaging contacts, marks entry)
create table teaching_assignment (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_year(id),
  section_id uuid not null references section(id),
  subject_id uuid not null references subject(id),
  staff_id uuid not null references staff(id),
  unique (academic_year_id, section_id, subject_id)
);

create table student (
  id uuid primary key default gen_random_uuid(),
  admission_no text not null unique,     -- 'LK/10/2014'  ← the login id
  auth_user_id uuid unique,              -- supabase auth user (password login); phone/otp users map via family_phone
  full_name text not null,
  dob date not null,
  gender text,
  blood_group text,
  house text,
  admission_type text not null default 'Day Scholar',
  address text,
  father_name text, mother_name text, guardian_name text,
  photo_path text,
  photo_consent boolean not null default false,
  -- sensitive ids kept here but NEVER exposed through the app API (RLS column policy below)
  aadhaar_no text, apaar_no text, pen_no text,
  first_login_done boolean not null default false,
  active boolean not null default true,
  tc_issued_on date,                     -- after this: read-only for 12 months (report cards/receipts), then closed
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- registered parent phones. one row per phone per student. OTP login finds every student on that phone.
create table family_phone (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references student(id) on delete cascade,
  phone text not null,                   -- 10 digits, no +91
  label text,                            -- 'Father', 'Mother'
  is_primary boolean not null default false,
  unique (student_id, phone)
);
create index family_phone_phone_idx on family_phone (phone);

-- enrolment of a student in a section for a year (students move sections each April)
create table enrolment (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_year(id),
  student_id uuid not null references student(id),
  section_id uuid not null references section(id),
  roll_no int,
  unique (academic_year_id, student_id)
);

-- devices signed in for a student (for "sign out all phones" and push tokens)
create table device_session (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references student(id) on delete cascade,
  staff_id uuid references staff(id) on delete cascade,
  push_token text,
  platform text,                         -- 'android' | 'ios' | 'web'
  device_label text,
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  check (student_id is not null or staff_id is not null)
);

-- ---------------------------------------------------------------------------
-- 3. Fees
-- ---------------------------------------------------------------------------
create table fee_head (
  id uuid primary key default gen_random_uuid(),
  name text not null,                    -- 'Tuition — Installment 3'
  kind fee_head_kind not null,
  sort_order int not null default 0
);

-- fee structure per grade per year: which heads, how much, due when
create table fee_plan (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_year(id),
  grade_id uuid not null references grade(id),
  fee_head_id uuid not null references fee_head(id),
  amount numeric(10,2) not null check (amount >= 0),
  due_on date not null,
  optional boolean not null default false,  -- transport: only for opted students
  can_pay_early boolean not null default true,
  unique (academic_year_id, grade_id, fee_head_id)
);

-- the late-fee rule, versioned so history stays correct
create table late_fee_rule (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_year(id),
  applies_to fee_head_kind[] not null default '{tuition,transport}',
  grace_days int not null default 0,
  per_day numeric(10,2) not null default 100,
  cap numeric(10,2),                     -- null = no cap
  effective_from date not null,
  created_by uuid references staff(id),
  created_at timestamptz not null default now()
);

-- one row per student per fee line = the ledger. Generated from fee_plan when a student is enrolled (plus transport if opted).
create table fee_ledger (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_year(id),
  student_id uuid not null references student(id),
  fee_head_id uuid not null references fee_head(id),
  title text not null,                   -- frozen copy of the head name at creation
  amount numeric(10,2) not null check (amount >= 0),
  due_on date not null,
  status ledger_status not null default 'pending',
  concession numeric(10,2) not null default 0,
  parent_ledger_id uuid references fee_ledger(id),   -- late fee → points at the installment it rides with
  paid_on date,
  payment_id uuid,                       -- fk after payment
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index fee_ledger_student_idx on fee_ledger (student_id, academic_year_id);
create index fee_ledger_due_idx on fee_ledger (status, due_on);

create table payment (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references student(id),
  amount numeric(10,2) not null check (amount > 0),
  mode payment_mode not null,
  status payment_status not null default 'created',
  gateway text,                          -- 'razorpay'
  gateway_order_id text, gateway_payment_id text unique, gateway_signature text,
  receipt_no text unique,                -- 'RCIS/26-27/04187' assigned on success
  collected_by uuid references staff(id),-- office payments
  paid_at timestamptz,
  raw_payload jsonb,
  created_at timestamptz not null default now()
);
alter table fee_ledger add constraint fee_ledger_payment_fk foreign key (payment_id) references payment(id);

create table payment_line (                -- which ledger rows a payment settled
  payment_id uuid not null references payment(id) on delete cascade,
  fee_ledger_id uuid not null references fee_ledger(id),
  amount numeric(10,2) not null,
  primary key (payment_id, fee_ledger_id)
);

create table receipt_sequence (
  academic_year_id uuid primary key references academic_year(id),
  prefix text not null,                  -- 'RCIS/26-27/'
  next_no int not null default 1
);

-- ---------------------------------------------------------------------------
-- 4. Communication: announcements, diary, messages
-- ---------------------------------------------------------------------------
create table announcement (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_year(id),
  category announcement_category not null default 'general',
  title text not null,
  body text not null,
  attachment_path text,
  author_id uuid not null references staff(id),
  -- audience: whole school, grade list, or section list
  audience_all boolean not null default false,
  audience_grade_ids uuid[] not null default '{}',
  audience_section_ids uuid[] not null default '{}',
  scheduled_for timestamptz,             -- null = sent now
  sent_at timestamptz,
  approved_by uuid references staff(id), -- required when a teacher posts beyond own classes
  reach_count int,
  created_at timestamptz not null default now()
);
create index announcement_sent_idx on announcement (sent_at desc);

create table announcement_read (
  announcement_id uuid not null references announcement(id) on delete cascade,
  student_id uuid not null references student(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (announcement_id, student_id)
);

create table diary_entry (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null references section(id),
  subject_id uuid references subject(id),       -- null = class teacher notice
  author_id uuid not null references staff(id),
  kind diary_kind not null default 'homework',
  title text not null,
  body text,
  for_date date not null,
  due_on date,
  attachment_path text,
  needs_submission boolean not null default false,
  submission_due_on date,
  scheduled_for timestamptz,
  posted_at timestamptz,
  created_at timestamptz not null default now()
);
create index diary_section_date_idx on diary_entry (section_id, for_date desc);

create table diary_read (
  diary_entry_id uuid not null references diary_entry(id) on delete cascade,
  student_id uuid not null references student(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (diary_entry_id, student_id)
);

-- one private conversation per (student, staff). Nobody else, except office review.
create table conversation (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references student(id),
  staff_id uuid not null references staff(id),
  last_message_at timestamptz,
  student_unread int not null default 0,
  staff_unread int not null default 0,
  staff_done boolean not null default false,
  unique (student_id, staff_id)
);

create table message (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversation(id) on delete cascade,
  sender_kind text not null check (sender_kind in ('student','staff')),
  body text,
  attachment_path text, attachment_name text, attachment_size int, attachment_mime text,
  diary_entry_id uuid references diary_entry(id),   -- set when sent via "Submit file" on a diary note
  queued_until timestamptz,              -- quiet hours: deliver at 06:00
  delivered_at timestamptz,
  seen_at timestamptz,
  flagged boolean not null default false,-- keyword flag for office review
  created_at timestamptz not null default now(),
  check (body is not null or attachment_path is not null)
);
create index message_conv_idx on message (conversation_id, created_at);

-- who a student may message: derived view (teachers of their section + class teacher + division coordinator + VP)
create or replace view student_contacts as
select e.student_id, ta.staff_id, 'subject'::text as kind, ta.subject_id
from enrolment e
join academic_year ay on ay.id = e.academic_year_id and ay.is_current
join teaching_assignment ta on ta.section_id = e.section_id and ta.academic_year_id = e.academic_year_id
union
select e.student_id, s.class_teacher_id, 'class', null
from enrolment e
join academic_year ay on ay.id = e.academic_year_id and ay.is_current
join section s on s.id = e.section_id where s.class_teacher_id is not null
union
select e.student_id, st.id, 'lead', null
from enrolment e
join academic_year ay on ay.id = e.academic_year_id and ay.is_current
join section s on s.id = e.section_id join grade g on g.id = s.grade_id
join staff st on (st.roles @> '{coordinator}' and st.division = g.division) or st.roles @> '{vice_principal}';

-- ---------------------------------------------------------------------------
-- 5. Academics: exams, plan, worksheets, marks & report cards
-- ---------------------------------------------------------------------------
create table exam (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_year(id),
  grade_id uuid not null references grade(id),
  name text not null,                    -- 'Term-II Periodic Test 1'
  term text not null,                    -- 'Term I' | 'Term II'
  starts_on date, ends_on date,
  max_marks int not null default 100,
  note text,
  portions_lock_on date,
  published_at timestamptz,
  created_by uuid references staff(id)
);

create table exam_paper (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references exam(id) on delete cascade,
  subject_id uuid not null references subject(id),
  on_date date,
  portions text,
  confirmed_by uuid references staff(id),
  confirmed_at timestamptz,
  unique (exam_id, subject_id)
);

create table monthly_plan (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_year(id),
  grade_id uuid not null references grade(id),
  month date not null,                   -- first of month
  subject_id uuid not null references subject(id),
  topics text not null,
  assessment text,
  published_at timestamptz,
  unique (academic_year_id, grade_id, month, subject_id)
);

create table worksheet (
  id uuid primary key default gen_random_uuid(),
  section_id uuid references section(id),
  grade_id uuid references grade(id),    -- either section or whole grade
  subject_id uuid not null references subject(id),
  kind text not null,                    -- 'Worksheet' | 'Revision notes' | ...
  title text not null,
  file_path text not null,
  answer_key_path text, answer_key_release_on date,
  author_id uuid not null references staff(id),
  created_at timestamptz not null default now(),
  check (section_id is not null or grade_id is not null)
);

create table grading_scale (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_year(id),
  min_pct numeric(5,2) not null, max_pct numeric(5,2) not null,
  grade_label text not null              -- 'A1'
);

create table mark (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references exam(id),
  subject_id uuid not null references subject(id),
  student_id uuid not null references student(id),
  internal numeric(6,2), external numeric(6,2),
  total numeric(6,2) generated always as (coalesce(internal,0)+coalesce(external,0)) stored,
  absent boolean not null default false,
  entered_by uuid references staff(id),
  updated_at timestamptz not null default now(),
  unique (exam_id, subject_id, student_id)
);

create table report_card (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_year(id),
  student_id uuid not null references student(id),
  term text not null,                    -- 'Term I' | 'Term II' | 'Overall'
  status report_status not null default 'draft',
  working_days int, days_present int,
  height_cm numeric(5,1), weight_kg numeric(5,1),
  remarks text,
  co_scholastic jsonb,
  pdf_path text,
  published_by uuid references staff(id), published_at timestamptz,
  unique (academic_year_id, student_id, term)
);

create table mark_audit (                  -- every change after publish
  id bigserial primary key,
  mark_id uuid not null references mark(id),
  changed_by uuid not null references staff(id),
  old_internal numeric(6,2), old_external numeric(6,2),
  new_internal numeric(6,2), new_external numeric(6,2),
  reason text,
  changed_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 6. Timetable, leave, star, moments, gallery, calendar, feedback
-- ---------------------------------------------------------------------------
create table timetable_slot (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null references section(id),
  weekday int not null check (weekday between 1 and 6),  -- 1=Mon
  period int not null,                   -- 1..8 ; breaks are not stored
  starts_at time not null,
  subject_id uuid references subject(id),
  label text,                            -- 'PE', 'Library', 'Assembly' when no subject
  staff_id uuid references staff(id),
  needs_kit boolean not null default false,
  unique (section_id, weekday, period)
);

create table leave_request (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references student(id),
  from_date date not null, to_date date not null,
  reason text not null, note text,
  status leave_status not null default 'pending',
  decided_by uuid references staff(id), decided_at timestamptz,
  created_at timestamptz not null default now(),
  check (to_date >= from_date)
);

create table star_of_month (
  id uuid primary key default gen_random_uuid(),
  section_id uuid not null references section(id),
  month date not null,
  student_id uuid not null references student(id),
  reason text not null,
  photo_path text,
  posted_by uuid not null references staff(id),
  created_at timestamptz not null default now(),
  unique (section_id, month)
);

create table moment (                      -- class moments: photos for one section's families
  id uuid primary key default gen_random_uuid(),
  section_id uuid references section(id),
  grade_id uuid references grade(id),
  caption text not null,
  photo_paths text[] not null,
  posted_by uuid not null references staff(id),
  scheduled_for timestamptz, posted_at timestamptz,
  created_at timestamptz not null default now(),
  check (section_id is not null or grade_id is not null)
);
create table moment_like (
  moment_id uuid not null references moment(id) on delete cascade,
  student_id uuid not null references student(id) on delete cascade,
  primary key (moment_id, student_id)
);

create table album (                       -- school-wide gallery
  id uuid primary key default gen_random_uuid(),
  title text not null,
  event_date date,
  audience_all boolean not null default true,
  audience_grade_ids uuid[] not null default '{}',
  cover_path text,
  posted_by uuid not null references staff(id),
  created_at timestamptz not null default now()
);
create table album_photo (
  id uuid primary key default gen_random_uuid(),
  album_id uuid not null references album(id) on delete cascade,
  path text not null,
  sort_order int not null default 0
);

create table calendar_event (
  id uuid primary key default gen_random_uuid(),
  academic_year_id uuid not null references academic_year(id),
  title text not null,
  starts_on date not null, ends_on date,
  kind text not null,                    -- 'holiday' | 'event' | 'exam' | 'fee'
  audience_all boolean not null default true,
  audience_grade_ids uuid[] not null default '{}'
);

create table feedback (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references student(id),   -- null when anonymous
  section_id uuid references section(id),   -- kept even when anonymous (grade-level context only)
  category text not null,
  subject text not null, body text not null,
  anonymous boolean not null default false,
  status text not null default 'new',    -- 'new' | 'replied' | 'closed'
  reply text, replied_by uuid references staff(id), replied_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 7. Transport
-- ---------------------------------------------------------------------------
create table route (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,             -- 'Route 7'
  bus_reg_no text not null,
  driver_staff_id uuid references staff(id),
  conductor_staff_id uuid references staff(id),
  morning_start time, afternoon_start time,
  active boolean not null default true
);
create table route_stop (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references route(id) on delete cascade,
  seq int not null,
  name text not null,
  lat double precision not null, lng double precision not null,
  km_from_start numeric(6,2) not null,
  morning_eta time, afternoon_eta time,
  unique (route_id, seq)
);
create table transport_enrolment (
  student_id uuid primary key references student(id),
  route_id uuid not null references route(id),
  stop_id uuid not null references route_stop(id),
  academic_year_id uuid not null references academic_year(id)
);
create table trip (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references route(id),
  kind trip_kind not null,
  started_by uuid not null references staff(id),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  status trip_status not null default 'running',
  last_lat double precision, last_lng double precision, last_fix_at timestamptz,
  next_stop_seq int
);
create index trip_active_idx on trip (route_id) where status = 'running';
create table trip_fix (                    -- raw GPS points, 90-day retention
  id bigserial primary key,
  trip_id uuid not null references trip(id) on delete cascade,
  lat double precision not null, lng double precision not null,
  speed_kmh numeric(5,1), accuracy_m numeric(6,1),
  fixed_at timestamptz not null default now()
);
create index trip_fix_trip_idx on trip_fix (trip_id, fixed_at);
create table eta_alert_pref (
  student_id uuid primary key references student(id) on delete cascade,
  trip_started boolean not null default true,
  ten_min boolean not null default true,
  two_stops boolean not null default true,
  at_stop boolean not null default true,
  trip_ended boolean not null default false
);

-- ---------------------------------------------------------------------------
-- 8. Notifications & audit
-- ---------------------------------------------------------------------------
create table notification (
  id bigserial primary key,
  student_id uuid references student(id) on delete cascade,
  staff_id uuid references staff(id) on delete cascade,
  kind notif_kind not null,
  title text not null, body text,
  deep_link text,                        -- 'fees' | 'notice/<id>' | 'chat/<id>' ...
  urgent boolean not null default false, -- bypasses quiet hours
  send_after timestamptz not null default now(),
  sent_at timestamptz, read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notification_pending_idx on notification (send_after) where sent_at is null;

create table school_setting (
  key text primary key,                  -- 'quiet_hours_start' = '21:00', 'quiet_hours_end' = '06:00', 'fee_reminder_days' = '3,0,-3,-6', ...
  value text not null,
  updated_by uuid references staff(id),
  updated_at timestamptz not null default now()
);

create table audit_log (                   -- money, marks, urgent notices, password resets, role changes
  id bigserial primary key,
  actor_staff_id uuid references staff(id),
  actor_student_id uuid references student(id),
  action text not null,                  -- 'payment.record', 'mark.edit', 'announcement.urgent', 'password.reset', ...
  entity text, entity_id uuid,
  detail jsonb,
  at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 9. updated_at trigger
-- ---------------------------------------------------------------------------
create or replace function touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
do $$ declare t text; begin
  for t in select unnest(array['staff','student','fee_ledger','mark']) loop
    execute format('create trigger %I_touch before update on %I for each row execute function touch_updated_at()', t, t);
  end loop; end $$;
