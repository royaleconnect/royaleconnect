import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/errors.dart';
import '../core/school_docs.dart' show PdfDocScreen;
import '../staff/class_logins.dart' show PasswordSlip, passwordSlipsPdf;
import '../staff/staff_data.dart' show callFunction;
import '../staff/staff_shell.dart' show Panel, toast;

/// IT / Principal: one button — every staff member who has not chosen a password yet gets an own first password,
/// printed as slips (10 per A4 page). Bus crew get theirs in Transport. Staff already using their own password are left alone.
Future<void> printAllStaffFirstPasswords(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
    title: const Text('Make first passwords for staff?'),
    content: const Text('Every staff member who has not yet chosen a password gets a new first password, printed on a slip. '
        'Any older first password stops working. Staff who already use their own password are not touched.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Make and print')),
    ],
  ));
  if (ok != true || !context.mounted) return;
  try {
    final r = await callFunction(ref, 'password', {'action': 'first_use_all_staff'});
    final slips = [
      for (final p in (r['passwords'] as List? ?? const []))
        PasswordSlip('${p['name'] ?? ''}', '${p['email'] ?? ''}', 'School staff', '${p['password']}'),
    ];
    if (!context.mounted) return;
    if (slips.isEmpty) { toast(context, 'Every staff member already uses their own password — no slips needed.'); return; }
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PdfDocScreen(
      title: 'Staff first passwords (${slips.length})',
      fileName: 'RCIS-staff-first-passwords.pdf',
      make: () => passwordSlipsPdf(slips, staff: true),
    )));
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
  }
}

/// A small panel for the IT settings page.
class StaffFirstPasswordsPanel extends ConsumerWidget {
  const StaffFirstPasswordsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Panel(
        title: 'First passwords for all staff',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Each staff member gets an own first password on a printed slip and chooses her own at the first sign-in.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: () => printAllStaffFirstPasswords(context, ref), icon: const Icon(Icons.key_rounded, size: 18), label: const Text('Make and print slips')),
        ]),
      );
}
