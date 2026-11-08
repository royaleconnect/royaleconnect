// POST /functions/v1/password   — all password operations in one place
//  { action:'change', student_id, new_password, current_password }   (bearer: family token; current_password is not needed only while the
//      school's first password still has to be replaced — then the child who signed in is the one changed, whatever student_id says)
//  { action:'change_staff', new_password, current_password }         (bearer: staff or bus crew token; same rule for current_password)
//  { action:'reset',  student_id, via:'print'|'sms' }                  (bearer: staff token with office/it_admin/class_teacher role)
//  { action:'signout_all', student_id }                                (bearer: staff token as above, or the student's own token)
//  { action:'crew_account', route_id, role:'driver'|'conductor' (= bus assistant), name, phone? }   (bearer: transport in-charge / office / IT / principal)
//      creates or refreshes the bus crew login for that route: login ID dr<route no.> / as<route no.> and an own 6-digit first
//      password (changed at the first sign-in)
//  { action:'crew_password' }   → refused now: there is no common bus password any more
//  { action:'bulk_first_use' | 'bulk_first_use_staff', ids:[…≤60] }   → first-use passwords for people who never signed in (Excel import slips)
//  { action:'first_use_all_staff' }   (bearer: IT admin / principal) → an own first password for every real staff member who has not
//      chosen a password yet (bus crew and the caller excluded) → [{id, name, email, password}] for the slips
//  { action:'view_as', student_id }   (bearer: IT admin / principal / vice principal) → a 2-hour READ-ONLY family token (the database refuses every change)
import { admin, json, preflight, hashPassword, verifyPassword, firstUsePassword, audit, mintToken, liveClaims } from "../_shared/lib.ts";
// the class to show: a section that is not open yet shows as "to be announced" (null)
const secName = (s: any) => (!s || s.placeholder || s.status === "planned" || s.status === "ready") ? null : s.name;


// sample staff from the demo data (fixed ids) never get passwords from the bulk tools
const SAMPLE = "00000000-0000-0000-";
const crewFirstPassword = () => String(100000 + (crypto.getRandomValues(new Uint32Array(1))[0] % 900000));
const now = () => new Date().toISOString();
// sign out every other phone of this account (the phone asking stays signed in)
async function signOutOthers(db: any, col: "staff_id" | "student_id", id: string, keepSid?: string) {
  let q = db.from("app_session").update({ revoked_at: now() }).eq(col, id).is("revoked_at", null);
  if (keepSid) q = q.neq("id", keepSid);
  await q;
}

