import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import 'staff_shell.dart';

/// Families who asked (Settings → Request account deletion) to delete their Royale Connect account.
/// The office (office, VP, Principal, IT) sees them, calls the family, and marks the request done.
final deletionRequestsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  final rows = await db.from('account_deletion_request')
      .select('id,note,requested_at,student:student_id(id,full_name,admission_no,family_phone(phone,label))')
      .eq('status', 'open').order('requested_at', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});

/// A panel for the Approvals page; shows nothing when there are no open requests.
class DeletionRequestsPanel extends ConsumerWidget {
  const DeletionRequestsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(deletionRequestsProvider).value ?? const [];
    if (list.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Panel(title: 'Account deletion requests · ${list.length}', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Please call the family to confirm, then mark the request done. Official school records stay as the law requires.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      const SizedBox(height: 8),
      for (final r in list) Builder(builder: (_) {
        final st = Map<String, dynamic>.from(r['student'] as Map? ?? const {});
        final phones = [for (final p in (st['family_phone'] as List? ?? const [])) '${p['phone']}'];
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outline.withValues(alpha: .4)))),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${st['full_name'] ?? ''} · ${st['admission_no'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('Asked ${DateFormat('d MMM, h:mm a').format(DateTime.parse(r['requested_at']).toLocal())}${phones.isEmpty ? '' : ' · ${phones.join(', ')}'}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              if ((r['note'] ?? '').toString().isNotEmpty) Text('“${r['note']}”', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13)),
            ])),
            if (phones.isNotEmpty) IconButton(tooltip: 'Call', onPressed: () => launchUrl(Uri.parse('tel:${phones.first}')), icon: Icon(Icons.call_rounded, color: context.tone(Brand.green))),
            TextButton(onPressed: () => _close(context, ref, r['id'] as String), child: const Text('Mark done')),
          ]),
        );
      }),
    ]));
  }

  Future<void> _close(BuildContext context, WidgetRef ref, String id) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Mark request done'),
      content: TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'What was agreed with the family (optional)')),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Mark done'))],
    ));
    final text = note.text.trim();
    note.dispose();
    if (ok != true) return;
    try {
      await db.rpc('close_account_deletion_request', params: {'p_id': id, 'p_note': text.isEmpty ? null : text});
      ref.invalidate(deletionRequestsProvider);
      if (context.mounted) toast(context, 'Marked done');
    } catch (e) {
      if (context.mounted) toast(context, friendlyError(e));
    }
  }
}
