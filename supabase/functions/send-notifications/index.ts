// Woken every minute by the database (job rc-push, only when something is waiting). Sends queued notifications
// through Firebase Cloud Messaging (HTTP v1).
// Rules: quiet hours 21:00–06:00 IST hold everything except urgent ones until 06:00.
//        One phone gets one copy of a whole-school notice even with two children on it.
//        With two or more children on a phone, the child's first name goes in front of personal notifications.
// Push tokens come from device_session.push_token (the app registers them). Dead tokens are cleared.
// Env: FCM_SERVICE_ACCOUNT_JSON (Firebase service account; a function secret, never in the app)
// deno-lint-ignore-file no-explicit-any
import { admin, isScheduler, json } from "../_shared/lib.ts";
import { create as jwtCreate, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const IST = "Asia/Kolkata";
const BATCH = 1500, PARALLEL = 25;
function istMinutes() { const p = new Intl.DateTimeFormat("en-GB", { timeZone: IST, hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(new Date()); const h = Number(p.find(x => x.type === "hour")!.value) % 24, m = Number(p.find(x => x.type === "minute")!.value); return h * 60 + m; }
function nextSixAmISO() { const d = new Date(); const dateIST = d.toLocaleDateString("en-CA", { timeZone: IST }); const six = new Date(`${dateIST}T06:00:00+05:30`); if (six <= d) six.setDate(six.getDate() + 1); return six.toISOString(); }
// the page a notification opens (same rules as the app's push.dart)
function routeFor(link: string | null, staff: boolean) {
  const l = (link ?? "").replace(/^\//, "");
  if (!l) return staff ? "/staff" : "/";
  if (l.startsWith("fee")) return "/fees";
  if (l.startsWith("chat/")) return staff ? "/staff/messages" : "/" + l;
  return "/" + l;
}
const WEB = (Deno.env.get("APP_WEB_URL") ?? "https://royaleconnect.github.io/royaleconnect").replace(/\/$/, "");
const chunks = <T>(a: T[], n: number) => Array.from({ length: Math.ceil(a.length / n) }, (_, i) => a.slice(i * n, i * n + n));

let sa: any = null;
let cachedToken: { t: string; exp: number } | null = null;
async function fcmAccessToken() {
  if (cachedToken && cachedToken.exp > Date.now() + 60_000) return cachedToken.t;
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), c => c.charCodeAt(0)), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const assertion = await jwtCreate({ alg: "RS256", typ: "JWT" }, { iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: getNumericDate(0), exp: getNumericDate(3600) }, key);
  const r = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }) });
  const j = await r.json();
  if (!j.access_token) throw new Error("Google sign-in for FCM failed: " + JSON.stringify(j));
  cachedToken = { t: j.access_token, exp: Date.now() + (j.expires_in ?? 3600) * 1000 };
  return cachedToken.t;
}

