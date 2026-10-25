-- Migration 0002: row-level security (who can see / change what)
-- Model:
--   * A student login (password or OTP) carries auth.uid(); the session is given a list of
--     linked student ids in the JWT claim `student_ids` (set by the login edge function:
--     the signed-in student + siblings added on that phone + all students on an OTP phone).
--   * A staff login carries claim `staff_id` and `roles`.
--   * Helper functions below read those claims. Service role (server jobs) bypasses RLS.

create or replace function jwt_student_ids() returns uuid[] language sql stable as $$
  select coalesce((select array_agg(x::uuid) from jsonb_array_elements_text(coalesce(auth.jwt()->'student_ids','[]'::jsonb)) x), '{}')
$$;
create or replace function jwt_staff_id() returns uuid language sql stable as $$
  select nullif(auth.jwt()->>'staff_id','')::uuid
$$;
create or replace function jwt_roles() returns text[] language sql stable as $$
  select coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(auth.jwt()->'roles','[]'::jsonb)) x), '{}')
$$;
create or replace function is_staff() returns boolean language sql stable as $$ select jwt_staff_id() is not null $$;
create or replace function has_role(r text) returns boolean language sql stable as $$ select r = any(jwt_roles()) $$;
create or replace function is_office() returns boolean language sql stable as $$
  select has_role('office') or has_role('it_admin') or has_role('principal') or has_role('vice_principal') $$;

-- sections the current staff member teaches or is class teacher of (current year)
create or replace function my_section_ids() returns uuid[] language sql stable as $$
  select coalesce(array_agg(distinct s.id), '{}') from section s
  join academic_year ay on ay.id = s.academic_year_id and ay.is_current
  where s.class_teacher_id = jwt_staff_id()
     or exists (select 1 from teaching_assignment ta where ta.section_id = s.id and ta.staff_id = jwt_staff_id())
     or (has_role('coordinator') and exists (select 1 from grade g join staff st on st.id = jwt_staff_id() where g.id = s.grade_id and g.division = st.division))
     or is_office()
$$;

-- ------------------------------------------------------------------ students & families
alter table student enable row level security;
create policy student_self_read on student for select using (id = any(jwt_student_ids()) or is_staff());
create policy student_office_write on student for all using (is_office()) with check (is_office());
-- sensitive columns are never selected by the app; expose a safe view and revoke direct column access from the anon/authenticated roles
revoke select (aadhaar_no, apaar_no, pen_no) on student from authenticated, anon;

alter table family_phone enable row level security;
create policy family_phone_read on family_phone for select using (student_id = any(jwt_student_ids()) or is_staff());
create policy family_phone_office on family_phone for all using (is_office()) with check (is_office());

alter table enrolment enable row level security;
create policy enrolment_read on enrolment for select using (student_id = any(jwt_student_ids()) or is_staff());
create policy enrolment_office on enrolment for all using (is_office()) with check (is_office());

alter table staff enable row level security;
create policy staff_read on staff for select using (true);          -- names/roles are public inside the app
create policy staff_admin on staff for all using (has_role('it_admin')) with check (has_role('it_admin'));

alter table device_session enable row level security;
create policy device_own on device_session for all
  using (student_id = any(jwt_student_ids()) or staff_id = jwt_staff_id() or is_office())
  with check (student_id = any(jwt_student_ids()) or staff_id = jwt_staff_id() or is_office());

-- ------------------------------------------------------------------ fees
alter table fee_ledger enable row level security;
create policy ledger_read on fee_ledger for select using (student_id = any(jwt_student_ids()) or has_role('accounts') or is_office());
create policy ledger_accounts on fee_ledger for all using (has_role('accounts') or has_role('it_admin')) with check (has_role('accounts') or has_role('it_admin'));

alter table payment enable row level security;
create policy payment_read on payment for select using (student_id = any(jwt_student_ids()) or has_role('accounts') or is_office());
create policy payment_office on payment for insert with check (has_role('accounts'));   -- app payments are inserted by the server (service role)

