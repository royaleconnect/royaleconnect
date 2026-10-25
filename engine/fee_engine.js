/**
 * Fee engine — the single source of truth for what a family owes on a given day.
 *
 * Rules agreed with the school (Oct 2026):
 *  - Installments have a due date. After it, a late fee accrues at ₹X/day (default ₹100), no cap unless set.
 *  - The late fee is a separate ledger line that RIDES WITH its installment: it can only be paid together
 *    with that installment, and it stops accruing on the day the installment is paid.
 *  - Partial payment of an installment is not allowed.
 *  - Future installments may be paid early.
 *  - Overdue items must be included in any payment; the parent chooses which other items to add.
 *
 * The same code runs in the server job (nightly accrual + reminders) and in the app (preview),
 * so the number on the parent's screen and the number on the receipt can never disagree.
 */

const DAY = 86400000;

function toDate(d) { return d instanceof Date ? d : new Date(d + 'T00:00:00+05:30'); }
function daysBetween(a, b) { return Math.floor((toDate(b).getTime() - toDate(a).getTime()) / DAY); }

/**
 * @param {object[]} ledger  rows from fee_ledger for one student & year
 *   { id, title, amount, due_on, status:'pending'|'paid'|'waived'|'cancelled', paid_on, parent_ledger_id, kind, can_pay_early }
 * @param {object} rule      { grace_days, per_day, cap, applies_to:[kinds] }
 * @param {string|Date} today
 * @returns {{ items, overdue, dueSoon, upcoming, paid, balance, total, pct, lateFees }}
 */
function computeFees(ledger, rule, today) {
  const t = toDate(today);
  const r = Object.assign({ grace_days: 0, per_day: 100, cap: null, applies_to: ['tuition', 'transport'] }, rule || {});

  // 1. Late fees are derived, never stored as truth: recompute for every unpaid applicable installment.
  const derivedLate = [];
  for (const row of ledger) {
    if (row.kind === 'late_fee') continue;
    if (!r.applies_to.includes(row.kind)) continue;
    if (row.status === 'waived' || row.status === 'cancelled') continue;

    const endDate = row.status === 'paid' && row.paid_on ? toDate(row.paid_on) : t;
    const lateDays = daysBetween(row.due_on, endDate) - r.grace_days;
    if (lateDays <= 0) continue;

    let fee = lateDays * r.per_day;
    if (r.cap != null) fee = Math.min(fee, r.cap);

    // if a stored late-fee row already exists for this installment, reuse its id/status
    const stored = ledger.find(l => l.kind === 'late_fee' && l.parent_ledger_id === row.id);
    derivedLate.push({
      id: stored ? stored.id : `late:${row.id}`,
      title: `Late fee — ${row.title.replace(/^Tuition — |^Transport — /, '')}`,
      sub: `₹${r.per_day} × ${lateDays} day${lateDays === 1 ? '' : 's'} late`,
      amount: fee,
      due_on: row.due_on,
      kind: 'late_fee',
      parent_ledger_id: row.id,
      status: stored && stored.status === 'paid' ? 'paid' : (row.status === 'paid' ? 'pending' : 'pending'),
      paid_on: stored ? stored.paid_on : null,
      locked: true,            // cannot be deselected; rides with parent
      lateDays
    });
  }

  const items = ledger.filter(l => l.kind !== 'late_fee').map(l => ({ ...l, locked: false })).concat(derivedLate);

  // 2. Buckets
  const unpaid = items.filter(i => i.status === 'pending');
  const isOverdue = i => daysBetween(i.due_on, t) > 0;
  const daysLeft = i => -daysBetween(i.due_on, t);

  const overdue = unpaid.filter(isOverdue);
  const dueSoon = unpaid.filter(i => !isOverdue(i) && daysLeft(i) <= 30);
  const upcoming = unpaid.filter(i => !isOverdue(i) && daysLeft(i) > 30);
  const paid = items.filter(i => i.status === 'paid');

  const sum = arr => arr.reduce((a, i) => a + Number(i.amount), 0);
  const total = sum(items.filter(i => i.status !== 'cancelled' && i.status !== 'waived'));
  const paidAmt = sum(paid);

  return {
    items, overdue, dueSoon, upcoming, paid, unpaid,
    total, paidAmount: paidAmt, balance: sum(unpaid),
    pct: total ? Math.round(paidAmt / total * 100) : 0,
    lateFees: derivedLate.filter(l => l.status === 'pending')
  };
}

/**
 * Build the payable selection the way the app does:
 *  - all overdue rows are mandatory (and their late fees come along)
 *  - the caller may add future rows (whole rows only)
 *  - toggling an installment toggles its late fee
 */
function buildSelection(fees, chosenIds) {
  const chosen = new Set(chosenIds || []);
  const sel = new Set();
  for (const i of fees.overdue) sel.add(i.id);
  for (const id of chosen) {
    const row = fees.unpaid.find(i => i.id === id);
    if (!row) continue;
    if (row.kind === 'late_fee') continue;                    // cannot pick a late fee alone
    if (row.can_pay_early === false && -daysBetween(row.due_on, new Date()) > 30) continue;
    sel.add(id);
  }
  // attach late fees of anything selected
  for (const i of fees.unpaid) if (i.kind === 'late_fee' && sel.has(i.parent_ledger_id)) sel.add(i.id);
  const rows = fees.unpaid.filter(i => sel.has(i.id));
  return { rows, total: rows.reduce((a, i) => a + Number(i.amount), 0) };
}

/** Nightly reminder schedule relative to due date: days before (positive) / after (negative) */
function reminderDue(ledgerRow, today, schedule = [3, 0, -3, -6, -10]) {
  if (ledgerRow.status !== 'pending') return null;
  const d = -daysBetween(ledgerRow.due_on, today);          // days until due (negative = overdue)
  if (!schedule.includes(d)) return null;
  if (d > 0) return { kind: 'fee_reminder', title: `Fee due in ${d} day${d === 1 ? '' : 's'}`, body: `${ledgerRow.title} · ₹${ledgerRow.amount} due ${ledgerRow.due_on}` };
  if (d === 0) return { kind: 'fee_reminder', title: 'Fee due today', body: `${ledgerRow.title} · ₹${ledgerRow.amount}` };
  return { kind: 'fee_overdue', title: `Fee overdue by ${-d} days`, body: `${ledgerRow.title} · late fee ₹${-d * 100} so far` };
}

module.exports = { computeFees, buildSelection, reminderDue, daysBetween };
