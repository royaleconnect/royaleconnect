import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/marks_rules.dart';
import '../core/sheet_reader.dart';
import '../core/theme.dart';
import '../core/xlsx_writer.dart';
import '../widgets/common.dart';
import '../widgets/royal_extras.dart' show ShimmerPage;
import '../widgets/hub_tabs.dart';
import 'staff_data.dart';
import 'staff_shell.dart';

/// Exams (the year's list, class by class) and Marks entry (a sheet you type into, saved as you go).
/// Who enters marks: the subject teacher (own subjects, own classes) · the class teacher (every subject of her class)
/// · the office and IT (any class). No reason is asked; the app quietly keeps who changed what.

Widget _loading() => const ShimmerPage();
Widget _err(Object e) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e), style: const TextStyle(color: Brand.crimsonDeep)));
String _d(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String _dm(String? iso) => iso == null ? '' : DateFormat('d MMM').format(DateTime.parse(iso));

int _gradeNo(String? code) => const {'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10, 'XI': 11, 'XII': 12}[(code ?? '').toUpperCase()] ?? 0;

/// "20 + 80" · "Theory 70 + Practical 30" · "30"
String outOf(int gno, Map p) {
  final mi = p['mi'] ?? p['max_internal'], me = p['me'] ?? p['max_external'];
  if (mi == null) return fmtMark(me as num?);
  final (li, le) = markLabels(gno, '${p['part'] ?? 'main'}');
  return li == 'Practical' ? '$le ${fmtMark(me as num?)} + $li ${fmtMark(mi as num?)}' : '$li ${fmtMark(mi as num?)} + $le ${fmtMark(me as num?)}';
}

// ================================================================== the year's exams
final examsYearProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  try { await db.rpc('exams_refresh'); } catch (_) {}
  final years = await ref.watch(liveYearIdsProvider.future);
  final data = await db.from('exam')
      .select('id,name,term,kind,sort,starts_on,ends_on,max_marks,note,published_at,grade:grade_id(id,code,name,sort_order),'
          'exam_paper(id,on_date,portions,max_internal,max_external,part,subject:subject_id(id,name))')
      .inFilter('academic_year_id', years).order('sort', ascending: true);
  final rows = List<Map<String, dynamic>>.from(data);
  rows.sort((a, b) {
    final g = ((a['grade']?['sort_order'] ?? 0) as int).compareTo((b['grade']?['sort_order'] ?? 0) as int);
    if (g != 0) return g;
    final s = ((a['sort'] ?? 50) as int).compareTo((b['sort'] ?? 50) as int);
    return s != 0 ? s : '${a['starts_on'] ?? '9'}'.compareTo('${b['starts_on'] ?? '9'}');
  });
  return rows;
});

String kindLabel(Map e) => switch ('${e['kind']}') { 'test' => 'Test', 'own' => 'Own maximum', _ => 'Term exam' };

class StaffExamsScreen extends ConsumerStatefulWidget {
  const StaffExamsScreen({super.key});
  @override
  ConsumerState<StaffExamsScreen> createState() => _StaffExamsScreenState();
}

class _StaffExamsScreenState extends ConsumerState<StaffExamsScreen> {
  String? grade;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    final canCreate = (s.hasRole('office') || s.hasRole('it_admin') || s.hasRole('coordinator')) && !s.viewOnly;
    final cs = Theme.of(context).colorScheme;
    final exams = ref.watch(examsYearProvider);
    final mine = ref.watch(mySectionsProvider).value ?? const <Map<String, dynamic>>[];
    return StaffPage(title: 'Exams & marks', hub: Hub.staffExams,
      subtitle: 'Every class gets PT 1, Half Yearly, PT 2 and Annual by itself (X and XII: Pre-board 1 and 2). Add dates and portions; publish the timetable when it is ready.',
      actions: [if (canCreate) FilledButton.icon(onPressed: () => _add(context), icon: const Icon(Icons.add_rounded), label: const Text('Add exam'))],
      body: exams.when(loading: _loading, error: (e, _) => _err(e), data: (rows) {
        final grades = <String, Map<String, dynamic>>{};
        for (final e in rows) { if (e['grade'] != null) grades[e['grade']['id']] = Map<String, dynamic>.from(e['grade']); }
        final myGrades = {for (final m in mine) m['grade']['id'] as String};
        final list = grades.values.where((g) => s.isOffice || canCreate || myGrades.contains(g['id'])).toList();
        if (list.isEmpty) return Panel(child: Text('No exams yet. They appear here once the classes have sections and subjects.', style: TextStyle(color: cs.onSurfaceVariant)));
        final gid = list.any((g) => g['id'] == grade) ? grade! : (list.firstWhere((g) => myGrades.contains(g['id']), orElse: () => list.first)['id'] as String);
        final gno = _gradeNo(grades[gid]?['code']);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final g in list) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
              label: Text('${g['code']}'), selected: g['id'] == gid, showCheckmark: false, selectedColor: Brand.crimson,
              labelStyle: TextStyle(fontWeight: FontWeight.w800, color: g['id'] == gid ? Colors.white : null),
              onSelected: (_) => setState(() => grade = g['id']))),
          ])),
          const SizedBox(height: 12),
          for (final e in rows.where((x) => x['grade']?['id'] == gid)) _ExamCard(e: e, gno: gno, canCreate: canCreate),
        ]);
      }),
    );
  }

  Future<void> _add(BuildContext context) async {
    final added = await showDialog<bool>(context: context, builder: (_) => const _AddExamDialog());
    if (added == true) ref.invalidate(examsYearProvider);
  }
}

