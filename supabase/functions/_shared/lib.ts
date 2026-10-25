// Shared helpers for Royale Connect edge functions (Supabase / Deno).
// deno-lint-ignore-file no-explicit-any
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { create as jwtCreate, verify as jwtVerify, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

export const env = (k: string): string => {
  const v = Deno.env.get(k);
  if (!v) throw new Error(`Missing env ${k}`);
  return v;
};

/** Server-side client (bypasses RLS). Only ever used inside functions, never shipped to the app. */
export const admin = () => createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });

export const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...cors, ...extra } });

export const cors: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

export const preflight = (req: Request) => (req.method === "OPTIONS" ? new Response("ok", { headers: cors }) : null);

/** Normalise an Indian mobile: strip spaces, +91, leading 0 → 10 digits. */
export const normPhone = (s: string) => {
  const d = (s || "").replace(/\D/g, "");
  return d.length > 10 ? d.slice(-10) : d;
};

/** Admission numbers are case-insensitive and stored upper-case: 'lk/10/2014' → 'LK/10/2014'. */
export const normAdmission = (s: string) => (s || "").trim().toUpperCase().replace(/\s+/g, "");

/**
 * Mint the app session token. It is a standard Supabase-compatible JWT signed with the project's JWT secret,
 * so PostgREST + RLS accept it. Claims:
 *   role=authenticated, sub=<primary id>, student_ids=[...], staff_id, roles=[...], kind='student'|'staff'
 */
export async function mintToken(claims: Record<string, unknown>, hours = 24 * 365) {
  const secret = env("SUPABASE_JWT_SECRET");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
  return await jwtCreate({ alg: "HS256", typ: "JWT" }, {
    aud: "authenticated",
    role: "authenticated",
    iss: "royale-connect",
    iat: getNumericDate(0),
    exp: getNumericDate(hours * 3600),
    ...claims,
  }, key);
}

/** Password hashing with PBKDF2 (WebCrypto, available in Deno). Stored as pbkdf2$<iterations>$<salt>$<hash>. */
export async function hashPassword(pw: string, iterations = 120_000) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const hash = await pbkdf2(pw, salt, iterations);
  return `pbkdf2$${iterations}$${b64(salt)}$${b64(hash)}`;
}
export async function verifyPassword(pw: string, stored: string) {
  const [scheme, it, salt, hash] = (stored || "").split("$");
  if (scheme !== "pbkdf2") return false;
  const calc = await pbkdf2(pw, unb64(salt), Number(it));
  return timingSafeEqual(calc, unb64(hash));
}
async function pbkdf2(pw: string, salt: Uint8Array, iterations: number) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(pw), "PBKDF2", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "PBKDF2", salt, iterations, hash: "SHA-256" }, key, 256);
  return new Uint8Array(bits);
}
const b64 = (u: Uint8Array) => btoa(String.fromCharCode(...u));
const unb64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
function timingSafeEqual(a: Uint8Array, b: Uint8Array) {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a[i] ^ b[i];
  return r === 0;
}

/** First-use password printed on the slip: 2 letters + 6 digits, no ambiguous characters. */
export function firstUsePassword() {
  const L = "ABCDEFGHJKMNPQRSTUVWXYZ", D = "23456789";
  const pick = (s: string) => s[crypto.getRandomValues(new Uint32Array(1))[0] % s.length];
  return pick(L) + pick(L) + Array.from({ length: 6 }, () => pick(D)).join("");
}

export async function audit(db: any, row: { actor_staff_id?: string; actor_student_id?: string; action: string; entity?: string; entity_id?: string; detail?: unknown }) {
  await db.from("audit_log").insert(row);
}

/** Read and verify the app session token from the Authorization header. Returns the claims or null. */
export async function verifyToken(req: Request): Promise<any | null> {
  const tok = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!tok) return null;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env("SUPABASE_JWT_SECRET")), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  try { return await jwtVerify(tok, key) as any; } catch { return null; }
}

/** HMAC-SHA256 hex, used for Razorpay signature checks. */
export async function hmacHex(secret: string, data: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
