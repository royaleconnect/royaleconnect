import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/school_docs.dart' show openReportCardPdf;
import '../core/theme.dart';
import '../widgets/common.dart';
import 'staff_data.dart';
import 'staff_shell.dart';

/// Class teachers fill in everything on the report card except marks (marks come from Marks entry):
/// attendance, height and weight, co-scholastic grades and remarks. Then preview the PDF and publish to families.
/// Office / principal can do it for any section. Families see nothing until it is published.

final _coAreasProvider = FutureProvider<List<String>>((ref) async {
  final r = await db.from('school_setting').select('value').eq('key', 'co_scholastic_areas').maybeSingle();
  final v = (r?['value'] as String?) ?? 'Art Education,Health & Physical Education,Discipline';
  return v.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
});

/// Report card names for a grade: Term I, Term II, plus every periodic test in the exam list.
final _termsProvider = FutureProvider.autoDispose.family<List<String>, String>((ref, gradeId) async {
  final yearId = await gradeYearId(gradeId);
  final ex = await db.from('exam').select('name,term,max_marks').eq('grade_id', gradeId).eq('academic_year_id', yearId).order('starts_on', ascending: true);
  final out = <String>['Term I', 'Term II'];
  for (final e in ex) {
    final t = '${e['term']}';
    if (!out.contains(t)) out.add(t);
  }
  for (final e in ex) {
    final n = '${e['name']}';
    if ((e['max_marks'] as num) < 100 && !out.contains(n)) out.add(n);
  }
  return out;
});

final _cardsProvider = FutureProvider.autoDispose.family<Map<String, Map<String, dynamic>>, (String, String)>((ref, key) async {
  final (sectionId, term) = key;
  final yearId = await sectionYearId(sectionId);
  final studs = await ref.watch(sectionStudentsProvider(sectionId).future);
  final ids = [for (final s in studs) s['student']['id'] as String];
  if (ids.isEmpty) return {};
  final rows = await db.from('report_card').select('id,student_id,status,working_days,days_present,height_cm,weight_kg,remarks,co_scholastic,published_at')
      .eq('academic_year_id', yearId).eq('term', term).inFilter('student_id', ids);
  return {for (final r in rows) r['student_id'] as String: Map<String, dynamic>.from(r)};
});

const _remarkIdeas = [
  'A sincere and hardworking student. Keep it up!',
  'Participates actively in class and is helpful to classmates.',
  'Shows good understanding. Regular revision at home will help even more.',
  'Neat and organised work. Should read more to build confidence.',
  'Creative and confident. Needs to focus on completing work on time.',
  'Well-behaved and attentive. Aim higher in Mathematics next term.',
];

class StaffReportsScreen extends ConsumerStatefulWidget {
  const StaffReportsScreen({super.key});
  @override
  ConsumerState<StaffReportsScreen> createState() => _StaffReportsScreenState();
}

class _Row {
  final present = TextEditingController(), height = TextEditingController(), weight = TextEditingController(), remarks = TextEditingController();
  final co = <String, String>{};
  String? id; String status = 'new';
  void dispose() { present.dispose(); height.dispose(); weight.dispose(); remarks.dispose(); }
}

class _StaffReportsScreenState extends ConsumerState<StaffReportsScreen> {
  String? sectionId; String term = 'Term I';
  final workingDays = TextEditingController();
  final rows = <String, _Row>{};
  String? loadedFor; bool busy = false;

  @override
  void dispose() { for (final r in rows.values) { r.dispose(); } workingDays.dispose(); super.dispose(); }

