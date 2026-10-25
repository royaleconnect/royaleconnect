const assert = require('assert');
const { computeFees, buildSelection, reminderDue } = require('./fee_engine');

// Aarav, Grade VIII, 2026-27 — mirrors the prototype
const ledger = [
  { id: 'i1', title: 'Tuition — Installment 1', kind: 'tuition', amount: 40000, due_on: '2026-04-05', status: 'paid', paid_on: '2026-04-02' },
  { id: 'i2', title: 'Tuition — Installment 2', kind: 'tuition', amount: 28000, due_on: '2026-06-05', status: 'paid', paid_on: '2026-06-04' },
  { id: 't1', title: 'Transport — Term 1', kind: 'transport', amount: 16500, due_on: '2026-06-05', status: 'paid', paid_on: '2026-06-04' },
  { id: 'i3', title: 'Tuition — Installment 3', kind: 'tuition', amount: 15700, due_on: '2026-10-17', status: 'pending' },
  { id: 't2', title: 'Transport — Term 2', kind: 'transport', amount: 16500, due_on: '2026-11-05', status: 'pending' },
  { id: 'i4', title: 'Tuition — Installment 4', kind: 'tuition', amount: 11000, due_on: '2026-12-05', status: 'pending' },
];
const rule = { grace_days: 0, per_day: 100, cap: null, applies_to: ['tuition', 'transport'] };

// 1. On 24 Oct: i3 is 7 days late → ₹700 late fee, rides with i3
let f = computeFees(ledger, rule, '2026-10-24');
assert.strictEqual(f.lateFees.length, 1);
assert.strictEqual(f.lateFees[0].amount, 700);
assert.strictEqual(f.lateFees[0].parent_ledger_id, 'i3');
assert.deepStrictEqual(f.overdue.map(i => i.id).sort(), ['i3', 'late:i3']);
assert.deepStrictEqual(f.dueSoon.map(i => i.id), ['t2']);          // 12 days away
assert.deepStrictEqual(f.upcoming.map(i => i.id), ['i4']);         // 42 days away
assert.strictEqual(f.balance, 15700 + 700 + 16500 + 11000);
assert.strictEqual(f.total, 40000 + 28000 + 16500 + 15700 + 700 + 16500 + 11000);
console.log('1 ok  late fee', f.lateFees[0].amount, 'balance', f.balance, 'pct', f.pct);

// 2. Selection: overdue mandatory; picking t2 adds it; picking the late fee alone is ignored
let s = buildSelection(f, []);
assert.deepStrictEqual(s.rows.map(i => i.id).sort(), ['i3', 'late:i3']); assert.strictEqual(s.total, 16400);
s = buildSelection(f, ['t2']);
assert.strictEqual(s.total, 16400 + 16500);
s = buildSelection(f, ['late:i3']);
assert.strictEqual(s.total, 16400);
console.log('2 ok  selection totals');

// 3. On the due date itself: no late fee
f = computeFees(ledger, rule, '2026-10-17');
assert.strictEqual(f.lateFees.length, 0);
assert.strictEqual(f.overdue.length, 0);
console.log('3 ok  no fee on due date');

// 4. Grace days: 5 days grace → on 20 Oct still nothing, on 24 Oct only 2 days charged
f = computeFees(ledger, { ...rule, grace_days: 5 }, '2026-10-20');
assert.strictEqual(f.lateFees.length, 0);
f = computeFees(ledger, { ...rule, grace_days: 5 }, '2026-10-24');
assert.strictEqual(f.lateFees[0].amount, 200);
console.log('4 ok  grace days');

// 5. Cap: ₹1,000 cap → 30 days late gives 1,000 not 3,000
f = computeFees(ledger, { ...rule, cap: 1000 }, '2026-11-16');
assert.strictEqual(f.lateFees.find(l => l.parent_ledger_id === 'i3').amount, 1000);
console.log('5 ok  cap');

// 6. Late fee freezes when the installment is paid: i3 paid on 24 Oct → on 30 Nov the fee is still ₹700
const paidLedger = ledger.map(r => r.id === 'i3' ? { ...r, status: 'paid', paid_on: '2026-10-24' } : r)
  .concat([{ id: 'lf3', title: 'Late fee — Installment 3', kind: 'late_fee', amount: 700, due_on: '2026-10-17', status: 'paid', paid_on: '2026-10-24', parent_ledger_id: 'i3' }]);
f = computeFees(paidLedger, rule, '2026-11-30');
const lf = f.items.find(i => i.parent_ledger_id === 'i3');
assert.strictEqual(lf.amount, 700); assert.strictEqual(lf.status, 'paid');
// and t2 is now overdue by 25 days → ₹2,500
assert.strictEqual(f.lateFees.find(l => l.parent_ledger_id === 't2').amount, 2500);
console.log('6 ok  frozen after payment; new late fee on t2 =', 2500);

// 7. Waived installment never accrues
f = computeFees(ledger.map(r => r.id === 'i3' ? { ...r, status: 'waived' } : r), rule, '2026-11-30');
assert.ok(!f.lateFees.find(l => l.parent_ledger_id === 'i3'));
console.log('7 ok  waived');

// 8. Reminders: 3 days before, on the day, 3/6/10 days after
assert.strictEqual(reminderDue(ledger[4], '2026-11-02').title, 'Fee due in 3 days');
assert.strictEqual(reminderDue(ledger[4], '2026-11-05').title, 'Fee due today');
assert.strictEqual(reminderDue(ledger[4], '2026-11-08').kind, 'fee_overdue');
assert.strictEqual(reminderDue(ledger[4], '2026-11-09'), null);
console.log('8 ok  reminder schedule');

console.log('\nall fee engine tests passed');
