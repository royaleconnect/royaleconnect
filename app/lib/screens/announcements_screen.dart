import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});
  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  String filter = 'all';
  static const cats = {'all': 'All', 'urgent': 'Urgent', 'general': 'General', 'exam': 'Exams', 'holiday': 'Holidays', 'event': 'Events', 'fees': 'Fees'};

  @override
  Widget build(BuildContext context) {
    final notices = ref.watch(noticesProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(20, 8, 20, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Announcements', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          for (final e in cats.entries) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
            label: Text(e.value), selected: filter == e.key, onSelected: (_) => setState(() => filter = e.key),
            selectedColor: Colors.white, backgroundColor: Colors.white.withValues(alpha: .14), side: BorderSide.none, showCheckmark: false,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: filter == e.key ? Brand.crimsonDeep : Colors.white))),
        ])),
      ])),
      Expanded(child: notices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load announcements.\n$e', textAlign: TextAlign.center)),
        data: (list) {
          final rows = filter == 'all' ? list : list.where((n) => n.category == filter).toList();
          if (rows.isEmpty) return const Center(child: Text('Nothing here yet.'));
          return RefreshIndicator(onRefresh: () async => ref.invalidate(noticesProvider), child: ListView.separated(
            padding: const EdgeInsets.all(20), itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final n = rows[i];
              return Material(color: cs.surface, borderRadius: BorderRadius.circular(18), child: InkWell(borderRadius: BorderRadius.circular(18),
                onTap: () => _open(n),
                child: Container(padding: const EdgeInsets.all(14), decoration: n.urgent ? BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: Brand.crimson, width: 1.5)) : null,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Pill(cats[n.category] ?? n.category, fg: n.urgent ? Colors.white : Brand.crimsonDeep, bg: n.urgent ? Brand.crimson : Brand.crimsonTint),
                      const SizedBox(width: 8),
                      Text(DateFormat('d MMM').format(DateTime.parse(n.when).toLocal()), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      const Spacer(),
                      if (!n.read) Container(width: 8, height: 8, decoration: const BoxDecoration(color: Brand.crimson, shape: BoxShape.circle)),
                    ]),
                    const SizedBox(height: 8),
                    Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.4, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Text('${n.by} · ${n.audience}${n.file != null ? ' · 📎 attachment' : ''}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                  ]))));
            }));
        })),
    ]));
  }

  void _open(Notice n) {
    final s = ref.read(sessionProvider).value?.active;
    if (s != null && !n.read) markNoticeRead(n.id, s.id).then((_) => ref.invalidate(noticesProvider));
    showModalBottomSheet(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => DraggableScrollableSheet(expand: false, initialChildSize: .7, builder: (_, ctl) => ListView(controller: ctl, padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
      Pill(cats[n.category] ?? n.category, fg: Brand.crimsonDeep, bg: Brand.crimsonTint),
      const SizedBox(height: 12),
      Text(n.title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 6),
      Text('${n.by} · ${DateFormat('d MMMM yyyy, h:mm a').format(DateTime.parse(n.when).toLocal())}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 16),
      SelectableText(n.body, style: const TextStyle(fontSize: 15, height: 1.55)),
      if (n.file != null) ...[const SizedBox(height: 18), OutlinedButton.icon(onPressed: () => openStorageFile(n.file!), icon: const Icon(Icons.download_rounded), label: const Text('Open attachment'))],
    ])));
  }
}
