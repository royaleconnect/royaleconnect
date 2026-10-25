// POST /functions/v1/login-student
// body: { admission_no, password, device_label?, link_to?: string[] }
//   link_to = student ids already on this phone (add-a-sibling): the new token carries all of them.
// returns: { token, students:[{id,admission_no,full_name,grade,section}], must_change_password }
import { admin, json, preflight, normAdmission, verifyPassword, mintToken, audit } from "../_shared/lib.ts";

Deno.serve(async (req) => {
  const pf = preflight(req); if (pf) return pf;
  try {
    const { admission_no, password, device_label, link_to } = await req.json();
    const adm = normAdmission(admission_no);
    if (!adm || !password) return json({ error: "Enter the admission number and password." }, 400);

    const db = admin();
    const { data: s } = await db.from("student")
      .select("id, admission_no, full_name, password_hash, must_change_password, failed_logins, locked_until, active, tc_issued_on")
      .eq("admission_no", adm).maybeSingle();

    // same message for unknown id and wrong password — never reveal which
    const bad = () => json({ error: "That admission number and password don't match. Check the slip from the school, or use Mobile OTP." }, 401);
    if (!s || !s.active) return bad();
    if (s.locked_until && new Date(s.locked_until) > new Date()) {
      return json({ error: "Too many attempts. Try again in 15 minutes or use Mobile OTP." }, 423);
    }
    if (!s.password_hash || !(await verifyPassword(password, s.password_hash))) {
      const failed = (s.failed_logins ?? 0) + 1;
      await db.from("student").update({
        failed_logins: failed,
        locked_until: failed >= 5 ? new Date(Date.now() + 15 * 60_000).toISOString() : null,
      }).eq("id", s.id);
      return bad();
    }
    await db.from("student").update({ failed_logins: 0, locked_until: null }).eq("id", s.id);

    // students linked on this device: the one signing in + any already linked (validated to exist)
    const ids = new Set<string>([s.id]);
    for (const id of (Array.isArray(link_to) ? link_to : [])) if (typeof id === "string") ids.add(id);
    const { data: students } = await db.from("student")
      .select("id, admission_no, full_name, enrolment!inner(section:section_id(name, grade:grade_id(code,name)), academic_year!inner(is_current))")
      .in("id", [...ids]).eq("enrolment.academic_year.is_current", true);

    const list = (students ?? []).map((x: any) => ({
      id: x.id, admission_no: x.admission_no, full_name: x.full_name,
      grade: x.enrolment?.[0]?.section?.grade?.name, grade_code: x.enrolment?.[0]?.section?.grade?.code,
      section: x.enrolment?.[0]?.section?.name,
    }));
    const studentIds = list.map((x: any) => x.id);

    const { data: sess } = await db.from("app_session")
      .insert({ student_id: s.id, linked_student_ids: studentIds, device_label: device_label ?? null }).select("id").single();

    const token = await mintToken({ sub: s.id, kind: "student", student_ids: studentIds, sid: sess?.id });
    await audit(db, { actor_student_id: s.id, action: "login.password", entity: "app_session", entity_id: sess?.id });

    return json({ token, students: list, must_change_password: !!s.must_change_password, session_id: sess?.id });
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
