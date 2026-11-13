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
import '../core/errors.dart';
import '../core/theme.dart';
import '../screens/family_screens.dart' show StorageImage, callNumber;
import '../widgets/common.dart';
import '../widgets/royal_extras.dart' show ShimmerPage;
import 'staff_data.dart';
import 'staff_shell.dart';
import 'class_logins.dart' show resetFirstPassword, printClassSlips;
import 'fees_office.dart' show FeeCategoryBar, RecentPaymentsPanel;
import 'transport_live.dart';
export 'exams_marks.dart' show StaffExamsScreen, StaffMarksScreen, marksCanLeave;

String _d(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String _dmy(String? iso) => iso == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());
String _dmt(String? iso) => iso == null ? '' : DateFormat('d MMM, h:mm a').format(DateTime.parse(iso).toLocal());
Widget _loading() => const ShimmerPage();
Widget _err(Object e) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e), style: const TextStyle(color: Brand.crimsonDeep)));
String _cls(Map<String, dynamic>? student) { final en = (student?['enrolment'] as List?) ?? []; if (en.isEmpty) return ''; final s = en.first['section']; return '${s?['grade']?['code'] ?? ''}-${s?['name'] ?? ''}'; }

/// Pick several PDFs / photos and upload them under [folder]; returns {path, name, mime} for each.
Future<List<Map<String, dynamic>>> pickAndUploadMany(BuildContext context, String folder, {int maxMb = 10}) async {
  final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'], withData: true, allowMultiple: true);
  if (r == null) return [];
  final out = <Map<String, dynamic>>[];
  for (final f in r.files) {
    if (f.bytes == null) continue;
    if (f.bytes!.length > maxMb * 1024 * 1024) { if (context.mounted) toast(context, '${f.name} is over $maxMb MB and was skipped.'); continue; }
    final ext = (f.extension ?? '').toLowerCase();
    final mime = ext == 'pdf' ? 'application/pdf' : 'image/${ext == 'jpg' ? 'jpeg' : ext}';
    final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_${f.name}';
    await db.storage.from('files').uploadBinary(path, Uint8List.fromList(f.bytes!), fileOptions: FileOptions(contentType: mime));
    out.add({'path': path, 'name': f.name, 'mime': mime});
  }
  return out;
}

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
    final history = sectionId == null ? null : ref.watch(staffStarHistoryProvider(sectionId!));
    return StaffPage(title: 'Star of the month', subtitle: 'One student per section per month, with a line on why. Shown to the whole section.', body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (history != null) history.when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (rows) => rows.isEmpty ? const SizedBox() : Panel(title: 'This year so far', child: Wrap(spacing: 10, runSpacing: 10, children: [for (final r in rows) Container(width: 220, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Brand.amberTint.withValues(alpha: .5), borderRadius: BorderRadius.circular(14)), child: Row(children: [
        r['student']?['photo_path'] != null ? StorageImage(r['student']['photo_path'], width: 44, height: 44, radius: BorderRadius.circular(14)) : Avatar((r['student']?['full_name'] ?? '?').toString().split(' ').take(2).map((w) => w[0]).join(), size: 44),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(DateFormat('MMM yyyy').format(DateTime.parse(r['month'])), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Brand.amber)), Text(r['student']?['full_name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))])),
      ]))]))),
      Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PickRow(children: [
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
        try { await postStar(ref, sectionId: sectionId!, studentId: studentId!, month: month, reason: reason.text.trim()); reason.clear(); ref.invalidate(staffStarHistoryProvider(sectionId!)); if (mounted) toast(context, 'Posted.'); } catch (e) { if (mounted) toast(context, friendlyError(e)); }
        if (mounted) setState(() => busy = false);
      }),
      const SizedBox(height: 6),
      Text("The student's profile photo is shown with the star. Parents see this month at the top and the earlier months of the year below it.", style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]))]));
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
    return StaffPage(title: 'Class photos', subtitle: 'A few photos from the classroom for the parents of that section. Only students with photo consent should appear.', body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
            try { for (final x in xs.take(10)) { final b = await x.readAsBytes(); final path = 'photos/${sectionId}/${DateTime.now().millisecondsSinceEpoch}_${x.name}'; await db.storage.from('files').uploadBinary(path, b, fileOptions: const FileOptions(contentType: 'image/jpeg')); paths.add(path); } } catch (e) { if (mounted) toast(context, 'Upload failed: $e'); }
            if (mounted) setState(() => busy = false);
          }, icon: const Icon(Icons.add_photo_alternate_rounded, size: 18), label: const Text('Add photos (up to 10)')),
        ]),
        const SizedBox(height: 12),
        PrimaryButton('Post to parents', icon: Icons.send_rounded, busy: busy, onPressed: () async {
          if (sectionId == null || caption.text.trim().isEmpty || paths.isEmpty) { toast(context, 'Caption and at least one photo are needed.'); return; }
          setState(() => busy = true);
          try { await postMoment(ref, sectionId: sectionId!, caption: caption.text.trim(), paths: List.of(paths)); caption.clear(); paths.clear(); ref.invalidate(staffMomentsProvider); if (mounted) toast(context, 'Posted.'); } catch (e) { if (mounted) toast(context, friendlyError(e)); }
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
    return StaffPage(title: 'Fees & receipts', subtitle: 'Every online payment lands here with its receipt number. Fee heads and plans are loaded from the accounts sheet.',
        actions: [OutlinedButton.icon(onPressed: () => context.go('/staff/fees/reports'), icon: const Icon(Icons.table_view_rounded, size: 18), label: const Text('Reports & Excel'))],
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedButton<int>(showSelectedIcon: !isNarrow(context), segments: [ButtonSegment(value: 0, label: Text(isNarrow(context) ? 'Ledger' : 'Student ledger')), const ButtonSegment(value: 1, label: Text('Overdue')), ButtonSegment(value: 2, label: Text(isNarrow(context) ? 'Payments' : 'Recent payments'))], selected: {tab}, onSelectionChanged: (v) => setState(() => tab = v.first)),
      const SizedBox(height: 14),
      if (tab == 0) ...[
        Panel(padding: const EdgeInsets.all(12), child: TextField(onChanged: (v) => setState(() { q = v; studentId = null; }), decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search by name or admission number'))),
        if (studentId == null) Consumer(builder: (_, r, __) => r.watch(studentSearchProvider(q)).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (rows) => Column(children: [for (final s in rows) ListTile(title: Text(s['full_name']), subtitle: Text('${s['admission_no']} · ${_cls(s)}'), onTap: () => setState(() { studentId = s['id']; studentName = s['full_name']; }))]))),
        if (studentId != null) FeeCategoryBar(studentId: studentId!, onChanged: () => ref.invalidate(studentLedgerProvider(studentId!))),
        if (studentId != null) Consumer(builder: (_, r, __) => r.watch(studentLedgerProvider(studentId!)).when(loading: _loading, error: (e, _) => _err(e), data: (rows) {
          final total = rows.fold<num>(0, (a, x) => a + (x['amount'] as num)); final paid = rows.where((x) => x['status'] == 'paid').fold<num>(0, (a, x) => a + (x['amount'] as num));
          return Panel(title: studentName, trailing: Text('Paid ${inr(paid)} of ${inr(total)}', style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.green)), child: Column(children: [for (final x in rows) ListTile(dense: true, contentPadding: EdgeInsets.zero,
            leading: Icon(x['status'] == 'paid' ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: x['status'] == 'paid' ? Brand.green : (DateTime.parse(x['due_on']).isBefore(DateTime.now()) ? Brand.crimson : cs.onSurfaceVariant)),
            title: Text(x['title']), subtitle: Text('Due ${_dmy(x['due_on'])}${x['paid_on'] != null ? ' · paid ${_dmy(x['paid_on'])}' : ''}${x['note'] != null ? ' · ${x['note']}' : ''}'), trailing: Text(inr(x['amount']), style: const TextStyle(fontWeight: FontWeight.w800)))]));
        })),
      ],
      if (tab == 1) Consumer(builder: (_, r, __) => r.watch(overdueReportProvider).when(loading: _loading, error: (e, _) => _err(e), data: (rows) => Panel(title: '${rows.length} overdue items · ${inr(rows.fold<num>(0, (a, x) => a + (x['amount'] as num)))}', padding: const EdgeInsets.all(12), child: Column(children: [for (final x in rows) ListTile(dense: true, title: Text('${x['student']?['full_name'] ?? ''} · ${_cls(x['student'])}'), subtitle: Text('${x['title']} · due ${_dmy(x['due_on'])}'), trailing: Text(inr(x['amount']), style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.crimsonDeep)))])))),
      if (tab == 2) const RecentPaymentsPanel(),
    ]));
  }
}