Deno.serve(async (req) => {
  const pf = preflight(req); if (pf) return pf;
  try {
    const c = await liveClaims(req, { allowPasswordChange: true });
    if (!c) return json({ error: "Please sign in again." }, 401);
    if (c.view_only) return json({ error: "This is a read-only view." }, 403);
    const body = await req.json();
    // a "choose your password first" sign-in may only do that
    if (c.pwd_change_pending && body.action !== "change" && body.action !== "change_staff") return json({ error: "Please choose your new password first." }, 403);
    const db = admin();
    const minLen = Number((await db.from("school_setting").select("value").eq("key", "password_min_length").maybeSingle()).data?.value ?? 8);
    // staff rights only for staff tokens (bus crew tokens carry crew_id, never staff_id)
    const roles: string[] = c.staff_id && Array.isArray(c.roles) ? c.roles : [];
    c.roles = roles;
    const isOffice = ["office", "it_admin", "principal", "vice_principal"].some((r) => roles.includes(r));
    const isClassTeacher = roles.includes("class_teacher");

    if (body.action === "change_staff") {
      // a staff member or a driver / bus assistant changes their own password
      const me: string | undefined = c.staff_id ?? c.crew_id ?? (c.kind === "crew" ? c.sub : undefined);
      if (!me) return json({ error: "Not allowed." }, 403);
      const { data: st } = await db.from("staff").select("password_hash, must_change_password, roles").eq("id", me).single();
      const crew = (st.roles ?? []).some((r: string) => r === "driver" || r === "conductor") && !c.staff_id;
      let pw = String(body.new_password ?? "");
      const need = crew ? 6 : minLen;
      if (pw.trim().length < need) return json({ error: `Use at least ${need} ${crew ? "letters or numbers" : "characters"}.` }, 400);
      if (crew) { pw = pw.trim().toLowerCase(); if (pw === "bus1") return json({ error: "Please choose a new password of your own." }, 400); }
      // the current password is needed, except while the school's first password still has to be replaced
      if (!st.must_change_password) {
        const cur = String(body.current_password ?? "");
        const ok = !!st.password_hash && ((await verifyPassword(cur, st.password_hash)) || (crew && await verifyPassword(cur.toLowerCase(), st.password_hash)));
        if (!ok) return json({ error: "Current password is incorrect." }, 401);
      }
      if (st.password_hash && await verifyPassword(pw, st.password_hash)) return json({ error: "Please choose a new password, not the one from the slip." }, 400);
      await db.from("staff").update({ password_hash: await hashPassword(pw), password_set_at: now(), must_change_password: false, failed_logins: 0, locked_until: null }).eq("id", me);
      await signOutOthers(db, "staff_id", me, c.sid);
      await audit(db, { actor_staff_id: me, action: crew ? "password.change.crew" : "password.change.staff" });
      return json({ ok: true });
    }

    if (body.action === "reset_staff") {
      // IT / principal resets a colleague's password → one-time password returned for the slip
      if (!(c.roles ?? []).some((r: string) => ["it_admin", "principal"].includes(r))) return json({ error: "Not allowed." }, 403);
      const temp = firstUsePassword();
      await db.from("staff").update({ password_hash: await hashPassword(temp), must_change_password: true, password_set_at: null, failed_logins: 0, locked_until: null }).eq("id", body.staff_id);
      await signOutOthers(db, "staff_id", body.staff_id);
      await audit(db, { actor_staff_id: c.staff_id, action: "password.reset.staff", entity: "staff", entity_id: body.staff_id });
      return json({ ok: true, first_use_password: temp });
    }

    if (body.action === "view_as") {
      if (!(c.roles ?? []).some((r: string) => ["it_admin", "principal", "vice_principal"].includes(r))) return json({ error: "Not allowed." }, 403);
      const { data: x } = await db.from("student")
        .select("id, admission_no, full_name, enrolment!inner(is_current, section:section_id(name, status, placeholder, grade:grade_id(code,name)))")
        .eq("id", body.student_id).eq("enrolment.is_current", true).maybeSingle();
      if (!x) return json({ error: "Student not found in this year's classes." }, 404);
      const e = (x as any).enrolment?.[0];
      const token = await mintToken({ sub: x.id, kind: "student", student_ids: [x.id], view_only: true, viewer: c.staff_id }, 2);
      await audit(db, { actor_staff_id: c.staff_id, action: "view_as.family", entity: "student", entity_id: x.id });
      return json({ token, students: [{ id: x.id, admission_no: x.admission_no, full_name: x.full_name, grade: e?.section?.grade?.name, grade_code: e?.section?.grade?.code, section: secName(e?.section) }] });
    }

    const canCrew = (c.roles ?? []).some((r: string) => ["transport_incharge", "office", "it_admin", "principal", "vice_principal"].includes(r));

    if (body.action === "crew_password") {
      // there is no common bus password any more: each driver / bus assistant gets an own first password
      return json({ error: "Each driver and bus assistant now gets an own first password. Use “New login” on the route to make one." }, 400);
    }

    if (body.action === "crew_account") {
      if (!canCrew) return json({ error: "Not allowed." }, 403);
      const role = body.role === "conductor" ? "conductor" : "driver";
      const name = String(body.name ?? "").trim();
      if (!name) return json({ error: "Enter the driver's / bus assistant's name." }, 400);
      const { data: route } = await db.from("route").select("id, name, driver_staff_id, conductor_staff_id").eq("id", body.route_id).maybeSingle();
      if (!route) return json({ error: "Route not found." }, 404);
      // login ID from the route number: Route 7 → dr7 (driver) / as7 (bus assistant)
      const no = (String(route.name).match(/\d+/)?.[0]) ?? String(route.name).toLowerCase().replace(/[^a-z0-9]/g, "");
      const username = `${role === "driver" ? "dr" : "as"}${no}`;
      const col = role === "driver" ? "driver_staff_id" : "conductor_staff_id";
      let staffId: string | null = (route as any)[col] ?? null;
      if (staffId) {
        // only reuse the current account if it is a pure crew account (never overwrite a teacher's login)
        const { data: cur } = await db.from("staff").select("roles").eq("id", staffId).maybeSingle();
        if (!cur || (cur.roles ?? []).some((r: string) => r !== "driver" && r !== "conductor")) staffId = null;
      }
      const { data: clash } = await db.from("staff").select("id").eq("username", username).maybeSingle();
      if (clash && clash.id !== staffId) {
        // the ID belongs to an old account of this route position: free it
        await db.from("staff").update({ username: null, active: false }).eq("id", clash.id);
      }
      const pw = crewFirstPassword();   // an own first password: changed at the first sign-in
      const fields = { username, full_name: name, display_name: name, phone: String(body.phone ?? "").trim() || null, roles: [role], password_hash: await hashPassword(pw, 20_000),
                       must_change_password: true, password_set_at: null, failed_logins: 0, locked_until: null, active: true };
      if (staffId) {
        const { error } = await db.from("staff").update(fields).eq("id", staffId);
        if (error) throw error;
        await signOutOthers(db, "staff_id", staffId);
      } else {
        const { data: ins, error } = await db.from("staff").insert({ ...fields, email: `${username}@bus.rcis.in` }).select("id").single();
        if (error) throw error;
        staffId = ins.id;
        await db.from("route").update({ [col]: staffId }).eq("id", route.id);
      }
      await audit(db, { actor_staff_id: c.staff_id, action: "crew.account", entity: "staff", entity_id: staffId!, detail: { route: route.name, role, username } });
      return json({ ok: true, username, password: pw, route: route.name, role });
    }

    if (body.action === "change") {
      if (c.staff_id || c.crew_id || !Array.isArray(c.student_ids)) return json({ error: "Not allowed." }, 403);
      // while the child who signed in still has the school's first password, that child is the one changed
      const target: string = c.pwd_change_pending ? c.sub : body.student_id;
      if (!c.student_ids.includes(target)) return json({ error: "Not allowed." }, 403);
      const pw = String(body.new_password ?? "");
      if (pw.length < minLen) return json({ error: `Use at least ${minLen} characters.` }, 400);
      const { data: s } = await db.from("student").select("password_hash, must_change_password, admission_no").eq("id", target).single();
      const { data: demo } = await db.rpc("_is_demo_student", { p_student: target });
      if (demo === true) return json({ error: "The demo family's password stays the same." }, 403);
      // the current password is needed, except while the school's first password still has to be replaced
      if (!s.must_change_password) {
        if (!s.password_hash || !(await verifyPassword(String(body.current_password ?? ""), s.password_hash))) return json({ error: "Current password is incorrect." }, 401);
      }
      if (pw.toUpperCase().replace(/\s+/g, "") === s.admission_no) return json({ error: "The password cannot be the admission number." }, 400);
      if (s.password_hash && await verifyPassword(pw, s.password_hash)) return json({ error: "Please choose a new password, not the one from the slip." }, 400);
      await db.from("student").update({ password_hash: await hashPassword(pw), password_set_at: now(), must_change_password: false, first_login_done: true, failed_logins: 0, locked_until: null }).eq("id", target);
      await signOutOthers(db, "student_id", target, c.sid);
      await audit(db, { actor_student_id: target, action: "password.change" });
      return json({ ok: true, student_id: target });
    }

    if (body.action === "reset") {
      if (!c.staff_id) return json({ error: "Staff only." }, 403);
      // class teacher: only for students in own section
      if (!isOffice) {
        if (!isClassTeacher) return json({ error: "Not allowed." }, 403);
        const { data: ok } = await db.from("enrolment").select("id, is_current, section:section_id!inner(class_teacher_id)")
          .eq("student_id", body.student_id).eq("section.class_teacher_id", c.staff_id).eq("is_current", true).maybeSingle();
        if (!ok) return json({ error: "You can reset passwords only for your own class." }, 403);
      }
      const temp = firstUsePassword();
      await db.from("student").update({ password_hash: await hashPassword(temp), must_change_password: true, failed_logins: 0, locked_until: null }).eq("id", body.student_id);
      await signOutOthers(db, "student_id", body.student_id);
      await db.from("password_slip").insert({ student_id: body.student_id, issued_by: c.staff_id, delivered_via: body.via ?? "print" });
      await audit(db, { actor_staff_id: c.staff_id, action: "password.reset", entity: "student", entity_id: body.student_id, detail: { via: body.via ?? "print" } });
      // returned once, for the slip; never stored in clear
      return json({ ok: true, first_use_password: temp });
    }

    if (body.action === "signout_all") {
      const own = (c.student_ids ?? []).includes(body.student_id);
      if (!own && !isOffice && !isClassTeacher) return json({ error: "Not allowed." }, 403);
      await signOutOthers(db, "student_id", body.student_id);
      await audit(db, { actor_staff_id: c.staff_id ?? null, actor_student_id: own ? body.student_id : null, action: "session.revoke_all", entity: "student", entity_id: body.student_id });
      return json({ ok: true });
    }

    if (body.action === "bulk_first_use" || body.action === "bulk_first_use_staff") {
      // after an Excel import: first-use passwords for many people at once, for the printed slips.
      // Only for people who have never signed in themselves, so families already using the app are never locked out.
      const staffKind = body.action === "bulk_first_use_staff";
      const allowed = staffKind ? (c.roles ?? []).some((r: string) => ["it_admin", "principal"].includes(r)) : isOffice;
      if (!allowed) return json({ error: "Not allowed." }, 403);
      const ids: string[] = Array.isArray(body.ids) ? body.ids.slice(0, 60) : [];
      if (!ids.length) return json({ ok: true, passwords: [] });
      const table = staffKind ? "staff" : "student";
      const { data: rows } = await db.from(table).select("id, password_set_at" + (staffKind ? "" : ", first_login_done")).in("id", ids);
      const out: { id: string; password?: string; skipped?: string }[] = [];
      for (const r of (rows ?? []) as any[]) {
        if (r.password_set_at || r.first_login_done) { out.push({ id: r.id, skipped: "already using the app" }); continue; }
        const temp = firstUsePassword();
        // first-use passwords must be changed at first sign-in, so a lighter hash keeps 2,000 slips quick
        await db.from(table).update({ password_hash: await hashPassword(temp, 20_000), must_change_password: true, failed_logins: 0, locked_until: null }).eq("id", r.id);
        out.push({ id: r.id, password: temp });
      }
      await audit(db, { actor_staff_id: c.staff_id, action: staffKind ? "password.bulk.staff" : "password.bulk", detail: { count: out.filter((x) => x.password).length } });
      return json({ ok: true, passwords: out });
    }

    if (body.action === "first_use_all_staff") {
      // every real staff member who has not chosen a password yet gets an own first password (replaces any shared one).
      // Bus crew (made in Transport), sample staff and the person asking are left out.
      if (!roles.some((r) => ["it_admin", "principal"].includes(r))) return json({ error: "Only IT or the Principal can do this." }, 403);
      const { data: rows } = await db.from("staff").select("id, email, full_name, display_name, roles").eq("active", true).is("password_set_at", null).order("full_name");
      const todo = ((rows ?? []) as any[]).filter((r) => !String(r.id).startsWith(SAMPLE) && r.id !== c.staff_id
        && !(r.roles ?? []).some((x: string) => x === "driver" || x === "conductor")).slice(0, 400);
      const out: { id: string; name: string; email: string; password: string }[] = [];
      for (const r of todo) {
        const temp = firstUsePassword();
        await db.from("staff").update({ password_hash: await hashPassword(temp, 20_000), must_change_password: true, failed_logins: 0, locked_until: null }).eq("id", r.id);
        await signOutOthers(db, "staff_id", r.id);
        out.push({ id: r.id, name: r.display_name || r.full_name, email: r.email, password: temp });
      }
      await audit(db, { actor_staff_id: c.staff_id, action: "password.first_use_all_staff", detail: { count: out.length } });
      return json({ ok: true, passwords: out });
    }

    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
