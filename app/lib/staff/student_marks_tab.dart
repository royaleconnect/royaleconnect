import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/marks_rules.dart';
import '../core/school_docs.dart' show openReportCardPdf;
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_extras.dart' show ShimmerPage;
import 'staff_shell.dart';

/// A student's Marks tab: one tab per exam of this year, the school's card layout (no percentage printed),
/// and "Enter / change marks" — marks, grades, height, weight, remarks and participation in one go.
/// Subject teachers can change their own subjects; the class teacher and IT / office everything.

final studentMarksProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async =>
    Map<String, dynamic>.from(await db.rpc('student_marks', params: {'p_student': id}) as Map));

class StudentMarksTab extends ConsumerStatefulWidget {
  final String studentId; final String name;
  const StudentMarksTab({super.key, required this.studentId, required this.name});
  @override
  ConsumerState<StudentMarksTab> createState() => _StudentMarksTabState();
}

class _StudentMarksTabState extends ConsumerState<StudentMarksTab> {
  String? examId; bool editing = false, busy = false;
  final marks = <String, TextEditingController>{};       // subject|i / subject|e
  final co = <String, String>{};
  final height = TextEditingController(), weight = TextEditingController(), remarks = TextEditingController(), part = TextEditingController();

  @override
  void dispose() {
    for (final c in marks.values) { c.dispose(); }
    height.dispose(); weight.dispose(); remarks.dispose(); part.dispose();
    super.dispose();
  }

  void _startEdit(Map<String, dynamic> ex, Map<String, dynamic>? card) {
    for (final c in marks.values) { c.dispose(); }
    marks.clear();
    final m = Map<String, dynamic>.from(ex['marks'] ?? const {});
    for (final p in List<Map<String, dynamic>>.from(ex['papers'] ?? const [])) {
      final mm = m[p['subject_id']] is Map ? Map<String, dynamic>.from(m[p['subject_id']]) : const <String, dynamic>{};
      marks['${p['subject_id']}|i'] = TextEditingController(text: fmtMark(mm['i'] as num?));
      marks['${p['subject_id']}|e'] = TextEditingController(text: mm['ab'] == true ? 'AB' : fmtMark(mm['e'] as num?));
    }
    co..clear()..addAll({for (final e in (card?['co_scholastic'] as Map? ?? const {}).entries) '${e.key}': '${e.value}'});
    height.text = fmtMark(card?['height_cm'] as num?);
    weight.text = fmtMark(card?['weight_kg'] as num?);
    remarks.text = card?['remarks'] ?? '';
    part.text = card?['participation'] ?? '';
    setState(() => editing = true);
  }

  Future<void> _save(Map<String, dynamic> d, Map<String, dynamic> ex) async {
    final rows = <Map<String, dynamic>>[];
    final old = Map<String, dynamic>.from(ex['marks'] ?? const {});
    for (final p in List<Map<String, dynamic>>.from(ex['papers'] ?? const [])) {
      if (p['can'] != true || !takesSubject(d['l2'], d['l3'], '${p['name']}')) continue;
      final ti = marks['${p['subject_id']}|i']?.text ?? '', te = marks['${p['subject_id']}|e']?.text ?? '';
      final ri = readMark(ti), re = readMark(te);
      if (ri.bad || re.bad || (p['mi'] == null && ti.trim().isNotEmpty) ||
          (ri.value != null && p['mi'] != null && ri.value! > (p['mi'] as num)) || (re.value != null && re.value! > (p['me'] as num))) {
        toast(context, '${p['name']}: please check the marks in red.');
        return;
      }
      final o = old[p['subject_id']] is Map ? Map<String, dynamic>.from(old[p['subject_id']]) : const <String, dynamic>{};
      final changed = ri.value != o['i'] || re.value != o['e'] || (re.absent || ri.absent) != (o['ab'] == true);
      if (changed) rows.add({'student': widget.studentId, 'subject': p['subject_id'], 'i': ri.value, 'e': re.value, 'ab': re.absent || ri.absent});
    }
    setState(() => busy = true);
    try {
      if (rows.isNotEmpty) await db.rpc('marks_save', params: {'p_exam': ex['id'], 'p_rows': rows});
      if (d['can_card'] == true && ex['kind'] == 'term') {
        await db.rpc('report_extras_save', params: {'p_student': widget.studentId, 'p_exam': ex['id'], 'p': {
          'co': co, 'height': height.text.trim(), 'weight': weight.text.trim(), 'remarks': remarks.text.trim(), 'participation': part.text.trim()}});
      }
      ref.invalidate(studentMarksProvider(widget.studentId));
      if (mounted) { setState(() { busy = false; editing = false; }); toast(context, 'Saved ✓ — families see it on the published card.'); }
    } catch (e) {
      if (mounted) { setState(() => busy = false); toast(context, friendlyError(e)); }
    }
  }

