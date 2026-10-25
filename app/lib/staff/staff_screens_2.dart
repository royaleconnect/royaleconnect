import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../auth/session.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../screens/family_screens.dart' show StorageImage, callNumber;
import '../widgets/common.dart';
import 'staff_data.dart';
import 'staff_shell.dart';

String _d(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String _dm(String? iso) => iso == null ? '' : DateFormat('d MMM').format(DateTime.parse(iso).toLocal());
String _dmy(String? iso) => iso == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());
String _dmt(String? iso) => iso == null ? '' : DateFormat('d MMM, h:mm a').format(DateTime.parse(iso).toLocal());
Widget _loading() => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
Widget _err(Object e) => Padding(padding: const EdgeInsets.all(24), child: Text('$e', style: const TextStyle(color: Brand.crimsonDeep)));
String _cls(Map<String, dynamic>? student) { final en = (student?['enrolment'] as List?) ?? []; if (en.isEmpty) return ''; final s = en.first['section']; return '${s?['grade']?['code'] ?? ''}-${s?['name'] ?? ''}'; }

/// Upload a picked file to the private bucket under [folder]; returns the stored path.
Future<String?> pickAndUpload(BuildContext context, String folder, {List<String> ext = const ['pdf'], int maxMb = 10}) async {
  final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ext, withData: true);
  if (r == null || r.files.isEmpty || r.files.first.bytes == null) return null;
  final f = r.files.first;
  if (f.bytes!.length > maxMb * 1024 * 1024) { if (context.mounted) toast(context, 'Files up to $maxMb MB only.'); return null; }
  final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_${f.name}';
  final mime = f.extension == 'pdf' ? 'application/pdf' : 'image/${f.extension == 'jpg' ? 'jpeg' : f.extension}';
  await db.storage.from('files').uploadBinary(path, Uint8List.fromList(f.bytes!), fileOptions: FileOptions(contentType: mime));
  return path;
}

// ---------------------------------------------------------------- exams & portions
class StaffExamsScreen extends ConsumerWidget {
  const StaffExamsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value!;
    final exams = ref.watch(staffExamsProvider);
    final canCreate = s.isOffice || s.hasRole('coordinator');
    final cs = Theme.of(context).colorScheme;
    return StaffPage(title: 'Exams & portions', subtitle: canCreate ? 'Create the schedule; subject teachers fill in portions; publish when ready.' : 'Fill in portions for the subjects you teach. The coordinator publishes.',
      actions: [if (canCreate) FilledButton.icon(onPressed: () => _create(context, ref), icon: const Icon(Icons.add_rounded), label: const Text('New exam'))],
      body: exams.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => rows.isEmpty ? Panel(child: Text('No exams yet.', style: TextStyle(color: cs.onSurfaceVariant))) : Column(children: [for (final e in rows) Panel(
        title: '${e['grade']?['name'] ?? ''} · ${e['name']} (${e['term']})',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Pill(e['published_at'] != null ? 'Published' : 'Draft', fg: e['published_at'] != null ? Brand.green : Brand.amber, bg: e['published_at'] != null ? Brand.greenTint : Brand.amberTint),
          if (canCreate) TextButton(onPressed: () async { await publishExam(e['id'], e['published_at'] == null); ref.invalidate(staffExamsProvider); }, child: Text(e['published_at'] != null ? 'Unpublish' : 'Publish')),
        ]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_dm(e['starts_on'])} – ${_dmy(e['ends_on'])} · max ${e['max_marks']}${e['note'] != null ? ' · ${e['note']}' : ''}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final p in (List<Map<String, dynamic>>.from(e['exam_paper'] ?? [])..sort((a, b) => (a['on_date'] ?? '9').compareTo(b['on_date'] ?? '9')))) ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            leading: SizedBox(width: 64, child: Text(p['on_date'] == null ? 'TBA' : DateFormat('EEE d').format(DateTime.parse(p['on_date'])), style: const TextStyle(fontWeight: FontWeight.w800))),
            title: Text(p['subject']?['name'] ?? ''), subtitle: Text(p['portions'] ?? 'Portions not entered', maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: TextButton(onPressed: () => _portions(context, ref, p), child: const Text('Edit')),
          ),
        ]))])));
  }

  void _portions(BuildContext context, WidgetRef ref, Map<String, dynamic> p) {
    DateTime? on = p['on_date'] == null ? null : DateTime.parse(p['on_date']); String portions = p['portions'] ?? '';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(title: Text(p['subject']?['name'] ?? ''), content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OutlinedButton.icon(onPressed: () async { final d = await showDatePicker(context: ctx, initialDate: on ?? DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) set(() => on = d); }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(on == null ? 'Exam date' : DateFormat('EEEE, d MMM').format(on!))),
      const SizedBox(height: 10),
      TextFormField(initialValue: portions, onChanged: (v) => portions = v, minLines: 4, maxLines: 10, decoration: const InputDecoration(labelText: 'Portions', hintText: 'Chapters / topics')),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () async {
      try { await savePortions(ref, p['id'], onDate: on, portions: portions.trim().isEmpty ? null : portions.trim()); ref.invalidate(staffExamsProvider); if (ctx.mounted) Navigator.pop(ctx); } catch (e) { if (ctx.mounted) toast(ctx, 'Not allowed or failed: $e'); }
    }, child: const Text('Save'))])));
  }

  void _create(BuildContext context, WidgetRef ref) {
    String? gradeId; String name = '', term = 'Term 1', note = ''; int max = 100; DateTime? a, b; final subs = <String>{}; bool busy = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(title: const Text('New exam'), content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Consumer(builder: (_, r, __) => r.watch(gradesProvider).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (gs) => PickField<String>(label: 'Grade', value: gradeId, items: [for (final g in gs) DropdownMenuItem(value: g['id'] as String, child: Text(g['name']))], onChanged: (v) => set(() => gradeId = v)))),
      const SizedBox(height: 10),
      TextField(onChanged: (v) => name = v, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Mid-term examination')), const SizedBox(height: 10),
      Row(children: [Expanded(child: TextFormField(initialValue: term, onChanged: (v) => term = v, decoration: const InputDecoration(labelText: 'Term'))), const SizedBox(width: 10), SizedBox(width: 120, child: TextFormField(initialValue: '100', keyboardType: TextInputType.number, onChanged: (v) => max = int.tryParse(v) ?? 100, decoration: const InputDecoration(labelText: 'Max marks')))]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: OutlinedButton(onPressed: () async { final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) set(() => a = d); }, child: Text(a == null ? 'Starts' : DateFormat('d MMM').format(a!)))), const SizedBox(width: 10), Expanded(child: OutlinedButton(onPressed: () async { final d = await showDatePicker(context: ctx, initialDate: a ?? DateTime.now(), firstDate: a ?? DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365))); if (d != null) set(() => b = d); }, child: Text(b == null ? 'Ends' : DateFormat('d MMM').format(b!))))]),
      const SizedBox(height: 10),
      TextField(onChanged: (v) => note = v, decoration: const InputDecoration(labelText: 'Note for parents (optional)')), const SizedBox(height: 12),
      const Text('Subjects', style: TextStyle(fontWeight: FontWeight.w800)),
      Consumer(builder: (_, r, __) => r.watch(subjectsProvider).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (ss) => Wrap(spacing: 6, children: [for (final s in ss) FilterChip(label: Text(s['name']), selected: subs.contains(s['id']), onSelected: (v) => set(() => v ? subs.add(s['id']) : subs.remove(s['id'])))]))),
    ]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: busy ? null : () async {
      if (gradeId == null || name.trim().isEmpty) { toast(ctx, 'Grade and name are needed.'); return; }
      set(() => busy = true);
      try { await createExam(ref, gradeId: gradeId!, name: name.trim(), term: term.trim(), starts: a, ends: b, maxMarks: max, note: note.trim().isEmpty ? null : note.trim(), subjectIds: subs.toList()); ref.invalidate(staffExamsProvider); if (ctx.mounted) Navigator.pop(ctx); } catch (e) { set(() => busy = false); if (ctx.mounted) toast(ctx, 'Failed: $e'); }
    }, child: const Text('Create'))])));
  }
}