  String _n(num? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  /// Fill the boxes from what is saved (once per section + term).
  void _load(List<Map<String, dynamic>> studs, Map<String, Map<String, dynamic>> cards, List<String> areas) {
    final key = '$sectionId|$term';
    if (loadedFor == key) return;
    loadedFor = key;
    for (final r in rows.values) { r.dispose(); }
    rows.clear();
    workingDays.text = '';
    for (final s in studs) {
      final id = s['student']['id'] as String;
      final c = cards[id];
      final r = _Row();
      if (c != null) {
        r.id = c['id']; r.status = c['status'];
        r.present.text = _n(c['days_present'] as num?);
        r.height.text = _n(c['height_cm'] as num?);
        r.weight.text = _n(c['weight_kg'] as num?);
        r.remarks.text = c['remarks'] ?? '';
        if (c['co_scholastic'] is Map) { (c['co_scholastic'] as Map).forEach((k, v) => r.co['$k'] = '$v'); }
        if (workingDays.text.isEmpty && c['working_days'] != null) workingDays.text = _n(c['working_days'] as num?);
      }
      rows[id] = r;
    }
  }

  num? _num(String t) => t.trim().isEmpty ? null : num.tryParse(t.trim());

  Future<bool> _save(List<String> areas, {bool quiet = false}) async {
    final wd = _num(workingDays.text);
    for (final e in rows.entries) {
      final p = _num(e.value.present.text);
      if (p != null && wd != null && p > wd) { toast(context, 'Days present cannot be more than working days.'); return false; }
    }
    setState(() => busy = true);
    try {
      final yearId = await sectionYearId(sectionId!);
      final payload = [
        for (final e in rows.entries) if (e.value.status != 'locked') {
          'academic_year_id': yearId, 'student_id': e.key, 'term': term,
          'status': e.value.status == 'new' ? 'draft' : e.value.status,
          'working_days': wd, 'days_present': _num(e.value.present.text),
          'height_cm': _num(e.value.height.text), 'weight_kg': _num(e.value.weight.text),
          'remarks': e.value.remarks.text.trim().isEmpty ? null : e.value.remarks.text.trim(),
          'co_scholastic': {for (final a in areas) if ((e.value.co[a] ?? '').isNotEmpty) a: e.value.co[a]},
        },
      ];
      if (payload.isNotEmpty) await db.from('report_card').upsert(payload, onConflict: 'academic_year_id,student_id,term');
      loadedFor = null;
      ref.invalidate(_cardsProvider((sectionId!, term)));
      if (mounted && !quiet) toast(context, 'Saved. Families cannot see it until you publish.');
      return true;
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e');
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _publish(List<String> areas) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Publish $term report cards?'),
      content: const Text('Every family in this section can then open and download the report card, and gets a notification. Please check a few with “Preview PDF” first.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Publish'))],
    ));
    if (ok != true) return;
    if (!await _save(areas, quiet: true)) return;
    setState(() => busy = true);
    try {
      final yearId = await sectionYearId(sectionId!);
      final s = ref.read(sessionProvider).value!;
      await db.from('report_card').update({'status': 'published', 'published_at': nowIso(), 'published_by': s.staff!['id']})
          .eq('academic_year_id', yearId).eq('term', term).inFilter('student_id', rows.keys.toList()).inFilter('status', ['draft', 'ready']);
      loadedFor = null;
      ref.invalidate(_cardsProvider((sectionId!, term)));
      if (mounted) toast(context, 'Published. Families are being notified.');
    } catch (e) {
      if (mounted) toast(context, 'Could not publish: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    final cs = Theme.of(context).colorScheme;
    final secsAll = ref.watch(mySectionsProvider).value ?? const <Map<String, dynamic>>[];
    final secs = s.isOffice ? secsAll : secsAll.where((x) => x['class_teacher_id'] == s.staff?['id']).toList();
    if (sectionId == null && secs.isNotEmpty) sectionId = secs.first['id'];
    final sec = secs.where((x) => x['id'] == sectionId).firstOrNull;
    final areas = ref.watch(_coAreasProvider).value ?? const <String>[];
    final terms = sec == null ? const <String>['Term I', 'Term II'] : (ref.watch(_termsProvider(sec['grade']['id'])).value ?? const <String>['Term I', 'Term II']);

    if (secs.isEmpty && ref.watch(mySectionsProvider).hasValue) {
      return StaffPage(title: 'Report cards', body: Panel(child: Text('Report cards are filled in by class teachers. You are not class teacher of any section this year.', style: TextStyle(color: cs.onSurfaceVariant))));
    }
    final studs = sectionId == null ? null : ref.watch(sectionStudentsProvider(sectionId!));
    final cards = sectionId == null ? null : ref.watch(_cardsProvider((sectionId!, term)));
    if (studs?.value != null && cards?.value != null) _load(studs!.value!, cards!.value!, areas);
    final published = rows.values.where((r) => r.status == 'published' || r.status == 'locked').length;

    return StaffPage(
      title: 'Report cards',
      subtitle: 'Attendance, height & weight, co-scholastic grades and remarks. Marks come from Marks entry. Families see nothing until you publish.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(padding: const EdgeInsets.all(12), child: PickRow(children: [
          Expanded(child: PickField<String>(label: 'Section', value: sectionId, items: [for (final x in secs) DropdownMenuItem(value: x['id'] as String, child: Text(sectionLabel(x)))], onChanged: (v) => setState(() { sectionId = v; loadedFor = null; }))),
          const SizedBox(width: 12),
          Expanded(child: PickField<String>(label: 'Report card', value: terms.contains(term) ? term : terms.first, items: [for (final t in terms) DropdownMenuItem(value: t, child: Text(t))], onChanged: (v) => setState(() { term = v ?? 'Term I'; loadedFor = null; }))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: workingDays, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Working days this term'))),
        ])),
        if (studs == null || cards == null || studs.isLoading || cards.isLoading) const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
        else if (studs.hasError || cards.hasError) Text('${studs.error ?? cards.error}', style: const TextStyle(color: Brand.crimsonDeep))
        else ...[
          Panel(padding: const EdgeInsets.all(12), child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${rows.length} students · $published published', style: const TextStyle(fontWeight: FontWeight.w800)),
            FilledButton.icon(onPressed: busy ? null : () => _save(areas), icon: const Icon(Icons.save_rounded, size: 18), label: const Text('Save all')),
            OutlinedButton.icon(onPressed: busy || rows.isEmpty ? null : () => _publish(areas), icon: const Icon(Icons.send_rounded, size: 18), label: const Text('Publish to families')),
          ])),
          for (final st in studs.value!) Builder(builder: (_) {
            final id = st['student']['id'] as String;
            final r = rows[id];
            if (r == null) return const SizedBox.shrink();
            final locked = r.status == 'locked';
            final (fg, bg, label) = switch (r.status) {
              'published' => (Brand.green, Brand.greenTint, 'Published'),
              'locked' => (Brand.muted, Brand.surface2, 'Locked'),
              'new' => (Brand.muted, Brand.surface2, 'Not started'),
              _ => (Brand.amber, Brand.amberTint, 'Draft'),
            };
            Widget numBox(TextEditingController c, String l, {double w = 120}) => SizedBox(width: w, child: TextField(controller: c, enabled: !locked, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: l, isDense: true)));
            return Panel(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('${st['roll_no'] ?? ''}${st['roll_no'] == null ? '' : '. '}${st['student']['full_name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                Pill(label, fg: fg, bg: bg),
                if (r.id != null) IconButton(onPressed: () => openReportCardPdf(context, r.id!, name: '${st['student']['full_name']} $term'), icon: const Icon(Icons.picture_as_pdf_rounded), tooltip: 'Preview PDF'),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                numBox(r.present, 'Days present'), numBox(r.height, 'Height (cm)'), numBox(r.weight, 'Weight (kg)'),
                for (final a in areas) SizedBox(width: 190, child: DropdownButtonFormField<String>(
                  value: (r.co[a] ?? '').isEmpty ? null : r.co[a],
                  isDense: true, isExpanded: true,
                  decoration: InputDecoration(labelText: a, isDense: true),
                  items: const [DropdownMenuItem(value: 'A', child: Text('A · Outstanding')), DropdownMenuItem(value: 'B', child: Text('B · Very good')), DropdownMenuItem(value: 'C', child: Text('C · Fair'))],
                  onChanged: locked ? null : (v) => setState(() => r.co[a] = v ?? ''),
                )),
              ]),
              const SizedBox(height: 10),
              TextField(controller: r.remarks, enabled: !locked, minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(
                labelText: 'Class teacher’s remarks', isDense: true,
                suffixIcon: locked ? null : PopupMenuButton<String>(
                  tooltip: 'Remark ideas', icon: const Icon(Icons.lightbulb_outline_rounded),
                  onSelected: (v) => setState(() => r.remarks.text = v),
                  itemBuilder: (_) => [for (final x in _remarkIdeas) PopupMenuItem(value: x, child: Text(x))],
                ),
              )),
            ]));
          }),
          if (rows.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Tip: “Save all” keeps your work as a draft. Preview a few PDFs, then “Publish to families”. Changes after publishing are saved straight to the published card.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
        ],
      ]),
    );
  }
}
