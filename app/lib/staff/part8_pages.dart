import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/marks_rules.dart';
import '../core/school_docs.dart' show openTablePdf;
import '../core/theme.dart';
import '../core/xlsx_writer.dart';
import '../widgets/common.dart';
import '../widgets/hub_tabs.dart';
import '../widgets/royal_extras.dart' show ShimmerPage;
import '../widgets/royal_motion.dart' show FadeRise;
import 'exams_marks.dart' show examsYearProvider;
import 'office_reports.dart' show StatCard, statGrid, ReportTable, wideTable;
import 'staff_data.dart';
import 'staff_shell.dart';

/// Part 8 pages for the class and exams side (what RCIS uses in MyClassBoard, made simpler):
///   • Exam reports — who has entered marks (with the last date and one button to remind), class marks sheet, grade-wise, overall result, absentees, who opened the report card
///   • Promotion — everyone passes unless marked detained
///   • Attendance register — one class, one month, like the paper register
///   • Diary check — today's timetable subjects with no diary post yet

Widget _loading() => const ShimmerPage();
Widget _err(Object e) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e), style: const TextStyle(color: Brand.crimsonDeep)));
String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
Widget _muted(BuildContext context, String t) => Text(t, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant));

/// The exams this person may look at (all for the office, IT, Principal and coordinators; own grades for teachers), newest sensible first.
List<Map<String, dynamic>> _myExams(WidgetRef ref, {bool termOnly = false}) {
  final s = ref.watch(sessionProvider).value;
  final exams = ref.watch(examsYearProvider).value ?? const <Map<String, dynamic>>[];
  final mine = ref.watch(mySectionsProvider).value ?? const <Map<String, dynamic>>[];
  final grades = {for (final m in mine) m['grade']['id'] as String};
  final all = s != null && (s.isOffice || s.hasRole('coordinator'));
  return [for (final e in exams) if ((all || grades.contains(e['grade']?['id'])) && (!termOnly || e['kind'] != 'test')) e];
}

Widget _examPick(List<Map<String, dynamic>> exams, String? value, ValueChanged<String?> onChanged) => PickField<String>(
    label: 'Exam', value: exams.any((e) => e['id'] == value) ? value : null,
    items: [for (final e in exams) DropdownMenuItem(value: e['id'] as String, child: Text('${e['grade']?['code']} · ${e['name']}', overflow: TextOverflow.ellipsis))],
    onChanged: onChanged);

/// The exam to open first: the latest term exam that has started (or the first in the list).
String? _firstExam(List<Map<String, dynamic>> exams) {
  if (exams.isEmpty) return null;
  final today = _iso(DateTime.now());
  final started = exams.where((e) => e['kind'] == 'term' && e['starts_on'] != null && '${e['starts_on']}'.compareTo(today) <= 0).toList();
  return (started.isEmpty ? exams.firstWhere((e) => e['kind'] == 'term', orElse: () => exams.first) : started.first)['id'] as String;
}

// ================================================================== MARKS STATUS
final _statusProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, exam) async =>
    Map<String, dynamic>.from(await db.rpc('marks_status', params: {'p_exam': exam}) as Map));

/// Who has entered marks for one exam: subject × section, the last date, and one button to remind. Shown inside Exam reports.
class MarksEntered extends ConsumerStatefulWidget {
  final Map<String, dynamic> exam;
  const MarksEntered({super.key, required this.exam});
  @override
  ConsumerState<MarksEntered> createState() => _MarksEnteredState();
}

class _MarksEnteredState extends ConsumerState<MarksEntered> {
  bool busy = false;
  String get examId => widget.exam['id'] as String;

  Future<void> _due(DateTime? d) async {
    final e = widget.exam;
    try {
      await db.rpc('exam_save', params: {'p_exam': e['id'], 'p_name': e['name'], 'p_starts': e['starts_on'], 'p_ends': e['ends_on'], 'p_due': d == null ? null : _iso(d)});
      ref.invalidate(examsYearProvider); ref.invalidate(_statusProvider(examId));
      if (mounted) toast(context, d == null ? 'Last date removed' : 'Last date set: ${DateFormat('d MMM').format(d)} ✓');
    } catch (x) { if (mounted) toast(context, friendlyError(x)); }
  }