// ---------------------------------------------------------------- marks entry
class StaffMarksScreen extends ConsumerStatefulWidget {
  const StaffMarksScreen({super.key});
  @override
  ConsumerState<StaffMarksScreen> createState() => _StaffMarksScreenState();
}
class _StaffMarksScreenState extends ConsumerState<StaffMarksScreen> {
  String? examId, subjectId, sectionId; final edits = <String, Map<String, dynamic>>{}; bool busy = false;
  @override
  Widget build(BuildContext context) {
    final exams = ref.watch(staffExamsProvider); final secs = ref.watch(mySectionsProvider); final assigns = ref.watch(myAssignmentsProvider);
    final s = ref.watch(sessionProvider).value!;
    final cs = Theme.of(context).colorScheme;
    final exam = (exams.value ?? []).where((e) => e['id'] == examId).firstOrNull;
    final sectionsForGrade = (secs.value ?? []).where((x) => exam == null || x['grade']['id'] == exam['grade']['id']).toList();
    final subjectsFor = s.isOffice ? (List<Map<String, dynamic>>.from(exam?['exam_paper'] ?? []).map((p) => p['subject']).toList()) : (assigns.value ?? []).where((a) => a['section_id'] == sectionId).map((a) => a['subject']).toList();
    final rows = (examId != null && subjectId != null && sectionId != null) ? ref.watch(marksProvider((examId!, subjectId!, sectionId!))) : null;
    return StaffPage(title: 'Marks entry', subtitle: 'Marks are private to staff. Parents see them only on the published report card.', body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(padding: const EdgeInsets.all(12), child: Wrap(spacing: 10, runSpacing: 10, children: [
        SizedBox(width: 300, child: PickField<String>(label: 'Exam', value: examId, items: [for (final e in exams.value ?? []) DropdownMenuItem(value: e['id'] as String, child: Text('${e['grade']?['code']} · ${e['name']}'))], onChanged: (v) => setState(() { examId = v; sectionId = null; subjectId = null; edits.clear(); }))),
        SizedBox(width: 180, child: PickField<String>(label: 'Section', value: sectionId, items: [for (final x in sectionsForGrade) DropdownMenuItem(value: x['id'] as String, child: Text(sectionLabel(x)))], onChanged: (v) => setState(() { sectionId = v; subjectId = null; edits.clear(); }))),
        SizedBox(width: 220, child: PickField<String>(label: 'Subject', value: subjectId, items: [for (final x in subjectsFor) DropdownMenuItem(value: x['id'] as String, child: Text(x['name']))], onChanged: (v) => setState(() { subjectId = v; edits.clear(); }))),
      ])),
      if (rows != null) rows.when(loading: _loading, error: (e, _) => _err(e), data: (list) => Panel(padding: EdgeInsets.zero, title: null, child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Row(children: [const SizedBox(width: 40, child: Text('Roll', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))), const Expanded(child: Text('Student', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))), const SizedBox(width: 90, child: Text('Internal', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))), const SizedBox(width: 90, child: Text('External', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12))), const SizedBox(width: 70, child: Text('Absent', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)))])),
        const Divider(height: 1),
        for (final r in list) Builder(builder: (_) {
          final st = r['student']; final id = st['id'] as String; final m = edits[id] ?? {'internal': r['mark']?['internal'], 'external': r['mark']?['external'], 'absent': r['mark']?['absent'] ?? false};
          return Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: Row(children: [
            SizedBox(width: 40, child: Text('${r['roll_no'] ?? ''}')), Expanded(child: Text(st['full_name'], style: const TextStyle(fontWeight: FontWeight.w600))),
            SizedBox(width: 80, child: TextFormField(initialValue: m['internal']?.toString() ?? '', keyboardType: TextInputType.number, enabled: m['absent'] != true, onChanged: (v) => setState(() => edits[id] = {...m, 'internal': num.tryParse(v)}), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)))), const SizedBox(width: 10),
            SizedBox(width: 80, child: TextFormField(initialValue: m['external']?.toString() ?? '', keyboardType: TextInputType.number, enabled: m['absent'] != true, onChanged: (v) => setState(() => edits[id] = {...m, 'external': num.tryParse(v)}), decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10)))), const SizedBox(width: 10),
            SizedBox(width: 70, child: Checkbox(value: m['absent'] == true, onChanged: (v) => setState(() => edits[id] = {...m, 'absent': v ?? false}))),
          ]));
        }),
        Padding(padding: const EdgeInsets.all(14), child: Row(children: [Text('${edits.length} changed', style: TextStyle(color: cs.onSurfaceVariant)), const Spacer(), FilledButton.icon(onPressed: edits.isEmpty || busy ? null : () async {
          setState(() => busy = true);
          try { await saveMarks(ref, examId!, subjectId!, [for (final e in edits.entries) {'student_id': e.key, ...e.value}]); edits.clear(); ref.invalidate(marksProvider((examId!, subjectId!, sectionId!))); if (mounted) toast(context, 'Saved.'); } catch (e) { if (mounted) toast(context, 'Not allowed or failed: $e'); }
          if (mounted) setState(() => busy = false);
        }, icon: const Icon(Icons.save_rounded), label: const Text('Save marks'))])),
      ]))),
    ]));
  }
}

