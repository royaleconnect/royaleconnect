// Scheduled daily at 06:05 IST (pg_cron → http call, or Supabase Scheduled Functions).
// 1. For every unpaid tuition/transport ledger row past due, make sure a late-fee ledger row exists and carries today's amount.
// 2. Queue fee reminders per the school's schedule (3 days before, due day, 3/6/10 days after).
// Idempotent: safe to run twice in a day.
// deno-lint-ignore-file no-explicit-any
import { admin, json } from "../_shared/lib.ts";
import { computeFees, reminderDue } from "../_shared/fee_engine.ts";

const IST = "Asia/Kolkata";
const todayIST = () => new Date().toLocaleDateString("en-CA", { timeZone: IST }); // YYYY-MM-DD

Deno.serve(async (req) => {
  // protect: only the scheduler (service key) may call
  if ((req.headers.get("authorization") ?? "") !== `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`) return json({ error: "forbidden" }, 403);
  const db = admin();
  const today = todayIST();

  const { data: year } = await db.from("academic_year").select("id").eq("is_current", true).single();
  const { data: rule } = await db.from("late_fee_rule").select("*").eq("academic_year_id", year.id).lte("effective_from", today).order("effective_from", { ascending: false }).limit(1).single();
  const { data: lateHead } = await db.from("fee_head").select("id").eq("kind", "late_fee").limit(1).single();
  const { data: setting } = await db.from("school_setting").select("value").eq("key", "fee_reminder_days").maybeSingle();
  const schedule = (setting?.value ?? "3,0,-3,-6,-10").split(",").map(Number);

  // all ledger rows for the year with their head kind
  const { data: rows } = await db.from("fee_ledger").select("id, student_id, title, amount, due_on, status, paid_on, parent_ledger_id, fee_head:fee_head_id(kind)").eq("academic_year_id", year.id);
  const byStudent = new Map<string, any[]>();
  for (const r of rows ?? []) {
    const k = r.fee_head?.kind ?? "other";
    const arr = byStudent.get(r.student_id) ?? [];
    arr.push({ ...r, kind: k, can_pay_early: true });
    byStudent.set(r.student_id, arr);
  }

  let lateUpserts = 0, reminders = 0;
  for (const [studentId, ledger] of byStudent) {
    const f = computeFees(ledger, { grace_days: rule.grace_days, per_day: Number(rule.per_day), cap: rule.cap == null ? null : Number(rule.cap), applies_to: rule.applies_to }, today);

    // (1) materialise late fees so receipts/reports can reference a real row
    for (const lf of f.items.filter((i: any) => i.kind === "late_fee")) {
      const existing = ledger.find((l: any) => l.kind === "late_fee" && l.parent_ledger_id === lf.parent_ledger_id);
      if (existing) {
        if (existing.status === "pending" && Number(existing.amount) !== lf.amount) {
          await db.from("fee_ledger").update({ amount: lf.amount, note: lf.sub }).eq("id", existing.id); lateUpserts++;
        }
      } else {
        await db.from("fee_ledger").insert({
          academic_year_id: year.id, student_id: studentId, fee_head_id: lateHead.id, title: lf.title, amount: lf.amount,
          due_on: lf.due_on, status: "pending", parent_ledger_id: lf.parent_ledger_id, note: lf.sub,
        }); lateUpserts++;
      }
    }

    // (2) reminders — one per installment per schedule day; skip late-fee rows (they ride along)
    for (const row of ledger.filter((l: any) => l.kind !== "late_fee")) {
      const r = reminderDue(row, today, schedule);
      if (!r) continue;
      const key = `fee:${row.id}:${today}`;
      const { data: dup } = await db.from("notification").select("id").eq("student_id", studentId).eq("deep_link", key).maybeSingle();
      if (dup) continue;
      await db.from("notification").insert({ student_id: studentId, kind: r.kind, title: r.title, body: r.body, deep_link: key, send_after: new Date().toISOString() });
      reminders++;
    }
  }
  return json({ ok: true, today, students: byStudent.size, late_fee_rows_written: lateUpserts, reminders_queued: reminders });
});