alter table payment_line enable row level security;
create policy payment_line_read on payment_line for select using (
  exists (select 1 from payment p where p.id = payment_id and (p.student_id = any(jwt_student_ids()) or has_role('accounts') or is_office())));

alter table fee_plan enable row level security;
create policy fee_plan_read on fee_plan for select using (true);
create policy fee_plan_write on fee_plan for all using (has_role('accounts') or has_role('it_admin')) with check (has_role('accounts') or has_role('it_admin'));
alter table late_fee_rule enable row level security;
create policy lfr_read on late_fee_rule for select using (true);
create policy lfr_write on late_fee_rule for all using (has_role('accounts') or has_role('it_admin')) with check (has_role('accounts') or has_role('it_admin'));

-- ------------------------------------------------------------------ announcements
alter table announcement enable row level security;
-- a student sees an announcement if it is sent and they are in the audience
create policy announcement_student_read on announcement for select using (
  sent_at is not null and (
    audience_all
    or exists (select 1 from enrolment e join section s on s.id = e.section_id
               where e.student_id = any(jwt_student_ids())
                 and (s.grade_id = any(audience_grade_ids) or s.id = any(audience_section_ids)))
  ) or is_staff());
create policy announcement_staff_write on announcement for insert with check (
  is_staff() and author_id = jwt_staff_id()
  and (category <> 'urgent' or is_office())                       -- Urgent: office / VP / principal / IT only
  and (is_office() or (not audience_all and audience_grade_ids = '{}' and audience_section_ids <@ my_section_ids()))  -- teachers: own sections only, else needs office approval flow
);
create policy announcement_staff_update on announcement for update using (author_id = jwt_staff_id() or is_office());

alter table announcement_read enable row level security;
create policy ann_read_own on announcement_read for all using (student_id = any(jwt_student_ids()) or is_staff()) with check (student_id = any(jwt_student_ids()));

-- ------------------------------------------------------------------ class diary
alter table diary_entry enable row level security;
create policy diary_student_read on diary_entry for select using (
  posted_at is not null and exists (select 1 from enrolment e where e.student_id = any(jwt_student_ids()) and e.section_id = diary_entry.section_id)
  or is_staff());
create policy diary_teacher_write on diary_entry for all
  using (author_id = jwt_staff_id() or is_office())
  with check (author_id = jwt_staff_id() and section_id = any(my_section_ids()));
alter table diary_read enable row level security;
create policy diary_read_own on diary_read for all using (student_id = any(jwt_student_ids()) or is_staff()) with check (student_id = any(jwt_student_ids()));

-- ------------------------------------------------------------------ messages (the strict one)
alter table conversation enable row level security;
create policy conv_student on conversation for select using (student_id = any(jwt_student_ids()));
create policy conv_staff on conversation for select using (staff_id = jwt_staff_id() or is_office());
-- a student may open a conversation only with an allowed contact
create policy conv_student_create on conversation for insert with check (
  student_id = any(jwt_student_ids())
  and exists (select 1 from student_contacts c where c.student_id = conversation.student_id and c.staff_id = conversation.staff_id));
create policy conv_staff_create on conversation for insert with check (
  staff_id = jwt_staff_id()
  and exists (select 1 from student_contacts c where c.student_id = conversation.student_id and c.staff_id = jwt_staff_id()));
create policy conv_update on conversation for update using (student_id = any(jwt_student_ids()) or staff_id = jwt_staff_id());

alter table message enable row level security;
create policy msg_read on message for select using (
  exists (select 1 from conversation c where c.id = conversation_id
          and (c.student_id = any(jwt_student_ids()) or c.staff_id = jwt_staff_id() or is_office())));
create policy msg_send_student on message for insert with check (
  sender_kind = 'student' and exists (select 1 from conversation c where c.id = conversation_id and c.student_id = any(jwt_student_ids())));