// ---------------------------------------------------------------- monthly plan (coordinator / office)
class StaffPlanScreen extends ConsumerStatefulWidget {
  const StaffPlanScreen({super.key});
  @override
  ConsumerState<StaffPlanScreen> createState() => _StaffPlanScreenState();
}
class _StaffPlanScreenState extends ConsumerState<StaffPlanScreen> {
  String? gradeId; DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String get iso => DateFormat('yyyy-MM-01').format(month);
  @override
  Widget build(BuildContext context) {
    final grades = ref.watch(gradesProvider); final subjects = ref.watch(subjectsProvider);
    gradeId ??= grades.value?.firstOrNull?['id'];
    final plan = gradeId == null ? null : ref.watch(staffPlanProvider((gradeId!, iso)));
    final cs = Theme.of(context).colorScheme;
    return StaffPage(title: 'Monthly plan', subtitle: 'What each subject covers this month. Parents see it under Monthly plan.', body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: PickField<String>(label: 'Grade', value: gradeId, items: [for (final g in grades.value ?? []) DropdownMenuItem(value: g['id'] as String, child: Text(g['name']))], onChanged: (v) => setState(() => gradeId = v))),
        const SizedBox(width: 12),
        IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left_rounded)), Text(DateFormat('MMMM yyyy').format(month), style: const TextStyle(fontWeight: FontWeight.w800)), IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right_rounded)),
      ])),
      if (plan != null) plan.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => Column(children: [for (final sub in subjects.value ?? []) Builder(builder: (_) {
        final r = rows.where((x) => x['subject']?['id'] == sub['id']).firstOrNull;
        return Panel(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 160, child: Text(sub['name'], style: const TextStyle(fontWeight: FontWeight.w800))),
          Expanded(child: r == null ? Text('Not set', style: TextStyle(color: cs.onSurfaceVariant)) : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r['topics']), if (r['assessment'] != null) Text('Assessment: ${r['assessment']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))])),
          TextButton(onPressed: () => _edit(context, sub, r), child: Text(r == null ? 'Add' : 'Edit')),
        ]));
      })])),
    ]));
  }
  void _edit(BuildContext context, Map<String, dynamic> sub, Map<String, dynamic>? r) {
    String topics = r?['topics'] ?? '', assessment = r?['assessment'] ?? '';
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text('${sub['name']} · ${DateFormat('MMMM').format(month)}'), content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(initialValue: topics, onChanged: (v) => topics = v, minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: 'Topics / chapters')), const SizedBox(height: 10),
      TextFormField(initialValue: assessment, onChanged: (v) => assessment = v, decoration: const InputDecoration(labelText: 'Assessment this month (optional)')),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () async {
      if (topics.trim().isEmpty) return;
      try { await savePlan(ref, gradeId: gradeId!, monthIso: iso, subjectId: sub['id'], topics: topics.trim(), assessment: assessment.trim().isEmpty ? null : assessment.trim()); ref.invalidate(staffPlanProvider((gradeId!, iso))); if (ctx.mounted) Navigator.pop(ctx); } catch (e) { if (ctx.mounted) toast(ctx, 'Not allowed or failed: $e'); }
    }, child: const Text('Save'))]));
  }
}

