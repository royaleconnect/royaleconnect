import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../core/cache.dart';
import '../core/data.dart';
import '../core/theme.dart';
import 'staff_shell.dart' show toast;
import '../widgets/royal_extras.dart' show GoldLoading;

/// Bin: everything deleted in the last 30 days (diary notes, notices, events, toppers, council, photos…).
/// IT and the Principal can bring anything back with one tap. After 30 days it is removed for good.
final binProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  final rows = await db.from('bin_item').select('id,table_name,label,deleted_at,who:deleted_by(display_name)')
      .isFilter('restored_at', null).order('deleted_at', ascending: false).limit(200);
  return List<Map<String, dynamic>>.from(rows);
});

const _kinds = {
  'diary_entry': ('Diary note', Icons.menu_book_rounded), 'announcement': ('Notice', Icons.campaign_rounded),
  'calendar_event': ('Calendar event', Icons.event_rounded), 'board_topper': ('Topper', Icons.emoji_events_rounded),
  'hall_of_fame': ('Hall of Fame', Icons.workspace_premium_rounded), 'council_post': ('Council post', Icons.how_to_vote_rounded),
  'council_member': ('Council member', Icons.how_to_vote_rounded), 'council_candidate': ('Candidate', Icons.how_to_vote_rounded),
  'moment': ('Class photo', Icons.photo_rounded), 'album': ('Album', Icons.photo_library_rounded),
  'star_of_month': ('Star of the month', Icons.star_rounded), 'principal_message': ("Principal's message", Icons.auto_awesome_rounded),
};

class BinPanel extends ConsumerWidget {
  const BinPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ref.watch(binProvider).when(
      loading: () => const GoldLoading(),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => list.isEmpty
          ? Padding(padding: const EdgeInsets.all(40), child: Column(children: [
              Icon(Icons.delete_outline_rounded, size: 46, color: Brand.gold),
              const SizedBox(height: 10),
              const Text('The Bin is empty', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text('Anything deleted stays here for 30 days and can be brought back.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            ]))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('Deleted in the last 30 days. Tap "Bring back" to restore it exactly as it was.', style: TextStyle(color: cs.onSurfaceVariant))),
              for (final r in list) Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
                leading: CircleAvatar(backgroundColor: Brand.crimsonTint, child: Icon(_kinds[r['table_name']]?.$2 ?? Icons.description_rounded, color: Brand.crimsonDeep, size: 20)),
                title: Text(r['label'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text([_kinds[r['table_name']]?.$1 ?? r['table_name'], if (r['who'] != null) 'by ${r['who']['display_name']}',
                    DateFormat('d MMM, h:mm a').format(DateTime.parse(r['deleted_at']).toLocal()),
                    '${30 - DateTime.now().difference(DateTime.parse(r['deleted_at'])).inDays} days left'].join(' · ')),
                trailing: FilledButton.tonal(onPressed: () async {
                  try { await db.rpc('bin_restore', params: {'p_id': r['id']}); ref.invalidate(binProvider); if (context.mounted) toast(context, 'Brought back ✓'); }
                  catch (e) { if (context.mounted) toast(context, '$e'.replaceAll(RegExp(r'^.*?message: |, code.*$'), '')); }
                }, child: const Text('Bring back')),
              )),
            ]),
    );
  }
}
