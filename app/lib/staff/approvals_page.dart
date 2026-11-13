import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_extras.dart' show ShimmerPage;
import 'password_requests.dart';
import 'staff_shell.dart';
import 'students_page.dart' show openStudentRecord;
import 'deletion_requests.dart';
import '../auth/staff_first_passwords.dart';

/// Approvals — only what needs a decision, one badge number in the menu.
///   Principal (VP sees them too): receipt cancellations · TC requests · data corrections (name, date of birth, parents' names)
///   Office / IT: password help for every class · certificates still to give
///   Leave requests are NOT here: they have their own page (class teacher).
///   Anyone who asked for a receipt cancellation sees what happened to it.

/// The number on the menu badge (only things this person can act on).
final approvalsCountProvider = Provider.autoDispose<int>((ref) {
  final m = ref.watch(approvalsInboxProvider).value;
  if (m == null) return 0;
  final decide = m['can_decide'] == true;
  final leavings = decide ? (ref.watch(leavingsInboxProvider).value?.length ?? 0) : 0;
  return leavings + [...['passwords', 'certificates'], if (decide) ...['cancels', 'tcs', 'corrections']]
      .fold<int>(0, (a, k) => a + ((m[k] as List?)?.length ?? 0));
});

/// Students leaving (Inactive): waiting for the Principal. The office sees its own requests, waiting.
final leavingsInboxProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.watch(approvalsInboxProvider);
  try { return [for (final x in (await db.rpc('approvals_inbox_leavings')) as List? ?? const []) Map<String, dynamic>.from(x as Map)]; }
  catch (_) { return const []; }
});

String _dmy(String? iso) => iso == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());
String _dm(String? iso) => iso == null ? '' : DateFormat('d MMM').format(DateTime.parse(iso).toLocal());

class StaffApprovalsScreen extends ConsumerWidget {
  const StaffApprovalsScreen({super.key});

  void _refresh(WidgetRef ref) { ref.invalidate(approvalsInboxProvider); ref.invalidate(leavingsInboxProvider); }

  Future<void> _leaving(BuildContext context, WidgetRef ref, Map<String, dynamic> r, bool approve) async {
    final note = TextEditingController();
    final due = ((r['dues'] ?? 0) as num);
    final sure = await _confirm(context, approve: approve, note: note,
      title: '${approve ? 'Approve' : 'Decline'} · ${r['student']} is leaving',
      body: approve
          ? '${r['reason']} · last day ${_dmy(r['last_day'])}${due > 0 ? '\nFees still due: ${inr(due)} — approving lets the student leave with these unpaid.' : ''}\n\n'
            'The student moves to Past students, future fees are cancelled${r['has_tc'] == true ? ' and the TC gets its number' : ''}. Nothing is deleted.'
          : 'The student stays as they are. The office is told.');
    if (sure != true) return;
    try {
      final res = await db.rpc('leaving_decide', params: {'p_id': r['id'], 'p_approve': approve, 'p_note': note.text.trim().isEmpty ? null : note.text.trim()});
      _refresh(ref);
      final n = res is Map ? res['number'] : null;
      if (context.mounted) toast(context, '${approve ? 'Approved' : 'Declined'} ✓ · ${r['student']}${n != null ? ' · TC $n' : ''} — office told');
    } catch (e) { if (context.mounted) toast(context, friendlyError(e)); }
  }

