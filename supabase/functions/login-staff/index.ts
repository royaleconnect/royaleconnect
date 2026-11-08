// POST /functions/v1/login-staff   { email, password, device_label? }
//   email = school email (staff)  → { token, staff:{id, name, email, roles, division}, must_change_password }
//   email = bus login ID, no "@" (driver dr7 / bus assistant as7) → { token, kind:"crew", crew:{staff_id, name, role, route, bus}, must_change_password }
// Staff tokens carry staff_id + roles (30 days). Bus crew tokens carry crew_id + roles and NO staff_id (30 days), so the
// database never treats a driver as staff. must_change_password = true → a "choose your password first" token
// (pwd_change_required): the database refuses everything until the password service has saved the new password.
// Limits: 5 wrong passwords for one account → 15 minutes' pause; 20 wrong tries from one network address in 15 minutes → pause.
import { admin, json, preflight, verifyPassword, mintToken, audit, clientIp, LIFETIME } from "../_shared/lib.ts";

Deno.serve(async (req) => {
  const pf = preflight(req); if (pf) return pf;
  try {
    const { email, password, device_label } = await req.json();
    const em = String(email ?? "").trim().toLowerCase();
    if (!em || !password) return json({ error: "Enter your school email (or bus login ID) and password." }, 400);
    const crewLogin = !em.includes("@");
    const db = admin();
    const ip = clientIp(req);
    if ((await db.rpc("login_ip_blocked", { p_ip: ip })).data === true) {
      return json({ error: "Too many attempts from this network. Please wait 15 minutes and try again." }, 429);
    }
    const { data: s } = await db.from("staff").select("id, email, full_name, display_name, roles, division, password_hash, must_change_password, failed_logins, locked_until, active").eq(crewLogin ? "username" : "email", em).maybeSingle();
    const bad = async () => {
      await db.rpc("login_ip_fail", { p_ip: ip });
      return json({ error: crewLogin ? "That login ID and password don't match." : "That email and password don't match." }, 401);
    };
    if (!s || !s.active) return await bad();
    const isCrew = (s.roles ?? []).some((r: string) => r === "driver" || r === "conductor");
    if (crewLogin && !isCrew) return await bad();
    if (s.locked_until && new Date(s.locked_until) > new Date()) return json({ error: "Too many attempts. Try again in 15 minutes." }, 423);
    // bus crew passwords are not case-sensitive (stored in small letters)
    const okPw = !!s.password_hash && ((await verifyPassword(password, s.password_hash)) || (isCrew && await verifyPassword(String(password).toLowerCase(), s.password_hash)));
    if (!okPw) {
      const failed = (s.locked_until ? 0 : (s.failed_logins ?? 0)) + 1;   // a pause that has ended starts the count again
      await db.from("staff").update({ failed_logins: failed, locked_until: failed >= 5 ? new Date(Date.now() + 15 * 60_000).toISOString() : null }).eq("id", s.id);
      return await bad();
    }
    await db.from("staff").update({ failed_logins: 0, locked_until: null }).eq("id", s.id);
    const { data: sess } = await db.from("app_session").insert({ staff_id: s.id, device_label: device_label ?? null }).select("id").single();
    const mustChange = !!s.must_change_password;
    const limited = mustChange ? { pwd_change_required: true } : {};
    if (crewLogin) {
      // bus crew: Start / End trip only
      const { data: route } = await db.from("route").select("name, bus_reg_no").or(`driver_staff_id.eq.${s.id},conductor_staff_id.eq.${s.id}`).eq("active", true).limit(1).maybeSingle();
      const token = await mintToken({ sub: s.id, kind: "crew", crew_id: s.id, roles: s.roles, sid: sess?.id, ...limited }, LIFETIME.crew);
      await audit(db, { actor_staff_id: s.id, action: "login.crew", entity: "app_session", entity_id: sess?.id });
      return json({ token, kind: "crew", must_change_password: mustChange,
                    crew: { staff_id: s.id, name: s.display_name || s.full_name, role: s.roles.includes("driver") ? "Driver" : "Bus assistant", route: route?.name, bus: route?.bus_reg_no } });
    }
    const token = await mintToken({ sub: s.id, kind: "staff", staff_id: s.id, roles: s.roles, sid: sess?.id, ...limited }, LIFETIME.staff);
    await audit(db, { actor_staff_id: s.id, action: "login.staff", entity: "app_session", entity_id: sess?.id });
    return json({ token, staff: { id: s.id, name: s.display_name || s.full_name, email: s.email, roles: s.roles, division: s.division }, must_change_password: mustChange });
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong. Please try again." }, 500);
  }
});