  Future<void> _card(Map<String, dynamic> d, Map<String, dynamic> ex, Map<String, dynamic>? card) async {
    String? id = card?['id'];
    if (id == null && d['can_card'] == true) {
      try { id = await db.rpc('report_extras_save', params: {'p_student': widget.studentId, 'p_exam': ex['id'], 'p': <String, dynamic>{}}) as String?; ref.invalidate(studentMarksProvider(widget.studentId)); }
      catch (e) { if (mounted) toast(context, friendlyError(e)); return; }
    }
    if (id == null) { if (mounted) toast(context, 'The class teacher has not started this report card yet.'); return; }
    if (mounted) openReportCardPdf(context, id, name: '${widget.name} ${ex['name']}');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ref.watch(studentMarksProvider(widget.studentId)).when(
      loading: () => const Padding(padding: EdgeInsets.all(16), child: ShimmerPage()),
      error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e)))),
      data: (d) {
        final exams = List<Map<String, dynamic>>.from(d['exams'] ?? const []);
        if (exams.isEmpty) return ListView(padding: const EdgeInsets.all(16), children: const [NoteBox('No exams for this class yet. They appear here by themselves once the class has subjects.')]);
        final ex = exams.firstWhere((e) => e['id'] == examId, orElse: () {
          // open on the latest exam that has marks
          final withMarks = exams.where((e) => (e['marks'] as Map?)?.isNotEmpty == true).toList();
          return withMarks.isEmpty ? exams.first : withMarks.last;
        });
        final cards = Map<String, dynamic>.from(d['cards'] ?? const {});
        final cardRaw = cards.entries.where((e) => e.key.toLowerCase() == '${ex['key']}'.toLowerCase()).firstOrNull?.value;
        final card = cardRaw is Map ? Map<String, dynamic>.from(cardRaw) : null;
        final canAny = List<Map<String, dynamic>>.from(ex['papers'] ?? const []).any((p) => p['can'] == true) || d['can_card'] == true;
        final status = '${card?['status'] ?? ''}';
        return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final e in exams) ChoiceChip(label: Text('${e['name']}'), selected: e['id'] == ex['id'], showCheckmark: false, selectedColor: Brand.ink,
                labelStyle: TextStyle(fontWeight: FontWeight.w800, color: e['id'] == ex['id'] ? Colors.white : null),
                onSelected: editing ? null : (_) => setState(() => examId = e['id'])),
          ]),
          const SizedBox(height: 14),
          Panel(
            title: '${ex['name']}',
            trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (status.isNotEmpty) Pill(status == 'published' || status == 'locked' ? 'Card published' : 'Card in draft',
                  fg: status == 'published' || status == 'locked' ? Brand.green : Brand.amber, bg: status == 'published' || status == 'locked' ? Brand.greenTint : Brand.amberTint),
              if (!editing) OutlinedButton.icon(onPressed: () => _card(d, ex, card), icon: const Icon(Icons.picture_as_pdf_rounded, size: 18), label: const Text('Report card')),
              if (!editing && canAny) FilledButton.icon(onPressed: () => _startEdit(ex, card), icon: const Icon(Icons.edit_rounded, size: 18), label: const Text('Enter / change marks')),
            ]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (editing) Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Brand.amberTint, borderRadius: BorderRadius.circular(12)),
                child: Text('Type in any box — marks, grades, height, weight, remarks. Type AB for absent. Press Save when done.',
                    style: TextStyle(color: context.tone(Brand.amber), fontWeight: FontWeight.w700, fontSize: 13))),
              ..._tables(context, d, ex, cs),
            ]),
          ),
          if (ex['kind'] == 'term') _extras(context, d, card, cs),
          if (editing) Padding(padding: const EdgeInsets.only(top: 4), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: busy ? null : () => setState(() => editing = false), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: busy ? null : () => _save(d, ex), icon: const Icon(Icons.save_rounded, size: 18), label: Text(busy ? 'Saving…' : 'Save')),
          ])),
          const SizedBox(height: 10),
          Builder(builder: (_) {
            final t = _totals(d, ex);
            return Text('No percentage is printed on the report card — only Total and Grade, as the school does now.${t.$2 > 0 ? ' For staff: ${(t.$1 * 100 / t.$2).toStringAsFixed(1)}%.' : ''}',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant));
          }),
        ]);
      },
    );
  }

  /// (marks, maximum) of the subjects in the total
  (num, num) _totals(Map<String, dynamic> d, Map<String, dynamic> ex) {
    final gno = (d['grade_no'] ?? 0) as int;
    final m = Map<String, dynamic>.from(ex['marks'] ?? const {});
    num got = 0, max = 0;
    for (final p in List<Map<String, dynamic>>.from(ex['papers'] ?? const [])) {
      if (!takesSubject(d['l2'], d['l3'], '${p['name']}') || cardPart(gno, '${p['part']}', '${p['name']}', d['l3']) != 'main') continue;
      final mm = m[p['subject_id']] is Map ? Map<String, dynamic>.from(m[p['subject_id']]) : null;
      if (mm == null || (mm['i'] == null && mm['e'] == null && mm['ab'] != true)) continue;
      got += ((mm['i'] ?? 0) as num) + ((mm['e'] ?? 0) as num);
      max += ((p['mi'] ?? 0) as num) + ((p['me'] ?? 0) as num);
    }
    return (got, max);
  }

  List<Widget> _tables(BuildContext context, Map<String, dynamic> d, Map<String, dynamic> ex, ColorScheme cs) {
    final gno = (d['grade_no'] ?? 0) as int;
    final papers = [for (final p in List<Map<String, dynamic>>.from(ex['papers'] ?? const [])) if (takesSubject(d['l2'], d['l3'], '${p['name']}')) p];
    final m = Map<String, dynamic>.from(ex['marks'] ?? const {});
    final groups = <String, List<Map<String, dynamic>>>{'main': [], 'r3': [], 'skill': []};
    for (final p in papers) { groups[cardPart(gno, '${p['part']}', '${p['name']}', d['l3'])]!.add(p); }
    if (papers.isEmpty) return [Text('No subjects in this exam yet.', style: TextStyle(color: cs.onSurfaceVariant))];
    final out = <Widget>[];
    for (final (key, title) in [('main', ''), ('r3', 'Third language · Grade IX · school-assessed (CBSE) · not added to the total'), ('skill', 'Shown separately · not added to the total')]) {
      final list = groups[key]!;
      if (list.isEmpty) continue;
      if (title.isNotEmpty) out.add(Padding(padding: const EdgeInsets.fromLTRB(2, 18, 2, 8), child: Text(title.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1, color: context.tone(Brand.gold)))));
      out.add(_table(context, gno, list, m, cs, total: key == 'main', result: key == 'r3'));
    }
    return out;
  }

  Widget _table(BuildContext context, int gno, List<Map<String, dynamic>> papers, Map<String, dynamic> m, ColorScheme cs, {bool total = false, bool result = false}) {
    final two = papers.any((p) => p['mi'] != null);
    final (li, le) = markLabels(gno, '${papers.first['part']}');
    final theoryFirst = li == 'Practical';
    final same = papers.every((p) => p['mi'] == papers.first['mi'] && p['me'] == papers.first['me']);
    String hdr(String l, num? mx) => same && mx != null ? '$l\n/${fmtMark(mx)}' : l;
    final cols = <String>['Subject',
      if (two) ...(theoryFirst ? [hdr(le, papers.first['me'] as num?), hdr(li, papers.first['mi'] as num?)] : [hdr(li, papers.first['mi'] as num?), hdr(le, papers.first['me'] as num?)])
      else hdr('Marks', papers.first['me'] as num?),
      if (two) 'Total\n/${fmtMark(((papers.first['mi'] ?? 0) as num) + ((papers.first['me'] ?? 0) as num))}', 'Grade', if (result) 'Result'];
    num got = 0, max = 0; var counted = 0;
    Widget cell(Map p, String f) {
      final mx = (f == 'i' ? p['mi'] : p['me']) as num?;
      if (mx == null) return const Text('—');
      if (editing && p['can'] == true) {
        final c = marks['${p['subject_id']}|$f']!;
        return SizedBox(width: 72, child: _Box(c: c, max: mx));
      }
      final mm = m[p['subject_id']] is Map ? Map<String, dynamic>.from(m[p['subject_id']]) : null;
      if (mm == null) return Text('—', style: TextStyle(color: cs.onSurfaceVariant));
      if (f == 'e' && mm['ab'] == true) return Text('AB', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(Brand.crimsonDeep)));
      final v = mm[f] as num?;
      return Text.rich(TextSpan(children: [TextSpan(text: v == null ? '—' : fmtMark(v), style: const TextStyle(fontWeight: FontWeight.w700)),
        if (!same) TextSpan(text: ' /${fmtMark(mx)}', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant))]));
    }
    final rows = <List<Widget>>[];
    for (final p in papers) {
      final mm = m[p['subject_id']] is Map ? Map<String, dynamic>.from(m[p['subject_id']]) : null;
      final has = mm != null && (mm['i'] != null || mm['e'] != null);
      final t = has ? ((mm['i'] ?? 0) as num) + ((mm['e'] ?? 0) as num) : null;
      final mx = ((p['mi'] ?? 0) as num) + ((p['me'] ?? 0) as num);
      if (t != null) { got += t; max += mx; counted++; }
      rows.add([
        Text('${p['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        if (two) ...(theoryFirst ? [cell(p, 'e'), cell(p, 'i')] : [cell(p, 'i'), cell(p, 'e')]) else cell(p, 'e'),
        if (two) Text(t == null ? '—' : fmtMark(t), style: const TextStyle(fontWeight: FontWeight.w900)),
        Text(t == null || mx == 0 ? '' : cbseGrade(t * 100 / mx), style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
        if (result) t == null ? const Text('') : Pill(t * 100 / mx >= 33 ? 'Qualified' : 'Re-assessment', fg: t * 100 / mx >= 33 ? Brand.green : Brand.crimsonDeep, bg: t * 100 / mx >= 33 ? Brand.greenTint : Brand.crimsonTint),
      ]);
    }
    if (total && counted > 0 && !editing) {
      rows.add([const Text('Total'), if (two) ...[const Text(''), const Text('')] else const Text(''), if (two) Text('${fmtMark(got)} / ${fmtMark(max)}'),
        Text(cbseGrade(got * 100 / max)), if (result) const Text('')]);
      if (!two) rows.last[1] = Text('${fmtMark(got)} / ${fmtMark(max)}');
    }
    final head = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .7, color: cs.onSurfaceVariant);
    return ClipRRect(borderRadius: BorderRadius.circular(14), child: Container(
      decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant.withValues(alpha: .7)), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(color: Brand.gold.withValues(alpha: .08), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Row(children: [
          for (final (i, c) in cols.indexed) Expanded(flex: i == 0 ? 4 : 2, child: Text(c.toUpperCase(), textAlign: i == 0 ? TextAlign.left : TextAlign.right, style: head)),
        ])),
        for (final (ri, r) in rows.indexed) Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: editing ? 8 : 13),
          decoration: BoxDecoration(color: total && ri == rows.length - 1 && counted > 0 && !editing ? Brand.gold.withValues(alpha: .06) : null,
              border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .5)))),
          child: DefaultTextStyle.merge(style: TextStyle(fontWeight: total && ri == rows.length - 1 && counted > 0 && !editing ? FontWeight.w900 : null),
            child: Row(children: [
              for (final (i, c) in r.indexed) Expanded(flex: i == 0 ? 4 : 2, child: Align(alignment: i == 0 ? Alignment.centerLeft : Alignment.centerRight, child: c)),
            ]))),
      ])));
  }

  Widget _extras(BuildContext context, Map<String, dynamic> d, Map<String, dynamic>? card, ColorScheme cs) {
    final areas = '${d['areas'] ?? ''}'.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    final att = Map<String, dynamic>.from(d['attendance'] ?? const {});
    final edit = editing && d['can_card'] == true;
    final cardCo = Map<String, dynamic>.from(card?['co_scholastic'] ?? const {});
    Widget line(String k, Widget v) => Container(padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .4)))),
        child: Row(children: [Expanded(child: Text(k)), v]));
    Widget numBox(TextEditingController c) => SizedBox(width: 90, child: TextField(controller: c, textAlign: TextAlign.center, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10))));
    final wd = card?['working_days'] ?? att['working'], dp = card?['days_present'] ?? att['present'];
    final left = Panel(title: 'Co-scholastic · health', trailing: Text('5-point A–E', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)), child: Column(children: [
      for (final a in areas) line(a, edit
          ? SizedBox(width: 170, child: DropdownButtonFormField<String>(value: coGrades.containsKey(co[a]) ? co[a] : null, isDense: true, isExpanded: true,
              decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
              items: [for (final e in coGrades.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} · ${e.value}', overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => co[a] = v ?? '')))
          : Text('${cardCo[a] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w900))),
      line('Height (cm)', edit ? numBox(height) : Text(card?['height_cm'] == null ? '—' : '${fmtMark(card!['height_cm'] as num)} cm', style: const TextStyle(fontWeight: FontWeight.w800))),
      line('Weight (kg)', edit ? numBox(weight) : Text(card?['weight_kg'] == null ? '—' : '${fmtMark(card!['weight_kg'] as num)} kg', style: const TextStyle(fontWeight: FontWeight.w800))),
      line('Attendance', Text.rich(TextSpan(children: [TextSpan(text: wd == null || wd == 0 ? '—' : '$dp of $wd days', style: const TextStyle(fontWeight: FontWeight.w800)),
        TextSpan(text: '  · from the register', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))]))),
    ]));
    InputDecoration box(String hint) => InputDecoration(hintText: hint, isDense: true);
    final right = Panel(title: 'Remarks & participation', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('REMARK — CLASS TEACHER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.onSurfaceVariant)),
      const SizedBox(height: 6),
      edit ? TextField(controller: remarks, minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences, decoration: box('e.g. A sincere and hardworking student.'))
           : Text((card?['remarks'] ?? '').toString().isEmpty ? '—' : '${card!['remarks']}'),
      const SizedBox(height: 16),
      Text('SPECIFIC PARTICIPATION', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.onSurfaceVariant)),
      const SizedBox(height: 6),
      edit ? TextField(controller: part, minLines: 1, maxLines: 3, textCapitalization: TextCapitalization.sentences, decoration: box('e.g. First place in the inter-house quiz.'))
           : Text((card?['participation'] ?? '').toString().isEmpty ? '—' : '${card!['participation']}'),
    ]));
    return LayoutBuilder(builder: (_, c) => c.maxWidth < 760
        ? Column(children: [left, right])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: left), const SizedBox(width: 14), Expanded(child: right)]));
  }
}

class _Box extends StatefulWidget {
  final TextEditingController c; final num max;
  const _Box({required this.c, required this.max});
  @override
  State<_Box> createState() => _BoxState();
}

class _BoxState extends State<_Box> {
  @override
  Widget build(BuildContext context) {
    final r = readMark(widget.c.text);
    final bad = r.bad || (r.value != null && r.value! > widget.max);
    return TextField(controller: widget.c, textAlign: TextAlign.center, textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.aAbB]')), LengthLimitingTextInputFormatter(5)],
      style: TextStyle(fontWeight: FontWeight.w800, color: bad ? context.tone(Brand.crimsonDeep) : null),
      decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10), hintText: '/${fmtMark(widget.max)}',
        filled: bad, fillColor: Brand.crimson.withValues(alpha: .08),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: bad ? Brand.crimson : Brand.gold.withValues(alpha: .6))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: bad ? Brand.crimson : Brand.gold, width: 2))),
      onChanged: (_) => setState(() {}));
  }
}
