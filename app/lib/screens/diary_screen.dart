import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

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
    final cs = Theme.of(context).colorScheme;
    final days = List.generate(30, (i) => DateTime.now().subtract(Duration(days: i)));   // today first; shown right-to-left
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Class diary', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
        SizedBox(height: 64, child: ListView.separated(scrollDirection: Axis.horizontal, reverse: true, itemCount: days.length, separatorBuilder: (_, __) => const SizedBox(width: 8),
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
      Expanded(child: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load the diary.\n$e', textAlign: TextAlign.center)),
        data: (list) => list.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('Nothing posted on ${DateFormat('EEEE, d MMMM').format(day)}.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant))))
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
                  if (e.needsSubmission) ...[const SizedBox(height: 12), OutlinedButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File submission opens once storage is switched on.'))), icon: const Icon(Icons.upload_file_rounded), label: const Text('Submit file'))],
                ]));
              }))),
    ]));
  }
}