class _ExamCard extends ConsumerWidget {
  final Map<String, dynamic> e; final int gno; final bool canCreate;
  const _ExamCard({required this.e, required this.gno, required this.canCreate});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final papers = List<Map<String, dynamic>>.from(e['exam_paper'] ?? const [])
      ..sort((a, b) { final p = '${a['part']}'.compareTo('${b['part']}'); return p != 0 ? p : '${a['subject']?['name']}'.compareTo('${b['subject']?['name']}'); });
    final pub = e['published_at'] != null;
    final dates = e['starts_on'] == null ? 'Dates not set yet' : '${_dm(e['starts_on'])}${e['ends_on'] != null ? ' – ${_dm(e['ends_on'])}' : ''}';
    return Panel(
      title: '${e['name']}',
      trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Pill(kindLabel(e), fg: Brand.violet, bg: Brand.violet.withValues(alpha: .1)),
        Pill(pub ? 'Timetable published' : 'Draft', fg: pub ? Brand.green : Brand.amber, bg: pub ? Brand.greenTint : Brand.amberTint),
        if (canCreate) TextButton(onPressed: () async {
          try { await db.from('exam').update({'published_at': pub ? null : nowIso()}).eq('id', e['id']); ref.invalidate(examsYearProvider); }
          catch (x) { if (context.mounted) toast(context, friendlyError(x)); }
        }, child: Text(pub ? 'Unpublish' : 'Publish')),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(dates, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
          TextButton.icon(onPressed: () => context.go('/staff/marks?exam=${e['id']}'), icon: const Icon(Icons.edit_note_rounded, size: 18), label: const Text('Enter marks')),
        ]),
        const SizedBox(height: 6),
        if (papers.isEmpty) Text('No subjects yet — they come in by themselves once the class has subject teachers.', style: TextStyle(color: cs.onSurfaceVariant))
        else for (final p in papers) InkWell(
          onTap: () => _editPaper(context, ref, p),
          child: Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .5)))),
            child: Row(children: [
              SizedBox(width: 74, child: Text(p['on_date'] == null ? 'TBA' : DateFormat('EEE d').format(DateTime.parse(p['on_date'])), style: const TextStyle(fontWeight: FontWeight.w800))),
              Expanded(flex: 3, child: Text('${p['subject']?['name'] ?? ''}${p['part'] == 'skill' ? '  · separate' : ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
              Expanded(flex: 3, child: Text(outOf(gno, p), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
              Expanded(flex: 4, child: Text(p['portions'] ?? 'Portions not entered', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: p['portions'] == null ? cs.onSurfaceVariant : null))),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ]))),
      ]),
    );
  }

  Future<void> _editPaper(BuildContext context, WidgetRef ref, Map<String, dynamic> p) async {
    DateTime? on = p['on_date'] == null ? null : DateTime.parse(p['on_date']);
    final portions = TextEditingController(text: p['portions'] ?? '');
    final mi = TextEditingController(text: fmtMark(p['max_internal'] as num?)), me = TextEditingController(text: fmtMark(p['max_external'] as num?));
    final (li, le) = markLabels(gno, '${p['part']}');
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: Text('${p['subject']?['name']} · ${e['name']}'),
      content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OutlinedButton.icon(onPressed: () async {
          final d = await showDatePicker(context: c, initialDate: on ?? DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 365)));
          if (d != null) set(() => on = d);
        }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(on == null ? 'Exam date' : DateFormat('EEEE, d MMM').format(on!))),
        const SizedBox(height: 10),
        TextField(controller: portions, minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: 'Portions', hintText: 'Chapters / topics')),
        if (canCreate) ...[
          const SizedBox(height: 14),
          Text('Out of', style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(c).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Row(children: [
            if (e['kind'] == 'term') ...[Expanded(child: TextField(controller: mi, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: li))), const SizedBox(width: 10)],
            Expanded(child: TextField(controller: me, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: e['kind'] == 'term' ? le : 'Marks'))),
          ]),
        ],
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
    )));
    if (ok != true) return;
    try {
      await db.from('exam_paper').update({'on_date': on == null ? null : _d(on!), 'portions': portions.text.trim().isEmpty ? null : portions.text.trim(),
        'confirmed_by': ref.read(sessionProvider).value?.staff?['id'], 'confirmed_at': nowIso()}).eq('id', p['id']);
      if (canCreate) {
        final nmi = num.tryParse(mi.text.trim()), nme = num.tryParse(me.text.trim());
        if (nme != null && (nme != p['max_external'] || nmi != p['max_internal'])) {
          await db.rpc('exam_paper_set', params: {'p_paper': p['id'], 'p_internal': e['kind'] == 'term' ? nmi : null, 'p_external': nme});
        }
      }
      ref.invalidate(examsYearProvider);
      if (context.mounted) toast(context, 'Saved ✓');
    } catch (x) { if (context.mounted) toast(context, friendlyError(x)); }
  }
}

