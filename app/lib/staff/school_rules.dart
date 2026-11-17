import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/data3.dart';
import '../core/errors.dart';
import '../core/marks_rules.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/hub_tabs.dart';
import '../widgets/royal_extras.dart' show ShimmerPage;
import '../widgets/royal_motion.dart' show FadeRise;
import 'school_settings.dart' show saveSettings;
import 'staff_shell.dart';
import 'subjects_ui.dart' show sectionStream;

/// School rules (IT only): the school's own rules, kept in one place so the school can change them without a developer.
///   Subjects · Sections & streams · Marks out of · Internal parts · Co-scholastic · Grading scale · Report card header · Lists

const _streams = ['Science · PCM / PCB', 'Science · PCM', 'Science · PCB', 'Commerce', 'Humanities', 'Two-day Science · PCM / PCB'];

final _seniorSectionsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = List<Map<String, dynamic>>.from(await db.from('section').select('id,name,stream,coaching,grade:grade_id(code,sort_order)').eq('status', 'active').eq('placeholder', false));
  final out = rows.where((r) => r['grade']?['code'] == 'XI' || r['grade']?['code'] == 'XII').toList()
    ..sort((a, b) { final g = (a['grade']['sort_order'] as int).compareTo(b['grade']['sort_order'] as int); return g != 0 ? g : '${a['name']}'.compareTo('${b['name']}'); });
  return out;
});
final _scaleProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final yr = await db.from('academic_year').select('id').eq('is_current', true).maybeSingle();
  if (yr == null) return [];
  return List<Map<String, dynamic>>.from(await db.from('grading_scale').select('min_pct,grade_label').eq('academic_year_id', yr['id']).order('min_pct', ascending: false));
});
final _cbseLogoProvider = FutureProvider.autoDispose<bool>((ref) async =>
    (await db.from('school_picture').select('key').eq('key', 'cbse_logo').maybeSingle()) != null);

class SchoolRulesPage extends ConsumerStatefulWidget {
  const SchoolRulesPage({super.key});
  @override
  ConsumerState<SchoolRulesPage> createState() => _SchoolRulesPageState();
}

class _SchoolRulesPageState extends ConsumerState<SchoolRulesPage> {
  String tab = 'subjects'; bool busy = false;
  static const _tabs = [('subjects', 'Subjects'), ('sections', 'Sections & streams'), ('split', 'Marks out of'), ('parts', 'Internal parts'), ('co', 'Co-scholastic'), ('scale', 'Grading scale'), ('header', 'Report card header'), ('lists', 'Other lists')];