create policy msg_send_staff on message for insert with check (
  sender_kind = 'staff' and exists (select 1 from conversation c where c.id = conversation_id and c.staff_id = jwt_staff_id()));
-- no delete policy on message: nothing can be deleted by either side.

-- ------------------------------------------------------------------ academics
alter table exam enable row level security;
create policy exam_read on exam for select using (published_at is not null or is_staff());
create policy exam_write on exam for all using (is_office() or has_role('coordinator')) with check (is_office() or has_role('coordinator'));
alter table exam_paper enable row level security;
create policy paper_read on exam_paper for select using (true);
create policy paper_teacher on exam_paper for update using (
  is_office() or exists (select 1 from teaching_assignment ta where ta.subject_id = exam_paper.subject_id and ta.staff_id = jwt_staff_id()));

alter table monthly_plan enable row level security;
create policy plan_read on monthly_plan for select using (published_at is not null or is_staff());
create policy plan_write on monthly_plan for all using (is_office() or has_role('coordinator')) with check (is_office() or has_role('coordinator'));

alter table worksheet enable row level security;
create policy ws_read on worksheet for select using (
  is_staff() or exists (select 1 from enrolment e join section s on s.id = e.section_id
    where e.student_id = any(jwt_student_ids()) and (s.id = worksheet.section_id or s.grade_id = worksheet.grade_id)));
create policy ws_write on worksheet for all using (author_id = jwt_staff_id() or is_office()) with check (author_id = jwt_staff_id());

alter table mark enable row level security;
-- students never read raw marks; they read report_card after publish (pdf + summary built server-side)
create policy mark_staff_read on mark for select using (is_staff());
create policy mark_teacher_write on mark for all using (
  is_office() or exists (select 1 from teaching_assignment ta join enrolment e on e.section_id = ta.section_id
     where ta.staff_id = jwt_staff_id() and ta.subject_id = mark.subject_id and e.student_id = mark.student_id))
  with check (entered_by = jwt_staff_id());

alter table report_card enable row level security;
create policy rc_student_read on report_card for select using (
  (status = 'published' or status = 'locked') and student_id = any(jwt_student_ids()) or is_staff());
create policy rc_class_teacher on report_card for all using (
  is_office() or exists (select 1 from enrolment e join section s on s.id = e.section_id
     where e.student_id = report_card.student_id and s.class_teacher_id = jwt_staff_id()));

-- ------------------------------------------------------------------ timetable, leave, star, moments, gallery, calendar, feedback
alter table timetable_slot enable row level security;
create policy tt_read on timetable_slot for select using (true);
create policy tt_write on timetable_slot for all using (is_office()) with check (is_office());

alter table leave_request enable row level security;
create policy leave_student on leave_request for select using (student_id = any(jwt_student_ids()));
create policy leave_student_create on leave_request for insert with check (student_id = any(jwt_student_ids()));
create policy leave_teacher on leave_request for all using (
  is_office() or exists (select 1 from enrolment e join section s on s.id = e.section_id
    where e.student_id = leave_request.student_id and s.class_teacher_id = jwt_staff_id()));

alter table star_of_month enable row level security;
create policy star_read on star_of_month for select using (
  is_staff() or exists (select 1 from enrolment e where e.student_id = any(jwt_student_ids()) and e.section_id = star_of_month.section_id));
create policy star_write on star_of_month for all using (posted_by = jwt_staff_id() or is_office()) with check (section_id = any(my_section_ids()));

alter table moment enable row level security;
create policy moment_read on moment for select using (
  posted_at is not null and (is_staff() or exists (select 1 from enrolment e join section s on s.id = e.section_id
    where e.student_id = any(jwt_student_ids()) and (s.id = moment.section_id or s.grade_id = moment.grade_id))));