// ---------------------------------------------------------------- transport
class StaffTransportScreen extends ConsumerWidget {
  final bool bodyOnly;
  const StaffTransportScreen({super.key, this.bodyOnly = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routes = ref.watch(routesProvider);
    final cs = Theme.of(context).colorScheme;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _CrewPasswordPanel(),
      const RunningBusesPanel(),
      routes.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => Column(children: [for (final r in rows) Panel(title: '${r['name']} · ${r['bus_reg_no']}', trailing: Pill(r['active'] == true ? 'Active' : 'Inactive', fg: r['active'] == true ? Brand.green : Brand.muted, bg: r['active'] == true ? Brand.greenTint : Brand.surface2), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 16, runSpacing: 6, children: [
          Text('Driver: ${r['driver']?['display_name'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)), if (r['driver']?['phone'] != null) InkWell(onTap: () => callNumber(r['driver']['phone']), child: Text(r['driver']['phone'], style: const TextStyle(color: Brand.blue))),
          Text('Bus assistant: ${r['conductor']?['display_name'] ?? '—'}', style: const TextStyle(fontWeight: FontWeight.w700)), if (r['conductor']?['phone'] != null) InkWell(onTap: () => callNumber(r['conductor']['phone']), child: Text(r['conductor']['phone'], style: const TextStyle(color: Brand.blue))),
          Text('${(r['transport_enrolment'] as List).length} students', style: TextStyle(color: cs.onSurfaceVariant)),
          Text('Morning ${(r['morning_start'] ?? '').toString().padRight(5).substring(0, 5)} · Afternoon ${(r['afternoon_start'] ?? '').toString().padRight(5).substring(0, 5)}', style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
        const SizedBox(height: 8),
        Text((List<Map<String, dynamic>>.from(r['route_stop'] ?? [])..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int))).map((s) => s['name']).join('  →  '), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final role in const ['driver', 'conductor']) OutlinedButton.icon(
            onPressed: () => crewLoginDialog(context, ref, r, role),
            icon: const Icon(Icons.key_rounded, size: 18),
            label: Text(r[role]?['username'] != null ? '${role == 'driver' ? 'Driver' : 'Bus assistant'}: ${r[role]['display_name'] ?? ''} · login ${r[role]['username']}' : 'Set up ${role == 'driver' ? 'driver' : 'bus assistant'} login'),
          ),
        ]),
      ]))])),
      const NoteBox('To add a route, place stops on the map or put students on a bus, choose “Routes, stops & students” at the top.'),
    ]);
    return bodyOnly ? body : StaffPage(title: 'Transport', subtitle: 'Routes, crew and live trips. Drivers and bus assistants sign in with the login ID and password made here.', body: body);
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
      Panel(padding: const EdgeInsets.all(12), child: PickRow(children: [
        Expanded(child: PickField<String>(label: 'Section', value: sectionId, items: [for (final x in secs.value ?? []) DropdownMenuItem(value: x['id'] as String, child: Text(sectionLabel(x)))], onChanged: (v) => setState(() => sectionId = v))),
        if (s.isOffice) ...[const SizedBox(width: 12), Expanded(child: TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search any student')))],
      ])),
      if (q.trim().length >= 2) Consumer(builder: (_, r, __) => r.watch(studentSearchProvider(q)).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (rows) => Panel(padding: const EdgeInsets.all(8), child: Column(children: [for (final st in rows) _row(context, st, _cls(st), true)]))))
      else if (sectionId != null && canReset) Padding(padding: const EdgeInsets.only(bottom: 10), child: Align(alignment: Alignment.centerRight, child: OutlinedButton.icon(
          onPressed: () => printClassSlips(context, ref, sectionId!, sectionLabel((secs.value ?? []).firstWhere((x) => x['id'] == sectionId))),
          icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Print slips for this class')))),
      if (q.trim().length < 2 && sectionId != null) Consumer(builder: (_, r, __) => r.watch(sectionStudentsProvider(sectionId!)).when(loading: _loading, error: (e, _) => _err(e), data: (rows) => Panel(padding: const EdgeInsets.all(8), child: rows.isEmpty ? Padding(padding: const EdgeInsets.all(12), child: Text('No students enrolled in this section yet.', style: TextStyle(color: cs.onSurfaceVariant))) : Column(children: [for (final e in rows) _row(context, e['student'], 'Roll ${e['roll_no'] ?? '—'}', canReset)])))),
    ]));
  }

  Widget _row(BuildContext context, Map<String, dynamic> st, String sub, bool canReset) {
    final phones = List<Map<String, dynamic>>.from(st['family_phone'] ?? []);
    return ListTile(
      leading: Avatar((st['full_name'] as String).split(' ').take(2).map((w) => w[0]).join(), size: 40),
      title: Text(st['full_name'], style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${st['admission_no']} · $sub${phones.isNotEmpty ? ' · ${phones.map((p) => p['phone']).join(', ')}' : ''}'),
      trailing: canReset ? PopupMenuButton<String>(onSelected: (v) => v == 'reset' ? _reset(context, st) : _signoutAll(context, st), itemBuilder: (_) => const [PopupMenuItem(value: 'reset', child: Text('New first password')), PopupMenuItem(value: 'signout', child: Text('Sign out all phones'))]) : null,
    );
  }

  // a new first password ("ana@8919"), shown big to read out; it also appears in Class logins until the family changes it
  Future<void> _reset(BuildContext context, Map<String, dynamic> st) => resetFirstPassword(context, ref, '${st['id']}', '${st['full_name'] ?? ''}');

  Future<void> _signoutAll(BuildContext context, Map<String, dynamic> st) async {
    try { await callFunction(ref, 'password', {'action': 'signout_all', 'student_id': st['id']}); if (context.mounted) toast(context, 'All phones signed out for ${st['full_name']}.'); } catch (e) { if (context.mounted) toast(context, friendlyError(e)); }
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
        } catch (e) { if (context.mounted) toast(context, friendlyError(e)); }
      }, child: Text(isNarrow(context) ? 'Reset' : 'Reset password')),
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
      Panel(title: 'Appearance', trailing: const ThemeChoice(), child: Text('Automatic (the usual): dark from 6:15 pm to 6:15 am, light in the day. Or keep Light or Dark all the time.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
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
      Panel(child: OutlinedButton.icon(onPressed: () async { await ref.read(sessionProvider.notifier).signOut(); if (context.mounted) context.go('/login'); },
          icon: const Icon(Icons.logout_rounded, color: Brand.crimson), label: const Text('Sign out of this device', style: TextStyle(color: Brand.crimson, fontWeight: FontWeight.w800)))),
    ]));
  }
}