  Future<void> _remind() async {
    setState(() => busy = true);
    try {
      final n = (await db.rpc('marks_remind', params: {'p_exam': examId}) as num?) ?? 0;
      if (mounted) toast(context, n == 0 ? 'Everyone is done — nobody to remind ✓' : 'Reminder sent to $n ${n == 1 ? 'teacher' : 'teachers'} ✓');
    } catch (x) { if (mounted) toast(context, friendlyError(x)); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    final cs = Theme.of(context).colorScheme;
    final exam = widget.exam;
    final canSet = (s.isOffice || s.hasRole('coordinator')) && !s.viewOnly;
    final due = exam['marks_due'] == null ? null : DateTime.parse(exam['marks_due']);
    return ref.watch(_statusProvider(examId)).when(loading: _loading, error: (e, _) => _err(e), data: (d) {
      final secs = List<Map<String, dynamic>>.from(d['sections'] ?? const []);
      final rows = List<Map<String, dynamic>>.from(d['rows'] ?? const []);
      if (secs.isEmpty || rows.isEmpty) return Panel(child: Text('This class has no sections or subjects yet.', style: TextStyle(color: cs.onSurfaceVariant)));
      var done = 0, total = 0;
      for (final r in rows) { for (final c in Map<String, dynamic>.from(r['cells'] ?? const {}).values) { done += ((c as Map)['done'] ?? 0) as int; total += (c['total'] ?? 0) as int; } }
      Widget cell(Map<String, dynamic> r, String sec) {
        final c = Map<String, dynamic>.from(r['cells'] ?? const {})[sec];
        if (c == null) return Text('—', style: TextStyle(color: cs.onSurfaceVariant));
        final dn = (c['done'] ?? 0) as int, tt = (c['total'] ?? 0) as int;
        if (tt == 0) return Text('—', style: TextStyle(color: cs.onSurfaceVariant));
        final (fg, bg) = dn >= tt ? (Brand.green, Brand.greenTint) : dn == 0 ? (Brand.crimsonDeep, Brand.crimsonTint) : (Brand.amber, Brand.amberTint);
        return Tooltip(message: '${c['teachers'] ?? 'No teacher set'}', child: Pill('$dn/$tt', fg: fg, bg: bg));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        statGrid(context, [
          StatCard('Marks entered', done, sub: 'of $total', tone: done >= total ? Brand.green : null),
          StatCard('Still to enter', total - done, tone: total - done > 0 ? Brand.amber : Brand.green),
          StatCard('Done', total == 0 ? 0 : (done * 100 / total).round(), sub: 'per cent'),
        ]),
        Panel(padding: const EdgeInsets.all(12), child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            onPressed: !canSet ? null : () async {
              final x = await showDatePicker(context: context, initialDate: due ?? DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 200)), lastDate: DateTime.now().add(const Duration(days: 300)));
              if (x != null) _due(x);
            },
            icon: const Icon(Icons.event_available_rounded, size: 18),
            label: Text(due == null ? 'Set the last date for marks' : 'Last date for marks: ${DateFormat('EEE, d MMM').format(due)}')),
          if (canSet && done < total) FilledButton.icon(onPressed: busy ? null : _remind, icon: const Icon(Icons.notifications_active_rounded, size: 18), label: Text(busy ? 'Sending…' : 'Remind teachers not done')),
        ])),
        Panel(padding: const EdgeInsets.all(10), child: wideTable(context, ReportTable(
          cols: [('Subject', 4, false), ('Teachers', 5, false), for (final x in secs) ('${x['label']}', 2, true)],
          rows: [for (final r in rows) [
            Text('${r['subject']}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text({for (final c in Map<String, dynamic>.from(r['cells'] ?? const {}).values) if ((c as Map)['teachers'] != null) ...'${c['teachers']}'.split(', ')}.join(', '),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            for (final x in secs) cell(r, x['id'] as String),
          ]]), min: 420.0 + secs.length * 90)),
        _muted(context, 'Green = done · amber = partly · red = not started. A mark counts once the written paper is in (or AB). Only students who take the subject are counted.'),
      ]);
    });
  }
}

// ================================================================== EXAM REPORTS
final _resultsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, exam) async {
  ref.cacheFor();
  return Map<String, dynamic>.from(await db.rpc('exam_results', params: {'p_exam': exam}) as Map);
});
final _viewsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, exam) async =>
    [for (final x in (await db.rpc('report_views', params: {'p_exam': exam})) as List? ?? const []) Map<String, dynamic>.from(x as Map)]);

class ExamReportsPage extends ConsumerStatefulWidget {
  /// The tab to open on: 'status' (Marks entered) · 'sheet' · 'grades' · 'result' · 'absent' · 'views'
  final String tab;
  const ExamReportsPage({super.key, this.tab = 'status'});
  @override
  ConsumerState<ExamReportsPage> createState() => _ExamReportsPageState();
}

class _ExamReportsPageState extends ConsumerState<ExamReportsPage> {
  String? examId; late String tab = widget.tab; String section = ''; String subject = '';
  static const _tabs = [('status', 'Marks entered'), ('sheet', 'Class marks sheet'), ('grades', 'Grade-wise'), ('result', 'Overall result'), ('absent', 'Absent'), ('views', 'Report card opened')];

  bool _takes(Map st, Map p) => takesSubject(st['l2'], st['l3'], '${p['name']}', grp: st['grp'], el: st['el']);
  Map? _m(Map st, Map p) { final m = st['marks'] is Map ? (st['marks'] as Map)[p['subject_id']] : null; return m is Map ? m : null; }