  /// Saves settings; [apply] also lets this year's exam papers follow the new rules.
  Future<void> _save(Map<String, String> values, {bool apply = false, String done = 'Saved ✓'}) async {
    setState(() => busy = true);
    try {
      await saveSettings(ref, values);
      if (apply) {
        final n = (await db.rpc('rules_apply') as num?) ?? 0;
        done = n > 0 ? 'Saved ✓ — $n exam ${n == 1 ? 'paper follows' : 'papers follow'} the new rule.' : 'Saved ✓';
      }
      if (mounted) toast(context, done);
    } catch (e) { if (mounted) toast(context, friendlyError(e)); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    final cs = Theme.of(context).colorScheme;
    final settings = ref.watch(appSettingsProvider).value;
    if (!s.hasRole('it_admin')) return StaffPage(title: 'Settings', body: Panel(child: Text('Only IT can open the school’s rules.', style: TextStyle(color: cs.onSurfaceVariant))));
    return StaffPage(title: 'Settings', hub: Hub.schoolSetup,
      subtitle: 'School rules · for IT only. The school’s own rules, kept here so the school can change them itself. A change is used straight away, everywhere.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, children: [
          Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(avatar: const Icon(Icons.arrow_back_rounded, size: 18), label: const Text('Switches and access'), labelStyle: const TextStyle(fontWeight: FontWeight.w800), onPressed: () => context.pushReplacement('/staff/settings'))),
          for (final (k, t) in _tabs) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(t), selected: tab == k, showCheckmark: false, selectedColor: Brand.crimson,
              labelStyle: TextStyle(fontWeight: FontWeight.w800, color: tab == k ? Colors.white : null), onSelected: (_) => setState(() => tab = k))),
        ])),
        const SizedBox(height: 12),
        if (settings == null) const ShimmerPage()
        else FadeRise(key: ValueKey(tab), dy: 8, child: switch (tab) {
          'sections' => _Sections(viewOnly: s.viewOnly),
          'split' => _Split(settings: settings, busy: busy, onSave: (v) => _save({'xi_split': v}, apply: true)),
          'parts' => _Parts(settings: settings, busy: busy, onSave: (v) => _save(v, apply: true)),
          'co' => _Lists(busy: busy, onSave: _save, items: [
              ('co_1_5', 'Grades I – V · 5-point A–E', coAreasFor(settings, 1).join(', '), ','),
              ('co_6_8', 'Grades VI – VIII · Part 2A · 5-point A–E', coAreasFor(settings, 6).join(', '), ','),
              ('life_skills', 'Grades VI – VIII · Part 2B · thinking, social and emotional skills (one on each line)', lifeSkillsFor(settings, 6).join('\n'), '|'),
              ('co_9_10', 'Grades IX – X · 5-point A–E', coAreasFor(settings, 9).join(', '), ','),
              ('co_11_12', 'Grades XI – XII · 3-point A–C', coAreasFor(settings, 11).join(', '), ','),
            ], note: 'These are the lines of Part 2 on the report card, and the boxes the class teacher fills in. Separate them with commas.'),
          'scale' => _Scale(busy: busy),
          'header' => _Header(settings: settings, busy: busy, onSave: _save),
          'lists' => _Lists(busy: busy, onSave: _save, items: [
              ('categories', 'Student categories', listSetting(settings, 'categories', 'General,OBC,SC,ST').join(', '), ','),
              ('french_grades', 'Grades that offer French as a 2nd language (as I, II … XII)', listSetting(settings, 'french_grades', 'IX').join(', '), ','),
            ], note: 'Add a category only when the school really has students in it: the list shows on every student’s page and in School strength.'),
          _ => _Lists(busy: busy, onSave: _save, items: [
              ('electives_science', 'Science (PCM / PCB) · electives, one each', listSetting(settings, 'electives_science', 'Maths,Biology,AI,IP,PE,Psychology,Home Science').join(', '), ','),
              ('electives_commerce', 'Commerce · electives, one each', listSetting(settings, 'electives_commerce', 'Applied Maths,Legal Studies,IP,PE,AI,Home Science').join(', '), ','),
              ('electives_humanities', 'Humanities · electives, one each', listSetting(settings, 'electives_humanities', 'Psychology,Home Science,Legal Studies').join(', '), ','),
            ], note: 'Main subjects — PCM: Physics, Chemistry, Maths · PCB: Physics, Chemistry, Biology · Commerce: Accountancy, Business Studies, Economics · Humanities: History, Sociology. '
                'Commerce and Humanities can never take Maths or Biology; PCM cannot take Maths again and PCB cannot take Biology again. '
                'A new elective also needs its subject and teacher in School setup, so it appears in Marks entry and on the report card.'),
        }),
      ]),
    );
  }
}

/// A few text lists, one box each, saved together.
class _Lists extends StatefulWidget {
  final List<(String, String, String, String)> items;   // key, label, value, separator
  final String note; final bool busy; final Future<void> Function(Map<String, String>) onSave;
  const _Lists({required this.items, required this.note, required this.busy, required this.onSave});
  @override
  State<_Lists> createState() => _ListsState();
}

class _ListsState extends State<_Lists> {
  late final c = {for (final i in widget.items) i.$1: TextEditingController(text: i.$3)};
  @override
  void dispose() { for (final x in c.values) { x.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    for (final i in widget.items) Padding(padding: const EdgeInsets.only(bottom: 14), child: TextField(controller: c[i.$1], minLines: i.$4 == '|' ? 5 : 1, maxLines: i.$4 == '|' ? 12 : 3,
        textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: i.$2, alignLabelWithHint: true))),
    Text(widget.note, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    const SizedBox(height: 12),
    Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: widget.busy ? null : () {
      final out = <String, String>{};
      for (final i in widget.items) {
        final parts = [for (final x in c[i.$1]!.text.split(i.$4 == '|' ? RegExp(r'[\n|]') : RegExp(r'[,\n]'))) if (x.trim().isNotEmpty) x.trim()];
        if (parts.isEmpty) { toast(context, '“${i.$2}” cannot be empty.'); return; }
        out[i.$1] = parts.join(i.$4);
      }
      widget.onSave(out);
    }, icon: const Icon(Icons.save_rounded, size: 18), label: Text(widget.busy ? 'Saving…' : 'Save'))),
  ]));
}

