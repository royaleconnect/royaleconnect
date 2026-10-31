import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:url_launcher/url_launcher.dart';
import '../auth/session.dart';
import '../core/config.dart';
import '../core/data.dart';
import '../core/sheet_reader.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'school_settings.dart' show yearMovePlanProvider;
import 'staff_data.dart';
import 'staff_shell.dart';

/// New sections for next year (IT and the Principal).
///   1 · Sections & class teachers   2 · Put students in sections (Excel list or one by one)   3 · Publish to families
/// Until "Publish", families see only "Grade IX · section to be announced". XI → XII keeps its sections by itself.
String _msg(Object e) => e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');

final _yearsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => Map<String, dynamic>.from(await db.rpc('plan_years') as Map));
final _overviewProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, yearId) async =>
    [for (final x in (await db.rpc('plan_overview', params: {'p_year': yearId})) as List) Map<String, dynamic>.from(x)]);
final _sectionsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, (String, String)>((ref, k) async {
  final rows = await db.from('section').select('id,name,status,class_teacher_id,class_teacher:class_teacher_id(display_name)')
      .eq('academic_year_id', k.$1).eq('grade_id', k.$2).eq('placeholder', false).order('name', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});
final _studentsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, (String, String)>((ref, k) async =>
    [for (final x in (await db.rpc('plan_students', params: {'p_year': k.$1, 'p_grade': k.$2})) as List) Map<String, dynamic>.from(x)]);

class NewSectionsScreen extends ConsumerStatefulWidget {
  const NewSectionsScreen({super.key});
  @override
  ConsumerState<NewSectionsScreen> createState() => _NewSectionsScreenState();
}

class _NewSectionsScreenState extends ConsumerState<NewSectionsScreen> {
  String? yearId; bool allGrades = false;
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    if (!s.hasRole('it_admin') && !s.hasRole('principal')) return const StaffPage(title: 'New sections', body: NoteBox('New sections are set by IT and the Principal.'));
    final cs = Theme.of(context).colorScheme;
    return ref.watch(_yearsProvider).when(
      loading: () => const StaffPage(title: 'New sections', body: Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))),
      error: (e, _) => StaffPage(title: 'New sections', body: Text(_msg(e))),
      data: (yrs) {
        final years = [Map<String, dynamic>.from(yrs['current']), Map<String, dynamic>.from(yrs['next'])];
        final y = years.firstWhere((x) => x['id'] == (yearId ?? yrs['default']), orElse: () => years.last);
        final plan = ref.watch(yearMovePlanProvider).value;
        return StaffPage(
          title: 'New sections for ${y['label']}',
          subtitle: 'Make the sections and class teachers, put the students in, then publish. Families see the new section only after you publish.',
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('School year:', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              for (final x in years) ChoiceChip(label: Text('${x['label']}'), selected: x['id'] == y['id'], showCheckmark: false, selectedColor: Brand.crimson,
                  labelStyle: TextStyle(fontWeight: FontWeight.w800, color: x['id'] == y['id'] ? Colors.white : null), onSelected: (_) => setState(() => yearId = x['id'])),
            ]),
            const SizedBox(height: 14),
            if (plan != null) Panel(padding: const EdgeInsets.all(14), child: Row(children: [
              const Icon(Icons.event_repeat_rounded, color: Brand.blue), const SizedBox(width: 12),
              Expanded(child: Text(
                'Move-up: ${plan['step1_grades']} on ${DateFormat('d MMM yyyy').format(DateTime.parse(plan['step1_on']))}${plan['step1_done'] == true ? ' ✓' : ''} · '
                'everyone else on ${DateFormat('d MMM yyyy').format(DateTime.parse(plan['step2_on']))}${plan['step2_done'] == true ? ' ✓' : ''}. '
                'You can prepare sections before that day — they open on the move-up day.', style: const TextStyle(fontSize: 13.5))),
            ])),
            ref.watch(_overviewProvider(y['id'])).when(
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
              error: (e, _) => Text(_msg(e)),
              data: (grades) {
                final busy = grades.where((g) => (g['sections'] ?? 0) > 0 || (g['placed'] ?? 0) > 0 || (g['waiting'] ?? 0) > 0).toList();
                final shown = allGrades || busy.isEmpty ? grades : busy;
                return Panel(title: 'Grades', trailing: TextButton(onPressed: () => setState(() => allGrades = !allGrades), child: Text(allGrades ? 'Show grades with students' : 'Show all grades')),
                  child: Column(children: [for (final g in shown) _GradeTile(g: g, onTap: () async {
                    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (c) => staffTheme(c, GradePlanner(yearId: y['id'], yearLabel: y['label'], grade: g))));
                    ref.invalidate(_overviewProvider(y['id']));
                  })]));
              },
            ),
            const NoteBox('XI → XII keep the same sections and students — they move by themselves. Change their class teachers here if needed.'),
          ]),
        );
      },
    );
  }
}

