import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_extras.dart' show GoldLoading;
import '../auth/session.dart';
import '../widgets/empty_state.dart';
import 'my_list.dart';
import '../core/errors.dart';

class DiaryScreen extends ConsumerStatefulWidget {
  const DiaryScreen({super.key});
  @override
  ConsumerState<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends ConsumerState<DiaryScreen> {
  DateTime day = DateTime.now();
  String get iso => DateFormat('yyyy-MM-dd').format(day);

  static const kinds = {'homework': ('Homework', Brand.blue, Brand.blueTint), 'to_bring': ('To bring', Brand.green, Brand.greenTint), 'reminder': ('Reminder', Brand.amber, Brand.amberTint), 'notice': ('Notice', Brand.amber, Brand.amberTint), 'test': ('Test', Brand.crimsonDeep, Brand.crimsonTint), 'project': ('Project', Brand.violet, Brand.violetTint)};

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(diaryProvider(iso));
    final tab = ref.watch(diaryTabProvider);
    final cs = Theme.of(context).colorScheme;
    final days = List.generate(30, (i) => DateTime.now().subtract(Duration(days: i)));   // today first; shown right-to-left
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Diary', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
        Padding(padding: EdgeInsets.only(bottom: tab == 0 ? 12 : 0), child: Row(children: [
          HeaderChip('Today', selected: tab == 0, onTap: () => ref.read(diaryTabProvider.notifier).state = 0),
          HeaderChip('My list', selected: tab == 1, onTap: () => ref.read(diaryTabProvider.notifier).state = 1),
        ])),
        if (tab == 0) SizedBox(height: 64, child: ListView.separated(scrollDirection: Axis.horizontal, reverse: true, itemCount: days.length, separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final d = days[i]; final sel = DateFormat('yyyy-MM-dd').format(d) == iso;
            return GestureDetector(onTap: () => setState(() => day = d), child: Container(width: 52, alignment: Alignment.center,
              decoration: BoxDecoration(color: sel ? Colors.white : Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(DateFormat('E').format(d).toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .6, color: sel ? Brand.muted : Colors.white.withValues(alpha: .8))),
                Text('${d.day}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: sel ? Brand.crimsonDeep : Colors.white)),
              ])));
          })),
      ])),
      Expanded(child: tab == 1 ? const MyListView() : entries.when(
        loading: () => const GoldLoading(),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (list) => list.isEmpty
            ? (iso == DateFormat('yyyy-MM-dd').format(DateTime.now())
                ? EmptyState(kind: EmptyKind.homework, title: 'No homework today', line: 'Enjoy your evening, ${(ref.watch(sessionProvider).value?.active?.fullName ?? '').split(' ').first}.')
                : EmptyState(kind: EmptyKind.homework, title: 'Nothing posted', line: 'Nothing was posted on ${DateFormat('EEEE, d MMMM').format(day)}.'))
            : ListView.separated(padding: const EdgeInsets.all(20), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) {
                final e = list[i]; final k = kinds[e.kind] ?? (e.kind, Brand.muted, Brand.surface2);
                return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Pill(k.$1, fg: k.$2, bg: k.$3), const SizedBox(width: 8), if (e.subject != null) Text(e.subject!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)), const Spacer(),
                    if (e.dueOn != null) Pill('For ${DateFormat('EEE d MMM').format(DateTime.parse(e.dueOn!))}', fg: Brand.amber, bg: Brand.amberTint)]),
                  const SizedBox(height: 8),
                  Text(e.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  if (e.body != null && e.body!.isNotEmpty) ...[const SizedBox(height: 4), Text(e.body!, style: TextStyle(fontSize: 13, height: 1.45, color: cs.onSurfaceVariant))],
                  const SizedBox(height: 8),
                  Text(e.by, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
                ]));
              }))),
    ]));
  }
}