/// XI – XII sections: the stream and the coaching name printed on the report card.
class _Sections extends ConsumerWidget {
  final bool viewOnly;
  const _Sections({required this.viewOnly});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ref.watch(_seniorSectionsProvider).when(
      loading: () => const ShimmerPage(), error: (e, _) => Text(friendlyError(e)),
      data: (rows) => Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (rows.isEmpty) Text('No XI or XII sections are open this year.', style: TextStyle(color: cs.onSurfaceVariant)),
        for (final r in rows) _SectionRow(key: ValueKey(r['id']), r: r, viewOnly: viewOnly, onSaved: () => ref.invalidate(_seniorSectionsProvider)),
        const SizedBox(height: 8),
        Text('The stream decides which group and electives a student of that section can have. The coaching name is printed after the class on the report card, for example “XI-Science / C INT (AKASH)”.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ])));
  }
}

class _SectionRow extends StatefulWidget {
  final Map<String, dynamic> r; final bool viewOnly; final VoidCallback onSaved;
  const _SectionRow({super.key, required this.r, required this.viewOnly, required this.onSaved});
  @override
  State<_SectionRow> createState() => _SectionRowState();
}

class _SectionRowState extends State<_SectionRow> {
  late String stream = (widget.r['stream'] ?? '').toString().trim().isNotEmpty ? '${widget.r['stream']}'.trim() : (sectionStream('${widget.r['grade']?['code']}', '${widget.r['name']}') ?? _streams.first);
  late final coaching = TextEditingController(text: '${widget.r['coaching'] ?? ''}');
  bool busy = false, dirty = false;
  @override
  void dispose() { coaching.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: PickRow(children: [
    SizedBox(width: 70, child: Text('${widget.r['grade']?['code']}-${widget.r['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
    Expanded(flex: 3, child: PickField<String>(label: 'Stream', value: _streams.contains(stream) ? stream : null, items: [for (final x in _streams) DropdownMenuItem(value: x, child: Text(x, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() { stream = v ?? stream; dirty = true; }))),
    const SizedBox(width: 10),
    Expanded(flex: 3, child: TextField(controller: coaching, onChanged: (_) => setState(() => dirty = true), decoration: const InputDecoration(labelText: 'Coaching name (optional)', hintText: 'e.g. INT (AKASH)'))),
    const SizedBox(width: 10),
    FilledButton(onPressed: widget.viewOnly || busy || !dirty ? null : () async {
      setState(() => busy = true);
      try {
        await db.rpc('section_rule_save', params: {'p_section': widget.r['id'], 'p_stream': stream, 'p_coaching': coaching.text.trim()});
        if (context.mounted) { toast(context, 'Saved ✓'); setState(() => dirty = false); }
        widget.onSaved();
      } catch (e) { if (context.mounted) toast(context, friendlyError(e)); }
      if (mounted) setState(() => busy = false);
    }, child: Text(busy ? '…' : 'Save')),
  ]));
}

/// XI – XII: practical / internal + theory for each subject.
class _Split extends StatefulWidget {
  final Map<String, String> settings; final bool busy; final ValueChanged<String> onSave;
  const _Split({required this.settings, required this.busy, required this.onSave});
  @override
  State<_Split> createState() => _SplitState();
}

class _SplitState extends State<_Split> {
  final rows = <(TextEditingController, TextEditingController, TextEditingController)>[];
  @override
  void initState() {
    super.initState();
    Map<String, dynamic> js = {};
    try { js = Map<String, dynamic>.from(jsonDecode(widget.settings['xi_split'] ?? '{}') as Map); } catch (_) {}
    js.forEach((k, v) { if (v is List && v.length == 2) rows.add((TextEditingController(text: k), TextEditingController(text: fmtMark(v[0] as num?)), TextEditingController(text: fmtMark(v[1] as num?)))); });
  }
  @override
  void dispose() { for (final r in rows) { r.$1.dispose(); r.$2.dispose(); r.$3.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget n(TextEditingController c, String l) => SizedBox(width: 110, child: TextField(controller: c, textAlign: TextAlign.center, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l, isDense: true)));
    return Panel(title: 'Grades XI – XII · each subject’s own split', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, r) in rows.indexed) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
        Expanded(child: TextField(controller: r.$1, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Subject', isDense: true))),
        const SizedBox(width: 10), n(r.$2, 'Practical'), const SizedBox(width: 10), n(r.$3, 'Theory'),
        IconButton(tooltip: 'Remove', onPressed: () => setState(() { final x = rows.removeAt(i); x.$1.dispose(); x.$2.dispose(); x.$3.dispose(); }), icon: const Icon(Icons.close_rounded, size: 18)),
      ])),
      Row(children: [
        TextButton.icon(onPressed: () => setState(() => rows.add((TextEditingController(), TextEditingController(text: '20'), TextEditingController(text: '80')))), icon: const Icon(Icons.add_rounded), label: const Text('Add a subject')),
        const Spacer(),
        FilledButton.icon(onPressed: widget.busy ? null : () {
          final out = <String, List<num>>{};
          for (final r in rows) {
            final name = r.$1.text.trim(); final a = num.tryParse(r.$2.text.trim()), b = num.tryParse(r.$3.text.trim());
            if (name.isEmpty) continue;
            if (a == null || b == null || a + b != 100) { toast(context, '$name: practical and theory must add up to 100.'); return; }
            out[name] = [a, b];
          }
          widget.onSave(jsonEncode(out));
        }, icon: const Icon(Icons.save_rounded, size: 18), label: Text(widget.busy ? 'Saving…' : 'Save')),
      ]),
      const SizedBox(height: 8),
      Text('A subject that is not in this list uses 30 + 70 when it has a practical (Physics, Chemistry, Biology …) and 20 + 80 otherwise. '
          'I – V: Internal 50 + Written 50 · VI – X: Internal 20 + Written 80 · PT 1 / PT 2: out of 30 for all (see Internal parts). '
          'A paper that already has marks above a new maximum is left as it is.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
    ]));
  }
}

/// Internal assessment columns for I – V and VI – X: one row for each part — its name and its marks.
class _Parts extends StatefulWidget {
  final Map<String, String> settings; final bool busy; final ValueChanged<Map<String, String>> onSave;
  const _Parts({required this.settings, required this.busy, required this.onSave});
  @override
  State<_Parts> createState() => _PartsState();
}

class _PartsState extends State<_Parts> {
  late final a = _rows(widget.settings['parts_1_5'] ?? 'PA:5,MA:5,SEA:5,PF:5,AOS:5,PBA:5,CWS:20');
  late final b = _rows(widget.settings['parts_6_10'] ?? 'PA:5,MA:5,SEA:5,PF:5');
  List<(TextEditingController, TextEditingController)> _rows(String t) => [
    for (final x in t.split(',')) if (x.trim().isNotEmpty) (TextEditingController(text: x.split(':').first.trim()), TextEditingController(text: x.contains(':') ? x.split(':')[1].trim() : '')),
  ];
  @override
  void dispose() { for (final r in [...a, ...b]) { r.$1.dispose(); r.$2.dispose(); } super.dispose(); }
  /// the rows → ("PA:5,MA:5", total), or null when a row is not filled in properly
  (String, num)? _read(List<(TextEditingController, TextEditingController)> rows) {
    final out = <String>[]; num sum = 0;
    for (final r in rows) {
      final name = r.$1.text.trim().toUpperCase().replaceAll(RegExp(r'[,:]'), ''); final m = num.tryParse(r.$2.text.trim());
      if (name.isEmpty && r.$2.text.trim().isEmpty) continue;
      if (name.isEmpty || m == null || m <= 0) return null;
      out.add('$name:${fmtMark(m)}'); sum += m;
    }
    return out.isEmpty ? null : (out.join(','), sum);
  }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ra = _read(a), rb = _read(b);
    Widget group(String title, List<(TextEditingController, TextEditingController)> rows, (String, num)? r) => Padding(padding: const EdgeInsets.only(bottom: 18), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
      const SizedBox(height: 8),
      for (final (i, x) in rows.indexed) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
        SizedBox(width: 150, child: TextField(controller: x.$1, textCapitalization: TextCapitalization.characters, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Part', isDense: true))),
        const SizedBox(width: 10),
        SizedBox(width: 100, child: TextField(controller: x.$2, textAlign: TextAlign.center, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Marks', isDense: true))),
        IconButton(tooltip: 'Remove', onPressed: rows.length <= 1 ? null : () => setState(() { final y = rows.removeAt(i); y.$1.dispose(); y.$2.dispose(); }), icon: const Icon(Icons.close_rounded, size: 18)),
      ])),
      Row(children: [
        TextButton.icon(onPressed: () => setState(() => rows.add((TextEditingController(), TextEditingController(text: '5')))), icon: const Icon(Icons.add_rounded), label: const Text('Add a part')),
        const SizedBox(width: 8),
        Expanded(child: Text(r == null ? 'Each part needs a name and its marks.' : r.$2 >= 100 ? 'The parts must add up to less than 100.' : 'Internal ${fmtMark(r.$2)} + Written ${fmtMark(100 - r.$2)} = 100',
            style: TextStyle(fontWeight: FontWeight.w800, color: r == null || r.$2 >= 100 ? context.tone(Brand.crimsonDeep) : context.tone(Brand.green)))),
      ]),
    ]));
    return Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      group('Grades I – V', a, ra), group('Grades VI – X', b, rb),
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Brand.green.withValues(alpha: .07), borderRadius: BorderRadius.circular(12)),
        child: const Text('PA fills in by itself from the periodic test: Half Yearly PA = PT 1 ÷ 30 × the PA marks, Annual PA = PT 2 ÷ 30 × the PA marks, rounded to a whole number. '
            'If a term has two tests, their average is used. If a student has no test mark (or was absent), the teacher types the PA.', style: TextStyle(fontWeight: FontWeight.w600))),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text('Computers / AI have one internal box, not the parts. A paper that already has marks above a new maximum is left as it is.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
        FilledButton.icon(onPressed: widget.busy || ra == null || rb == null || ra.$2 >= 100 || rb.$2 >= 100 ? null : () => widget.onSave({'parts_1_5': ra.$1, 'parts_6_10': rb.$1}),
            icon: const Icon(Icons.save_rounded, size: 18), label: Text(widget.busy ? 'Saving…' : 'Save')),
      ]),
    ]));
  }
}