// ---------------------------------------------------------------- worksheets
class StaffWorksheetsScreen extends ConsumerWidget {
  const StaffWorksheetsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(staffWorksheetsProvider);
    final cs = Theme.of(context).colorScheme;
    return StaffPage(title: 'Worksheets', subtitle: 'PDFs for a section or a whole grade. Answer keys can be released on a later date.',
      actions: [FilledButton.icon(onPressed: () => _add(context, ref), icon: const Icon(Icons.upload_file_rounded), label: const Text('Upload worksheet'))],
      body: list.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => rows.isEmpty ? Panel(child: Text('No worksheets yet.', style: TextStyle(color: cs.onSurfaceVariant))) : Column(children: [for (final w in rows) Panel(padding: const EdgeInsets.all(14), child: Row(children: [
        const Icon(Icons.picture_as_pdf_rounded, color: Brand.crimsonDeep), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(w['title'], style: const TextStyle(fontWeight: FontWeight.w800)), Text('${w['subject']?['name'] ?? ''} · ${w['section'] != null ? sectionLabel(w['section']) : 'Grade ${w['grade']?['code'] ?? ''}'} · ${w['kind']} · ${w['author']?['display_name'] ?? ''} · ${_dm(w['created_at'])}${w['answer_key_path'] != null ? ' · key ${w['answer_key_release_on'] != null ? 'on ${_dm(w['answer_key_release_on'])}' : 'attached'}' : ''}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))])),
        TextButton(onPressed: () => openStorageFile(w['file_path']), child: const Text('Open')),
      ]))])));
  }
  void _add(BuildContext context, WidgetRef ref) {
    String? sectionId, gradeId, subjectId, path, keyPath; String kind = 'Practice', title = ''; DateTime? keyDate; bool busy = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(title: const Text('Upload worksheet'), content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(onChanged: (v) => title = v, decoration: const InputDecoration(labelText: 'Title')), const SizedBox(height: 10),
      Wrap(spacing: 6, children: [for (final k in ['Practice', 'Revision', 'Holiday', 'Project']) ChoiceChip(label: Text(k), selected: kind == k, onSelected: (_) => set(() => kind = k))]), const SizedBox(height: 10),
      Consumer(builder: (_, r, __) => r.watch(subjectsProvider).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (ss) => PickField<String>(label: 'Subject', value: subjectId, items: [for (final s in ss) DropdownMenuItem(value: s['id'] as String, child: Text(s['name']))], onChanged: (v) => set(() => subjectId = v)))), const SizedBox(height: 10),
      Consumer(builder: (_, r, __) => r.watch(mySectionsProvider).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (ss) => PickField<String?>(label: 'Section (or leave blank for a whole grade)', value: sectionId, items: [const DropdownMenuItem(value: null, child: Text('— whole grade —')), for (final s in ss) DropdownMenuItem(value: s['id'] as String, child: Text(sectionLabel(s)))], onChanged: (v) => set(() { sectionId = v; if (v != null) gradeId = null; })))), const SizedBox(height: 10),
      if (sectionId == null) Consumer(builder: (_, r, __) => r.watch(gradesProvider).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (gs) => PickField<String>(label: 'Grade', value: gradeId, items: [for (final g in gs) DropdownMenuItem(value: g['id'] as String, child: Text(g['name']))], onChanged: (v) => set(() => gradeId = v)))),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: () async { final p = await pickAndUpload(ctx, 'worksheets'); if (p != null) set(() => path = p); }, icon: const Icon(Icons.picture_as_pdf_rounded, size: 18), label: Text(path == null ? 'Choose worksheet PDF' : 'PDF attached ✓')), const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: () async { final p = await pickAndUpload(ctx, 'worksheets'); if (p != null) set(() => keyPath = p); }, icon: const Icon(Icons.key_rounded, size: 18), label: Text(keyPath == null ? 'Answer key PDF (optional)' : 'Key attached ✓')),
      if (keyPath != null) TextButton.icon(onPressed: () async { final d = await showDatePicker(context: ctx, initialDate: DateTime.now().add(const Duration(days: 3)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90))); if (d != null) set(() => keyDate = d); }, icon: const Icon(Icons.schedule_rounded, size: 18), label: Text(keyDate == null ? 'Release key on… (optional)' : 'Key visible from ${DateFormat('d MMM').format(keyDate!)}')),
    ]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: busy ? null : () async {
      if (title.trim().isEmpty || subjectId == null || path == null || (sectionId == null && gradeId == null)) { toast(ctx, 'Title, subject, section/grade and the PDF are needed.'); return; }
      set(() => busy = true);
      try { await addWorksheet(ref, sectionId: sectionId, gradeId: gradeId, subjectId: subjectId!, kind: kind, title: title.trim(), filePath: path!, keyPath: keyPath, keyRelease: keyDate); ref.invalidate(staffWorksheetsProvider); if (ctx.mounted) Navigator.pop(ctx); } catch (e) { set(() => busy = false); if (ctx.mounted) toast(ctx, 'Failed: $e'); }
    }, child: const Text('Publish'))])));
  }
}

