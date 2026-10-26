import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'family_screens.dart' show StorageImage;

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});
  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  String filter = 'all';
  static const cats = noticeCategories;

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
                onTap: () => context.push('/notice/${n.id}'),
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
                    Text('${n.by} · ${n.audience}${n.hasFiles ? ' · 📎 ${n.attachments.length} file${n.attachments.length > 1 ? 's' : ''}' : ''}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                  ]))));
            }));
        })),
    ]));
  }

}

const noticeCategories = {'all': 'All', 'urgent': 'Urgent', 'general': 'General', 'exams': 'Exams', 'holiday': 'Holidays', 'field_trip': 'Trips', 'fees': 'Fees'};

/// One announcement, full page: any length of text, then its PDFs, photos and links.
class NoticeScreen extends ConsumerStatefulWidget {
  final String id;
  const NoticeScreen({super.key, required this.id});
  @override
  ConsumerState<NoticeScreen> createState() => _NoticeScreenState();
}

class _NoticeScreenState extends ConsumerState<NoticeScreen> {
  bool marked = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final list = ref.watch(noticesProvider);
    final wide = MediaQuery.sizeOf(context).width >= 960;
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(8, 4, 12, 14), child: Row(children: [
        IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/announcements'), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), tooltip: 'Back'),
        const Expanded(child: Text('Announcement', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800))),
      ])),
      Expanded(child: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load.\n$e', textAlign: TextAlign.center)),
        data: (rows) {
          final n = rows.where((x) => x.id == widget.id).firstOrNull;
          if (n == null) return Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('This announcement is no longer available.', style: TextStyle(color: cs.onSurfaceVariant))));
          final me = ref.read(sessionProvider).value?.active;
          if (!marked && me != null && !n.read) { marked = true; markNoticeRead(n.id, me.id).then((_) => ref.invalidate(noticesProvider)); }
          final images = n.attachments.where((a) => (a['mime'] ?? '').toString().startsWith('image/')).toList();
          final docs = n.attachments.where((a) => !(a['mime'] ?? '').toString().startsWith('image/')).toList();
          return Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: wide ? 820 : double.infinity), child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 40), children: [
            Row(children: [
              Pill(noticeCategories[n.category] ?? n.category, fg: n.urgent ? Colors.white : Brand.crimsonDeep, bg: n.urgent ? Brand.crimson : Brand.crimsonTint),
              const SizedBox(width: 8),
              Flexible(child: Text(n.audience, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
            ]),
            const SizedBox(height: 12),
            Text(n.title, style: t.headlineSmall?.copyWith(fontSize: 24, height: 1.25)),
            const SizedBox(height: 6),
            Text('${n.by} · ${DateFormat('d MMMM yyyy, h:mm a').format(DateTime.parse(n.when).toLocal())}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            const SizedBox(height: 18),
            SelectableText(n.body, style: const TextStyle(fontSize: 15.5, height: 1.6)),
            if (n.hasFiles) ...[
              const SizedBox(height: 22),
              Eyebrow('Attachments · ${n.attachments.length}'),
              const SizedBox(height: 8),
              for (final d in docs) Padding(padding: const EdgeInsets.only(bottom: 8), child: Material(color: cs.surface, borderRadius: BorderRadius.circular(14), child: InkWell(
                borderRadius: BorderRadius.circular(14), onTap: () => openStorageFile(d['path']),
                child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outline.withValues(alpha: .6))), child: Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9), decoration: BoxDecoration(color: const Color(0xFFD93025), borderRadius: BorderRadius.circular(6)), child: Text((d['name'] ?? '').toString().split('.').last.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))),
                  const SizedBox(width: 12),
                  Expanded(child: Text(d['name'] ?? 'File', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Icon(Icons.open_in_new_rounded, size: 18, color: cs.onSurfaceVariant),
                ]))))),
              if (images.isNotEmpty) GridView.count(crossAxisCount: wide ? 3 : 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, children: [
                for (final (i, im) in images.indexed) GestureDetector(onTap: () => _viewImages(context, images, i), child: StorageImage(im['path'], radius: BorderRadius.circular(14))),
              ]),
            ],
            const SizedBox(height: 26),
            OutlinedButton.icon(onPressed: () => context.push('/messages'), icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18), label: const Text('Ask the class teacher about this')),
          ])));
        })),
    ]));
  }

  void _viewImages(BuildContext context, List<Map<String, dynamic>> images, int start) => Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, actions: [IconButton(onPressed: () => openStorageFile(images[start]['path']), icon: const Icon(Icons.download_rounded), tooltip: 'Download')]),
    body: PageView(controller: PageController(initialPage: start), children: [for (final im in images) InteractiveViewer(maxScale: 5, child: Center(child: StorageImage(im['path'], fit: BoxFit.contain)))]),
  )));
}