/// This year's grading scale: a grade and the percentage it starts from.
class _Scale extends ConsumerStatefulWidget {
  final bool busy;
  const _Scale({required this.busy});
  @override
  ConsumerState<_Scale> createState() => _ScaleState();
}

class _ScaleState extends ConsumerState<_Scale> {
  List<(TextEditingController, TextEditingController)>? rows; bool saving = false;
  @override
  void dispose() { for (final r in rows ?? const <(TextEditingController, TextEditingController)>[]) { r.$1.dispose(); r.$2.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final data = ref.watch(_scaleProvider);
    if (rows == null && data.hasValue) {
      final src = data.value!.isEmpty ? [for (final g in gradeScale) {'grade_label': g.$1, 'min_pct': g.$2}] : data.value!;
      rows = [for (final r in src) (TextEditingController(text: '${r['grade_label']}'), TextEditingController(text: fmtMark(r['min_pct'] as num?)))];
    }
    if (rows == null) return const ShimmerPage();
    return Panel(title: 'Scholastic grades · this year', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, r) in rows!.indexed) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [
        SizedBox(width: 120, child: TextField(controller: r.$1, textAlign: TextAlign.center, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Grade', isDense: true))),
        const SizedBox(width: 10),
        SizedBox(width: 140, child: TextField(controller: r.$2, textAlign: TextAlign.center, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'From %', isDense: true))),
        IconButton(tooltip: 'Remove', onPressed: rows!.length <= 2 ? null : () => setState(() { final x = rows!.removeAt(i); x.$1.dispose(); x.$2.dispose(); }), icon: const Icon(Icons.close_rounded, size: 18)),
      ])),
      Row(children: [
        TextButton.icon(onPressed: () => setState(() => rows!.add((TextEditingController(), TextEditingController()))), icon: const Icon(Icons.add_rounded), label: const Text('Add a grade')),
        const Spacer(),
        FilledButton.icon(onPressed: saving || widget.busy ? null : () async {
          final out = <Map<String, dynamic>>[];
          for (final r in rows!) {
            final f = num.tryParse(r.$2.text.trim());
            if (r.$1.text.trim().isEmpty || f == null) { toast(context, 'Each grade needs a name and a “from” percentage.'); return; }
            out.add({'label': r.$1.text.trim(), 'from': f});
          }
          setState(() => saving = true);
          try {
            await db.rpc('grading_save', params: {'p_rows': out});
            ref.invalidate(_scaleProvider); ref.invalidate(appSettingsProvider);
            if (context.mounted) toast(context, 'Saved ✓ — report cards and reports use it now.');
          } catch (e) { if (context.mounted) toast(context, friendlyError(e)); }
          if (mounted) setState(() => saving = false);
        }, icon: const Icon(Icons.save_rounded, size: 18), label: Text(saving ? 'Saving…' : 'Save')),
      ]),
      const SizedBox(height: 8),
      Text('RCIS prints 91–100 A1 · 81–90 A2 … 33–40 D · below 33 E. A mark is rounded to the whole percent first, so A1 starts from 90.5 and A2 from 80.5. '
          'With this, 417 out of 500 (83.4%) is A2.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
    ]));
  }
}