// ---------------------------------------------------------------- star of the month
class StaffStarScreen extends ConsumerStatefulWidget {
  const StaffStarScreen({super.key});
  @override
  ConsumerState<StaffStarScreen> createState() => _StaffStarScreenState();
}
class _StaffStarScreenState extends ConsumerState<StaffStarScreen> {
  String? sectionId, studentId; DateTime month = DateTime(DateTime.now().year, DateTime.now().month); final reason = TextEditingController(); bool busy = false;
  @override
  Widget build(BuildContext context) {
    final secs = ref.watch(mySectionsProvider);
    sectionId ??= secs.value?.firstOrNull?['id'];
    final students = sectionId == null ? null : ref.watch(sectionStudentsProvider(sectionId!));
    return StaffPage(title: 'Star of the month', subtitle: 'One student per section per month, with a line on why. Shown to the whole section.', body: Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: PickField<String>(label: 'Section', value: sectionId, items: [for (final s in secs.value ?? []) DropdownMenuItem(value: s['id'] as String, child: Text(sectionLabel(s)))], onChanged: (v) => setState(() { sectionId = v; studentId = null; }))),
        const SizedBox(width: 12),
        IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left_rounded)), Text(DateFormat('MMMM yyyy').format(month), style: const TextStyle(fontWeight: FontWeight.w800)), IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right_rounded)),
      ]),
      const SizedBox(height: 12),
      if (students != null) students.when(loading: _loading, error: (e, _) => _err(e), data: (list) => PickField<String>(label: 'Student', value: studentId, items: [for (final r in list) DropdownMenuItem(value: r['student']['id'] as String, child: Text('${r['roll_no'] ?? ''}  ${r['student']['full_name']}'))], onChanged: (v) => setState(() => studentId = v))),
      const SizedBox(height: 12),
      TextField(controller: reason, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Why this student shines this month')),
      const SizedBox(height: 14),
      PrimaryButton('Post star of the month', icon: Icons.star_rounded, busy: busy, onPressed: () async {
        if (sectionId == null || studentId == null || reason.text.trim().isEmpty) { toast(context, 'Pick a student and write a line.'); return; }
        setState(() => busy = true);
        try { await postStar(ref, sectionId: sectionId!, studentId: studentId!, month: month, reason: reason.text.trim()); reason.clear(); if (mounted) toast(context, 'Posted.'); } catch (e) { if (mounted) toast(context, 'Not allowed or failed: $e'); }
        if (mounted) setState(() => busy = false);
      }),
    ])));
  }
}

// ---------------------------------------------------------------- class moments (photos)
class StaffMomentsScreen extends ConsumerStatefulWidget {
  const StaffMomentsScreen({super.key});
  @override
  ConsumerState<StaffMomentsScreen> createState() => _StaffMomentsScreenState();
}
class _StaffMomentsScreenState extends ConsumerState<StaffMomentsScreen> {
  String? sectionId; final caption = TextEditingController(); final paths = <String>[]; bool busy = false;
  @override
  Widget build(BuildContext context) {
    final secs = ref.watch(mySectionsProvider); final list = ref.watch(staffMomentsProvider);
    sectionId ??= secs.value?.firstOrNull?['id'];
    final cs = Theme.of(context).colorScheme;
    return StaffPage(title: 'Class moments', subtitle: 'A few photos from the classroom for the parents of that section. Only students with photo consent should appear.', body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(title: 'Share a moment', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PickField<String>(label: 'Section', value: sectionId, items: [for (final s in secs.value ?? []) DropdownMenuItem(value: s['id'] as String, child: Text(sectionLabel(s)))], onChanged: (v) => setState(() => sectionId = v)),
        const SizedBox(height: 10),
        TextField(controller: caption, decoration: const InputDecoration(labelText: 'Caption', hintText: 'e.g. Science fair models — well done, VIII-B!')),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in paths) StorageImage(p, width: 72, height: 72, radius: BorderRadius.circular(12)),
          OutlinedButton.icon(onPressed: busy ? null : () async {
            final xs = await ImagePicker().pickMultiImage(imageQuality: 82, maxWidth: 1600); if (xs.isEmpty) return;
            setState(() => busy = true);
            try { for (final x in xs.take(6)) { final b = await x.readAsBytes(); final path = 'photos/${sectionId}/${DateTime.now().millisecondsSinceEpoch}_${x.name}'; await db.storage.from('files').uploadBinary(path, b, fileOptions: const FileOptions(contentType: 'image/jpeg')); paths.add(path); } } catch (e) { if (mounted) toast(context, 'Upload failed: $e'); }
            if (mounted) setState(() => busy = false);
          }, icon: const Icon(Icons.add_photo_alternate_rounded, size: 18), label: const Text('Add photos (up to 6)')),
        ]),
        const SizedBox(height: 12),
        PrimaryButton('Post to parents', icon: Icons.send_rounded, busy: busy, onPressed: () async {
          if (sectionId == null || caption.text.trim().isEmpty || paths.isEmpty) { toast(context, 'Caption and at least one photo are needed.'); return; }
          setState(() => busy = true);
          try { await postMoment(ref, sectionId: sectionId!, caption: caption.text.trim(), paths: List.of(paths)); caption.clear(); paths.clear(); ref.invalidate(staffMomentsProvider); if (mounted) toast(context, 'Posted.'); } catch (e) { if (mounted) toast(context, 'Failed: $e'); }
          if (mounted) setState(() => busy = false);
        }),
      ])),
      list.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => Column(children: [for (final m in rows) Panel(padding: const EdgeInsets.all(12), child: Row(children: [
        if ((m['photo_paths'] as List).isNotEmpty) StorageImage(m['photo_paths'][0], width: 64, height: 64, radius: BorderRadius.circular(12)), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m['caption'], style: const TextStyle(fontWeight: FontWeight.w700)), Text('${m['section'] != null ? sectionLabel(m['section']) : ''} · ${m['posted_by_staff']?['display_name'] ?? ''} · ${_dmt(m['posted_at'])} · ${(m['photo_paths'] as List).length} photo(s)', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))])),
      ]))])),
    ]));
  }
}

