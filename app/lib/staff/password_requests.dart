import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/theme.dart';
import 'staff_shell.dart';
import 'class_logins.dart' show resetFirstPassword;

/// Everything waiting for this staff member, in one call (password help, receipts to cancel, leave, certificates).
/// The database decides what each person sees: class teachers their own class, the office everything,
/// receipt cancellations only the Principal / IT.
final approvalsInboxProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.cacheFor();
  final r = await db.rpc('approvals_inbox');
  return r == null ? const {} : Map<String, dynamic>.from(r as Map);
});

List<Map<String, dynamic>> inboxList(Map<String, dynamic>? m, String key) =>
    [for (final x in (m?[key] as List?) ?? const []) Map<String, dynamic>.from(x as Map)];


/// "Give new password": a new one-time password (same as Students → Reset password), the slip, and every
/// open request of this student is marked done (so the card clears for the teacher and the office).
Future<void> givePasswordSlip(BuildContext context, WidgetRef ref, Map<String, dynamic> st) async {
  // the same easy first password (e.g. ana@8919) and big read-out screen as Class logins
  final ok = await resetFirstPassword(context, ref, '${st['student_id']}', '${st['full_name'] ?? ''}');
  if (!ok) return;
  try { await db.rpc('password_request_done', params: {'p_student': st['student_id']}); } catch (_) {}
  ref.invalidate(approvalsInboxProvider);
}

/// One row of a password request (used on Today and in Approvals).
class PasswordRequestRow extends ConsumerWidget {
  final Map<String, dynamic> st;
  const PasswordRequestRow(this.st, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final at = st['first_at'] == null ? '' : DateFormat('d MMM, h:mm a').format(DateTime.parse(st['first_at']).toLocal());
    final times = (st['times'] ?? 1) as int;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: CardRow(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${st['full_name']}${(st['class'] ?? '').toString().isNotEmpty ? ' · ${st['class']}' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
        Text('${st['admission_no']} · asked from ${st['phone']} · $at${times > 1 ? ' · asked $times times' : ''}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ])),
      const SizedBox(width: 10),
      FilledButton.icon(onPressed: () => givePasswordSlip(context, ref, st), style: FilledButton.styleFrom(backgroundColor: Brand.crimson, foregroundColor: Colors.white),
          icon: const Icon(Icons.key_rounded, size: 18), label: const Text('Give new password')),
    ]));
  }
}

/// Red card on staff Today: families who asked for a new password (class teacher: own class; office: all).
/// Shows nothing when nobody is waiting.
class PasswordRequestsCard extends ConsumerWidget {
  const PasswordRequestsCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = inboxList(ref.watch(approvalsInboxProvider).value, 'passwords');
    if (rows.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Brand.crimson.withValues(alpha: .08), borderRadius: BorderRadius.circular(18), border: Border.all(color: Brand.crimson, width: 1.4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.lock_reset_rounded, color: context.tone(Brand.crimson)),
          const SizedBox(width: 10),
          Expanded(child: Text(rows.length == 1 ? 'A family is asking for a new password' : '${rows.length} families are asking for a new password',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface))),
        ]),
        const SizedBox(height: 4),
        Text('Tap “Give new password”, then send the slip to the family (or read it out on the phone).', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        for (final st in rows) PasswordRequestRow(st),
      ]),
    );
  }
}