/// What is printed on top of report cards and certificates.
class _Header extends ConsumerStatefulWidget {
  final Map<String, String> settings; final bool busy; final Future<void> Function(Map<String, String>) onSave;
  const _Header({required this.settings, required this.busy, required this.onSave});
  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  late final name = TextEditingController(text: widget.settings['school_name'] ?? ''), address = TextEditingController(text: widget.settings['school_address'] ?? ''),
      aff = TextEditingController(text: widget.settings['cbse_affiliation_no'] ?? ''), phone = TextEditingController(text: widget.settings['school_phone'] ?? '');
  late bool header = widget.settings['rc_header'] != 'off', cbse = widget.settings['rc_cbse'] != 'off';
  @override
  void dispose() { name.dispose(); address.dispose(); aff.dispose(); phone.dispose(); super.dispose(); }

  Future<void> _logo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg'], withData: true);
    final bytes = r?.files.first.bytes;
    if (bytes == null) return;
    if (bytes.length > 250 * 1024) { if (mounted) toast(context, 'Please choose a smaller picture (under 250 KB).'); return; }
    try {
      await db.from('school_picture').upsert({'key': 'cbse_logo', 'data': base64Encode(bytes), 'updated_by': ref.read(sessionProvider).value?.staff?['id'], 'updated_at': DateTime.now().toUtc().toIso8601String()}, onConflict: 'key');
      ref.invalidate(_cbseLogoProvider);
      if (mounted) toast(context, 'CBSE logo saved ✓ — it prints on the report card.');
    } catch (e) { if (mounted) toast(context, friendlyError(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final has = ref.watch(_cbseLogoProvider).value == true;
    return Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(controller: name, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'School name')),
      const SizedBox(height: 12),
      TextField(controller: address, decoration: const InputDecoration(labelText: 'Address line')),
      const SizedBox(height: 12),
      PickRow(children: [
        Expanded(child: TextField(controller: aff, decoration: const InputDecoration(labelText: 'CBSE affiliation number'))),
        const SizedBox(width: 12),
        Expanded(child: TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone numbers'))),
      ]),
      const SizedBox(height: 6),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: header, onChanged: (v) => setState(() => header = v), title: const Text('Print report cards with this header', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Off = the top is left empty for the school’s pre-printed paper. The class teacher can still switch it for one print.')),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: cbse, onChanged: (v) => setState(() => cbse = v), title: const Text('CBSE logo on the report card', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(has ? 'A logo is saved. You can replace it.' : 'No logo saved yet — choose the picture once and it is used on every card.')),
      Row(children: [
        OutlinedButton.icon(onPressed: _logo, icon: const Icon(Icons.image_rounded, size: 18), label: Text(has ? 'Replace the CBSE logo' : 'Choose the CBSE logo')),
        if (has) Padding(padding: const EdgeInsets.only(left: 10), child: Pill('Logo saved', fg: Brand.green, bg: Brand.greenTint)),
        const Spacer(),
        FilledButton.icon(onPressed: widget.busy ? null : () {
          if (name.text.trim().isEmpty) { toast(context, 'Please type the school name.'); return; }
          widget.onSave({'school_name': name.text.trim(), 'school_address': address.text.trim(), 'cbse_affiliation_no': aff.text.trim(), 'school_phone': phone.text.trim(),
            'rc_header': header ? 'on' : 'off', 'rc_cbse': cbse ? 'on' : 'off'});
        }, icon: const Icon(Icons.save_rounded, size: 18), label: Text(widget.busy ? 'Saving…' : 'Save')),
      ]),
      const SizedBox(height: 8),
      Text('The school’s own logo and the Principal’s signature are already inside the app. The same name and address print on receipts and certificates.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
    ]));
  }
}
