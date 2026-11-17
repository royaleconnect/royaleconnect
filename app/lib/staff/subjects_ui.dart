// Release K7 · Subjects on the Students page
//   • Grade I – IX: 2nd and 3rd language (Hindi / Kannada — choosing the 2nd sets the 3rd to the other one).
//     Grade X: 2nd language only this year (the 3rd reaches Grade X from 2027-28, as this year's IX moves up).
//   • Grade XI – XII: the section's stream decides the group (PCM / PCB in mixed sections); one elective each.
//   • Changes are kept on the page (marked "changed") until Save; Undo puts everything back.
import 'package:flutter/material.dart';
import '../core/marks_rules.dart';
import '../core/theme.dart';
import 'staff_shell.dart' show Panel;

const langs = ['Kannada', 'Hindi'];
/// 2nd languages of a grade: French too where the school offers it (Grade IX).
List<String> langs2(int gno) => frenchGrades.contains(gno) ? const ['Kannada', 'Hindi', 'French'] : langs;
String otherLang(String l) => l == 'Kannada' ? 'Hindi' : 'Kannada';

/// 2nd language: Grade I – X. 3rd language: Grade I – IX this year, I – X from 2027-28 (the batch moves up).
bool has2nd(int gno) => gno >= 1 && gno <= 10;
bool has3rd(int gno, {DateTime? now}) {
  final d = now ?? DateTime.now();
  final yearStart = d.month >= 4 ? d.year : d.year - 1;     // the school year starts in April – June
  final top = (9 + (yearStart - 2026)).clamp(9, 10);
  return gno >= 1 && gno <= top;
}