class _AddExamDialog extends ConsumerStatefulWidget {
  const _AddExamDialog();
  @override
  ConsumerState<_AddExamDialog> createState() => _AddExamDialogState();
}

class _AddExamDialogState extends ConsumerState<_AddExamDialog> {
  final name = TextEditingController(), max = TextEditingController();
  String kind = 'term'; final picked = <String>{}; DateTime? a, b; bool busy = false;

  @override
  Widget build(BuildContext context) {
    final grades = (ref.watch(gradesProvider).value ?? const <Map<String, dynamic>>[]).where((g) => _gradeNo(g['code']) > 0).toList();
    final cs = Theme.of(context).colorScheme;
    Widget kindTile(String k, String t, String sub) => RadioListTile<String>(value: k, groupValue: kind, onChanged: (v) => setState(() => kind = v!), contentPadding: EdgeInsets.zero,
        title: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(sub, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)));
    return AlertDialog(
      title: const Text('Add an exam'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Pre-board 3')),
        const SizedBox(height: 8),
        kindTile('term', 'Term exam — like Half Yearly', 'VI–X: Internals 20 + Written 80 · I–V: 50 · XI–XII: each subject’s Theory + Practical'),
        kindTile('test', 'Test — like PT 1', 'Out of 30, every subject'),
        kindTile('own', 'Our own maximum', 'One mark per subject, out of the number you type'),
        if (kind == 'own') TextField(controller: max, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Maximum marks')),
        const SizedBox(height: 12),
        Text('Classes', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final g in grades) FilterChip(label: Text('${g['code']}'), selected: picked.contains(g['id']),
            onSelected: (v) => setState(() => v ? picked.add(g['id']) : picked.remove(g['id'])))]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () async { final d = await _pick(context, a); if (d != null) setState(() => a = d); }, child: Text(a == null ? 'Starts (optional)' : DateFormat('d MMM yyyy').format(a!)))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton(onPressed: () async { final d = await _pick(context, b ?? a); if (d != null) setState(() => b = d); }, child: Text(b == null ? 'Ends (optional)' : DateFormat('d MMM yyyy').format(b!)))),
        ]),
        const SizedBox(height: 8),
        Text('The subjects of each class come in by themselves.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Adding…' : 'Add exam')),
      ],
    );
  }

  Future<DateTime?> _pick(BuildContext context, DateTime? init) => showDatePicker(context: context, initialDate: init ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 180)), lastDate: DateTime.now().add(const Duration(days: 400)));

  Future<void> _save() async {
    if (name.text.trim().isEmpty) { toast(context, 'Please type a name for the exam.'); return; }
    if (picked.isEmpty) { toast(context, 'Please pick at least one class.'); return; }
    setState(() => busy = true);
    try {
      final n = await db.rpc('exam_add', params: {'p_grades': picked.toList(), 'p_name': name.text.trim(), 'p_kind': kind,
        'p_starts': a == null ? null : _d(a!), 'p_ends': b == null ? null : _d(b!), 'p_max': kind == 'own' ? int.tryParse(max.text.trim()) : null});
      if (mounted) { toast(context, 'Added for $n ${n == 1 ? 'class' : 'classes'} ✓'); Navigator.pop(context, true); }
    } catch (e) { if (mounted) { setState(() => busy = false); toast(context, friendlyError(e)); } }
  }
}

