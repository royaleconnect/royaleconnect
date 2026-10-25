// POST /functions/v1/password   — all password operations in one place
//  { action:'change', student_id, new_password, current_password? }   (bearer: student token; current_password not needed right after OTP login or first sign-in)
//  { action:'reset',  student_id, via:'print'|'sms' }                  (bearer: staff token with office/it_admin/class_teacher role)
//  { action:'signout_all', student_id }                                (bearer: staff token as above, or the student's own token)
import { admin, json, preflight, hashPassword, verifyPassword, firstUsePassword, audit } from "../_shared/lib.ts";
import { verify } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

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
        const { data: ok } = await db.from("enrolment").select("id, section:section_id!inner(class_teacher_id), academic_year!inner(is_current)")
          .eq("student_id", body.student_id).eq("section.class_teacher_id", c.staff_id).eq("academic_year.is_current", true).maybeSingle();
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

    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