/// A XI – XII section's stream, by the school's fixed rule (the same rule as _section_stream on the server).
String? sectionStream(String? gradeCode, String? sectionName) {
  final n = (sectionName ?? '').trim().toUpperCase();
  if (gradeCode != 'XI' && gradeCode != 'XII') return null;
  if (n.startsWith('A')) return 'Science · PCM / PCB';
  if (n.startsWith('B')) return 'Science · PCM';
  if (n.startsWith('C')) return 'Science · PCB';
  if (n.startsWith('D')) return 'Commerce';
  if (n.startsWith('E') && gradeCode == 'XII') return 'Humanities';
  if (n.startsWith('E') || n.startsWith('F')) return 'Two-day Science · PCM / PCB';
  return null;
}
const romanGrade = {'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10, 'XI': 11, 'XII': 12};

/// The page's unsaved subject changes, by student id.
class SubjectEdits {
  final Map<String, Map<String, String?>> _m = {};
  bool get isEmpty => _m.isEmpty;
  int get count => _m.length;
  void clear() => _m.clear();

  String? val(Map<String, dynamic> r, String k) {
    final e = _m['${r['id']}'];
    if (e != null && e.containsKey(k)) return e[k];
    final v = r[k];
    return v == null || '$v'.isEmpty ? null : '$v';
  }
  bool changed(Map<String, dynamic> r) => _m.containsKey('${r['id']}');

  void _put(Map<String, dynamic> r, String k, String? v) {
    final id = '${r['id']}';
    final orig = r[k] == null || '${r[k]}'.isEmpty ? null : '${r[k]}';
    final e = _m.putIfAbsent(id, () => {});
    if (v == orig) { e.remove(k); } else { e[k] = v; }
    if (e.isEmpty) _m.remove(id);
  }

  /// One change, with the school's rules: the 3rd language is the other one; a group drops an elective it cannot take.
  void set(Map<String, dynamic> r, String k, String v) {
    final g = (r['grade_no'] ?? 0) as int;
    switch (k) {
      case 'l2':
        _put(r, 'l2', v);
        if (has3rd(g) && v != 'French') _put(r, 'l3', otherLang(v));   // French: the office picks the 3rd language by hand
      case 'l3':
        _put(r, 'l3', v);
        if (val(r, 'l2') == v) _put(r, 'l2', otherLang(v));
      case 'grp':
        _put(r, 'grp', v);
        final el = val(r, 'el');
        if (el != null && !electivesFor(v).contains(el)) _put(r, 'el', null);
      case 'el':
        if (electivesFor(val(r, 'grp')).contains(v)) _put(r, 'el', v);
    }
  }

  /// What student_subjects_save needs: only the changed keys, in the database's names.
  List<Map<String, dynamic>> payload() => [
    for (final e in _m.entries) {
      'id': e.key,
      for (final f in e.value.entries) {'l2': 'second_language', 'l3': 'third_language', 'grp': 'subject_group', 'el': 'elective'}[f.key]!: f.value,
    },
  ];
}

bool subjectsUnset(SubjectEdits ed, Map<String, dynamic> r) {
  final g = (r['grade_no'] ?? 0) as int;
  if (g >= 11) return ed.val(r, 'el') == null || (streamGroups(r['stream']).length > 1 && ed.val(r, 'grp') == null);
  if (!has2nd(g)) return false;
  return ed.val(r, 'l2') == null || (has3rd(g) && ed.val(r, 'l3') == null);
}

/// Every subject this student studies that is worth finding (languages; XI – XII group subjects and the elective).
List<String> findableSubjects(SubjectEdits ed, Map<String, dynamic> r) {
  final g = (r['grade_no'] ?? 0) as int;
  if (g >= 11) {
    final grp = ed.val(r, 'grp'), el = ed.val(r, 'el');
    return [...?groupCore[grp], if (el != null) el];
  }
  return [];
}

/// A small coloured dropdown that looks like a chip.
class ChipDrop extends StatelessWidget {
  final String? value; final List<String> items; final ValueChanged<String>? onChanged; final Color fg, bg;
  const ChipDrop({super.key, required this.value, required this.items, required this.onChanged, required this.fg, required this.bg});
  @override
  Widget build(BuildContext context) {
    final unset = value == null;
    final f = unset ? context.tone(Brand.crimsonDeep) : context.tone(fg);
    final b = unset ? Brand.crimsonTint : bg;
    final box = BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? f.withValues(alpha: .16) : b, borderRadius: BorderRadius.circular(99), border: Border.all(color: f.withValues(alpha: .35)));
    if (onChanged == null) {
      return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: box,
          child: Text(value ?? 'Not set', style: TextStyle(color: f, fontWeight: FontWeight.w800, fontSize: 12.5)));
    }
    return Container(height: 30, padding: const EdgeInsets.only(left: 10, right: 4), decoration: box,
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: unset ? null : value, isDense: true, borderRadius: BorderRadius.circular(12),
        hint: Text('Not set', style: TextStyle(color: f, fontWeight: FontWeight.w800, fontSize: 12.5)),
        icon: Icon(Icons.expand_more_rounded, size: 18, color: f),
        style: TextStyle(color: f, fontWeight: FontWeight.w800, fontSize: 12.5),
        items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i))],
        onChanged: (v) { if (v != null) onChanged!(v); },
      )));
  }
}

/// The SUBJECTS cell of one student's line.
class SubjectsCell extends StatelessWidget {
  final Map<String, dynamic> r; final SubjectEdits ed; final bool canEdit; final VoidCallback onChange;
  const SubjectsCell({super.key, required this.r, required this.ed, required this.canEdit, required this.onChange});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = (r['grade_no'] ?? 0) as int;
    Widget k(String t) => Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant));
    void set(String key, String v) { ed.set(r, key, v); onChange(); }
    Color lf(String? l) => l == 'Hindi' ? Brand.blue : l == 'French' ? Brand.violet : Brand.amber;
    Color lb(String? l) => l == 'Hindi' ? Brand.blueTint : l == 'French' ? Brand.violetTint : Brand.amberTint;
    if (g >= 11) {
      final gs = streamGroups(r['stream']);
      if (gs.isEmpty) return Text('—', style: TextStyle(color: cs.onSurfaceVariant));
      final grp = ed.val(r, 'grp'), el = ed.val(r, 'el'), code = subjectCode(grp, el);
      return Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (gs.length > 1) ChipDrop(value: grp, items: gs, fg: Brand.green, bg: Brand.greenTint, onChanged: canEdit ? (v) => set('grp', v) : null)
        else k(gs.first),
        k('+'),
        ChipDrop(value: el, items: electivesFor(grp), fg: Brand.green, bg: Brand.greenTint, onChanged: canEdit ? (v) => set('el', v) : null),
        if (code != null) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: context.tone(Brand.green), borderRadius: BorderRadius.circular(6)),
            child: Text(code, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5))),
      ]);
    }
    if (!has2nd(g)) return Text('—', style: TextStyle(color: cs.onSurfaceVariant));
    final l2 = ed.val(r, 'l2'), l3 = ed.val(r, 'l3');
    return Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      k('2nd'), ChipDrop(value: l2, items: langs2(g), fg: lf(l2), bg: lb(l2), onChanged: canEdit ? (v) => set('l2', v) : null),
      if (has3rd(g)) ...[k('3rd'), ChipDrop(value: l3, items: langs, fg: lf(l3), bg: lb(l3), onChanged: canEdit ? (v) => set('l3', v) : null)],
    ]);
  }
}

