// POST /functions/v1/razorpay-webhook   — called by Razorpay (payment.captured / payment.failed) AND by the app after Checkout
// Either way the signature is checked, then the payment is marked success, the ledger rows paid, a receipt number issued
// (all in one database step: settle_payment).
// Idempotent: a payment already marked success is left alone.
import { admin, json, preflight, hmacHex, env, liveClaims } from "../_shared/lib.ts";

// One database step (public.settle_payment) gives the receipt number, marks the payment and the fee rows paid, and tells the
// family — so two calls at the same moment (Razorpay + the app) can never take two numbers or half-finish.
async function settle(db: any, paymentId: string, gatewayPaymentId: string, method: string | undefined, payload: unknown) {
  const { data, error } = await db.rpc("settle_payment", { p_payment: paymentId, p_gateway_payment_id: gatewayPaymentId, p_method: method ?? null, p_payload: payload ?? null });
  if (error) { console.error("settle_payment", error.message); throw new Error(error.message); }
  return data;
}

Deno.serve(async (req) => {
  const pf = preflight(req); if (pf) return pf;
  const db = admin();
  try {
    const raw = await req.text();
    const rzSig = req.headers.get("x-razorpay-signature");

    if (rzSig) {
      // --- server-to-server webhook from Razorpay ---
      if (rzSig !== await hmacHex(env("RAZORPAY_WEBHOOK_SECRET"), raw)) return json({ error: "bad signature" }, 400);
      const ev = JSON.parse(raw);
      const p = ev.payload?.payment?.entity;
      if (!p) return json({ ok: true });
      // app orders are matched by order id; web payment links carry our payment_id in notes
      const byNote = p.notes?.payment_id ? (await db.from("payment").select("id").eq("id", p.notes.payment_id).maybeSingle()).data : null;
      const pay = byNote ?? (await db.from("payment").select("id").eq("gateway_order_id", p.order_id).maybeSingle()).data;
      if (!pay) return json({ ok: true });
      if (ev.event === "payment.captured") await settle(db, pay.id, p.id, p.method, ev);
      else if (ev.event === "payment.failed") await db.from("payment").update({ status: "failed", raw_payload: ev }).eq("id", pay.id).neq("status", "success");
      return json({ ok: true });
    }

    // --- app confirmation right after Checkout closes (bearer: student token) ---
    const c = await liveClaims(req);
    if (!c) return json({ error: "Please sign in again." }, 401);
    const { payment_id, razorpay_order_id, razorpay_payment_id, razorpay_signature } = JSON.parse(raw);
    const { data: pay } = await db.from("payment").select("id,student_id,gateway_order_id").eq("id", payment_id).single();
    if (!pay || !(c.student_ids ?? []).includes(pay.student_id) || pay.gateway_order_id !== razorpay_order_id) return json({ error: "Not allowed." }, 403);
    const expected = await hmacHex(env("RAZORPAY_KEY_SECRET"), `${razorpay_order_id}|${razorpay_payment_id}`);
    if (expected !== razorpay_signature) return json({ error: "Payment could not be verified. If money was deducted it will be reconciled automatically." }, 400);
    return json(await settle(db, payment_id, razorpay_payment_id, undefined, { via: "app" }));
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong." }, 500);
  }
});
