// POST /functions/v1/razorpay-order   (bearer: student token)
//  { student_id, fee_ledger_ids: [...] }
// Validates the selection with the fee engine (late fee rides with its installment, no partial payments),
// creates a Razorpay order for the exact amount, records a 'created' payment row, returns what the app needs to open Checkout.
import { admin, json, preflight, verifyToken, env, audit } from "../_shared/lib.ts";
import { computeFees, buildSelection } from "../_shared/fee_engine.ts";

Deno.serve(async (req) => {
  const pf = preflight(req); if (pf) return pf;
  try {
    const c = await verifyToken(req);
    if (!c) return json({ error: "Please sign in again." }, 401);
    if (!Deno.env.get("RAZORPAY_KEY_ID") || !Deno.env.get("RAZORPAY_KEY_SECRET")) {
      return json({ error: "Online payment is not switched on yet. Please pay at the school office." }, 503);
    }
    const { student_id, fee_ledger_ids, channel } = await req.json();   // channel: "app" (Razorpay SDK) | "web" (hosted payment link)
    if (!(c.student_ids ?? []).includes(student_id)) return json({ error: "Not allowed." }, 403);
    if (!Array.isArray(fee_ledger_ids) || fee_ledger_ids.length === 0) return json({ error: "Choose at least one item to pay." }, 400);

    const db = admin();
    const { data: year } = await db.from("academic_year").select("id,label").eq("is_current", true).single();
    const { data: ledger } = await db.from("fee_ledger").select("*").eq("student_id", student_id).eq("academic_year_id", year.id);
    const { data: rule } = await db.from("late_fee_rule").select("*").eq("academic_year_id", year.id).maybeSingle();
    const fees = computeFees(ledger ?? [], rule ?? {}, new Date());
    const sel = buildSelection(fees, fee_ledger_ids);           // adds overdue items + riding late fees; no partial amounts
    if (sel.rows.length === 0 || sel.total <= 0) return json({ error: "Nothing to pay." }, 400);
    const ids = sel.rows.map((r: any) => r.id);

    const { data: st } = await db.from("student").select("full_name, admission_no").eq("id", student_id).single();
    const keyId = env("RAZORPAY_KEY_ID"), keySecret = env("RAZORPAY_KEY_SECRET");
    const { data: pay } = await db.from("payment").insert({ student_id, amount: sel.total, mode: "other", status: "created", gateway: "razorpay" }).select("id").single();
    const headers = { "content-type": "application/json", authorization: "Basic " + btoa(`${keyId}:${keySecret}`) };
    const notes = { payment_id: pay.id, student_id, admission_no: st.admission_no, year: year.label, items: ids.join(",") };
    const paise = Math.round(sel.total * 100);
    const order = channel === "web"
      ? await fetch("https://api.razorpay.com/v1/payment_links", { method: "POST", headers, body: JSON.stringify({ amount: paise, currency: "INR", description: `${st.full_name} · ${year.label} fees`, reference_id: pay.id, notes,
          callback_url: `${(Deno.env.get("APP_WEB_URL") ?? "https://royaleconnect.github.io/royaleconnect").replace(/\/$/, "")}/#/pay/done?payment_id=${pay.id}`, callback_method: "get", notify: { sms: false, email: false } }) }).then((r) => r.json())
      : await fetch("https://api.razorpay.com/v1/orders", { method: "POST", headers, body: JSON.stringify({ amount: paise, currency: "INR", receipt: pay.id, notes }) }).then((r) => r.json());
    if (!order.id) { await db.from("payment").update({ status: "failed", raw_payload: order }).eq("id", pay.id); return json({ error: "Could not start the payment. Try again in a minute." }, 502); }

    await db.from("payment").update({ gateway_order_id: order.id }).eq("id", pay.id);
    await db.from("payment_line").insert(sel.rows.map((l: any) => ({ payment_id: pay.id, fee_ledger_id: l.id, amount: l.amount })));
    await audit(db, { actor_student_id: student_id, action: "payment.order", entity: "payment", entity_id: pay.id, detail: { amount: sel.total, items: ids } });

    return json({ payment_id: pay.id, order_id: order.id, url: order.short_url ?? null, key_id: keyId, amount: sel.total, currency: "INR",
      name: "Royale Concorde International School", description: `${st.full_name} · ${year.label} fees`, prefill: { name: st.full_name }, items: sel.rows });
  } catch (e) {
    console.error(e);
    return json({ error: "Something went wrong." }, 500);
  }
});
