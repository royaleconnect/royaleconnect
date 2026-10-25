// Runs every minute (scheduler). Sends pending push notifications through Firebase Cloud Messaging (HTTP v1).
// Rules: quiet hours 21:00–06:00 IST hold everything except urgent=true; Urgent uses a distinct channel/sound.
// Push tokens come from device_session.push_token (one row per phone). Dead tokens are cleared.
// Env: FCM_PROJECT_ID, FCM_SERVICE_ACCOUNT_JSON (Firebase service account; stored as a Supabase secret, never in the app)
// deno-lint-ignore-file no-explicit-any
import { admin, json } from "../_shared/lib.ts";
import { create as jwtCreate, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const IST = "Asia/Kolkata";
function istMinutes() { const p = new Intl.DateTimeFormat("en-GB", { timeZone: IST, hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(new Date()); const h = Number(p.find(x => x.type === "hour")!.value), m = Number(p.find(x => x.type === "minute")!.value); return h * 60 + m; }
function nextSixAmISO() { const d = new Date(); const dateIST = d.toLocaleDateString("en-CA", { timeZone: IST }); const six = new Date(`${dateIST}T06:00:00+05:30`); if (six <= d) six.setDate(six.getDate() + 1); return six.toISOString(); }

let cachedToken: { t: string; exp: number } | null = null;
async function fcmAccessToken() {
  if (cachedToken && cachedToken.exp > Date.now() + 60_000) return cachedToken.t;
  const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT_JSON")!);
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), c => c.charCodeAt(0)), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const assertion = await jwtCreate({ alg: "RS256", typ: "JWT" }, { iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: getNumericDate(0), exp: getNumericDate(3600) }, key);
  const r = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }) });
  const j = await r.json();
  cachedToken = { t: j.access_token, exp: Date.now() + (j.expires_in ?? 3600) * 1000 };
  return cachedToken.t;
}

Deno.serve(async (req) => {
  if ((req.headers.get("authorization") ?? "") !== `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`) return json({ error: "forbidden" }, 403);
  const db = admin();
  const { data: qs } = await db.from("school_setting").select("key,value").in("key", ["quiet_hours_start", "quiet_hours_end"]);
  const get = (k: string, d: string) => qs?.find((x: any) => x.key === k)?.value ?? d;
  const [qsH, qsM] = get("quiet_hours_start", "21:00").split(":").map(Number); const [qeH, qeM] = get("quiet_hours_end", "06:00").split(":").map(Number);
  const now = istMinutes(), qStart = qsH * 60 + qsM, qEnd = qeH * 60 + qeM;
  const quiet = qStart > qEnd ? (now >= qStart || now < qEnd) : (now >= qStart && now < qEnd);

  const { data: pending } = await db.from("notification").select("*").is("sent_at", null).lte("send_after", new Date().toISOString()).order("id").limit(500);
  if (!pending?.length) return json({ ok: true, sent: 0 });

  // quiet hours: push non-urgent back to 06:00 in one update
  if (quiet) {
    const hold = pending.filter((n: any) => !n.urgent).map((n: any) => n.id);
    if (hold.length) await db.from("notification").update({ send_after: nextSixAmISO() }).in("id", hold);
  }
  const toSend = quiet ? pending.filter((n: any) => n.urgent) : pending;
  if (!toSend.length) return json({ ok: true, sent: 0, held: pending.length });

  const token = await fcmAccessToken();
  const project = Deno.env.get("FCM_PROJECT_ID")!;
  let sent = 0, dead = 0;
  for (const n of toSend) {
    const q = db.from("device_session").select("id, push_token").is("revoked_at", null).not("push_token", "is", null);
    const { data: devices } = n.student_id ? await q.eq("student_id", n.student_id) : await q.eq("staff_id", n.staff_id);
    for (const d of devices ?? []) {
      const msg = {
        message: {
          token: d.push_token,
          notification: { title: n.title, body: n.body ?? "" },
          data: { deep_link: n.deep_link ?? "", kind: n.kind, urgent: String(!!n.urgent) },
          android: { priority: n.urgent ? "HIGH" : "NORMAL", notification: { channel_id: n.urgent ? "urgent" : "default", sound: n.urgent ? "urgent" : "default" } },
          apns: { payload: { aps: { sound: n.urgent ? "urgent.caf" : "default", "interruption-level": n.urgent ? "time-sensitive" : "active" } } },
        },
      };
      const r = await fetch(`https://fcm.googleapis.com/v1/projects/${project}/messages:send`, { method: "POST", headers: { authorization: `Bearer ${token}`, "content-type": "application/json" }, body: JSON.stringify(msg) });
      if (r.ok) sent++;
      else if (r.status === 404 || r.status === 410) { await db.from("device_session").update({ push_token: null }).eq("id", d.id); dead++; }
      else console.error("FCM", r.status, await r.text());
    }
    await db.from("notification").update({ sent_at: new Date().toISOString() }).eq("id", n.id);
  }
  return json({ ok: true, sent, dead_tokens_cleared: dead, quiet });
});