/// "Find by subject": a number for each language / group / subject in the chosen class. Tap one to see only those students.
class FindBySubject extends StatelessWidget {
  final List<Map<String, dynamic>> rows; final SubjectEdits ed; final String selected; final ValueChanged<String> onPick;
  const FindBySubject({super.key, required this.rows, required this.ed, required this.selected, required this.onPick});

  static bool matches(SubjectEdits ed, Map<String, dynamic> r, String f) {
    if (f.isEmpty) return true;
    if (f == 'none') return subjectsUnset(ed, r);
    final i = f.indexOf('|'); final a = f.substring(0, i), b = f.substring(i + 1);
    if (a == 'l2' || a == 'l3' || a == 'grp') return ed.val(r, a) == b;
    if (a == 'code') return subjectCode(ed.val(r, 'grp'), ed.val(r, 'el')) == b;
    if (a == 's') return findableSubjects(ed, r).contains(b);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final senior = rows.any((r) => ((r['grade_no'] ?? 0) as int) >= 11);
    final keys = <(String, String)>[('', 'All')];
    if (senior) {
      final grps = {for (final r in rows) if (ed.val(r, 'grp') != null) ed.val(r, 'grp')!};
      if (grps.length > 1) keys.addAll([for (final g in grps) ('grp|$g', g)]);
      if (rows.any((r) => subjectCode(ed.val(r, 'grp'), ed.val(r, 'el')) == 'PCMB')) keys.add(('code|PCMB', 'PCMB'));
      const common = {'Physics', 'Chemistry', 'Accountancy', 'Business Studies', 'Economics', 'History', 'Sociology'};
      final subs = <String>{for (final r in rows) ...findableSubjects(ed, r)}.where((s) => !common.contains(s)).toList()
        ..sort((a, b) => electives.indexOf(a).compareTo(electives.indexOf(b)));
      keys.addAll([for (final s in subs) ('s|$s', s)]);
    } else {
      final g3 = rows.any((r) => has3rd((r['grade_no'] ?? 0) as int));
      keys.addAll([('l2|Kannada', '2nd Kannada'), ('l2|Hindi', '2nd Hindi'), if (rows.any((r) => ed.val(r, 'l2') == 'French')) ('l2|French', '2nd French'), if (g3) ('l3|Kannada', '3rd Kannada'), if (g3) ('l3|Hindi', '3rd Hindi')]);
    }
    final unset = rows.where((r) => subjectsUnset(ed, r)).length;
    if (unset > 0) keys.add(('none', 'Not set'));
    return Panel(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('FIND BY SUBJECT · TAP A NUMBER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.onSurfaceVariant)),
      const SizedBox(height: 8),
      Wrap(spacing: 7, runSpacing: 7, children: [
        for (final (key, label) in keys) Builder(builder: (_) {
          final n = key.isEmpty ? rows.length : rows.where((r) => matches(ed, r, key)).length;
          final on = selected == key; final warn = key == 'none';
          return InkWell(borderRadius: BorderRadius.circular(12), onTap: () => onPick(key), child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                color: on ? Brand.gold.withValues(alpha: .16) : null, border: Border.all(color: on ? Brand.gold : cs.outlineVariant, width: on ? 1.6 : 1)),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$label  ', style: TextStyle(fontWeight: FontWeight.w700, color: warn ? context.tone(Brand.crimsonDeep) : null)),
              TextSpan(text: '$n', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: warn ? context.tone(Brand.crimsonDeep) : null)),
            ])),
          ));
        }),
      ]),
      const SizedBox(height: 8),
      Text(senior
          ? 'Each student is their group and one elective. PCM + Biology and PCB + Maths both show as PCMB. Commerce takes Applied Maths (not Maths); Humanities is History and Sociology plus one elective. English is common to all.'
          : rows.any((r) => has3rd((r['grade_no'] ?? 0) as int))
              ? 'Choosing the 2nd language sets the 3rd to the other one by itself (Hindi ↔ Kannada). You can still change the 3rd on its own.'
              : 'Grade X: 2nd language only this year (the 3rd language reaches Grade X from 2027-28).',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
    ]));
  }
}