// ---------------------------------------------------------------- parent feedback (office)
class StaffFeedbackScreen extends ConsumerWidget {
  const StaffFeedbackScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(staffFeedbackProvider);
    final cs = Theme.of(context).colorScheme;
    return StaffPage(title: 'Parent feedback', subtitle: 'Suggestions, appreciation and concerns sent from the app. Anonymous ones show the class only.', body: list.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => rows.isEmpty ? Panel(child: Text('No feedback yet.', style: TextStyle(color: cs.onSurfaceVariant))) : Column(children: [for (final f in rows) Panel(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Pill(f['category'], fg: Brand.violet, bg: Brand.violetTint), const SizedBox(width: 8), Pill(f['status'], fg: f['status'] == 'new' ? Brand.crimsonDeep : Brand.green, bg: f['status'] == 'new' ? Brand.crimsonTint : Brand.greenTint), const Spacer(), Text(_dmt(f['created_at']), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))]),
      const SizedBox(height: 8),
      Text(f['subject'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      Text(f['body'], style: const TextStyle(height: 1.45)),
      const SizedBox(height: 6),
      Text(f['anonymous'] == true ? 'Anonymous · ${f['section'] != null ? sectionLabel(f['section']) : ''}' : '${f['student']?['full_name'] ?? ''} · ${f['student']?['admission_no'] ?? ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
      if (f['reply'] != null) Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Brand.greenTint, borderRadius: BorderRadius.circular(10)), child: Text('Reply: ${f['reply']}')),
      Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () {
        String reply = f['reply'] ?? ''; String status = f['status'] == 'new' ? 'in_progress' : f['status'];
        showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(title: const Text('Reply / update'), content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(initialValue: reply, onChanged: (v) => reply = v, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Reply (visible to the parent, unless anonymous)')), const SizedBox(height: 10),
          Wrap(spacing: 6, children: [for (final s in ['in_progress', 'resolved', 'closed']) ChoiceChip(label: Text(s.replaceAll('_', ' ')), selected: status == s, onSelected: (_) => set(() => status = s))]),
        ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () async { await replyFeedback(ref, f['id'], reply.trim(), status); ref.invalidate(staffFeedbackProvider); ref.invalidate(staffOverviewProvider); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('Save'))])));
      }, child: const Text('Reply / update'))),
    ]))])));
  }
}

// ---------------------------------------------------------------- fees desk (office / accounts)
class StaffFeesScreen extends ConsumerStatefulWidget {
  const StaffFeesScreen({super.key});
  @override
  ConsumerState<StaffFeesScreen> createState() => _StaffFeesScreenState();
}
class _StaffFeesScreenState extends ConsumerState<StaffFeesScreen> {
  int tab = 0; String q = ''; String? studentId; String studentName = '';
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StaffPage(title: 'Fees desk', subtitle: 'Every online payment lands here with its receipt number. Fee heads and plans are loaded from the accounts sheet.', body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<int>(segments: const [ButtonSegment(value: 0, label: Text('Student ledger')), ButtonSegment(value: 1, label: Text('Overdue')), ButtonSegment(value: 2, label: Text('Recent payments'))], selected: {tab}, onSelectionChanged: (v) => setState(() => tab = v.first)),
      const SizedBox(height: 14),
      if (tab == 0) ...[
        Panel(padding: const EdgeInsets.all(12), child: TextField(onChanged: (v) => setState(() { q = v; studentId = null; }), decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search by name or admission number'))),
        if (studentId == null) Consumer(builder: (_, r, __) => r.watch(studentSearchProvider(q)).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (rows) => Column(children: [for (final s in rows) ListTile(title: Text(s['full_name']), subtitle: Text('${s['admission_no']} · ${_cls(s)}'), onTap: () => setState(() { studentId = s['id']; studentName = s['full_name']; }))]))),
        if (studentId != null) Consumer(builder: (_, r, __) => r.watch(studentLedgerProvider(studentId!)).when(loading: _loading, error: (e, _) => _err(e), data: (rows) {
          final total = rows.fold<num>(0, (a, x) => a + (x['amount'] as num)); final paid = rows.where((x) => x['status'] == 'paid').fold<num>(0, (a, x) => a + (x['amount'] as num));
          return Panel(title: studentName, trailing: Text('Paid ${inr(paid)} of ${inr(total)}', style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.green)), child: Column(children: [for (final x in rows) ListTile(dense: true, contentPadding: EdgeInsets.zero,
            leading: Icon(x['status'] == 'paid' ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: x['status'] == 'paid' ? Brand.green : (DateTime.parse(x['due_on']).isBefore(DateTime.now()) ? Brand.crimson : cs.onSurfaceVariant)),
            title: Text(x['title']), subtitle: Text('Due ${_dmy(x['due_on'])}${x['paid_on'] != null ? ' · paid ${_dmy(x['paid_on'])}' : ''}${x['note'] != null ? ' · ${x['note']}' : ''}'), trailing: Text(inr(x['amount']), style: const TextStyle(fontWeight: FontWeight.w800)))]));
        })),
      ],
      if (tab == 1) Consumer(builder: (_, r, __) => r.watch(overdueReportProvider).when(loading: _loading, error: (e, _) => _err(e), data: (rows) => Panel(title: '${rows.length} overdue items · ${inr(rows.fold<num>(0, (a, x) => a + (x['amount'] as num)))}', padding: const EdgeInsets.all(12), child: Column(children: [for (final x in rows) ListTile(dense: true, title: Text('${x['student']?['full_name'] ?? ''} · ${_cls(x['student'])}'), subtitle: Text('${x['title']} · due ${_dmy(x['due_on'])}'), trailing: Text(inr(x['amount']), style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.crimsonDeep)))])))),
      if (tab == 2) Consumer(builder: (_, r, __) => r.watch(recentPaymentsProvider).when(loading: _loading, error: (e, _) => _err(e), data: (rows) => Panel(padding: const EdgeInsets.all(12), child: rows.isEmpty ? Text('No online payments yet.', style: TextStyle(color: cs.onSurfaceVariant)) : Column(children: [for (final p in rows) ListTile(dense: true, leading: const Icon(Icons.receipt_long_rounded, color: Brand.green), title: Text('${p['receipt_no']} · ${p['student']?['full_name'] ?? ''}'), subtitle: Text('${p['mode']} · ${_dmt(p['paid_at'])}'), trailing: Text(inr(p['amount']), style: const TextStyle(fontWeight: FontWeight.w800)))])))),
    ]));
  }
}

