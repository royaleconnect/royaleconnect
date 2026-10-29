// POST /functions/v1/password   — all password operations in one place
//  { action:'change', student_id, new_password, current_password? }   (bearer: student token; current_password not needed right after OTP login or first sign-in)
//  { action:'reset',  student_id, via:'print'|'sms' }                  (bearer: staff token with office/it_admin/class_teacher role)
//  { action:'signout_all', student_id }                                (bearer: staff token as above, or the student's own token)
//  { action:'crew_account', route_id, role:'driver'|'conductor' (= bus assistant), name, phone? }   (bearer: transport in-charge / office / IT / principal)
//      creates or refreshes the bus crew login for that route: login ID dr<route no.> / as<route no.>, the common bus password
//  { action:'crew_password', password }   (same people) → one common password for every driver and bus assistant (not case-sensitive)
//  { action:'bulk_first_use' | 'bulk_first_use_staff', ids:[…≤60] }   → first-use passwords for people who never signed in (Excel import slips)
//  { action:'view_as', student_id }   (bearer: IT admin / principal / vice principal) → a 2-hour READ-ONLY family token (the database refuses every change)
import { admin, json, preflight, hashPassword, verifyPassword, firstUsePassword, audit, mintToken } from "../_shared/lib.ts";
import { verify } from "https://deno.land/x/djwt@v3.0.2/mod.ts";
// the class to show: a section that is not open yet shows as "to be announced" (null)
const secName = (s: any) => (!s || s.placeholder || s.status === "planned" || s.status === "ready") ? null : s.name;


async function claims(req: Request) {
  const h = req.headers.get("authorization") ?? "";
  const tok = h.replace(/^Bearer\s+/i, "");
  if (!tok) return null;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(Deno.env.get("APP_JWT_SECRET")!), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  try { return await verify(tok, key) as any; } catch { return null; }
}

Deno.serve(async (req) => {
  const pf = preflight(req); if (pf) return pf;
  try {
    const c = await claims(req);
    if (!c) return json({ error: "Please sign in again." }, 401);
    if (c.view_only) return json({ error: "This is a read-only view." }, 403);
    const body = await req.json();
    const db = admin();
    const minLen = Number((await db.from("school_setting").select("value").eq("key", "password_min_length").maybeSingle()).data?.value ?? 8);
    const isOffice = Array.isArray(c.roles) && ["office", "it_admin", "principal", "vice_principal"].some((r) => c.roles.includes(r));
    const isClassTeacher = Array.isArray(c.roles) && c.roles.includes("class_teacher");

    if (body.action === "change_staff") {
      // a staff member changes their own password
      if (!c.staff_id) return json({ error: "Not allowed." }, 403);
      const pw = String(body.new_password ?? "");
      if (pw.length < minLen) return json({ error: `Use at least ${minLen} characters.` }, 400);
      const { data: st } = await db.from("staff").select("password_hash, must_change_password").eq("id", c.staff_id).single();
      if (!st.must_change_password && body.current_password !== undefined && !(await verifyPassword(String(body.current_password), st.password_hash))) return json({ error: "Current password is incorrect." }, 401);
      await db.from("staff").update({ password_hash: await hashPassword(pw), password_set_at: new Date().toISOString(), must_change_password: false }).eq("id", c.staff_id);
      await audit(db, { actor_staff_id: c.staff_id, action: "password.change.staff" });
      return json({ ok: true });
    }

    if (body.action === "reset_staff") {
      // IT / principal resets a colleague's password → one-time password returned for the slip
      if (!(c.roles ?? []).some((r: string) => ["it_admin", "principal"].includes(r))) return json({ error: "Not allowed." }, 403);
      const temp = firstUsePassword();
      await db.from("staff").update({ password_hash: await hashPassword(temp), must_change_password: true, failed_logins: 0, locked_until: null }).eq("id", body.staff_id);
      await db.from("app_session").update({ revoked_at: new Date().toISOString() }).eq("staff_id", body.staff_id).is("revoked_at", null);
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
    // the common bus password lives in app_secret (no app can read that table); default "Bus1"
    const crewPassword = async () => (await db.from("app_secret").select("value").eq("name", "crew_password").maybeSingle()).data?.value ?? "Bus1";

    if (body.action === "crew_password") {
      if (!canCrew) return json({ error: "Not allowed." }, 403);
      const pw = String(body.password ?? "").trim();
      if (pw.length < 4 || /\s/.test(pw)) return json({ error: "Use at least 4 letters or numbers, no spaces." }, 400);
      await db.from("app_secret").upsert({ name: "crew_password", value: pw });
      const hash = await hashPassword(pw.toLowerCase());
      const { data: crew } = await db.from("staff").select("id").overlaps("roles", ["driver", "conductor"]);
      const ids = (crew ?? []).map((x: any) => x.id);
      if (ids.length) await db.from("staff").update({ password_hash: hash, failed_logins: 0, locked_until: null }).in("id", ids);
      await audit(db, { actor_staff_id: c.staff_id, action: "crew.password", detail: { accounts: ids.length } });
      return json({ ok: true, updated: ids.length });
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
      const pw = await crewPassword();
      const fields = { username, full_name: name, display_name: name, phone: String(body.phone ?? "").trim() || null, roles: [role], password_hash: await hashPassword(pw.toLowerCase()),
                       must_change_password: false, failed_logins: 0, locked_until: null, active: true };
      if (staffId) {
        const { error } = await db.from("staff").update(fields).eq("id", staffId);
        if (error) throw error;
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
      if (!(c.student_ids ?? []).includes(body.student_id)) return json({ error: "Not allowed." }, 403);
      const pw = String(body.new_password ?? "");
      if (pw.length < minLen) return json({ error: `Use at least ${minLen} characters.` }, 400);
      const { data: s } = await db.from("student").select("password_hash, must_change_password, admission_no").eq("id", body.student_id).single();
      // require the current password unless this is the forced first change, or the token came from OTP (kind 'student' with no password proof is still fine — OTP proved the phone)
      if (!s.must_change_password && c.via !== "otp" && body.current_password !== undefined) {
        if (!(await verifyPassword(String(body.current_password), s.password_hash))) return json({ error: "Current password is incorrect." }, 401);
      }
      if (pw.toUpperCase().replace(/\s+/g, "") === s.admission_no) return json({ error: "The password cannot be the admission number." }, 400);
      await db.from("student").update({ password_hash: await hashPassword(pw), password_set_at: new Date().toISOString(), must_change_password: false, first_login_done: true }).eq("id", body.student_id);
      await audit(db, { actor_student_id: body.student_id, action: "password.change" });
      return json({ ok: true });
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
      await db.from("app_session").update({ revoked_at: new Date().toISOString() }).eq("student_id", body.student_id).is("revoked_at", null);
      await db.from("password_slip").insert({ student_id: body.student_id, issued_by: c.staff_id, delivered_via: body.via ?? "print" });
      await audit(db, { actor_staff_id: c.staff_id, action: "password.reset", entity: "student", entity_id: body.student_id, detail: { via: body.via ?? "print" } });
      // returned once, for the slip; never stored in clear
      return json({ ok: true, first_use_password: temp });
    }

    if (body.action === "signout_all") {
      const own = (c.student_ids ?? []).includes(body.student_id);
      if (!own && !isOffice && !isClassTeacher) return json({ error: "Not allowed." }, 403);
      await db.from("app_session").update({ revoked_at: new Date().toISOString() }).eq("student_id", body.student_id).is("revoked_at", null);
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

    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