// ================================================================== Marks entry
/// Set while the page has marks not saved yet. The router asks it before leaving (GoRoute onExit).
Future<bool> Function()? _marksLeaveGuard;
Future<bool> marksCanLeave() async => _marksLeaveGuard == null ? true : await _marksLeaveGuard!();

final _sheetProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, (String, String, String)>((ref, k) async {
  final (exam, section, subject) = k;
  return Map<String, dynamic>.from(await db.rpc('marks_sheet', params: {'p_exam': exam, 'p_section': section, 'p_subject': subject.isEmpty ? null : subject}) as Map);
});

class StaffMarksScreen extends ConsumerStatefulWidget {
  final String? examId;
  const StaffMarksScreen({super.key, this.examId});
  @override
  ConsumerState<StaffMarksScreen> createState() => _StaffMarksScreenState();
}

class _StaffMarksScreenState extends ConsumerState<StaffMarksScreen> {
  String? examId, sectionId; String subjectId = '';
  /// typed text not saved yet: "student|subject|i" or "…|e" → text
  final pending = <String, String>{};
  /// what is saved now (after load and after each save), same keys
  final saved = <String, String>{};
  String? loadedFor; Timer? timer; bool saving = false; DateTime? savedAt; String? problem;
  int version = 0;

  @override
  void initState() { super.initState(); examId = widget.examId; _marksLeaveGuard = _leave; }
  @override
  void dispose() { timer?.cancel(); if (_marksLeaveGuard == _leave) _marksLeaveGuard = null; super.dispose(); }