  /// A student's result over the subjects that count: (marks, maximum, a subject below 33%, absent somewhere, marks missing)
  ({num got, num max, bool low, bool absent, bool missing, bool any}) _overall(Map st, List<Map<String, dynamic>> papers, int gno) {
    num got = 0, max = 0; var low = false, ab = false, miss = false, any = false;
    for (final p in papers) {
      if (!_takes(st, p) || cardPart(gno, '${p['part']}', '${p['name']}', st['l3'] as String?) != 'main') continue;
      final r = markOf(_m(st, p), p);
      if (!r.has) { miss = true; continue; }
      any = true; got += r.total; max += r.max;
      if (r.absent) { ab = true; } else if (r.max > 0 && r.total * 100 / r.max < 32.5) { low = true; }
    }
    return (got: got, max: max, low: low, absent: ab, missing: miss, any: any);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final exams = _myExams(ref);
    examId ??= _firstExam(exams);
    final exam = exams.where((e) => e['id'] == examId).firstOrNull;
    final data = exam == null ? null : ref.watch(_resultsProvider(examId!));
    return StaffPage(title: 'Exams & marks · Reports', hub: Hub.staffExams,
      subtitle: 'Who has entered marks, then the reports. Everything opens straight away, with Excel and Print where it helps.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _examPick(exams, examId, (v) => setState(() { examId = v; section = ''; subject = ''; })),
          const SizedBox(height: 12),
          SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final (k, t) in _tabs) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(t), selected: tab == k, showCheckmark: false, selectedColor: Brand.crimson,
                labelStyle: TextStyle(fontWeight: FontWeight.w800, color: tab == k ? Colors.white : null), onSelected: (_) => setState(() => tab = k))),
          ])),
        ])),
        if (exam == null) Panel(child: Text(exams.isEmpty ? 'No exams for your classes yet.' : 'Pick an exam.', style: TextStyle(color: cs.onSurfaceVariant)))
        else if (tab == 'status') MarksEntered(key: ValueKey(examId), exam: exam)
        else if (tab == 'views') _views(context, cs)
        else data!.when(loading: _loading, error: (e, _) => _err(e), data: (d) {
          final secs = List<Map<String, dynamic>>.from(d['sections'] ?? const []);
          final papers = List<Map<String, dynamic>>.from(d['papers'] ?? const []);
          final students = List<Map<String, dynamic>>.from(d['students'] ?? const []);
          final gno = (d['exam']?['grade_no'] ?? 0) as int;
          if (secs.isEmpty || students.isEmpty) return Panel(child: Text('No students to show for this exam.', style: TextStyle(color: cs.onSurfaceVariant)));
          final label = {for (final x in secs) x['id'] as String: '${x['label']}'};
          return FadeRise(key: ValueKey('$examId|$tab'), dy: 8, child: switch (tab) {
            'grades' => _grades(context, cs, secs, papers, students, label),
            'result' => _result(context, cs, secs, papers, students, gno, exam),
            'absent' => _absent(context, cs, papers, students, label, exam),
            _ => _sheet(context, cs, secs, papers, students, gno, label, exam),
          });
        }),
      ]),
    );
  }

  Widget _picks(List<Map<String, dynamic>> secs, List<Map<String, dynamic>> papers, {bool allSecs = true, bool allSubs = true, List<Widget> actions = const []}) => Padding(padding: const EdgeInsets.only(bottom: 12), child: PickRow(children: [
    Expanded(flex: 2, child: PickField<String>(label: 'Class', value: secs.any((x) => x['id'] == section) ? section : (allSecs ? '' : secs.first['id'] as String), items: [
      if (allSecs) const DropdownMenuItem(value: '', child: Text('All sections')),
      for (final x in secs) DropdownMenuItem(value: x['id'] as String, child: Text('${x['label']}')),
    ], onChanged: (v) => setState(() => section = v ?? ''))),
    const SizedBox(width: 12),
    Expanded(flex: 3, child: PickField<String>(label: 'Subject', value: papers.any((p) => p['subject_id'] == subject) ? subject : (allSubs ? '' : papers.first['subject_id'] as String), items: [
      if (allSubs) const DropdownMenuItem(value: '', child: Text('All subjects')),
      for (final p in papers) DropdownMenuItem(value: p['subject_id'] as String, child: Text('${p['name']}')),
    ], onChanged: (v) => setState(() => subject = v ?? ''))),
    for (final a in actions) ...[const SizedBox(width: 8), a],
  ]));

  // ---------------------------------------------------------------- class marks sheet
  Widget _sheet(BuildContext context, ColorScheme cs, List<Map<String, dynamic>> secs, List<Map<String, dynamic>> papers, List<Map<String, dynamic>> students, int gno, Map<String, String> label, Map<String, dynamic> exam) {
    final sec = secs.any((x) => x['id'] == section) ? section : secs.first['id'] as String;
    final list = students.where((st) => st['section_id'] == sec).toList();
    final one = papers.where((p) => p['subject_id'] == subject).firstOrNull;
    final head = <String>['Roll', 'Student', 'Admission no.'];
    final rows = <List<String>>[];
    if (one != null) {
      final ps = partsOf(one);
      final (li, le) = ps.isNotEmpty ? ('Internal', 'Written') : markLabels(gno, '${one['part']}');
      head.addAll([for (final c in ps) '${c.$1} /${fmtMark(c.$2)}', if (one['mi'] != null) '$li /${fmtMark(one['mi'] as num?)}', '${one['mi'] == null ? 'Marks' : le} /${fmtMark(one['me'] as num?)}', 'Total', 'Grade']);
      for (final st in list) {
        if (!_takes(st, one)) continue;
        final m = _m(st, one); final r = markOf(m, one);
        final pv = m?['p'] is Map ? m!['p'] as Map : const {};
        rows.add(['${st['roll'] ?? ''}', '${st['name']}', '${st['adm'] ?? ''}', for (final c in ps) pv[c.$1] == null ? '' : fmtMark(pv[c.$1] as num),
          if (one['mi'] != null) fmtMark(r.internal), r.absent ? 'AB' : fmtMark(r.written), r.has ? fmtMark(r.total) : '', r.absent ? 'Absent' : r.has && r.max > 0 ? cbseGrade(r.total * 100 / r.max) : '']);
      }
    } else {
      head.addAll([for (final p in papers) '${p['name']}', 'Total', 'Grade']);
      for (final st in list) {
        final o = _overall(st, papers, gno);
        rows.add(['${st['roll'] ?? ''}', '${st['name']}', '${st['adm'] ?? ''}',
          for (final p in papers) !_takes(st, p) ? '—' : (() { final r = markOf(_m(st, p), p); return r.absent ? 'AB${r.internal == null ? '' : ' (${fmtMark(r.internal)})'}' : r.has ? fmtMark(r.total) : ''; })(),
          o.any ? '${fmtMark(o.got)} / ${fmtMark(o.max)}' : '', o.any && o.max > 0 && !o.absent ? cbseGrade(o.got * 100 / o.max) : o.absent ? 'Absent' : '']);
      }
    }
    final title = '${exam['name']} · ${label[sec]}${one == null ? '' : ' · ${one['name']}'}';
    return Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _picks(secs, papers, allSecs: false, actions: [
        OutlinedButton.icon(onPressed: () async {
          try { await saveBytes(buildXlsx('Marks', head, [for (final r in rows) [for (final (i, c) in r.indexed) i == 0 || i > 2 ? (num.tryParse(c) ?? c) : c]], widths: [7, 26, 16, for (var i = 3; i < head.length; i++) 13]), 'RCIS-${title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}.xlsx'); }
          catch (e) { if (context.mounted) toast(context, 'Could not save the file: ${friendlyError(e)}'); }
        }, icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Excel')),
        OutlinedButton.icon(onPressed: () => openTablePdf(context, title: 'Marks sheet', sub: title, head: head, rows: rows, leftAligned: 3,
            flex: [1, 4, 2.4, for (var i = 3; i < head.length; i++) 1.4], landscape: head.length > 9, size: head.length > 11 ? 7.5 : 8.5),
            icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Print')),
      ]),
      if (rows.isEmpty) Text('No students take this subject in this class.', style: TextStyle(color: cs.onSurfaceVariant))
      else wideTable(context, ReportTable(
        cols: [for (final (i, h) in head.indexed) (h, i == 1 ? 5 : i == 2 ? 3 : i == 0 ? 1 : 2, i > 2)],
        rows: [for (final r in rows) [for (final (i, c) in r.indexed) Text(c, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: i == 1 || i >= r.length - 2 ? FontWeight.w800 : null, color: c.startsWith('AB') || c == 'Absent' ? context.tone(Brand.crimsonDeep) : null))]]),
        min: 420.0 + (head.length - 3) * 86),
      const SizedBox(height: 8),
      _muted(context, 'AB = absent for the written paper. The total then shows the internal marks alone (in brackets on the all-subjects sheet).'),
    ]));
  }

  // ---------------------------------------------------------------- grade-wise
  Widget _grades(BuildContext context, ColorScheme cs, List<Map<String, dynamic>> secs, List<Map<String, dynamic>> papers, List<Map<String, dynamic>> students, Map<String, String> label) {
    final p = papers.where((x) => x['subject_id'] == subject).firstOrNull ?? papers.first;
    final list = students.where((st) => (section.isEmpty || st['section_id'] == section) && _takes(st, p)).toList();
    final by = <String, List<Map<String, dynamic>>>{for (final g in gradeScale) g.$1: []};
    final absent = <Map<String, dynamic>>[]; var none = 0;
    for (final st in list) {
      final r = markOf(_m(st, p), p);
      if (r.absent) { absent.add(st); } else if (!r.has || r.max <= 0) { none++; } else { by[cbseGrade(r.total * 100 / r.max)]!.add(st); }
    }
    final mx = [for (final l in by.values) l.length, absent.length, 1].reduce((a, b) => a > b ? a : b);
    void who(String g, List<Map<String, dynamic>> l) => showDialog<void>(context: context, builder: (c) => AlertDialog(
      title: Text('$g · ${l.length} ${l.length == 1 ? 'student' : 'students'}'),
      content: SizedBox(width: 420, child: ListView(shrinkWrap: true, children: [for (final st in l) ListTile(dense: true, title: Text('${st['name']}', style: const TextStyle(fontWeight: FontWeight.w700)), trailing: Text('${label[st['section_id']] ?? ''}'))])),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))]));
    Widget bar(String g, List<Map<String, dynamic>> l, Color color) => InkWell(onTap: l.isEmpty ? null : () => who(g, l), borderRadius: BorderRadius.circular(10), child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
      SizedBox(width: 62, child: Text(g, style: const TextStyle(fontWeight: FontWeight.w900))),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: l.length / mx), duration: const Duration(milliseconds: 700), curve: Curves.easeOutCubic,
          builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 20, backgroundColor: cs.surfaceContainerHighest, valueColor: AlwaysStoppedAnimation(color))))),
      SizedBox(width: 44, child: Text('${l.length}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900))),
    ])));
    return Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _picks(secs, papers, allSubs: false),
      for (final (i, g) in gradeScale.indexed) bar(g.$1, by[g.$1]!, i < 2 ? Brand.green : i >= gradeScale.length - 2 ? Brand.crimson : Brand.blue),
      if (absent.isNotEmpty) bar('Absent', absent, Brand.amber),
      const SizedBox(height: 8),
      _muted(context, '${list.length} students take ${p['name']}.${none > 0 ? ' $none without marks yet.' : ''} Tap a bar to see who.'),
    ]));
  }

  // ---------------------------------------------------------------- overall result
  Widget _result(BuildContext context, ColorScheme cs, List<Map<String, dynamic>> secs, List<Map<String, dynamic>> papers, List<Map<String, dynamic>> students, int gno, Map<String, dynamic> exam) {
    var appeared = 0, passed = 0, low = 0, missing = 0;
    final table = <String, Map<String, int>>{for (final x in secs) x['id'] as String: {}};
    for (final st in students) {
      final o = _overall(st, papers, gno);
      if (o.missing) missing++;
      if (!o.any) continue;
      appeared++;
      if (o.low) low++;
      if (!o.low && !o.absent) passed++;
      final g = o.absent ? 'AB' : cbseGrade(o.max > 0 ? o.got * 100 / o.max : 0);
      final t = table[st['section_id']]; if (t != null) t[g] = (t[g] ?? 0) + 1;
    }
    final gs = [for (final g in gradeScale) g.$1, 'AB'];
    final tot = {for (final g in gs) g: table.values.fold<int>(0, (a, t) => a + (t[g] ?? 0))};
    final test = exam['kind'] == 'test';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      statGrid(context, [
        StatCard('Appeared', appeared),
        StatCard('Passed', passed, tone: Brand.green, sub: '33% or more in every subject'),
        StatCard('Below 33% in a subject', low, tone: low > 0 ? Brand.crimsonDeep : null, sub: low > 0 ? 'needs attention' : null),
        StatCard('Marks not entered', missing, tone: missing > 0 ? Brand.amber : null, sub: 'students with a gap'),
      ]),
      Panel(title: test ? 'By overall grade (all subjects together, for staff only)' : 'By overall grade', padding: const EdgeInsets.all(10), child: wideTable(context, ReportTable(
        cols: [('Class', 3, false), for (final g in gs) (g, 1, true), ('Total', 2, true)],
        rows: [
          for (final x in secs) [Text('${x['label']}', style: const TextStyle(fontWeight: FontWeight.w800)), for (final g in gs) Text('${table[x['id']]![g] ?? 0}'),
            Text('${table[x['id']]!.values.fold<int>(0, (a, b) => a + b)}', style: const TextStyle(fontWeight: FontWeight.w900))],
          [const Text('Total'), for (final g in gs) Text('${tot[g]}'), Text('${tot.values.fold<int>(0, (a, b) => a + b)}')],
        ], totals: {secs.length}), min: 640)),
      _muted(context, 'The grade is worked out from the real percentage of the subjects that count in the total. AB = absent for a written paper.'),
    ]);
  }

  // ---------------------------------------------------------------- absent in the exam
  Widget _absent(BuildContext context, ColorScheme cs, List<Map<String, dynamic>> papers, List<Map<String, dynamic>> students, Map<String, String> label, Map<String, dynamic> exam) {
    final rows = <List<String>>[];
    for (final st in students) {
      final subs = [for (final p in papers) if (_takes(st, p) && markOf(_m(st, p), p).absent) '${p['name']}'];
      if (subs.isNotEmpty) rows.add(['${label[st['section_id']] ?? ''}', '${st['roll'] ?? ''}', '${st['name']}', '${st['adm'] ?? ''}', subs.join(', ')]);
    }
    const head = ['Class', 'Roll', 'Student', 'Admission no.', 'Absent for'];
    return Panel(title: '${rows.length} ${rows.length == 1 ? 'student was' : 'students were'} absent for a paper', trailing: rows.isEmpty ? null : Wrap(spacing: 8, children: [
      OutlinedButton.icon(onPressed: () async {
        try { await saveBytes(buildXlsx('Absent', head, rows, widths: [9, 7, 26, 16, 44]), 'RCIS-absent-${'${exam['grade']?['code']}-${exam['name']}'.replaceAll(' ', '-')}.xlsx'); }
        catch (e) { if (context.mounted) toast(context, 'Could not save the file: ${friendlyError(e)}'); }
      }, icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Excel')),
      OutlinedButton.icon(onPressed: () => openTablePdf(context, title: 'Absent in the exam', sub: '${exam['grade']?['code']} · ${exam['name']}', head: head, rows: rows, leftAligned: 5, flex: [1.4, 1, 4, 2.6, 6]),
          icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Print')),
    ]), child: rows.isEmpty
        ? Text('Nobody is marked AB in this exam.', style: TextStyle(color: cs.onSurfaceVariant))
        : wideTable(context, ReportTable(cols: const [('Class', 2, false), ('Roll', 1, false), ('Student', 5, false), ('Admission no.', 3, false), ('Absent for', 7, false)],
            rows: [for (final r in rows) [for (final (i, c) in r.indexed) Text(c, style: TextStyle(fontWeight: i == 2 ? FontWeight.w800 : null))]]), min: 640));
  }

  // ---------------------------------------------------------------- who opened the report card
  Widget _views(BuildContext context, ColorScheme cs) => ref.watch(_viewsProvider(examId!)).when(loading: _loading, error: (e, _) => _err(e), data: (rows) {
    if (rows.isEmpty) return Panel(child: Text('No report cards to show for this exam.', style: TextStyle(color: cs.onSurfaceVariant)));
    return Panel(title: 'How many families opened the published report card', padding: const EdgeInsets.all(10), child: wideTable(context, ReportTable(
      cols: const [('Class', 2, false), ('Students', 2, true), ('Published', 2, true), ('Opened', 2, true), ('Share', 5, false), ('', 4, true)],
      rows: [for (final r in rows) (() {
        final pub = (r['published'] ?? 0) as int, op = (r['opened'] ?? 0) as int;
        final not = List<String>.from(r['not_opened'] ?? const []);
        return <Widget>[
          Text('${r['label']}', style: const TextStyle(fontWeight: FontWeight.w800)), Text('${r['students']}'), Text('$pub'), Text('$op', style: const TextStyle(fontWeight: FontWeight.w900)),
          pub == 0 ? Text('Not published yet', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))
              : ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: op / pub, minHeight: 10, backgroundColor: cs.surfaceContainerHighest, valueColor: AlwaysStoppedAnimation(op >= pub ? Brand.green : Brand.gold))),
          not.isEmpty ? const SizedBox() : TextButton(onPressed: () => showDialog<void>(context: context, builder: (c) => AlertDialog(
            title: Text('${r['label']} · not opened yet (${not.length})'),
            content: SizedBox(width: 380, child: ListView(shrinkWrap: true, children: [for (final n in not) Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(n))])),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))])), child: Text('Not opened (${not.length})')),
        ];
      })()]), min: 700));
  });
}

