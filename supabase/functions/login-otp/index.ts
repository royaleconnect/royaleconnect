// POST /functions/v1/login-otp
//   { phone }                     → sends OTP. Returns { sent:true, kind:'student'|'crew'|'none' }
//   { phone, code, device_label } → verifies. Returns the same shape as login-student, or for crew:
//                                   { token, kind:'crew', crew:{name, role, route, bus} }
// SMS provider: set SMS_PROVIDER=msg91 and MSG91_AUTHKEY/MSG91_TEMPLATE_ID; without them (dev) the code is logged.
import { admin, json, preflight, normPhone, mintToken, hashPassword, verifyPassword, audit } from "../_shared/lib.ts";
// the class to show: a section that is not open yet shows as "to be announced" (null)
const secName = (s: any) => (!s || s.placeholder || s.status === "planned" || s.status === "ready") ? null : s.name;


async function sendSms(phone: string, code: string) {
  const provider = Deno.env.get("SMS_PROVIDER");
  if (provider === "msg91") {
    const r = await fetch("https://control.msg91.com/api/v5/otp?" + new URLSearchParams({
      template_id: Deno.env.get("MSG91_TEMPLATE_ID")!, mobile: "91" + phone, otp: code,
    }), { method: "POST", headers: { authkey: Deno.env.get("MSG91_AUTHKEY")! } });
    if (!r.ok) throw new Error("SMS send failed: " + (await r.text()));
    return;
  }
  console.log(`[dev] OTP for ${phone}: ${code}`);   // visible in Supabase function logs only
}

Deno.serve(async (req) => {
  const pf = preflight(req); if (pf) return pf;
  try {
    const body = await req.json();
    const phone = normPhone(body.phone);
    if (phone.length !== 10) return json({ error: "Enter a 10-digit mobile number." }, 400);
    const db = admin();

    // who is this number? parents' students, or a bus crew member
    const { data: fam } = await db.from("family_phone").select("student_id").eq("phone", phone);
    const { data: crew } = await db.from("staff").select("id, display_name, roles").eq("phone", phone).eq("active", true).maybeSingle();
    const isCrew = !!crew && (crew.roles?.includes("driver") || crew.roles?.includes("conductor"));
    const studentIds = (fam ?? []).map((f: any) => f.student_id);
    if (!studentIds.length && !isCrew) {
      return json({ error: "No student is registered with this number. Sign in with the admission number, or ask the office to add this number." }, 404);
    }

    // ---- step 1: send ----
    if (!body.code) {
      const { count } = await db.from("otp_code").select("*", { count: "exact", head: true })
        .eq("phone", phone).gt("created_at", new Date(Date.now() - 10 * 60_000).toISOString());
      if ((count ?? 0) >= 3) return json({ error: "Too many codes requested. Please wait 10 minutes." }, 429);
      const code = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, "0");
      await db.from("otp_code").insert({ phone, code_hash: await hashPassword(code, 20_000), expires_at: new Date(Date.now() + 5 * 60_000).toISOString() });
      await sendSms(phone, code);
      return json({ sent: true, kind: isCrew ? "crew" : "student" });
    }

    // ---- step 2: verify ----
    const { data: otp } = await db.from("otp_code").select("*").eq("phone", phone).is("used_at", null)
      .gt("expires_at", new Date().toISOString()).order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (!otp) return json({ error: "That code has expired. Request a new one." }, 401);
    if (otp.attempts >= 5) return json({ error: "Too many wrong attempts. Request a new code." }, 429);
    if (!(await verifyPassword(String(body.code).trim(), otp.code_hash))) {
      await db.from("otp_code").update({ attempts: otp.attempts + 1 }).eq("id", otp.id);
      return json({ error: "That OTP is not correct." }, 401);
    }
    await db.from("otp_code").update({ used_at: new Date().toISOString() }).eq("id", otp.id);

    if (isCrew) {
      const { data: route } = await db.from("route").select("name, bus_reg_no")
        .or(`driver_staff_id.eq.${crew!.id},conductor_staff_id.eq.${crew!.id}`).eq("active", true).maybeSingle();
      const { data: sess } = await db.from("app_session").insert({ staff_id: crew!.id, device_label: body.device_label ?? null }).select("id").single();
      const token = await mintToken({ sub: crew!.id, kind: "crew", staff_id: crew!.id, roles: crew!.roles, sid: sess?.id });
      await audit(db, { actor_staff_id: crew!.id, action: "login.otp.crew", entity: "app_session", entity_id: sess?.id });
      return json({ token, kind: "crew", crew: { staff_id: crew!.id, name: crew!.display_name, role: crew!.roles.includes("driver") ? "Driver" : "Conductor", route: route?.name, bus: route?.bus_reg_no } });
    }

    const { data: students } = await db.from("student")
      .select("id, admission_no, full_name, must_change_password, enrolment!inner(is_current, section:section_id(name, status, placeholder, grade:grade_id(code,name)))")
      .in("id", studentIds).eq("active", true).eq("enrolment.is_current", true);
    const list = (students ?? []).map((x: any) => ({
      id: x.id, admission_no: x.admission_no, full_name: x.full_name,
      grade: x.enrolment?.[0]?.section?.grade?.name, grade_code: x.enrolment?.[0]?.section?.grade?.code, section: secName(x.enrolment?.[0]?.section),
    }));
    const ids = list.map((x: any) => x.id);
    const { data: sess } = await db.from("app_session").insert({ student_id: ids[0], linked_student_ids: ids, device_label: body.device_label ?? null }).select("id").single();
    const token = await mintToken({ sub: ids[0], kind: "student", student_ids: ids, sid: sess?.id });
    await audit(db, { actor_student_id: ids[0], action: "login.otp", entity: "app_session", entity_id: sess?.id, detail: { phone_last4: phone.slice(-4), count: ids.length } });
    // OTP login counts as identity proof: the family may set a new password from Settings without the old one
    return json({ token, kind: "student", students: list, must_change_password: false, session_id: sess?.id });
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
