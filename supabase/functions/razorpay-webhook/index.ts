// POST /functions/v1/razorpay-webhook   — called by Razorpay (payment.captured / payment.failed) AND by the app after Checkout
// Either way the signature is checked, then the payment is marked success, the ledger rows paid, a receipt number issued.
// Idempotent: a payment already marked success is left alone.
import { admin, json, preflight, hmacHex, env, verifyToken, audit } from "../_shared/lib.ts";

async function settle(db: any, paymentId: string, gatewayPaymentId: string, method: string | undefined, payload: unknown) {
  const { data: pay } = await db.from("payment").select("id,status,student_id,amount").eq("id", paymentId).single();
  if (!pay) return { error: "Unknown payment." };
  if (pay.status === "success") return { ok: true, receipt_no: (await db.from("payment").select("receipt_no").eq("id", paymentId).single()).data?.receipt_no };

  // receipt number from the per-year sequence
  const { data: year } = await db.from("academic_year").select("id,label").eq("is_current", true).single();
  const { data: seq } = await db.from("receipt_sequence").select("*").eq("academic_year_id", year.id).maybeSingle();
  const prefix = seq?.prefix ?? `RCIS/${year.label.replace("20", "").replace("-20", "-")}/`;
  const n = seq?.next_no ?? 1;
  const receipt_no = `${prefix}${String(n).padStart(5, "0")}`;
  await db.from("receipt_sequence").upsert({ academic_year_id: year.id, prefix, next_no: n + 1 });

  const mode = ({ upi: "upi", card: "card", netbanking: "netbanking", wallet: "wallet" } as Record<string, string>)[method ?? ""] ?? "other";
  const now = new Date().toISOString();
  await db.from("payment").update({ status: "success", mode, gateway_payment_id: gatewayPaymentId, receipt_no, paid_at: now, raw_payload: payload }).eq("id", paymentId);
  const { data: lines } = await db.from("payment_line").select("fee_ledger_id").eq("payment_id", paymentId);
  await db.from("fee_ledger").update({ status: "paid", paid_on: now.slice(0, 10), payment_id: paymentId }).in("id", lines.map((l: any) => l.fee_ledger_id));
  await db.from("notification").insert({ student_id: pay.student_id, title: "Payment received", body: `₹${Number(pay.amount).toLocaleString("en-IN")} received. Receipt ${receipt_no}.`, kind: "system", deep_link: `receipt/${paymentId}` });
  await audit(db, { actor_student_id: pay.student_id, action: "payment.success", entity: "payment", entity_id: paymentId, detail: { receipt_no, amount: pay.amount } });
  return { ok: true, receipt_no };
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
    const c = await verifyToken(req);
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