// ================================================================== PROMOTION
final _promoProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, section) async =>
    Map<String, dynamic>.from(await db.rpc('promotion_sheet', params: {'p_section': section}) as Map));

class PromotionPage extends ConsumerStatefulWidget {
  const PromotionPage({super.key});
  @override
  ConsumerState<PromotionPage> createState() => _PromotionPageState();
}

class _PromotionPageState extends ConsumerState<PromotionPage> {
  String? sectionId; final detained = <String>{}; String? loadedFor; bool busy = false, changed = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    final cs = Theme.of(context).colorScheme;
    final all = ref.watch(mySectionsProvider).value ?? const <Map<String, dynamic>>[];
    final secs = [for (final x in all) if (gradeNoOf('${x['grade']?['code']}') > 0 && (s.isOffice || x['class_teacher_id'] == s.staff?['id'])) x];
    if (sectionId == null && secs.isNotEmpty) sectionId = secs.first['id'] as String;
    final data = sectionId == null ? null : ref.watch(_promoProvider(sectionId!));
    final d = data?.value;
    if (d != null && loadedFor != sectionId) {
      loadedFor = sectionId; changed = false;
      detained..clear()..addAll([for (final r in List<Map<String, dynamic>>.from(d['rows'] ?? const [])) if (r['result'] == 'detained') r['id'] as String]);
    }
    final rows = List<Map<String, dynamic>>.from(d?['rows'] ?? const []);
    final can = d?['can'] == true;
    return StaffPage(title: 'Promotion', hub: Hub.staffExams, subtitle: 'Who moves up at the end of the year. Everyone starts as Passed; change only the few who are detained.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(padding: const EdgeInsets.all(14), child: PickRow(children: [
          Expanded(flex: 2, child: PickField<String>(label: 'Class', value: secs.any((x) => x['id'] == sectionId) ? sectionId : null,
              items: [for (final x in secs) DropdownMenuItem(value: x['id'] as String, child: Text(sectionLabel(x)))], onChanged: (v) => setState(() { sectionId = v; loadedFor = null; }))),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: Text(d == null ? '' : '${rows.length - detained.length} passed · ${detained.length} detained', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
          if (can) FilledButton.icon(onPressed: busy ? null : () async {
            setState(() => busy = true);
            try {
              await db.rpc('promotion_save', params: {'p_section': sectionId, 'p_detained': detained.toList()});
              ref.invalidate(_promoProvider(sectionId!)); loadedFor = null;
              if (mounted) toast(context, 'Saved ✓ — the move-up will follow this.');
            } catch (x) { if (mounted) toast(context, friendlyError(x)); }
            if (mounted) setState(() => busy = false);
          }, icon: const Icon(Icons.save_rounded, size: 18), label: Text(busy ? 'Saving…' : 'Save')),
        ])),
        if (secs.isEmpty && ref.watch(mySectionsProvider).hasValue) Panel(child: Text('Promotion is saved by the class teacher, the office, IT or the Principal.', style: TextStyle(color: cs.onSurfaceVariant)))
        else if (data == null || data.isLoading && d == null) _loading()
        else if (data.hasError) _err(data.error!)
        else ...[
          if (d?['saved'] != true) Padding(padding: const EdgeInsets.only(bottom: 10), child: NoteBox('Not saved for this class yet. If everyone has passed, just press Save.')),
          Panel(padding: const EdgeInsets.all(10), child: ReportTable(
            cols: const [('Roll', 1, false), ('Student', 5, false), ('Result', 5, false), ('Moves to', 2, false)],
            rows: [for (final r in rows) (() {
              final det = detained.contains(r['id']);
              Widget chip(String t, bool on, Color c, bool value) => ChoiceChip(label: Text(t), selected: on, showCheckmark: false, selectedColor: c,
                  labelStyle: TextStyle(fontWeight: FontWeight.w800, color: on ? Colors.white : null),
                  onSelected: !can ? null : (_) => setState(() { value ? detained.add(r['id'] as String) : detained.remove(r['id']); changed = true; }));
              return <Widget>[
                Text('${r['roll'] ?? ''}', style: TextStyle(color: cs.onSurfaceVariant)),
                Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Wrap(spacing: 8, children: [chip('Passed', !det, Brand.green, false), chip('Detained', det, Brand.crimson, true)]),
                Text(det ? '${d?['code'] ?? ''} (same)' : '${d?['next'] ?? '—'}', style: TextStyle(fontWeight: FontWeight.w700, color: det ? context.tone(Brand.crimsonDeep) : null)),
              ];
            })()])),
          _muted(context, 'A detained student stays in the same grade when the classes move up, and the TC helper shows “not promoted”. Grades X and XII leave after the board exams, so nothing moves for them.'),
          if (changed) Padding(padding: const EdgeInsets.only(top: 6), child: Text('You have changes that are not saved yet.', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(Brand.amber)))),
        ],
      ]),
    );
  }
}