class _GradeTile extends StatelessWidget {
  final Map<String, dynamic> g; final VoidCallback onTap;
  const _GradeTile({required this.g, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sec = (g['sections'] ?? 0) as int, waiting = (g['waiting'] ?? 0) as int, pub = (g['published'] ?? 0) as int;
    final done = sec > 0 && waiting == 0 && pub == sec;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: CircleAvatar(backgroundColor: done ? Brand.greenTint : Brand.crimsonTint, child: Text('${g['code']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: done ? Brand.green : Brand.crimsonDeep))),
      title: Text('${g['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text([
        sec == 0 ? 'No sections yet' : '$sec section${sec == 1 ? '' : 's'} · ${g['with_teacher']} with class teacher',
        '${g['placed']} placed',
        if (waiting > 0) '$waiting not placed yet',
        sec == 0 ? '' : pub == sec ? 'published' : 'not published',
      ].where((x) => x.isNotEmpty).join(' · '), style: TextStyle(color: waiting > 0 ? context.tone(Brand.crimsonDeep) : cs.onSurfaceVariant)),
      trailing: done ? Icon(Icons.check_circle_rounded, color: context.tone(Brand.green)) : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

// ================================================================== one grade
class GradePlanner extends ConsumerStatefulWidget {
  final String yearId, yearLabel; final Map<String, dynamic> grade;
  const GradePlanner({super.key, required this.yearId, required this.yearLabel, required this.grade});
  @override
  ConsumerState<GradePlanner> createState() => _GradePlannerState();
}

class _GradePlannerState extends ConsumerState<GradePlanner> {
  String? filter;   // null = all, '' = not placed yet, or a section id
  bool busy = false;
  (String, String) get key => (widget.yearId, widget.grade['grade_id'] as String);
  String get code => widget.grade['code'] as String;

  void _refresh() { ref.invalidate(_sectionsProvider(key)); ref.invalidate(_studentsProvider(key)); }

  Future<void> _editSection([Map<String, dynamic>? sec]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _SectionDialog(yearId: widget.yearId, gradeId: key.$2, gradeCode: code, section: sec));
    if (saved == true) _refresh();
  }

  Future<void> _place(String studentId, String? sectionId) async {
    try { await db.rpc('plan_place', params: {'p_year': widget.yearId, 'p_grade': key.$2, 'p_section': sectionId, 'p_students': [studentId]}); ref.invalidate(_studentsProvider(key)); }
    catch (e) { if (mounted) toast(context, _msg(e)); }
  }

  Future<void> _addNew(List<Map<String, dynamic>> sections) async {
    if (sections.isEmpty) { toast(context, 'Add the sections first (step 1).'); return; }
    final adm = TextEditingController(); String sec = sections.first['id'];
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
      title: const Text('Add a new admission'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('For a student admitted for next year who is not in the list (for example a new Grade XI admission). Admit them first in Students → New admission.'),
        const SizedBox(height: 12),
        TextField(controller: adm, autofocus: true, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Admission number')),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: sec, decoration: const InputDecoration(labelText: 'Section'), items: [for (final s in sections) DropdownMenuItem(value: s['id'] as String, child: Text('$code-${s['name']}'))], onChanged: (v) => set(() => sec = v ?? sec)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add'))],
    )));
    if (ok != true || adm.text.trim().isEmpty) return;
    final name = sections.firstWhere((s) => s['id'] == sec)['name'];
    await _uploadRows([{'i': 1, 'admission_no': adm.text.trim(), 'section': name}], quiet: true);
  }

  Future<void> _excel() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx', 'xlsm', 'xls', 'csv', 'txt', 'htm', 'html'], withData: true);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    try {
      final sheets = readSpreadsheet(Uint8List.fromList(r.files.first.bytes!), r.files.first.name);
      // find a header row with an admission-number column and a section column
      for (final sh in sheets) {
        for (var h = 0; h < sh.rows.length && h < 15; h++) {
          final head = [for (final c in sh.rows[h]) c.toLowerCase()];
          final a = head.indexWhere((c) => c.contains('adm')), s = head.indexWhere((c) => c.contains('section') || c.contains('new class') || c == 'sec');
          if (a < 0 || s < 0) continue;
          final rows = <Map<String, dynamic>>[];
          for (var i = h + 1; i < sh.rows.length; i++) {
            final row = sh.rows[i];
            final adm = a < row.length ? row[a].trim() : '';
            var sec = s < row.length ? row[s].trim() : '';
            if (adm.isEmpty) continue;
            // "IX-B", "9 B", "B" → "B"
            sec = sec.replaceFirst(RegExp(r'^(grade\s*)?[ivx0-9]+\s*[-–/ ]\s*', caseSensitive: false), '').trim();
            rows.add({'i': i + 1, 'admission_no': adm, 'section': sec});
          }
          await _uploadRows(rows);
          return;
        }
      }
      if (mounted) toast(context, 'Could not find the columns. The sheet needs an “Admission number” column and a “Section” column.');
    } catch (e) {
      if (mounted) toast(context, e is SheetError ? e.message : _msg(e));
    }
  }

  Future<void> _uploadRows(List<Map<String, dynamic>> rows, {bool quiet = false}) async {
    if (rows.isEmpty) { toast(context, 'The list is empty.'); return; }
    setState(() => busy = true);
    try {
      final res = [for (final x in (await db.rpc('plan_place_rows', params: {'p_year': widget.yearId, 'p_grade': key.$2, 'p_rows': rows})) as List) Map<String, dynamic>.from(x)];
      ref.invalidate(_studentsProvider(key));
      final bad = res.where((x) => x['status'] == 'error').toList();
      if (!mounted) return;
      if (quiet && bad.isEmpty) { toast(context, 'Added.'); }
      else {
        await showDialog(context: context, builder: (ctx) => AlertDialog(
          title: Text(bad.isEmpty ? 'All ${res.length} students placed ✓' : '${res.length - bad.length} placed · ${bad.length} need a look'),
          content: SizedBox(width: 480, child: bad.isEmpty ? const Text('Check the counts, then publish.') : SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final b in bad) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('Row ${b['i']}: ${b['message']}')),
          ]))),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ));
      }
    } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _download(List<Map<String, dynamic>> students) async {
    String q(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
    final csv = StringBuffer('Admission number,Student,Last year,New section\n');
    for (final st in students) { csv.writeln([q(st['admission_no']), q(st['full_name']), q(st['from_class']), q(st['section_name'] == null ? '' : '$code-${st['section_name']}')].join(',')); }
    try {
      await FilePicker.platform.saveFile(dialogTitle: 'Save the list', fileName: 'Grade-$code-${widget.yearLabel}-sections.csv', bytes: Uint8List.fromList(utf8.encode('﻿$csv')));
    } catch (e) { if (mounted) toast(context, _msg(e)); }
  }

  Future<void> _publish(int waiting) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Publish Grade $code sections?'),
      content: Text('${waiting > 0 ? '$waiting students are not placed yet — they will keep seeing “section to be announced”.\n\n' : ''}'
          'Families get a notification with the new section and class teacher. If the students have not moved up yet, the sections open on the move-up day.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Publish'))],
    ));
    if (ok != true) return;
    setState(() => busy = true);
    try {
      final r = Map<String, dynamic>.from(await db.rpc('plan_publish', params: {'p_year': widget.yearId, 'p_grade': key.$2}) as Map);
      _refresh(); ref.invalidate(mySectionsProvider);
      if (mounted) toast(context, r['on_move_up'] == true ? 'Published. The sections open for families on the move-up day.' : 'Published. Families can see the new sections now.');
    } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sections = ref.watch(_sectionsProvider(key)).value ?? const <Map<String, dynamic>>[];
    final studentsAsync = ref.watch(_studentsProvider(key));
    final students = studentsAsync.value ?? const <Map<String, dynamic>>[];
    final waiting = students.where((s) => s['section_id'] == null).length;
    final withTeacher = sections.where((s) => s['class_teacher_id'] != null).length;
    final published = sections.isNotEmpty && sections.every((s) => s['status'] == 'ready' || s['status'] == 'active');
    final shown = students.where((s) => filter == null || (filter == '' ? s['section_id'] == null : s['section_id'] == filter)).toList();
    final narrow = isNarrow(context);

    Widget stepBar(int n, String text, {required bool done, required bool current}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: done ? Brand.greenTint : current ? Brand.crimsonTint : cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(12)),
      child: Text('$n · $text${done ? '  ✓' : ''}', style: TextStyle(fontWeight: FontWeight.w800, color: done ? Brand.green : current ? Brand.crimsonDeep : null)));

    return Scaffold(
      appBar: AppBar(backgroundColor: Brand.crimsonDeep, foregroundColor: Colors.white, title: Text('Grade $code · ${widget.yearLabel}', style: const TextStyle(fontWeight: FontWeight.w800))),
      body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
        // ---------------- step 1
        stepBar(1, sections.isEmpty ? 'Sections & class teachers' : 'Sections & class teachers ($withTeacher of ${sections.length} have a class teacher)', done: sections.isNotEmpty && withTeacher == sections.length, current: sections.isEmpty),
        Panel(title: 'Sections', trailing: FilledButton.icon(onPressed: () => _editSection(), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add section')), child: sections.isEmpty
            ? Text('Add each section for ${widget.yearLabel} (A, B, C … or Science, Commerce) and choose its class teacher.', style: TextStyle(color: cs.onSurfaceVariant))
            : Wrap(spacing: 8, runSpacing: 8, children: [for (final s in sections) ActionChip(
                avatar: Icon(s['class_teacher_id'] == null ? Icons.person_off_rounded : Icons.person_rounded, size: 18, color: s['class_teacher_id'] == null ? Brand.amber : Brand.green),
                label: Text('$code-${s['name']} · ${s['class_teacher']?['display_name'] ?? 'no class teacher'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                onPressed: () => _editSection(s))])),
        // ---------------- step 2
        stepBar(2, 'Put students in sections', done: students.isNotEmpty && waiting == 0, current: sections.isNotEmpty && waiting > 0),
        if (sections.isNotEmpty) ...[
          LayoutBuilder(builder: (_, c) {
            final two = c.maxWidth >= 640;
            final a = _BigChoice(icon: Icons.upload_file_rounded, title: 'Upload the school’s Excel list', text: 'Columns: Admission number and Section. The app checks every row.', onTap: busy ? null : _excel);
            final b = _BigChoice(icon: Icons.touch_app_rounded, title: 'Choose one by one', text: 'Pick the section for each student in the list below.', selected: true, onTap: null);
            return two ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]) : Column(children: [a, const SizedBox(height: 10), b]);
          }),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: () => launchUrl(Uri.parse('${AppConfig.webUrl}/templates/new_sections.csv'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Sample Excel list'))),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(label: Text('All · ${students.length}'), selected: filter == null, onSelected: (_) => setState(() => filter = null)),
            for (final s in sections) ChoiceChip(label: Text('$code-${s['name']} · ${students.where((x) => x['section_id'] == s['id']).length}'), selected: filter == s['id'], onSelected: (_) => setState(() => filter = s['id'])),
            ChoiceChip(label: Text('Not placed yet · $waiting'), selected: filter == '', selectedColor: Brand.crimsonTint,
                labelStyle: TextStyle(fontWeight: FontWeight.w800, color: waiting > 0 ? Brand.crimsonDeep : null), onSelected: (_) => setState(() => filter = '')),
            ActionChip(avatar: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text('Add a new admission'), onPressed: () => _addNew(sections)),
          ]),
          const SizedBox(height: 10),
          Panel(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: studentsAsync.isLoading && students.isEmpty
              ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
              : shown.isEmpty
                  ? Padding(padding: const EdgeInsets.all(16), child: Text(students.isEmpty ? 'No students for Grade $code yet. They appear here when the class below moves up, or add new admissions.' : 'No one here.', style: TextStyle(color: cs.onSurfaceVariant)))
                  : Column(children: [for (final st in shown) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
                      if (!narrow) SizedBox(width: 150, child: Text('${st['admission_no']}', style: TextStyle(color: cs.onSurfaceVariant))),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${st['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text([if (narrow) st['admission_no'], if (st['from_class'] != null) 'last year ${st['from_class']}'].join(' · '), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                      ])),
                      SizedBox(width: narrow ? 120 : 160, child: DropdownButtonFormField<String?>(
                        value: st['section_id'] as String?, isExpanded: true, isDense: true,
                        decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: st['section_id'] == null ? Brand.crimson : cs.outline))),
                        items: [const DropdownMenuItem<String?>(value: null, child: Text('Choose', style: TextStyle(color: Brand.crimson, fontWeight: FontWeight.w800))),
                          for (final s in sections) DropdownMenuItem<String?>(value: s['id'] as String, child: Text('$code-${s['name']}', style: const TextStyle(fontWeight: FontWeight.w800)))],
                        onChanged: (v) => _place(st['student_id'], v),
                      )),
                    ]))])),
        ],
        // ---------------- step 3
        stepBar(3, 'Check & publish', done: published && waiting == 0, current: sections.isNotEmpty && waiting == 0 && !published),
        Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(onPressed: students.isEmpty ? null : () => _download(students), icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Download list (Excel)')),
          FilledButton.icon(onPressed: busy || sections.isEmpty ? null : () => _publish(waiting), icon: const Icon(Icons.campaign_rounded, size: 18), label: Text(published ? 'Publish again' : 'Publish to families')),
        ]),
        const SizedBox(height: 14),
        const NoteBox('Teachers see their new class in their menu once it is published and the students have moved up. Subject teachers for each section are set in Classes & fees → Classes.'),
      ]))),
    );
  }
}