  /// Approve / Decline with a short check first. [note] = a line for the person who asked (decline only).
  Future<bool?> _confirm(BuildContext context, {required String title, required String body, required bool approve, TextEditingController? note}) => showDialog<bool>(context: context, builder: (c) => AlertDialog(
    title: Text(title),
    content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(body),
      if (!approve && note != null) Padding(padding: const EdgeInsets.only(top: 12), child: TextField(controller: note, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'A line for the office (optional)'))),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
      FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(approve ? 'Approve' : 'Decline'))],
  ));

  Future<void> _receipt(BuildContext context, WidgetRef ref, Map<String, dynamic> k, bool cancel) async {
    final note = TextEditingController();
    final sure = await _confirm(context, approve: cancel, note: note,
      title: cancel ? 'Cancel receipt ${k['receipt_no']}?' : 'Keep receipt ${k['receipt_no']}?',
      body: cancel
          ? '${k['student']} · ${inr(k['amount'] as num)}\nReason: ${k['reason']}\n\nThe receipt becomes cancelled and the fees it paid are open again. This is written in the activity log.'
          : 'The receipt stays as it is. ${k['asked_by'] ?? 'Accounts'} will be told.');
    if (sure != true) return;
    try {
      await db.rpc('receipt_cancel_decide', params: {'p_request': k['id'], 'p_approve': cancel, 'p_note': note.text.trim().isEmpty ? null : note.text.trim()});
      _refresh(ref);
      if (context.mounted) toast(context, '${cancel ? 'Approved' : 'Declined'} ✓ · ${k['receipt_no']} — ${k['asked_by'] ?? 'Accounts'} told');
    } catch (e) { if (context.mounted) toast(context, friendlyError(e)); }
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, Map<String, dynamic> r, bool approve, {required String what, required String body}) async {
    final note = TextEditingController();
    final sure = await _confirm(context, approve: approve, note: note, title: '${approve ? 'Approve' : 'Decline'} · $what', body: body);
    if (sure != true) return;
    try {
      final res = await db.rpc('approval_decide', params: {'p_id': r['id'], 'p_approve': approve, 'p_note': note.text.trim().isEmpty ? null : note.text.trim()});
      _refresh(ref);
      final num = res is Map ? res['number'] : null;
      if (context.mounted) toast(context, '${approve ? 'Approved' : 'Declined'} ✓ · ${r['student']}${num != null ? ' · $num' : ''} — office told');
    } catch (e) { if (context.mounted) toast(context, friendlyError(e)); }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(sessionProvider);
    final cs = Theme.of(context).colorScheme;
    final inbox = ref.watch(approvalsInboxProvider);
    return StaffPage(title: 'Approvals', subtitle: 'Only what needs your decision.', body: inbox.when(
      loading: () => const ShimmerPage(),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e), style: const TextStyle(color: Brand.crimsonDeep))),
      data: (m) {
        final decide = m['can_decide'] == true;
        final rc = inboxList(m, 'cancels'), tc = inboxList(m, 'tcs'), dc = inboxList(m, 'corrections');
        final pw = inboxList(m, 'passwords'), ce = inboxList(m, 'certificates'), mine = inboxList(m, 'my_cancels');
        final lv = ref.watch(leavingsInboxProvider).value ?? const <Map<String, dynamic>>[];
        final waiting = rc.length + tc.length + dc.length + pw.length + ce.length + (decide ? lv.length : 0);
        Widget sub(String t) => Text(t, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant));
        // one card per request: what it is (pill), the details, then Approve / Decline
        Widget card({required String head, required String kind, required Color fg, required Color bg, required List<Widget> lines, VoidCallback? onApprove, VoidCallback? onDecline}) =>
          Panel(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(head, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              const SizedBox(width: 8), Pill(kind, fg: fg, bg: bg),
            ]),
            const SizedBox(height: 6), ...lines,
            if (onApprove != null) Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
              OutlinedButton(onPressed: onDecline, child: const Text('Decline')),
              FilledButton(onPressed: onApprove, child: const Text('Approve')),
            ]))
            else if (!decide) Padding(padding: const EdgeInsets.only(top: 8), child: sub('Waiting for the Principal.')),
          ]));

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (waiting == 0) Panel(child: Column(children: [
            const Text('✨', style: TextStyle(fontSize: 34)),
            const Text('All done', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Nothing needs your decision.', style: TextStyle(color: cs.onSurfaceVariant)),
          ]))
          else Padding(padding: const EdgeInsets.fromLTRB(2, 0, 2, 8), child: sub('$waiting waiting${decide || pw.isNotEmpty || ce.isNotEmpty ? ' for you' : ''}')),
          for (final k in rc) card(
            head: '${k['receipt_no']} · ${inr(k['amount'] as num)}', kind: 'Receipt cancellation', fg: Brand.crimsonDeep, bg: Brand.crimsonTint,
            lines: [
              sub('Asked by ${k['asked_by'] ?? 'Accounts'} on ${_dm(k['asked_at'])} · ${k['student']}${(k['class'] ?? '').toString().isNotEmpty ? ', ${k['class']}' : ''} · paid ${_dmy(k['paid_at'])} (${k['mode']})'),
              Text('Reason: ${k['reason']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
            onApprove: decide ? () => _receipt(context, ref, k, true) : null, onDecline: decide ? () => _receipt(context, ref, k, false) : null),
          for (final r in lv) card(
            head: '${r['student']}${(r['class'] ?? '').toString().isNotEmpty ? ' · ${r['class']}' : ''} is leaving', kind: 'Inactive · leaving', fg: Brand.violet, bg: Brand.violetTint,
            lines: [
              sub([if (r['reason'] != null) '${r['reason']}', 'last day ${_dmy(r['last_day'])}', ((r['dues'] ?? 0) as num) > 0 ? 'Fees due: ${inr(r['dues'] as num)}' : 'No dues ✓',
                if (r['has_tc'] == true) 'TC prepared'].join(' · ')),
              sub('Asked by ${r['asked_by'] ?? 'the office'} on ${_dm(r['asked_at'])}'),
              Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => openStudentRecord(context, r['student_id']).then((_) => _refresh(ref)), child: const Text('Open the student'))),
            ],
            onApprove: decide ? () => _leaving(context, ref, r, true) : null, onDecline: decide ? () => _leaving(context, ref, r, false) : null),
          for (final r in tc) card(
            head: '${r['student']}${(r['class'] ?? '').toString().isNotEmpty ? ' · ${r['class']}' : ''}', kind: 'TC request', fg: Brand.blue, bg: Brand.blueTint,
            lines: [
              sub([if ((r['reason'] ?? r['leaving_reason']) != null) '${r['reason'] ?? r['leaving_reason']}', ((r['dues'] ?? 0) as num) > 0 ? 'Fees due: ${inr(r['dues'] as num)}' : 'No dues ✓', 'Office has filled the TC'].join(' · ')),
              sub('Asked by ${r['asked_by'] ?? 'the office'} on ${_dm(r['asked_at'])}'),
            ],
            onApprove: decide ? () => _decide(context, ref, r, true, what: 'TC · ${r['student']}', body: 'The TC gets its number now and is kept. The office prints it from Certificates.') : null,
            onDecline: decide ? () => _decide(context, ref, r, false, what: 'TC · ${r['student']}', body: 'The TC is not issued. The office is told.') : null),
          for (final r in dc) Builder(builder: (_) {
            final ch = [for (final x in (r['changes'] as List?) ?? const []) Map<String, dynamic>.from(x as Map)];
            String v(dynamic x) => x == null ? '—' : RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('$x') ? DateFormat('dd-MM-yyyy').format(DateTime.parse('$x')) : '$x';
            final what = ch.map((c) => c['field']).join(', ');
            return card(
              head: '$what · ${r['student']}', kind: 'Data correction', fg: Brand.amber, bg: Brand.amberTint,
              lines: [
                for (final c in ch) Text('${c['field']}: ${v(c['from'])} → ${v(c['to'])}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                sub('Asked by ${r['asked_by'] ?? 'the office'} on ${_dm(r['asked_at'])}${r['reason'] != null ? ' · ${r['reason']}' : ''}'),
              ],
              onApprove: decide ? () => _decide(context, ref, r, true, what: '$what · ${r['student']}', body: 'The record is changed now and the change is written in the activity log.') : null,
              onDecline: decide ? () => _decide(context, ref, r, false, what: '$what · ${r['student']}', body: 'Nothing is changed. The office is told.') : null);
          }),
          const DeletionRequestsPanel(),
          if (ref.watch(sessionProvider).value?.hasRole('it_admin') ?? false) const StaffFirstPasswordsPanel(),
          if (pw.isNotEmpty) Panel(title: 'Password help (${pw.length})', child: Column(children: [for (final st in pw) PasswordRequestRow(st)])),
          if (ce.isNotEmpty) Panel(title: 'Certificates still to give (${ce.length})', child: Column(children: [
            for (final st in ce) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: CardRow(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${st['full_name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                sub([st['admission_no'], if (st['class'] != null) st['class'], 'left ${_dmy(st['left_on'])}',
                  'still to upload: ${[if (st['has_tc'] != true) 'TC', if (st['has_conduct'] != true) 'conduct certificate'].join(' and ')}'].join(' · ')),
              ])),
              OutlinedButton(onPressed: () => openStudentRecord(context, st['id']).then((_) => ref.invalidate(approvalsInboxProvider)), child: const Text('Open')),
            ])),
          ])),
          if (mine.isNotEmpty) MyReceiptCancels(rows: mine),
        ]);
      },
    ));
  }
}

/// "Receipt cancellations you asked for" — waiting / approved / not approved (Accounts see it on Today too).
class MyReceiptCancels extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const MyReceiptCancels({super.key, required this.rows});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Panel(title: 'Receipt cancellations you asked for', child: Column(children: [
      for (final k in rows) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: CardRow(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${k['receipt_no']} · ${k['student']} · ${inr(k['amount'] as num)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text([
            'Asked ${_dm(k['asked_at'])}',
            if (k['decided_at'] != null) 'decided ${_dm(k['decided_at'])}',
            if (k['note'] != null) 'Note: ${k['note']}',
          ].join(' · '), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ])),
        const SizedBox(width: 8),
        switch (k['status']) {
          'approved' => const Pill('Cancelled ✓', fg: Brand.green, bg: Brand.greenTint),
          'rejected' => const Pill('Not approved', fg: Brand.crimsonDeep, bg: Brand.crimsonTint),
          _ => const Pill('Waiting for the Principal', fg: Brand.amber, bg: Brand.amberTint),
        },
      ])),
    ]));
  }
}