// ---------------------------------------------------------------- transport
class StaffTransportScreen extends ConsumerWidget {
  const StaffTransportScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(routesProvider); final trips = ref.watch(runningTripsProvider);
    final cs = Theme.of(context).colorScheme;
    return StaffPage(title: 'Transport', subtitle: 'Routes, crew and live trips. Drivers and conductors sign in with their phone number.', body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(title: 'Live now', child: trips.when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (list) => list.isEmpty ? Text('No trips running.', style: TextStyle(color: cs.onSurfaceVariant)) : Wrap(spacing: 10, runSpacing: 10, children: [for (final t in list) Chip(avatar: const Icon(Icons.gps_fixed_rounded, color: Brand.green, size: 16), label: Text('${t['route']?['name']} · ${t['kind']} · since ${_dmt(t['started_at'])}${t['last_fix_at'] != null ? ' · GPS ${DateFormat('h:mm:ss').format(DateTime.parse(t['last_fix_at']).toLocal())}' : ''}'), backgroundColor: Brand.greenTint, side: BorderSide.none)]))),
      routes.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => Column(children: [for (final r in rows) Panel(title: '${r['name']} · ${r['bus_reg_no']}', trailing: Pill(r['active'] == true ? 'Active' : 'Inactive', fg: r['active'] == true ? Brand.green : Brand.muted, bg: r['active'] == true ? Brand.greenTint : Brand.surface2), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 16, runSpacing: 6, children: [
          Text('Driver: ${r['driver']?['display_name'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)), if (r['driver']?['phone'] != null) InkWell(onTap: () => callNumber(r['driver']['phone']), child: Text(r['driver']['phone'], style: const TextStyle(color: Brand.blue))),
          Text('Conductor: ${r['conductor']?['display_name'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)), if (r['conductor']?['phone'] != null) InkWell(onTap: () => callNumber(r['conductor']['phone']), child: Text(r['conductor']['phone'], style: const TextStyle(color: Brand.blue))),
          Text('${(r['transport_enrolment'] as List).length} students', style: TextStyle(color: cs.onSurfaceVariant)),
          Text('Morning ${(r['morning_start'] ?? '').toString().padRight(5).substring(0, 5)} · Afternoon ${(r['afternoon_start'] ?? '').toString().padRight(5).substring(0, 5)}', style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
        const SizedBox(height: 8),
        Text((List<Map<String, dynamic>>.from(r['route_stop'] ?? [])..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int))).map((s) => s['name']).join('  →  '), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]))])),
      const NoteBox('Adding or editing routes, stops and crew is done by the import tool for now (the sheet from the transport office). Live editing screens come with the next update.'),
    ]));
  }
}