Deno.serve(async (req) => {
  if (!(await isScheduler(req))) return json({ error: "forbidden" }, 403);
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!raw) return json({ ok: false, error: "FCM_SERVICE_ACCOUNT_JSON not set" }, 500);
  sa ??= JSON.parse(raw);
  const db = admin();

  // ---- quiet hours
  const { data: qs } = await db.from("school_setting").select("key,value").in("key", ["quiet_hours_start", "quiet_hours_end"]);
  const get = (k: string, d: string) => qs?.find((x: any) => x.key === k)?.value ?? d;
  const [qsH, qsM] = get("quiet_hours_start", "21:00").split(":").map(Number); const [qeH, qeM] = get("quiet_hours_end", "06:00").split(":").map(Number);
  const now = istMinutes(), qStart = qsH * 60 + qsM, qEnd = qeH * 60 + qeM;
  const quiet = qStart > qEnd ? (now >= qStart || now < qEnd) : (now >= qStart && now < qEnd);
  if (quiet) await db.from("notification").update({ send_after: nextSixAmISO() }).is("sent_at", null).eq("urgent", false).lte("send_after", new Date().toISOString());

  // ---- take a batch (marked as sent in the same step, so an overlapping run can never double-send)
  const { data: batch, error } = await db.rpc("claim_notifications", { lim: BATCH, urgent_only: quiet });
  if (error) return json({ ok: false, error: error.message }, 500);
  if (!batch?.length) return json({ ok: true, sent: 0, quiet });

  // ---- phones for everyone in the batch
  const studentIds = [...new Set(batch.filter((n: any) => n.student_id).map((n: any) => n.student_id))] as string[];
  const staffIds = [...new Set(batch.filter((n: any) => n.staff_id).map((n: any) => n.staff_id))] as string[];
  const devices: any[] = [];
  for (const c of chunks(studentIds, 150)) { const { data } = await db.from("device_session").select("id,student_id,push_token,platform").in("student_id", c).is("revoked_at", null).not("push_token", "is", null); devices.push(...(data ?? [])); }
  for (const c of chunks(staffIds, 150)) { const { data } = await db.from("device_session").select("id,staff_id,push_token,platform").in("staff_id", c).is("revoked_at", null).not("push_token", "is", null); devices.push(...(data ?? [])); }
  const byStudent = new Map<string, any[]>(), byStaff = new Map<string, any[]>();
  const kidsOnToken = new Map<string, number>();
  for (const d of devices) {
    if (d.student_id) { byStudent.set(d.student_id, [...(byStudent.get(d.student_id) ?? []), d]); kidsOnToken.set(d.push_token, (kidsOnToken.get(d.push_token) ?? 0) + 1); }
    if (d.staff_id) byStaff.set(d.staff_id, [...(byStaff.get(d.staff_id) ?? []), d]);
  }
  // first names, for phones that carry two or more children
  const firstName = new Map<string, string>();
  const needNames = studentIds.filter(id => (byStudent.get(id) ?? []).some(d => (kidsOnToken.get(d.push_token) ?? 0) > 1));
  for (const c of chunks(needNames, 150)) { const { data } = await db.from("student").select("id,full_name").in("id", c); for (const s of data ?? []) firstName.set(s.id, String(s.full_name).trim().split(/\s+/)[0]); }

  // ---- build messages
  const shared = new Set(["announcement", "moment", "worksheet"]);   // same text for every child → one copy per phone
  const seen = new Set<string>();
  const out: { token: string; deviceId: string; body: any }[] = [];
  for (const n of batch) {
    const list = n.student_id ? byStudent.get(n.student_id) ?? [] : byStaff.get(n.staff_id) ?? [];
    for (const d of list) {
      const dedupe = shared.has(n.kind) ? `${d.push_token}|${n.kind}|${n.deep_link}|${n.title}` : `${d.push_token}|${n.id}`;
      if (seen.has(dedupe)) continue; seen.add(dedupe);
      const prefix = n.student_id && !shared.has(n.kind) && (kidsOnToken.get(d.push_token) ?? 0) > 1 && firstName.get(n.student_id) ? `${firstName.get(n.student_id)} · ` : "";
      out.push({
        token: d.push_token, deviceId: d.id,
        body: {
          message: {
            token: d.push_token,
            notification: { title: prefix + n.title, body: n.body ?? "" },
            data: { deep_link: n.deep_link ?? "", kind: n.kind, urgent: String(!!n.urgent), student_id: n.student_id ?? "", notification_id: String(n.id) },
            android: { priority: "HIGH", notification: { tag: `${n.kind}-${n.id}`, default_sound: true } },
            ...(d.platform === "web" ? { webpush: { fcm_options: { link: WEB + routeFor(n.deep_link, !n.student_id) } } } : {}),
            apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default", ...(n.urgent ? { "interruption-level": "time-sensitive" } : {}) } } },
          },
        },
      });
    }
  }

  // ---- send, 25 at a time
  const token = await fcmAccessToken();
  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  let sent = 0, failed = 0; const dead: string[] = [];
  for (const group of chunks(out, PARALLEL)) {
    await Promise.all(group.map(async (m) => {
      try {
        const r = await fetch(url, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify(m.body) });
        if (r.ok) { sent++; await r.body?.cancel(); return; }
        const t = await r.text();
        if (r.status === 404 || (r.status === 400 && /UNREGISTERED|registration-token-not-registered|INVALID_ARGUMENT.*token/i.test(t))) dead.push(m.token);
        else { failed++; console.error("FCM", r.status, t.slice(0, 300)); }
      } catch (e) { failed++; console.error("FCM fetch", String(e)); }
    }));
  }
  for (const c of chunks([...new Set(dead)], 100)) await db.from("device_session").update({ push_token: null }).in("push_token", c);
  return json({ ok: true, notifications: batch.length, pushes: out.length, sent, failed, dead_tokens_cleared: dead.length, quiet });
});