/// The bar at the bottom: set the ticked students together, then Save or Undo.
class SubjectsBar extends StatelessWidget {
  final List<Map<String, dynamic>> ticked; final SubjectEdits ed; final bool busy;
  final void Function(String key, String value) onSet; final VoidCallback onClear, onUndo, onSave;
  const SubjectsBar({super.key, required this.ticked, required this.ed, required this.busy, required this.onSet, required this.onClear, required this.onUndo, required this.onSave});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget btn(String key, String v, Color c) => OutlinedButton(
      style: OutlinedButton.styleFrom(foregroundColor: context.tone(c), visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
      onPressed: busy ? null : () => onSet(key, v), child: Text(v, style: const TextStyle(fontWeight: FontWeight.w800)));
    Widget lab(String t) => Text(t, style: const TextStyle(fontWeight: FontWeight.w700));
    final parts = <Widget>[];
    if (ticked.isNotEmpty) {
      parts.add(Text('${ticked.length} ticked', style: const TextStyle(fontWeight: FontWeight.w900)));
      final gnos = {for (final r in ticked) (r['grade_no'] ?? 0) as int};
      final senior = gnos.any((g) => g >= 11), junior = gnos.any((g) => g < 11);
      if (senior && junior) {
        parts.add(Text('Tick students of one grade group to set them together.', style: TextStyle(color: cs.onSurfaceVariant)));
      } else if (senior) {
        final grps = {for (final r in ticked) ...streamGroups(r['stream'])};
        final sci = grps.every((g) => g == 'PCM' || g == 'PCB');
        if (!sci && grps.length > 1) {
          parts.add(Text('Tick students of one stream to set their subjects.', style: TextStyle(color: cs.onSurfaceVariant)));
        } else {
          if (grps.length > 1) parts.add(Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [lab('Group:'), for (final g in grps) btn('grp', g, Brand.green)]));
          final allowed = grps.length == 1 ? electivesFor(grps.first) : electives;
          parts.add(Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [lab('Elective:'), for (final e in allowed) btn('el', e, Brand.green)]));
        }
      } else {
        parts.add(Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [lab('2nd language:'), for (final l in (gnos.isNotEmpty && gnos.every(frenchGrades.contains) ? langs2(gnos.first) : langs)) btn('l2', l, l == 'Hindi' ? Brand.blue : l == 'French' ? Brand.violet : Brand.amber)]));
        if (gnos.any(has3rd)) parts.add(Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [lab('3rd:'), for (final l in langs) btn('l3', l, l == 'Hindi' ? Brand.blue : Brand.amber)]));
      }
      parts.add(TextButton(onPressed: busy ? null : onClear, child: const Text('Clear ticks')));
    }
    return Material(elevation: 10, color: cs.surface, child: Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.gold, width: 2))),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      child: SafeArea(top: false, child: Row(children: [
        Expanded(child: Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: parts)),
        if (!ed.isEmpty) ...[
          const SizedBox(width: 10),
          OutlinedButton(onPressed: busy ? null : onUndo, child: const Text('Undo')),
          const SizedBox(width: 8),
          FilledButton(onPressed: busy ? null : onSave, child: Text(busy ? 'Saving…' : 'Save ${ed.count} change${ed.count == 1 ? '' : 's'}')),
        ],
      ])),
    ));
  }
}