// ---------------------------------------------------------------- students
class StaffStudentsScreen extends ConsumerStatefulWidget {
  const StaffStudentsScreen({super.key});
  @override
  ConsumerState<StaffStudentsScreen> createState() => _StaffStudentsScreenState();
}
class _StaffStudentsScreenState extends ConsumerState<StaffStudentsScreen> {
  String? sectionId; String q = '';
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!; final secs = ref.watch(mySectionsProvider);
    sectionId ??= secs.value?.firstOrNull?['id'];
    final cs = Theme.of(context).colorScheme;
    final canReset = s.isOffice || (secs.value ?? []).any((x) => x['id'] == sectionId && x['class_teacher_id'] == s.staff?['id']);
    return StaffPage(title: 'Students', subtitle: 'Section lists, family phones, password slips and sign-out-all.', body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: PickField<String>(label: 'Section', value: sectionId, items: [for (final x in secs.value ?? []) DropdownMenuItem(value: x['id'] as String, child: Text(sectionLabel(x)))], onChanged: (v) => setState(() => sectionId = v))),
        if (s.isOffice) ...[const SizedBox(width: 12), Expanded(child: TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search any student')))],
      ])),
      if (q.trim().length >= 2) Consumer(builder: (_, r, __) => r.watch(studentSearchProvider(q)).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (rows) => Panel(padding: const EdgeInsets.all(8), child: Column(children: [for (final st in rows) _row(context, st, _cls(st), true)]))))
      else if (sectionId != null) Consumer(builder: (_, r, __) => r.watch(sectionStudentsProvider(sectionId!)).when(loading: _loading, error: (e, _) => _err(e), data: (rows) => Panel(padding: const EdgeInsets.all(8), child: rows.isEmpty ? Padding(padding: const EdgeInsets.all(12), child: Text('No students enrolled in this section yet.', style: TextStyle(color: cs.onSurfaceVariant))) : Column(children: [for (final e in rows) _row(context, e['student'], 'Roll ${e['roll_no'] ?? '—'}', canReset)])))),
    ]));
  }

  Widget _row(BuildContext context, Map<String, dynamic> st, String sub, bool canReset) {
    final phones = List<Map<String, dynamic>>.from(st['family_phone'] ?? []);
    return ListTile(
      leading: Avatar((st['full_name'] as String).split(' ').take(2).map((w) => w[0]).join(), size: 40),
      title: Text(st['full_name'], style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${st['admission_no']} · $sub${phones.isNotEmpty ? ' · ${phones.map((p) => p['phone']).join(', ')}' : ''}'),
      trailing: canReset ? PopupMenuButton<String>(onSelected: (v) => v == 'reset' ? _reset(context, st) : _signoutAll(context, st), itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('Reset password (print slip)')), PopupMenuItem(value: 'signout', child: Text('Sign out all phones'))]) : null,
    );
  }

  Future<void> _reset(BuildContext context, Map<String, dynamic> st) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Reset password?'), content: Text('${st['full_name']} will get a new one-time password and must set a new one on next sign-in. All phones currently signed in for this student are signed out.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset'))]));
    if (ok != true) return;
    try {
      final r = await callFunction(ref, 'password', {'action': 'reset', 'student_id': st['id'], 'via': 'print'});
      if (!context.mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Password slip'), content: SelectableText('Royale Connect — first-use password\n\nStudent: ${st['full_name']}\nAdmission no: ${st['admission_no']}\nPassword: ${r['first_use_password']}\n\nSign in at the app, then set your own password. This slip is the only copy.', style: const TextStyle(fontFamily: 'monospace', height: 1.6)), actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))]));
    } catch (e) { if (context.mounted) toast(context, 'Failed: $e'); }
  }

  Future<void> _signoutAll(BuildContext context, Map<String, dynamic> st) async {
    try { await callFunction(ref, 'password', {'action': 'signout_all', 'student_id': st['id']}); if (context.mounted) toast(context, 'All phones signed out for ${st['full_name']}.'); } catch (e) { if (context.mounted) toast(context, 'Failed: $e'); }
  }
}

// ---------------------------------------------------------------- staff directory & my settings
class StaffUsersScreen extends ConsumerWidget {
  const StaffUsersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(staffListProvider);
    final cs = Theme.of(context).colorScheme;
    return StaffPage(title: 'Staff & settings', subtitle: 'Who has which role. IT or the principal can issue a one-time password to a colleague.', body: list.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => Panel(padding: const EdgeInsets.all(8), child: Column(children: [for (final st in rows) ListTile(
      leading: Avatar((st['full_name'] as String).split(' ').take(2).map((w) => w[0]).join(), size: 40),
      title: Text(st['display_name'] ?? st['full_name'], style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${st['email']} · ${List<String>.from(st['roles'] ?? []).map(roleLabel).join(', ')}${st['division'] != null ? ' · ${st['division']}' : ''}', style: TextStyle(color: cs.onSurfaceVariant)),
      trailing: TextButton(onPressed: () async {
        try { final r = await callFunction(ref, 'password', {'action': 'reset_staff', 'staff_id': st['id']}); if (!context.mounted) return;
          showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('One-time password'), content: SelectableText('${st['full_name']}\n${st['email']}\n\nPassword: ${r['first_use_password']}\n\nThey must change it at first sign-in.', style: const TextStyle(fontFamily: 'monospace', height: 1.6)), actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))]));
        } catch (e) { if (context.mounted) toast(context, 'Failed: $e'); }
      }, child: const Text('Reset password')),
    )]))));
  }
}

class StaffMeScreen extends ConsumerStatefulWidget {
  const StaffMeScreen({super.key});
  @override
  ConsumerState<StaffMeScreen> createState() => _StaffMeScreenState();
}
class _StaffMeScreenState extends ConsumerState<StaffMeScreen> {
  final cur = TextEditingController(), a = TextEditingController(), b = TextEditingController(); bool busy = false;
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    return StaffPage(title: 'My settings', body: Column(children: [
      Panel(title: 'Signed in as', child: Text('${s.staff?['name']} · ${s.staff?['email']}\n${s.roles.map(roleLabel).join(', ')}')),
      Panel(title: 'Change password', child: Column(children: [
        TextField(controller: cur, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')), const SizedBox(height: 10),
        TextField(controller: a, obscureText: true, decoration: const InputDecoration(labelText: 'New password (8+)')), const SizedBox(height: 10),
        TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'Repeat new password')), const SizedBox(height: 14),
        PrimaryButton('Update password', busy: busy, onPressed: () async {
          if (a.text.length < 8 || a.text != b.text) { toast(context, 'Check the new password (8+ characters, both the same).'); return; }
          setState(() => busy = true);
          try { await ref.read(sessionProvider.notifier).changeStaffPassword(a.text, current: cur.text); if (mounted) { toast(context, 'Password updated.'); context.go('/staff'); } } catch (e) { if (mounted) toast(context, '$e'); }
          if (mounted) setState(() => busy = false);
        }),
      ])),
    ]));
  }
}