// ================================================================== ATTENDANCE REGISTER
final _registerProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, (String, String)>((ref, k) async =>
    Map<String, dynamic>.from(await db.rpc('attendance_register', params: {'p_section': k.$1, 'p_month': k.$2}) as Map));

class AttendanceRegisterPage extends ConsumerStatefulWidget {
  const AttendanceRegisterPage({super.key});
  @override
  ConsumerState<AttendanceRegisterPage> createState() => _AttendanceRegisterPageState();
}

class _AttendanceRegisterPageState extends ConsumerState<AttendanceRegisterPage> {
  String? sectionId; DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final secs = ref.watch(mySectionsProvider).value ?? const <Map<String, dynamic>>[];
    if (sectionId == null && secs.isNotEmpty) sectionId = secs.first['id'] as String;
    final data = sectionId == null ? null : ref.watch(_registerProvider((sectionId!, _iso(month))));
    final now = DateTime.now();
    final canNext = DateTime(month.year, month.month + 1).isBefore(DateTime(now.year, now.month + 1));
    return StaffPage(title: 'Attendance register', hub: Hub.staffAttendance,
      subtitle: 'One class, one month, ready to print — like the paper register.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(padding: const EdgeInsets.all(14), child: PickRow(children: [
          Expanded(flex: 3, child: PickField<String>(label: 'Class', value: secs.any((x) => x['id'] == sectionId) ? sectionId : null,
              items: [for (final x in secs) DropdownMenuItem(value: x['id'] as String, child: Text(sectionLabel(x)))], onChanged: (v) => setState(() => sectionId = v))),
          const SizedBox(width: 12),
          IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left_rounded), tooltip: 'Month before'),
          Text(DateFormat('MMMM yyyy').format(month), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          IconButton(onPressed: canNext ? () => setState(() => month = DateTime(month.year, month.month + 1)) : null, icon: const Icon(Icons.chevron_right_rounded), tooltip: 'Next month'),
        ])),
        if (data == null) Panel(child: Text('Pick a class.', style: TextStyle(color: cs.onSurfaceVariant)))
        else data.when(loading: _loading, error: (e, _) => _err(e), data: (d) {
          final days = List<Map<String, dynamic>>.from(d['days'] ?? const []);
          final rows = List<Map<String, dynamic>>.from(d['rows'] ?? const []);
          final working = [for (final x in days) if (x['closed'] != true && x['marked'] == true) '${x['d']}'];
          if (rows.isEmpty) return Panel(child: Text('No students in this class.', style: TextStyle(color: cs.onSurfaceVariant)));
          String mark(Map<String, dynamic> r, Map<String, dynamic> day) {
            if (day['closed'] == true) return DateTime.parse('${day['d']}').weekday == 7 ? 'S' : 'H';
            return '${(r['marks'] as Map?)?['${day['d']}'] ?? (day['marked'] == true ? '' : '·')}';
          }
          int present(Map<String, dynamic> r) => working.where((x) => (r['marks'] as Map?)?[x] == 'P').length;
          final head = ['Roll', 'Student', for (final x in days) '${DateTime.parse('${x['d']}').day}', 'Present', '%'];
          final table = [for (final r in rows) ['${r['roll'] ?? ''}', '${r['name']}', for (final x in days) mark(r, x), '${present(r)}/${working.length}',
            working.isEmpty ? '' : '${(present(r) * 100 / working.length).round()}']];
          final title = '${d['label']} · ${DateFormat('MMMM yyyy').format(month)}';
          Color? tone(String c) => c == 'A' ? context.tone(Brand.crimsonDeep) : c == 'L' ? context.tone(Brand.violet) : c == 'P' ? context.tone(Brand.green) : cs.onSurfaceVariant.withValues(alpha: .5);
          const w = 26.0;
          final head1 = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant);
          final grid = SizedBox(width: 44 + 190 + days.length * w + 120, child: Column(children: [
            Container(color: Brand.gold.withValues(alpha: .08), padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10), child: Row(children: [
              SizedBox(width: 34, child: Text('ROLL', style: head1)), SizedBox(width: 180, child: Text('STUDENT', style: head1)),
              for (final x in days) SizedBox(width: w, child: Text('${DateTime.parse('${x['d']}').day}', textAlign: TextAlign.center, style: head1)),
              SizedBox(width: 70, child: Text('PRESENT', textAlign: TextAlign.right, style: head1)), SizedBox(width: 40, child: Text('%', textAlign: TextAlign.right, style: head1)),
            ])),
            for (var i = 0; i < rows.length; i++) Container(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .5)))),
              child: Row(children: [
                SizedBox(width: 34, child: Text(table[i][0], style: TextStyle(color: cs.onSurfaceVariant))),
                SizedBox(width: 180, child: Text(table[i][1], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                for (final (j, _) in days.indexed) SizedBox(width: w, child: Text(table[i][2 + j], textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: tone(table[i][2 + j])))),
                SizedBox(width: 70, child: Text(table[i][2 + days.length], textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900))),
                SizedBox(width: 40, child: Text(table[i][3 + days.length], textAlign: TextAlign.right, style: TextStyle(color: cs.onSurfaceVariant))),
              ])),
          ]));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Panel(padding: EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 12, 12, 10), child: Row(children: [
                Expanded(child: Text('$title · ${working.length} working ${working.length == 1 ? 'day' : 'days'} marked', style: const TextStyle(fontWeight: FontWeight.w900))),
                OutlinedButton.icon(onPressed: () async {
                  try { await saveBytes(buildXlsx('Register', head, table, widths: [6, 26, for (final _ in days) 4, 10, 6]), 'RCIS-register-${title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}.xlsx'); }
                  catch (e) { if (context.mounted) toast(context, 'Could not save the file: ${friendlyError(e)}'); }
                }, icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Excel')),
                const SizedBox(width: 8),
                FilledButton.icon(onPressed: () => openTablePdf(context, title: 'Attendance register', sub: title, head: head, rows: table, leftAligned: 2, landscape: true, size: 7,
                    flex: [1.2, 6, for (final _ in days) 1, 2.2, 1.3], note: 'P present · A absent · L approved leave · S Sunday · H holiday · a dot = attendance not marked that day'),
                    icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Print')),
              ])),
              LayoutBuilder(builder: (_, c) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: grid)),
            ])),
            _muted(context, 'P present · A absent · L approved leave (marked by itself from the leave request) · S Sunday · H holiday · a dot = attendance not marked that day'),
          ]);
        }),
      ]),
    );
  }
}

