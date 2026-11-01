import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../auth/session.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'password_requests.dart';
import 'staff_data.dart';
import 'staff_shell.dart';
import 'students_page.dart' show openStudentRecord;

/// Approvals — one list of everything waiting for me, one badge number in the menu.
///   • Password help (class teacher: own class; office: all)
///   • Receipts to cancel (only the Principal / IT decide)
///   • Leave requests (class teacher: own class; office: all)
///   • Certificates still to give (office)

/// The number on the menu badge.
final approvalsCountProvider = Provider.autoDispose<int>((ref) {
  final m = ref.watch(approvalsInboxProvider).value;
  if (m == null) return 0;
  return ['passwords', 'cancels', 'leaves', 'certificates'].fold<int>(0, (a, k) => a + ((m[k] as List?)?.length ?? 0));
});

String _msg(Object e) => e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');
String _dmy(String? iso) => iso == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());
String _dm(String? iso) => iso == null ? '' : DateFormat('d MMM').format(DateTime.parse(iso).toLocal());

class StaffApprovalsScreen extends ConsumerWidget {
  const StaffApprovalsScreen({super.key});

  void _refresh(WidgetRef ref) { ref.invalidate(approvalsInboxProvider); ref.invalidate(staffLeavesProvider); ref.invalidate(staffOverviewProvider); }

  Future<void> _leave(BuildContext context, WidgetRef ref, String id, bool ok) async {
    try { await decideLeave(ref, id, ok); _refresh(ref); if (context.mounted) toast(context, ok ? 'Leave approved ✓' : 'Leave declined.'); }
    catch (e) { if (context.mounted) toast(context, _msg(e)); }
  }

  Future<void> _receipt(BuildContext context, WidgetRef ref, Map<String, dynamic> k, bool cancel) async {
    final sure = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(cancel ? 'Cancel receipt ${k['receipt_no']}?' : 'Keep receipt ${k['receipt_no']}?'),
      content: Text(cancel
          ? '${k['student']} · ${inr(k['amount'] as num)}\nReason: ${k['reason']}\n\nThe receipt becomes cancelled and the fees it paid are open again. This is written in the activity log.'
          : 'The receipt stays as it is. ${k['asked_by'] ?? 'Accounts'} will be told.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(cancel ? 'Yes, cancel it' : 'Keep it'))],
    ));
    if (sure != true) return;
    try {
      await db.rpc('receipt_cancel_decide', params: {'p_request': k['id'], 'p_approve': cancel});
      _refresh(ref);
      if (context.mounted) toast(context, cancel ? 'Receipt ${k['receipt_no']} cancelled.' : 'Receipt kept.');
    } catch (e) { if (context.mounted) toast(context, _msg(e)); }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value!;
    final cs = Theme.of(context).colorScheme;
    final inbox = ref.watch(approvalsInboxProvider);
    return StaffPage(title: 'Approvals', subtitle: 'Everything waiting for you, in one place.', body: inbox.when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(_msg(e), style: const TextStyle(color: Brand.crimsonDeep))),
      data: (m) {
        final pw = inboxList(m, 'passwords'), rc = inboxList(m, 'cancels'), lv = inboxList(m, 'leaves'), ce = inboxList(m, 'certificates');
        if (pw.isEmpty && rc.isEmpty && lv.isEmpty && ce.isEmpty) {
          return Panel(child: Row(children: [
            Icon(Icons.check_circle_rounded, color: context.tone(Brand.green)), const SizedBox(width: 10),
            const Expanded(child: Text('Nothing waiting for you ✓', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          ]));
        }
        Widget sub(String t) => Text(t, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (pw.isNotEmpty) Panel(title: 'Password help (${pw.length})', child: Column(children: [for (final st in pw) PasswordRequestRow(st)])),
          if (rc.isNotEmpty) Panel(title: 'Receipts to cancel (${rc.length})', child: Column(children: [
            for (final k in rc) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: CardRow(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${k['receipt_no']} · ${k['student']}${(k['class'] ?? '').toString().isNotEmpty ? ' · ${k['class']}' : ''} · ${inr(k['amount'] as num)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                sub('Paid ${_dmy(k['paid_at'])} (${k['mode']}) · asked by ${k['asked_by'] ?? '—'} on ${_dm(k['asked_at'])}'),
                Text('Reason: ${k['reason']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ])),
              if (s.hasRole('principal') || s.hasRole('it_admin')) ...[
                TextButton(onPressed: () => _receipt(context, ref, k, false), child: const Text('Keep')),
                FilledButton(onPressed: () => _receipt(context, ref, k, true), style: FilledButton.styleFrom(backgroundColor: Brand.crimson, foregroundColor: Colors.white), child: const Text('Cancel receipt')),
              ],
            ])),
          ])),
          if (lv.isNotEmpty) Panel(title: 'Leave requests (${lv.length})', child: Column(children: [
            for (final l in lv) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: CardRow(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${l['student']}${(l['class'] ?? '').toString().isNotEmpty ? ' · ${l['class']}' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                sub('${l['from_date'] == l['to_date'] ? _dmy(l['from_date']) : '${_dm(l['from_date'])} – ${_dmy(l['to_date'])}'} · ${l['reason']}${l['note'] != null ? ' — ${l['note']}' : ''}'),
              ])),
              TextButton(onPressed: () => _leave(context, ref, l['id'], false), child: const Text('Decline', style: TextStyle(color: Brand.crimson, fontWeight: FontWeight.w800))),
              FilledButton(onPressed: () => _leave(context, ref, l['id'], true), child: const Text('Approve')),
            ])),
          ])),
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
        ]);
      },
    ));
  }
}
