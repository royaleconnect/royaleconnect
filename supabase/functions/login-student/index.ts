// POST /functions/v1/login-student
// body: { admission_no, password, device_label?, link_to?: string[] }
//   link_to = student ids already on this phone (add-a-sibling). They are kept ONLY when the request also carries the phone's
//   current, still-valid sign-in (Authorization: Bearer <token>) and those ids are already in it. Anything else is dropped,
//   so nobody can add a child they never proved (each child is proved by its own admission number + password).
// returns: { token, students:[{id,admission_no,full_name,grade,section}], must_change_password, session_id }
//   must_change_password = true → the token is a "choose your password first" token (pwd_change_required): the database
//   refuses everything until the password service has saved the new password.
// Limits: 5 wrong passwords for one admission number → 15 minutes' pause; 20 wrong tries from one network address in 15 minutes → pause.
import { admin, json, preflight, normAdmission, verifyPassword, mintToken, audit, liveClaims, clientIp, LIFETIME } from "../_shared/lib.ts";
// the class to show: a section that is not open yet shows as "to be announced" (null)
const secName = (s: any) => (!s || s.placeholder || s.status === "planned" || s.status === "ready") ? null : s.name;

Deno.serve(async (req) => {
  const pf = preflight(req); if (pf) return pf;
  try {
    const { admission_no, password, device_label, link_to } = await req.json();
    const adm = normAdmission(admission_no);
    if (!adm || !password) return json({ error: "Enter the admission number and password." }, 400);

    const db = admin();
    const ip = clientIp(req);
    if ((await db.rpc("login_ip_blocked", { p_ip: ip })).data === true) {
      return json({ error: "Too many attempts from this network. Please wait 15 minutes and try again." }, 429);
    }
    const { data: s } = await db.from("student")
      .select("id, admission_no, full_name, password_hash, must_change_password, failed_logins, locked_until, active, tc_issued_on")
      .eq("admission_no", adm).maybeSingle();

    // same message for unknown id and wrong password — never reveal which
    const bad = async () => { await db.rpc("login_ip_fail", { p_ip: ip }); return json({ error: "That admission number and password don't match. Check the slip from the school." }, 401); };
    if (!s || !s.active) return await bad();
    if (s.locked_until && new Date(s.locked_until) > new Date()) return json({ error: "Too many attempts. Try again in 15 minutes." }, 423);
    if (!s.password_hash || !(await verifyPassword(password, s.password_hash))) {
      // a pause that has ended starts the count again
      const failed = (s.locked_until ? 0 : (s.failed_logins ?? 0)) + 1;
      await db.from("student").update({
        failed_logins: failed,
        locked_until: failed >= 5 ? new Date(Date.now() + 15 * 60_000).toISOString() : null,
      }).eq("id", s.id);
      return await bad();
    }
    await db.from("student").update({ failed_logins: 0, locked_until: null }).eq("id", s.id);

    // children on this phone: the one signing in + brothers/sisters already proved on this phone (in its valid sign-in)
    const ids = new Set<string>([s.id]);
    const asked = (Array.isArray(link_to) ? link_to : []).filter((x: unknown) => typeof x === "string") as string[];
    if (asked.length) {
      const cur = await liveClaims(req);
      const proved = new Set<string>(cur && !cur.view_only && Array.isArray(cur.student_ids) ? cur.student_ids : []);
      for (const id of asked) if (proved.has(id)) ids.add(id);
    }
    const { data: students } = await db.from("student")
      .select("id, admission_no, full_name, enrolment!inner(is_current, section:section_id(name, status, placeholder, grade:grade_id(code,name)))")
      .in("id", [...ids]).eq("active", true).eq("enrolment.is_current", true);

    const list = (students ?? []).map((x: any) => ({
      id: x.id, admission_no: x.admission_no, full_name: x.full_name,
      grade: x.enrolment?.[0]?.section?.grade?.name, grade_code: x.enrolment?.[0]?.section?.grade?.code,
      section: secName(x.enrolment?.[0]?.section),
    }));
    const studentIds = list.map((x: any) => x.id);
    if (!studentIds.includes(s.id)) studentIds.unshift(s.id);

    const { data: sess } = await db.from("app_session")
      .insert({ student_id: s.id, linked_student_ids: studentIds, device_label: device_label ?? null }).select("id").single();

    const { data: demo } = await db.rpc("_is_demo_student", { p_student: s.id });
    const mustChange = !!s.must_change_password && demo !== true;
    const token = await mintToken({ sub: s.id, kind: "student", student_ids: studentIds, sid: sess?.id, ...(mustChange ? { pwd_change_required: true } : {}) }, LIFETIME.family);
    await audit(db, { actor_student_id: s.id, action: "login.password", entity: "app_session", entity_id: sess?.id });

    return json({ token, students: list, must_change_password: mustChange, session_id: sess?.id });
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