create policy moment_write on moment for all using (posted_by = jwt_staff_id() or is_office()) with check (posted_by = jwt_staff_id());
alter table moment_like enable row level security;
create policy like_own on moment_like for all using (student_id = any(jwt_student_ids())) with check (student_id = any(jwt_student_ids()));

alter table album enable row level security;
create policy album_read on album for select using (
  is_staff() or audience_all or exists (select 1 from enrolment e join section s on s.id = e.section_id
    where e.student_id = any(jwt_student_ids()) and s.grade_id = any(album.audience_grade_ids)));
create policy album_write on album for all using (is_staff()) with check (posted_by = jwt_staff_id());
alter table album_photo enable row level security;
create policy album_photo_read on album_photo for select using (exists (select 1 from album a where a.id = album_id));
create policy album_photo_write on album_photo for all using (is_staff()) with check (is_staff());

alter table calendar_event enable row level security;
create policy cal_read on calendar_event for select using (true);
create policy cal_write on calendar_event for all using (is_office()) with check (is_office());

alter table feedback enable row level security;
create policy fb_create on feedback for insert with check (student_id = any(jwt_student_ids()) or student_id is null);
create policy fb_own_read on feedback for select using (student_id = any(jwt_student_ids()) or is_office());
create policy fb_office on feedback for update using (is_office());

-- ------------------------------------------------------------------ transport
alter table route enable row level security;      create policy route_read on route for select using (true);
create policy route_write on route for all using (has_role('transport_incharge') or has_role('it_admin')) with check (has_role('transport_incharge') or has_role('it_admin'));
alter table route_stop enable row level security; create policy stop_read on route_stop for select using (true);
create policy stop_write on route_stop for all using (has_role('transport_incharge') or has_role('it_admin')) with check (has_role('transport_incharge') or has_role('it_admin'));
alter table transport_enrolment enable row level security;
create policy te_read on transport_enrolment for select using (student_id = any(jwt_student_ids()) or is_staff());
create policy te_write on transport_enrolment for all using (has_role('transport_incharge') or is_office()) with check (has_role('transport_incharge') or is_office());

alter table trip enable row level security;
-- parents see trips only for their child's route; crew see their own route; office sees all
create policy trip_read on trip for select using (
  is_staff() or exists (select 1 from transport_enrolment te where te.student_id = any(jwt_student_ids()) and te.route_id = trip.route_id));
create policy trip_crew on trip for all using (
  exists (select 1 from route r where r.id = route_id and (r.driver_staff_id = jwt_staff_id() or r.conductor_staff_id = jwt_staff_id())) or has_role('transport_incharge'))
  with check (started_by = jwt_staff_id());
alter table trip_fix enable row level security;
create policy fix_insert on trip_fix for insert with check (
  exists (select 1 from trip t join route r on r.id = t.route_id where t.id = trip_id and t.status = 'running'
          and (r.driver_staff_id = jwt_staff_id() or r.conductor_staff_id = jwt_staff_id())));
create policy fix_read on trip_fix for select using (has_role('transport_incharge') or has_role('it_admin'));
alter table eta_alert_pref enable row level security;
create policy eta_own on eta_alert_pref for all using (student_id = any(jwt_student_ids())) with check (student_id = any(jwt_student_ids()));

-- ------------------------------------------------------------------ notifications, settings, audit
alter table notification enable row level security;
create policy notif_own on notification for select using (student_id = any(jwt_student_ids()) or staff_id = jwt_staff_id());
create policy notif_mark_read on notification for update using (student_id = any(jwt_student_ids()) or staff_id = jwt_staff_id());
alter table school_setting enable row level security;
create policy setting_read on school_setting for select using (true);
create policy setting_write on school_setting for all using (has_role('it_admin') or has_role('principal')) with check (has_role('it_admin') or has_role('principal'));
alter table audit_log enable row level security;
create policy audit_read on audit_log for select using (has_role('it_admin') or has_role('principal'));
-- audit rows are written by server functions only (service role)