// ================================================================== DIARY CHECK
final diaryCheckProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => Map<String, dynamic>.from(await db.rpc('diary_check') as Map));

class DiaryCheckPage extends ConsumerWidget {
  const DiaryCheckPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return StaffPage(title: 'Diary check',
      subtitle: 'Today’s subjects (from the timetable) that have no diary post yet. One tap reminds the teacher.',
      actions: [OutlinedButton.icon(onPressed: () => ref.invalidate(diaryCheckProvider), icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Check again'))],
      body: ref.watch(diaryCheckProvider).when(loading: _loading, error: (e, _) => _err(e), data: (d) {
        final rows = List<Map<String, dynamic>>.from(d['rows'] ?? const []);
        final total = (d['total'] ?? 0) as int, posted = (d['posted'] ?? 0) as int;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          statGrid(context, [
            StatCard('Diary posts today', posted, sub: 'of $total subjects on the timetable', tone: total > 0 && posted >= total ? Brand.green : null),
            StatCard('Still to post', rows.length, tone: rows.isEmpty ? Brand.green : Brand.amber),
          ]),
          if (total == 0) Panel(child: Text('Nothing to check today: it is a holiday, or the timetable is not filled in yet.', style: TextStyle(color: cs.onSurfaceVariant)))
          else if (rows.isEmpty) Panel(child: Row(children: [Icon(Icons.verified_rounded, color: context.tone(Brand.green)), const SizedBox(width: 10), const Expanded(child: Text('Every subject on today’s timetable has its diary post ✓', style: TextStyle(fontWeight: FontWeight.w800)))]))
          else Panel(padding: const EdgeInsets.all(10), child: wideTable(context, ReportTable(
            cols: const [('Class', 2, false), ('Subject', 4, false), ('Teacher', 4, false), ('', 3, true)],
            rows: [for (final r in rows) [
              Text('${r['class']}', style: const TextStyle(fontWeight: FontWeight.w800)), Text('${r['subject']}'),
              Text('${r['teacher'] ?? 'No teacher set'}', style: TextStyle(color: r['has_teacher'] == true ? null : cs.onSurfaceVariant)),
              r['reminded'] == true ? Pill('Reminded', fg: Brand.green, bg: Brand.greenTint)
                  : r['has_teacher'] != true ? const SizedBox()
                  : OutlinedButton(onPressed: () async {
                      try { await db.rpc('diary_remind', params: {'p_section': r['section_id'], 'p_subject': r['subject_id']}); ref.invalidate(diaryCheckProvider); if (context.mounted) toast(context, 'Reminder sent to ${r['teacher']} ✓'); }
                      catch (e) { if (context.mounted) toast(context, friendlyError(e)); }
                    }, child: const Text('Remind')),
            ]]), min: 560)),
          _muted(context, 'Holidays are not counted. A subject counts as posted once any diary note for it is posted today.'),
        ]);
      }),
    );
  }
}