  Future<bool> _leave() async {
    if (pending.isEmpty || !mounted) return true;
    if (await _saveNow()) return true;
    if (!mounted) return true;
    final r = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Some marks are not saved'),
      content: Text(problem ?? 'Please check the boxes in red.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leave without them')), FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay and fix'))],
    ));
    return r == true;
  }

  Future<void> _pick(VoidCallback change) async {
    if (pending.isNotEmpty && !await _leave()) return;
    setState(() { change(); pending.clear(); saved.clear(); loadedFor = null; problem = null; savedAt = null; });
  }

  String _key(String st, String sub, String f) => '$st|$sub|$f';

  void _load(Map<String, dynamic> sheet) {
    final id = '$examId|$sectionId|$subjectId|$version';
    if (loadedFor == id) return;
    loadedFor = id;
    saved.clear();
    for (final st in List<Map<String, dynamic>>.from(sheet['students'] ?? const [])) {
      final marks = Map<String, dynamic>.from(st['marks'] ?? const {});
      marks.forEach((sub, m) {
        final mm = Map<String, dynamic>.from(m as Map);
        saved[_key(st['id'], sub, 'i')] = fmtMark(mm['i'] as num?);
        saved[_key(st['id'], sub, 'e')] = mm['ab'] == true ? 'AB' : fmtMark(mm['e'] as num?);
      });
    }
  }

  String _text(String k) => pending[k] ?? saved[k] ?? '';

  /// a box is wrong when it is not a number / AB, or above its maximum
  bool _bad(String text, num? max) {
    final r = readMark(text);
    if (r.bad) return true;
    if (r.absent) return false;
    return r.value != null && max != null && r.value! > max;
  }

  void _changed(String k, String v) {
    setState(() { if ((saved[k] ?? '') == v) { pending.remove(k); } else { pending[k] = v; } problem = null; });
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 1200), _saveNow);
  }

  /// Saves every finished row (both boxes valid). Returns true when nothing is left unsaved.
  Future<bool> _saveNow() async {
    timer?.cancel();
    if (pending.isEmpty || examId == null || sectionId == null) return true;
    if (saving) return false;
    final sheet = ref.read(_sheetProvider((examId!, sectionId!, subjectId))).value;
    if (sheet == null) return false;
    final papers = {for (final p in List<Map<String, dynamic>>.from(sheet['papers'] ?? const [])) p['subject_id'] as String: p};
    final cells = <String, (String, String)>{};   // student|subject → (internal text, external text)
    for (final k in pending.keys) {
      final parts = k.split('|');
      cells['${parts[0]}|${parts[1]}'] = (_text('${parts[0]}|${parts[1]}|i'), _text('${parts[0]}|${parts[1]}|e'));
    }
    final rows = <Map<String, dynamic>>[]; final done = <String>[]; var bad = 0;
    cells.forEach((k, v) {
      final parts = k.split('|'); final p = papers[parts[1]];
      if (p == null) return;
      final (ti, te) = v;
      if (_bad(ti, p['mi'] as num?) || _bad(te, p['me'] as num?) || (p['mi'] == null && ti.trim().isNotEmpty)) { bad++; return; }
      final ri = readMark(ti), re = readMark(te);
      rows.add({'student': parts[0], 'subject': parts[1], 'i': ri.value, 'e': re.value, 'ab': re.absent || ri.absent});
      done..add('$k|i')..add('$k|e');
    });
    if (rows.isEmpty) { if (bad > 0) setState(() => problem = 'Fix the boxes in red — they are not saved.'); return false; }
    setState(() => saving = true);
    try {
      await db.rpc('marks_save', params: {'p_exam': examId, 'p_rows': rows});
      for (final k in done) { if (pending.containsKey(k)) { saved[k] = pending.remove(k)!; } }
      if (mounted) setState(() { saving = false; savedAt = DateTime.now(); problem = bad > 0 ? 'Fix the boxes in red — they are not saved.' : null; });
      return pending.isEmpty;
    } catch (e) {
      if (mounted) { setState(() { saving = false; problem = friendlyError(e); }); toast(context, friendlyError(e)); }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    final cs = Theme.of(context).colorScheme;
    final exams = ref.watch(examsYearProvider).value ?? const <Map<String, dynamic>>[];
    final mine = ref.watch(mySectionsProvider).value ?? const <Map<String, dynamic>>[];
    final myGrades = {for (final m in mine) m['grade']['id'] as String};
    final examList = exams.where((e) => myGrades.contains(e['grade']?['id'])).toList();
    final exam = examList.where((e) => e['id'] == examId).firstOrNull;
    final secs = exam == null ? const <Map<String, dynamic>>[] : mine.where((m) => m['grade']['id'] == exam['grade']['id']).toList();
    if (exam != null && sectionId == null && secs.length == 1) sectionId = secs.first['id'];
    final sheetA = exam != null && sectionId != null ? ref.watch(_sheetProvider((examId!, sectionId!, subjectId))) : null;
    final sheet = sheetA?.value;
    if (sheet != null) _load(sheet);
    // subjects to pick: all (class teacher / office / IT) or the ones I teach here
    final allPapers = List<Map<String, dynamic>>.from(exam?['exam_paper'] ?? const []);
    final canAll = sheet?['can_all'] == true || s.hasRole('office') || s.hasRole('it_admin') || secs.any((x) => x['id'] == sectionId && x['class_teacher_id'] == s.staff?['id']);

    return StaffPage(title: 'Marks entry', hub: Hub.staffExams,
      subtitle: 'Type the marks and press Tab for the next box. They save by themselves. Type AB for absent.',
      actions: [
        if (sheet != null) OutlinedButton.icon(onPressed: () => _excelOut(sheet, exam!), icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Excel')),
        if (sheet != null) OutlinedButton.icon(onPressed: () => _excelIn(sheet), icon: const Icon(Icons.upload_file_rounded, size: 18), label: const Text('Fill from Excel')),
        if (sheet != null && subjectId.isNotEmpty && !canAll) FilledButton.icon(onPressed: () => _done(), icon: const Icon(Icons.check_circle_rounded, size: 18), label: const Text('Done — tell the class teacher')),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(padding: const EdgeInsets.all(14), child: PickRow(children: [
          Expanded(flex: 3, child: PickField<String>(label: 'Exam', value: exam == null ? null : examId, items: [
            for (final e in examList) DropdownMenuItem(value: e['id'] as String, child: Text('${e['grade']?['code']} · ${e['name']}', overflow: TextOverflow.ellipsis)),
          ], onChanged: (v) => _pick(() { examId = v; sectionId = null; subjectId = ''; }))),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: PickField<String>(label: 'Class', value: secs.any((x) => x['id'] == sectionId) ? sectionId : null, items: [
            for (final x in secs) DropdownMenuItem(value: x['id'] as String, child: Text(sectionLabel(x))),
          ], onChanged: (v) => _pick(() { sectionId = v; subjectId = ''; }))),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: PickField<String>(label: 'Subject', value: subjectId, items: [
            DropdownMenuItem(value: '', child: Text(canAll ? 'All subjects' : 'My subjects')),
            for (final p in allPapers) DropdownMenuItem(value: p['subject']['id'] as String, child: Text('${p['subject']['name']}')),
          ], onChanged: (v) => _pick(() { subjectId = v ?? ''; }))),
        ])),
        if (exam == null) Panel(child: Text(examList.isEmpty ? 'No exams for your classes yet.' : 'Pick the exam and the class.', style: TextStyle(color: cs.onSurfaceVariant)))
        else if (sectionId == null) Panel(child: Text('Pick the class.', style: TextStyle(color: cs.onSurfaceVariant)))
        else if (sheetA == null || sheetA.isLoading && sheet == null) _loading()
        else if (sheetA.hasError) _err(sheetA.error!)
        else _grid(context, sheet!, cs),
      ]),
    );
  }

  Widget _grid(BuildContext context, Map<String, dynamic> sheet, ColorScheme cs) {
    final gno = (sheet['exam']?['grade_no'] ?? 0) as int;
    final papers = [for (final p in List<Map<String, dynamic>>.from(sheet['papers'] ?? const [])) if (p['can'] == true) p];
    final students = List<Map<String, dynamic>>.from(sheet['students'] ?? const []);
    if (papers.isEmpty) return Panel(child: Text('You can enter marks only for the subjects you teach in this class.', style: TextStyle(color: cs.onSurfaceVariant)));
    if (students.isEmpty) return Panel(child: Text('No students in this class.', style: TextStyle(color: cs.onSurfaceVariant)));
    final single = papers.length == 1;
    const boxW = 64.0, gap = 6.0;
    // the order of boxes in one subject: Internals → Written, or Theory → Practical
    List<String> fields(Map p) {
      if (p['mi'] == null) return ['e'];
      final (li, _) = markLabels(gno, '${p['part']}');
      return li == 'Practical' ? ['e', 'i'] : ['i', 'e'];
    }
    String label(Map p, String f) {
      if (p['mi'] == null) return 'Marks /${fmtMark(p['me'] as num?)}';
      final (li, le) = markLabels(gno, '${p['part']}');
      return f == 'i' ? '$li /${fmtMark(p['mi'] as num?)}' : '$le /${fmtMark(p['me'] as num?)}';
    }
    double groupW(Map p) => fields(p).length * (boxW + gap) + (single ? 0 : 10);
    final width = 44 + 220 + papers.fold<double>(0, (a, p) => a + groupW(p)) + (single ? 150 : 0) + 24;
    var missing = 0;
    for (final st in students) {
      for (final p in papers) {
        if (!takesSubject(st['l2'], st['l3'], '${p['name']}')) continue;
        final e = _text(_key(st['id'], p['subject_id'], 'e')), i = _text(_key(st['id'], p['subject_id'], 'i'));
        if (e.trim().isEmpty && (p['mi'] == null || i.trim().isEmpty)) missing++;
      }
    }
    final head = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: cs.onSurfaceVariant);
    final table = SizedBox(width: width, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(padding: const EdgeInsets.fromLTRB(12, 12, 12, 10), color: Brand.gold.withValues(alpha: .08), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        SizedBox(width: 44, child: Text('ROLL', style: head)), SizedBox(width: 220, child: Text('STUDENT', style: head)),
        for (final p in papers) SizedBox(width: groupW(p), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!single) Text('${p['name']}'.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: head.copyWith(color: cs.onSurface)),
          Row(children: [for (final f in fields(p)) SizedBox(width: boxW + gap, child: Text(label(p, f).replaceFirst(' /', '\n/'), textAlign: TextAlign.center, style: head.copyWith(fontSize: 10.5)))]),
        ])),
        if (single) SizedBox(width: 150, child: Row(children: [Expanded(child: Text('TOTAL', textAlign: TextAlign.center, style: head)), Expanded(child: Text('GRADE', textAlign: TextAlign.center, style: head))])),
      ])),
      for (final st in students) Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .5)))),
        child: Row(children: [
          SizedBox(width: 44, child: Text('${st['roll'] ?? ''}', style: TextStyle(color: cs.onSurfaceVariant))),
          SizedBox(width: 220, child: Text('${st['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
          for (final p in papers) SizedBox(width: groupW(p), child: Row(children: [
            for (final f in fields(p)) Padding(padding: const EdgeInsets.only(right: gap), child: SizedBox(width: boxW, child: !takesSubject(st['l2'], st['l3'], '${p['name']}')
              ? Center(child: Tooltip(message: 'Not this student’s language', child: Text('—', style: TextStyle(color: cs.onSurfaceVariant))))
              : _MarkBox(key: ValueKey('${_key(st['id'], p['subject_id'], f)}|$loadedFor'), initial: _text(_key(st['id'], p['subject_id'], f)),
                  max: (f == 'i' ? p['mi'] : p['me']) as num?, pending: pending.containsKey(_key(st['id'], p['subject_id'], f)),
                  onChanged: (v) => _changed(_key(st['id'], p['subject_id'], f), v)))),
          ])),
          if (single) SizedBox(width: 150, child: Builder(builder: (_) {
            final p = papers.first;
            final ri = readMark(_text(_key(st['id'], p['subject_id'], 'i'))), re = readMark(_text(_key(st['id'], p['subject_id'], 'e')));
            final mx = ((p['mi'] ?? 0) as num) + ((p['me'] ?? 0) as num);
            final any = ri.value != null || re.value != null;
            final t = (ri.value ?? 0) + (re.value ?? 0);
            return Row(children: [
              Expanded(child: Text(re.absent ? 'AB' : any ? fmtMark(t) : '—', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900))),
              Expanded(child: Text(any && !re.absent && mx > 0 ? cbseGrade(t * 100 / mx) : '', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
            ]);
          })),
        ])),
    ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(padding: EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 10), child: Row(children: [
          Expanded(child: Text('${sheet['exam']?['name']} · ${students.length} students${single ? ' · ${papers.first['name']}' : ' · ${papers.length} subjects'}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
          if (saving) Text('Saving…', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700))
          else if (problem != null) Flexible(child: Text(problem!, textAlign: TextAlign.right, style: TextStyle(color: context.tone(Brand.crimsonDeep), fontWeight: FontWeight.w800)))
          else if (pending.isNotEmpty) Text('Typing…', style: TextStyle(color: cs.onSurfaceVariant))
          else if (savedAt != null) Text('✓ Saved ${DateFormat('h:mm a').format(savedAt!)}', style: TextStyle(color: context.tone(Brand.green), fontWeight: FontWeight.w800)),
        ])),
        LayoutBuilder(builder: (_, c) => c.maxWidth >= width ? table : SingleChildScrollView(scrollDirection: Axis.horizontal, child: table)),
      ])),
      Text(missing == 0 ? 'Every mark is in ✓' : '$missing ${missing == 1 ? 'mark is' : 'marks are'} still to enter. A number above the maximum turns red and is not saved.',
          style: TextStyle(fontSize: 12.5, color: missing == 0 ? context.tone(Brand.green) : cs.onSurfaceVariant, fontWeight: missing == 0 ? FontWeight.w800 : null)),
    ]);
  }

  // ---------------------------------------------------------------- Excel out / in
  List<(Map<String, dynamic>, String, String)> _columns(Map<String, dynamic> sheet) {
    final gno = (sheet['exam']?['grade_no'] ?? 0) as int;
    final out = <(Map<String, dynamic>, String, String)>[];
    for (final p in List<Map<String, dynamic>>.from(sheet['papers'] ?? const [])) {
      if (p['can'] != true) continue;
      if (p['mi'] == null) { out.add((p, 'e', '${p['name']} (${fmtMark(p['me'] as num?)})')); continue; }
      final (li, le) = markLabels(gno, '${p['part']}');
      out..add((p, 'i', '${p['name']} $li (${fmtMark(p['mi'] as num?)})'))..add((p, 'e', '${p['name']} $le (${fmtMark(p['me'] as num?)})'));
    }
    return out;
  }

  Future<void> _excelOut(Map<String, dynamic> sheet, Map<String, dynamic> exam) async {
    final cols = _columns(sheet);
    final students = List<Map<String, dynamic>>.from(sheet['students'] ?? const []);
    final sec = (ref.read(mySectionsProvider).value ?? const []).where((x) => x['id'] == sectionId).firstOrNull;
    try {
      await saveBytes(buildXlsx('Marks', ['Roll', 'Admission no', 'Student', for (final c in cols) c.$3], [
        for (final st in students) [st['roll'], st['adm'], st['name'], for (final c in cols) _text(_key(st['id'], c.$1['subject_id'], c.$2))],
      ], widths: [7, 16, 26, for (final _ in cols) 16]), 'RCIS-marks-${exam['name']}-${sec == null ? '' : sectionLabel(sec)}.xlsx'.replaceAll(' ', '-'));
    } catch (e) { if (mounted) toast(context, 'Could not save the file: ${friendlyError(e)}'); }
  }

  Future<void> _excelIn(Map<String, dynamic> sheet) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx', 'csv'], withData: true);
    if (r == null || r.files.first.bytes == null) return;
    try {
      final rows = readSpreadsheet(Uint8List.fromList(r.files.first.bytes!), r.files.first.name).first.rows;
      if (rows.length < 2) { if (mounted) toast(context, 'The file has no marks.'); return; }
      final head = [for (final h in rows.first) h.trim().toLowerCase()];
      final adm = head.indexWhere((h) => h.contains('admission'));
      if (adm < 0) { if (mounted) toast(context, 'Use the file from the Excel button — it needs the Admission no column.'); return; }
      final cols = _columns(sheet);
      final at = {for (final c in cols) c: head.indexOf(c.$3.toLowerCase())};
      final byAdm = {for (final st in List<Map<String, dynamic>>.from(sheet['students'] ?? const [])) '${st['adm']}'.trim().toLowerCase(): st};
      var n = 0;
      for (final row in rows.skip(1)) {
        if (adm >= row.length) continue;
        final st = byAdm[row[adm].trim().toLowerCase()];
        if (st == null) continue;
        for (final c in cols) {
          final i = at[c]!;
          if (i < 0 || i >= row.length) continue;
          final v = row[i].trim();
          final k = _key(st['id'], c.$1['subject_id'], c.$2);
          if (v != (saved[k] ?? '')) { pending[k] = v; n++; }
        }
      }
      setState(() { version++; loadedFor = null; });
      final sheetNow = ref.read(_sheetProvider((examId!, sectionId!, subjectId))).value;
      if (sheetNow != null) _load(sheetNow);
      if (mounted) toast(context, n == 0 ? 'Nothing new in the file.' : '$n marks filled in — saving now.');
      if (n > 0) await _saveNow();
    } catch (e) { if (mounted) toast(context, 'Could not read the file: ${friendlyError(e)}'); }
  }

  Future<void> _done() async {
    if (!await _saveNow() && pending.isNotEmpty) { if (mounted) toast(context, problem ?? 'Some marks are not saved yet.'); return; }
    try {
      await db.rpc('marks_done', params: {'p_exam': examId, 'p_section': sectionId, 'p_subject': subjectId});
      if (mounted) toast(context, 'The class teacher has been told ✓');
    } catch (e) { if (mounted) toast(context, friendlyError(e)); }
  }
}

/// One mark box: red when the number is above the maximum (or not a number / AB).
class _MarkBox extends StatefulWidget {
  final String initial; final num? max; final bool pending; final ValueChanged<String> onChanged;
  const _MarkBox({super.key, required this.initial, required this.max, required this.pending, required this.onChanged});
  @override
  State<_MarkBox> createState() => _MarkBoxState();
}

class _MarkBoxState extends State<_MarkBox> {
  late final c = TextEditingController(text: widget.initial);
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final r = readMark(c.text);
    final bad = r.bad || (!r.absent && r.value != null && widget.max != null && r.value! > widget.max!);
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: c, textAlign: TextAlign.center, textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.aAbB]')), LengthLimitingTextInputFormatter(5)],
      style: TextStyle(fontWeight: FontWeight.w800, color: bad ? context.tone(Brand.crimsonDeep) : r.absent ? cs.onSurfaceVariant : null),
      decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        filled: true, fillColor: bad ? Brand.crimson.withValues(alpha: .08) : widget.pending ? Brand.gold.withValues(alpha: .08) : null,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: bad ? Brand.crimson : cs.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: bad ? Brand.crimson : Brand.gold, width: 2))),
      onChanged: (v) { setState(() {}); widget.onChanged(v); },
    );
  }
}