/// Office / transport in-charge: make the login for a route's driver or bus assistant.
/// Login ID = dr + route number (driver) or as + route number (bus assistant); the password is the common bus password.
Future<void> crewLoginDialog(BuildContext context, WidgetRef ref, Map<String, dynamic> route, String role) async {
  final cur = route[role] as Map<String, dynamic>?;
  final no = RegExp(r'\d+').firstMatch('${route['name']}')?.group(0) ?? '';
  final id = '${role == 'driver' ? 'dr' : 'as'}$no';
  final name = TextEditingController(text: cur?['display_name'] ?? '');
  final phone = TextEditingController(text: cur?['phone'] ?? '');
  final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
    title: Text('${role == 'driver' ? 'Driver' : 'Bus assistant'} · ${route['name']}'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
      const SizedBox(height: 10),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile number (parents can call)')),
      const SizedBox(height: 14),
      Text('Login ID: $id', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const Text('Password: the common bus password (set at the top of this page).', style: TextStyle(fontSize: 12)),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
  ));
  if (ok != true || !context.mounted) return;
  try {
    final r = await callFunction(ref, 'password', {'action': 'crew_account', 'route_id': route['id'], 'role': role, 'name': name.text, 'phone': phone.text});
    ref.invalidate(routesProvider);
    if (!context.mounted) return;
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text('Bus login'),
      content: SelectableText('Royale Connect — ${r['route']} ${r['role'] == 'driver' ? 'driver' : 'bus assistant'}\n\nName: ${name.text}\nLogin ID: ${r['username']}\nPassword: ${r['password']}\n\nOpen the app → “School staff? Sign in here” → type the login ID and password.',
          style: const TextStyle(fontFamily: 'monospace', height: 1.6)),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
    ));
  } catch (e) {
    if (context.mounted) toast(context, 'Could not save: $e');
  }
}

/// One password for every driver and bus assistant. Changing it here changes it for all of them at once.
class _CrewPasswordPanel extends ConsumerStatefulWidget {
  const _CrewPasswordPanel();
  @override
  ConsumerState<_CrewPasswordPanel> createState() => _CrewPasswordPanelState();
}
class _CrewPasswordPanelState extends ConsumerState<_CrewPasswordPanel> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Panel(title: 'Bus crew sign-in', child: Text(
        'Login ID = dr + bus number for the driver (dr7), as + bus number for the bus assistant (as7). Each one has their own password: tap “New login” on a bus below to make it, and give it to them. They choose their own at the first sign-in.',
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)));
  }
}