class _BigChoice extends StatelessWidget {
  final IconData icon; final String title, text; final bool selected; final VoidCallback? onTap;
  const _BigChoice({required this.icon, required this.title, required this.text, this.selected = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(color: selected ? Brand.crimsonTint : cs.surface, borderRadius: BorderRadius.circular(14), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? Brand.crimson : cs.outline)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: selected ? Brand.crimsonDeep : Brand.crimson), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: selected ? Brand.ink : null)),
          Text(text, style: TextStyle(fontSize: 12.5, color: selected ? Brand.muted : cs.onSurfaceVariant)),
        ])),
      ]))));
  }
}

class _SectionDialog extends ConsumerStatefulWidget {
  final String yearId, gradeId, gradeCode; final Map<String, dynamic>? section;
  const _SectionDialog({required this.yearId, required this.gradeId, required this.gradeCode, this.section});
  @override
  ConsumerState<_SectionDialog> createState() => _SectionDialogState();
}

class _SectionDialogState extends ConsumerState<_SectionDialog> {
  late final name = TextEditingController(text: widget.section?['name'] ?? '');
  late String? teacher = widget.section?['class_teacher_id'];
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final staff = (ref.watch(staffListProvider).value ?? const <Map<String, dynamic>>[])
        .where((s) => s['active'] == true && !List<String>.from(s['roles'] ?? const []).any((r) => r == 'driver' || r == 'conductor')).toList()
      ..sort((a, b) => '${a['display_name']}'.compareTo('${b['display_name']}'));
    return AlertDialog(
      title: Text(widget.section == null ? 'Add a section · Grade ${widget.gradeCode}' : 'Section ${widget.gradeCode}-${widget.section!['name']}'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: name, autofocus: widget.section == null, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Section name', hintText: 'A, B, C … or SCIENCE')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(value: staff.any((s) => s['id'] == teacher) ? teacher : null, isExpanded: true, decoration: const InputDecoration(labelText: 'Class teacher'),
            items: [const DropdownMenuItem<String?>(value: null, child: Text('Not chosen yet')), for (final s in staff) DropdownMenuItem<String?>(value: s['id'] as String, child: Text('${s['display_name'] ?? s['full_name']}'))],
            onChanged: (v) => setState(() => teacher = v)),
      ])),
      actions: [
        if (widget.section != null && widget.section!['status'] != 'active') TextButton(onPressed: busy ? null : () async {
          setState(() => busy = true);
          try { await db.rpc('plan_delete_section', params: {'p_id': widget.section!['id']}); if (context.mounted) Navigator.pop(context, true); }
          catch (e) { if (context.mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
        }, child: const Text('Delete section', style: TextStyle(color: Brand.crimson))),
        TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : () async {
          if (name.text.trim().isEmpty) { toast(context, 'Type the section name.'); return; }
          setState(() => busy = true);
          try {
            await db.rpc('plan_save_section', params: {'p_id': widget.section?['id'], 'p_year': widget.yearId, 'p_grade': widget.gradeId, 'p_name': name.text.trim(), 'p_teacher': teacher});
            if (context.mounted) Navigator.pop(context, true);
          } catch (e) { if (context.mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
        }, child: Text(busy ? 'Saving…' : 'Save')),
      ],
    );
  }
}
