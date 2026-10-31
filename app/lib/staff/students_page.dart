import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../auth/session.dart';
import '../core/data.dart';
import '../core/school_docs.dart' show openReceiptPdf, openReportCardPdf;
import '../core/theme.dart';
import '../widgets/common.dart';
import 'school_setup.dart' show StudentEditor, setupSectionsProvider;
import 'staff_data.dart';
import 'staff_screens_2.dart' show StaffStudentsScreen, pickAndUpload;
import 'staff_shell.dart';

/// Students — one page for the office: current and past students, one search box
/// (name, admission number — old or new — or a parent's phone), and each student's full record:
/// Details · Fees · Marks · Attendance · Documents · Bus.
/// Teachers keep the simple class list (their own sections).
String _msg(Object e) => e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');
String _dmy(String? iso) => iso == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());
const _recordRoles = ['office', 'it_admin', 'principal', 'vice_principal', 'accounts'];

final _findProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, (String, bool)>((ref, k) async {
  final (q, past) = k;
  final r = await db.rpc('find_students', params: {'p_q': q.trim(), 'p_past': past, 'p_limit': 60});
  return [for (final x in r as List) Map<String, dynamic>.from(x)];
});
final _certsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
    Map<String, dynamic>.from((await db.rpc('certificates_pending')) as Map? ?? const {}));
final _linksProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async =>
    [for (final x in (await db.rpc('link_list')) as List) Map<String, dynamic>.from(x)]);

class StudentsPage extends ConsumerStatefulWidget {
  const StudentsPage({super.key});
  @override
  ConsumerState<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends ConsumerState<StudentsPage> {
  bool past = false; String q = ''; String? sectionId;

  Future<void> _admit() async {
    final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => StudentEditor(sectionId: sectionId));
    if (saved == true) { ref.invalidate(_findProvider); ref.invalidate(setupSectionsProvider); ref.invalidate(_linksProvider); if (sectionId != null) ref.invalidate(sectionStudentsProvider(sectionId!)); }
  }

  void _open(String id) => openStudentRecord(context, id).then((_) { ref.invalidate(_findProvider); ref.invalidate(_linksProvider); });

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    if (!_recordRoles.any(s.hasRole)) return const StaffStudentsScreen();   // teachers: their own class lists
    final cs = Theme.of(context).colorScheme;
    final sections = ref.watch(setupSectionsProvider).value ?? const <Map<String, dynamic>>[];
    final links = ref.watch(_linksProvider).value ?? const [];
    final toCheck = links.where((l) => l['status'] == 'suggested').length;
    final autoLinked = links.where((l) => l['status'] == 'auto').length;

    Widget row(Map<String, dynamic> r) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Avatar(_initials(r['full_name'] ?? ''), size: 42, bg: past ? Brand.surface2 : Brand.crimsonTint, fg: past ? Brand.muted : Brand.crimsonDeep),
      title: Text(r['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text([
        r['admission_no'] ?? '',
        if (!past && r['class'] != null) r['class'],
        if (past && r['left_on'] != null) 'Left ${_dmy(r['left_on'])}',
        if (past && r['leaving_reason'] != null) r['leaving_reason'],
        if (r['previous_admission_no'] != null) 'earlier ${r['previous_admission_no']}',
        if (r['later_admission_no'] != null) 'now ${r['later_admission_no']}',
      ].join(' · '), style: TextStyle(color: cs.onSurfaceVariant)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _open(r['id'] ?? r['student_id']),
    );

    Widget list;
    if (q.trim().length >= 2 || past) {
      list = ref.watch(_findProvider((q, past))).when(
        loading: () => const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text(_msg(e), style: const TextStyle(color: Brand.crimsonDeep)),
        data: (rows) => rows.isEmpty
            ? Padding(padding: const EdgeInsets.all(16), child: Text(q.trim().isEmpty ? 'No past students yet.' : 'No ${past ? 'past ' : ''}student found for “$q”.', style: TextStyle(color: cs.onSurfaceVariant)))
            : Column(children: [for (final r in rows) row(r)]));
    } else if (sectionId != null) {
      list = ref.watch(sectionStudentsProvider(sectionId!)).when(
        loading: () => const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text(_msg(e)),
        data: (rows) => rows.isEmpty
            ? Padding(padding: const EdgeInsets.all(16), child: Text('No students in this class yet.', style: TextStyle(color: cs.onSurfaceVariant)))
            : Column(children: [for (final e in rows) if (e['student'] != null) row({...Map<String, dynamic>.from(e['student']), 'class': e['roll_no'] == null ? null : 'Roll ${e['roll_no']}'})]));
    } else {
      list = Padding(padding: const EdgeInsets.all(16), child: Text('Type a name, admission number or a parent’s phone number — or pick a class.', style: TextStyle(color: cs.onSurfaceVariant)));
    }

    return StaffPage(
      title: 'Students',
      subtitle: 'Current and past students in one place. Open a student for their details, fees, marks, attendance, documents and bus.',
      actions: [FilledButton.icon(onPressed: _admit, icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text('New admission'))],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (past) Builder(builder: (_) {
          final c = ref.watch(_certsProvider).value;
          final pending = List<Map<String, dynamic>>.from(c?['pending'] ?? const []);
          if (pending.isEmpty) return const SizedBox.shrink();
          return Panel(padding: const EdgeInsets.all(14), child: CardRow(children: [
            const Icon(Icons.assignment_late_rounded, color: Brand.amber), const SizedBox(width: 12),
            Expanded(child: Text('${pending.length} student${pending.length == 1 ? '' : 's'} still waiting for a TC or conduct certificate.', style: const TextStyle(fontWeight: FontWeight.w700))),
            FilledButton(onPressed: () async { await showDialog(context: context, builder: (_) => const _CertsDialog()); ref.invalidate(_certsProvider); ref.invalidate(_findProvider); }, child: const Text('See the list')),
          ]));
        }),
        if (toCheck > 0 || autoLinked > 0) Panel(padding: const EdgeInsets.all(14), child: CardRow(children: [
          const Icon(Icons.link_rounded, color: Brand.amber), const SizedBox(width: 12),
          Expanded(child: Text(toCheck > 0
              ? '$toCheck re-admission${toCheck == 1 ? '' : 's'} to check — the app found an earlier admission that may be the same child.'
              : '$autoLinked re-admission${autoLinked == 1 ? ' was' : 's were'} linked to the earlier admission automatically.', style: const TextStyle(fontWeight: FontWeight.w700))),
          FilledButton(onPressed: () async { await showDialog(context: context, builder: (_) => const _LinkReview()); ref.invalidate(_linksProvider); ref.invalidate(_findProvider); }, child: Text(toCheck > 0 ? 'Check now' : 'See')),
        ])),
        Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('Current students'), icon: Icon(Icons.school_rounded)), ButtonSegment(value: true, label: Text('Past students'), icon: Icon(Icons.history_edu_rounded))],
            selected: {past}, onSelectionChanged: (v) => setState(() => past = v.first), showSelectedIcon: false),
          const SizedBox(height: 12),
          PickRow(children: [
            Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Name, admission number or parent’s phone'), onChanged: (v) => setState(() => q = v))),
            if (!past) ...[const SizedBox(width: 10), Expanded(child: PickField<String>(label: 'Class', value: sections.any((x) => x['id'] == sectionId) ? sectionId : null, onChanged: (v) => setState(() => sectionId = v),
                items: [for (final x in sections) DropdownMenuItem(value: x['id'] as String, child: Text('${sectionLabel(x)}  ·  ${(x['enrolment'] as List?)?.firstOrNull?['count'] ?? 0} students'))]))],
          ]),
          const SizedBox(height: 8),
          list,
        ])),
        NoteBox(past
            ? 'Past students: those who finished Grade X or XII, or left with a TC. Their records stay here for ever — open one to upload or print a TC, marksheet or certificate.'
            : 'A student who leaves: open them → Edit details → switch off “Studying here”. Grade X and XII move to Past students by themselves on the second move-up day.'),
      ]),
    );
  }
}

String _initials(String n) => n.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

/// Opens the full record of one student (current or past) as a full screen page.
Future<void> openStudentRecord(BuildContext context, String id) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (c) => staffTheme(c, StudentRecordScreen(studentId: id))));

// ================================================================== re-admission links
class _LinkReview extends ConsumerWidget {
  const _LinkReview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final links = ref.watch(_linksProvider);
    Widget person(String head, Map<String, dynamic> p) => Expanded(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(head, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .6, color: cs.onSurfaceVariant)),
        Text('${p['full_name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        Text('${p['admission_no']} · born ${_dmy(p['dob'])}', style: const TextStyle(fontSize: 12.5)),
        if (p['father_name'] != null) Text('Father: ${p['father_name']}', style: const TextStyle(fontSize: 12.5)),
        if (p['mother_name'] != null) Text('Mother: ${p['mother_name']}', style: const TextStyle(fontSize: 12.5)),
      ])));
    return AlertDialog(
      title: const Text('Re-admissions'),
      content: SizedBox(width: 620, child: links.when(
        loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text(_msg(e)),
        data: (rows) => rows.isEmpty ? const Text('Nothing to check.') : SingleChildScrollView(child: Column(children: [
          const NoteBox('When a Grade X student comes back for Grade XI with a new admission number, the app links both admissions so the child has one history. Please check the ones it was not sure about.'),
          const SizedBox(height: 10),
          for (final l in rows) Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: l['status'] == 'suggested' ? Brand.amber : Brand.green, width: 1.5), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l['status'] == 'suggested' ? 'Same child?' : 'Linked automatically ✓', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(l['status'] == 'suggested' ? Brand.amber : Brand.green))),
              Text('Matches: ${List<String>.from(l['reasons'] ?? const []).join(', ')}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [person('NEW ADMISSION', Map<String, dynamic>.from(l['new'])), const SizedBox(width: 8), person('EARLIER ADMISSION', Map<String, dynamic>.from(l['old']))]),
              const SizedBox(height: 8),
              Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
                if (l['status'] == 'suggested') ...[
                  OutlinedButton(onPressed: () async { await _decide(context, ref, l['id'], false); }, child: const Text('Not the same')),
                  FilledButton(onPressed: () async { await _decide(context, ref, l['id'], true); }, child: const Text('Same child — link')),
                ] else OutlinedButton(onPressed: () async { await _decide(context, ref, l['id'], false); }, child: const Text('Undo link')),
              ]),
            ])),
        ])))),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    );
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, String id, bool same) async {
    try { await db.rpc('link_decide', params: {'p_link': id, 'p_same': same}); ref.invalidate(_linksProvider); }
    catch (e) { if (context.mounted) toast(context, _msg(e)); }
  }
}

// ================================================================== the record
final _recordProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final st = Map<String, dynamic>.from(await db.from('student').select(
      'id,admission_no,full_name,dob,gender,blood_group,house,admission_type,address,father_name,mother_name,guardian_name,photo_path,active,left_on,leaving_reason,tc_issued_on,previous_student_id,'
      'family_phone(phone,label,is_primary),transport_enrolment(route:route_id(name,bus_reg_no),stop:stop_id(name))').eq('id', id).single());
  final cls = await db.from('current_class').select('grade_name,grade_code,section_name,section_tba,year_label,roll_no').eq('student_id', id).maybeSingle();
  final prev = st['previous_student_id'] == null ? null : await db.from('student').select('id,admission_no,full_name').eq('id', st['previous_student_id']).maybeSingle();
  final later = await db.from('student').select('id,admission_no,full_name').eq('previous_student_id', id).maybeSingle();
  return {...st, 'class': cls, 'previous': prev, 'later': later,
    // one history: this admission and the earlier / later one
    'ids': [id, if (prev != null) prev['id'], if (later != null) later['id']]};
});

class StudentRecordScreen extends ConsumerWidget {
  final String studentId;
  const StudentRecordScreen({super.key, required this.studentId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(_recordProvider(studentId));
    const tabs = ['Details', 'Fees', 'Marks', 'Attendance', 'Documents', 'Bus'];
    return DefaultTabController(length: tabs.length, child: Scaffold(
      appBar: AppBar(
        backgroundColor: Brand.crimsonDeep, foregroundColor: Colors.white,
        title: Text(rec.value?['full_name'] ?? 'Student', style: const TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, labelColor: Colors.white, unselectedLabelColor: Colors.white70, indicatorColor: Brand.gold2,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800), tabs: [for (final t in tabs) Tab(text: t)]),
      ),
      body: rec.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_msg(e)))),
        data: (r) {
          final ids = List<String>.from(r['ids']);
          Widget page(Widget child) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: child));
          return TabBarView(children: [
            page(_DetailsTab(r: r)),
            page(_FeesTab(ids: ids)),
            page(_MarksTab(ids: ids)),
            page(_AttendanceTab(ids: ids)),
            page(_DocumentsTab(student: r, ids: ids)),
            page(_BusTab(r: r)),
          ]);
        },
      ),
    ));
  }
}

Widget _pad(List<Widget> children) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: children);

class _DetailsTab extends ConsumerWidget {
  final Map<String, dynamic> r;
  const _DetailsTab({required this.r});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final cls = r['class'] as Map<String, dynamic>?;
    final phones = List<Map<String, dynamic>>.from(r['family_phone'] ?? const []);
    final active = r['active'] == true;
    Widget kv(String k, String? v) => v == null || v.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 140, child: Text(k, style: TextStyle(color: cs.onSurfaceVariant))), Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700)))]));
    final classText = cls == null ? null : '${cls['grade_name']} ${cls['section_tba'] == true ? '· section to be announced' : '– ${cls['section_name'] ?? ''}'} (${cls['year_label']})';
    return _pad([
      Panel(child: Row(children: [
        Avatar(_initials(r['full_name'] ?? ''), size: 60, bg: active ? Brand.crimsonTint : Brand.surface2, fg: active ? Brand.crimsonDeep : Brand.muted),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r['full_name'] ?? '', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          Text('${r['admission_no']}${classText != null && active ? ' · $classText' : ''}', style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          if (active) const Pill('Studying here', fg: Brand.green, bg: Brand.greenTint)
          else Pill('Past student${r['left_on'] != null ? ' · left ${_dmy(r['left_on'])}' : ''}', fg: Brand.muted, bg: Brand.surface2),
        ])),
      ])),
      if (r['previous'] != null || r['later'] != null) Panel(padding: const EdgeInsets.all(12), child: Column(children: [
        if (r['previous'] != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.history_rounded, color: Brand.amber),
            title: Text('Earlier admission: ${r['previous']['admission_no']}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: const Text('Same child — fees, marks and documents of both are shown here.'),
            trailing: const Icon(Icons.open_in_new_rounded), onTap: () => openStudentRecord(context, r['previous']['id'])),
        if (r['later'] != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.update_rounded, color: Brand.green),
            title: Text('Re-admitted as ${r['later']['admission_no']}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: const Text('The family now signs in with the new admission number.'),
            trailing: const Icon(Icons.open_in_new_rounded), onTap: () => openStudentRecord(context, r['later']['id'])),
      ])),
      Panel(title: 'Details', trailing: OutlinedButton.icon(onPressed: () async {
        final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => StudentEditor(studentId: r['id']));
        if (saved == true) ref.invalidate(_recordProvider(r['id']));
      }, icon: const Icon(Icons.edit_rounded, size: 18), label: const Text('Edit details')), child: Column(children: [
        kv('Date of birth', r['dob'] == null ? null : _dmy(r['dob'])),
        kv('Gender', r['gender']),
        kv('Class', classText),
        kv('Roll number', cls?['roll_no']?.toString()),
        kv('Father', r['father_name']), kv('Mother', r['mother_name']), kv('Guardian', r['guardian_name']),
        kv('Phones', phones.map((p) => '${p['phone']}${p['label'] != null ? ' (${p['label']})' : ''}').join(', ')),
        kv('Address', r['address']), kv('Blood group', r['blood_group']), kv('House', r['house']), kv('Admission type', r['admission_type']),
        kv('Left on', r['left_on'] == null ? null : _dmy(r['left_on'])), kv('Reason', r['leaving_reason']), kv('TC issued', r['tc_issued_on'] == null ? null : _dmy(r['tc_issued_on'])),
      ])),
      if (active) Panel(title: 'Leaving the school', child: CardRow(children: [
        Expanded(child: Text('For a student leaving during the year: upload the signed TC and conduct certificate, and the student moves to Past students. Nothing is deleted.', style: TextStyle(color: cs.onSurfaceVariant))),
        const SizedBox(width: 10),
        FilledButton.icon(onPressed: () async {
          final done = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => LeavingDialog(student: r));
          if (done == true) { ref.invalidate(_recordProvider(r['id'])); ref.invalidate(_docsProvider); ref.invalidate(_findProvider); ref.invalidate(_certsProvider); }
        }, icon: const Icon(Icons.logout_rounded, size: 18), label: const Text('Student is leaving')),
      ])),
      Panel(title: 'Sign-in', child: Wrap(spacing: 8, runSpacing: 8, children: [
        if (active) OutlinedButton.icon(onPressed: () => _reset(context, ref), icon: const Icon(Icons.key_rounded, size: 18), label: const Text('New password slip')),
        OutlinedButton.icon(onPressed: () async {
          try { await callFunction(ref, 'password', {'action': 'signout_all', 'student_id': r['id']}); if (context.mounted) toast(context, 'Signed out of every phone.'); } catch (e) { if (context.mounted) toast(context, _msg(e)); }
        }, icon: const Icon(Icons.phonelink_erase_rounded, size: 18), label: const Text('Sign out all phones')),
        if (r['previous'] == null) OutlinedButton.icon(onPressed: () => _linkByHand(context, ref), icon: const Icon(Icons.link_rounded, size: 18), label: const Text('Link an earlier admission')),
      ])),
    ]);
  }

  Future<void> _reset(BuildContext context, WidgetRef ref) async {
    try {
      final x = await callFunction(ref, 'password', {'action': 'reset', 'student_id': r['id'], 'via': 'print'});
      if (!context.mounted) return;
      showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Password slip'),
          content: SelectableText('Royale Connect — first-use password\n\nStudent: ${r['full_name']}\nAdmission no: ${r['admission_no']}\nPassword: ${x['first_use_password']}\n\nSign in at the app, then set your own password. This slip is the only copy.', style: const TextStyle(fontFamily: 'monospace', height: 1.6)),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))]));
    } catch (e) { if (context.mounted) toast(context, _msg(e)); }
  }

  Future<void> _linkByHand(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Link an earlier admission'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('For a child who studied here before with another admission number (for example Grade X before re-admission in Grade XI).'),
        const SizedBox(height: 12),
        TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Earlier admission number')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Link'))],
    ));
    if (ok != true || c.text.trim().isEmpty) return;
    try { await db.rpc('link_manual', params: {'p_student': r['id'], 'p_previous_admission': c.text.trim()}); ref.invalidate(_recordProvider(r['id'])); if (context.mounted) toast(context, 'Linked.'); }
    catch (e) { if (context.mounted) toast(context, _msg(e)); }
  }
}

// ---------------------------------------------------------------- fees
final _feesProvider = FutureProvider.autoDispose.family<(List<Map<String, dynamic>>, List<Map<String, dynamic>>), String>((ref, idsKey) async {
  final ids = idsKey.split(',');
  final l = await db.from('fee_ledger').select('id,title,amount,concession,due_on,status,paid_on,note,academic_year:academic_year_id(label,starts_on)').inFilter('student_id', ids).order('due_on', ascending: true);
  final p = await db.from('payment').select('id,amount,receipt_no,paid_at,mode').inFilter('student_id', ids).eq('status', 'success').order('paid_at', ascending: false);
  return (List<Map<String, dynamic>>.from(l), List<Map<String, dynamic>>.from(p));
});

class _FeesTab extends ConsumerWidget {
  final List<String> ids;
  const _FeesTab({required this.ids});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ref.watch(_feesProvider(ids.join(','))).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(_msg(e))),
      data: (d) {
        final (ledger, pays) = d;
        final byYear = <String, List<Map<String, dynamic>>>{};
        for (final x in ledger) { byYear.putIfAbsent(x['academic_year']?['label'] ?? '', () => []).add(x); }
        final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
        final pending = ledger.where((x) => x['status'] == 'pending').fold<num>(0, (a, x) => a + (x['amount'] as num) - ((x['concession'] ?? 0) as num));
        return _pad([
          Panel(child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Still to pay', style: TextStyle(color: cs.onSurfaceVariant)), Text(inr(pending), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: context.tone(pending > 0 ? Brand.crimsonDeep : Brand.green)))])),
            Text('${pays.length} receipts', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
          ])),
          for (final y in years) Panel(title: 'Fees $y', child: Column(children: [
            for (final x in byYear[y]!) ListTile(contentPadding: EdgeInsets.zero, dense: true,
              title: Text(x['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([if (x['due_on'] != null) 'due ${_dmy(x['due_on'])}', if (x['paid_on'] != null) 'paid ${_dmy(x['paid_on'])}', if (x['note'] != null) x['note']].join(' · ')),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(inr((x['amount'] as num) - ((x['concession'] ?? 0) as num)), style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${x['status']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.tone(x['status'] == 'pending' ? Brand.amber : Brand.green))),
              ])),
          ])),
          if (pays.isNotEmpty) Panel(title: 'Receipts', child: Column(children: [
            for (final p in pays) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.receipt_long_rounded, color: Brand.green),
              title: Text('${p['receipt_no'] ?? 'Receipt'} · ${inr(p['amount'] as num)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${_dmy(p['paid_at'])} · ${p['mode']}'), trailing: const Icon(Icons.picture_as_pdf_rounded),
              onTap: () => openReceiptPdf(context, p['id'], receiptNo: p['receipt_no'])),
          ])),
          if (ledger.isEmpty && pays.isEmpty) const NoteBox('No fees recorded for this student.'),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------- marks
final _marksProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, idsKey) async {
  final r = await db.from('mark').select('internal,external,absent,subject:subject_id(name),exam:exam_id(id,name,term,max_marks,starts_on,academic_year:academic_year_id(label))').inFilter('student_id', idsKey.split(','));
  return List<Map<String, dynamic>>.from(r);
});

class _MarksTab extends ConsumerWidget {
  final List<String> ids;
  const _MarksTab({required this.ids});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ref.watch(_marksProvider(ids.join(','))).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(_msg(e))),
      data: (rows) {
        if (rows.isEmpty) return _pad([const NoteBox('No marks entered yet.')]);
        final byExam = <String, List<Map<String, dynamic>>>{};
        final exams = <String, Map<String, dynamic>>{};
        for (final m in rows) { final e = m['exam'] as Map<String, dynamic>? ?? {}; byExam.putIfAbsent(e['id'] ?? '', () => []).add(m); exams[e['id'] ?? ''] = e; }
        final order = exams.keys.toList()..sort((a, b) => ((exams[b]?['starts_on'] ?? '') as String).compareTo((exams[a]?['starts_on'] ?? '') as String));
        return _pad([
          for (final id in order) Panel(title: '${exams[id]?['name'] ?? ''} · ${exams[id]?['academic_year']?['label'] ?? ''}', child: Column(children: [
            for (final m in byExam[id]!..sort((a, b) => '${a['subject']?['name']}'.compareTo('${b['subject']?['name']}'))) Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
              Expanded(child: Text('${m['subject']?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(m['absent'] == true ? 'Absent' : '${((m['internal'] ?? 0) as num) + ((m['external'] ?? 0) as num)} / ${exams[id]?['max_marks'] ?? 100}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: m['absent'] == true ? context.tone(Brand.crimsonDeep) : null)),
            ])),
          ])),
          Text('Marks are private to staff. Families see them on the published report card.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
        ]);
      },
    );
  }
}

// ---------------------------------------------------------------- attendance (from the report cards)
final _attendanceProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, idsKey) async {
  final r = await db.from('report_card').select('id,term,working_days,days_present,status,academic_year:academic_year_id(label)').inFilter('student_id', idsKey.split(',')).order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(r);
});

class _AttendanceTab extends ConsumerWidget {
  final List<String> ids;
  const _AttendanceTab({required this.ids});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(_attendanceProvider(ids.join(','))).when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (e, _) => Center(child: Text(_msg(e))),
    data: (rows) => _pad([
      if (rows.isEmpty) const NoteBox('No attendance recorded yet. Class teachers enter the days present on each report card.'),
      for (final r in rows) Panel(padding: const EdgeInsets.all(14), child: CardRow(children: [
        const Icon(Icons.event_available_rounded, color: Brand.blue), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r['term']} · ${r['academic_year']?['label'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(r['working_days'] == null ? 'Not filled in yet' : '${r['days_present'] ?? 0} of ${r['working_days']} days present'
              '${(r['working_days'] ?? 0) > 0 ? ' · ${(((r['days_present'] ?? 0) as num) * 100 / (r['working_days'] as num)).round()}%' : ''}'),
        ])),
        if (r['status'] == 'published' || r['status'] == 'locked') OutlinedButton(onPressed: () => openReportCardPdf(context, r['id'], name: '${r['term']}'), child: const Text('Report card')),
      ])),
      const NoteBox('Daily attendance (with an alert to parents when a child is absent) comes in the next update.', icon: Icons.upcoming_rounded),
    ]),
  );
}

// ---------------------------------------------------------------- documents: uploaded by the office, never made by the app
const docKinds = {'tc': 'Transfer Certificate (TC)', 'marksheet': 'Marksheet', 'conduct': 'Conduct certificate', 'bonafide': 'Bonafide / Study certificate', 'birth': 'Birth certificate', 'other': 'Other'};

final _docsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, idsKey) async {
  final r = await db.from('student_document').select('id,student_id,kind,title,file_path,file_name,uploaded_at,uploader:uploaded_by(display_name)')
      .inFilter('student_id', idsKey.split(',')).isFilter('deleted_at', null).order('uploaded_at', ascending: false);
  return List<Map<String, dynamic>>.from(r);
});

Future<void> _log(WidgetRef ref, String docId, String action) async {
  try { await db.from('document_log').insert({'document_id': docId, 'staff_id': myId(ref), 'action': action}); } catch (_) {}
}

class _DocumentsTab extends ConsumerStatefulWidget {
  final Map<String, dynamic> student; final List<String> ids;
  const _DocumentsTab({required this.student, required this.ids});
  @override
  ConsumerState<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends ConsumerState<_DocumentsTab> {
  bool busy = false;

  Future<void> _upload() async {
    String kind = 'tc';
    final title = TextEditingController(text: docKinds['tc']);
    final go = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
      title: const Text('Upload a document'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('What is it?', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final e in docKinds.entries) ChoiceChip(label: Text(e.value), selected: kind == e.key, onSelected: (_) => set(() { kind = e.key; title.text = e.value; }))]),
        const SizedBox(height: 12),
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Name shown in the list', hintText: 'e.g. TC 2026 or Class X marksheet')),
        const SizedBox(height: 8),
        const Text('Next you pick the file: a PDF or a photo (up to 10 MB).', style: TextStyle(fontSize: 12.5)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pick the file'))],
    )));
    if (go != true || !mounted) return;
    setState(() => busy = true);
    try {
      final path = await pickAndUpload(context, 'documents/${widget.student['id']}', ext: const ['pdf', 'jpg', 'jpeg', 'png', 'webp']);
      if (path != null) {
        final row = await db.from('student_document').insert({'student_id': widget.student['id'], 'kind': kind, 'title': title.text.trim().isEmpty ? docKinds[kind] : title.text.trim(),
          'file_path': path, 'file_name': path.split('/').last.replaceFirst(RegExp(r'^\d+_'), ''), 'uploaded_by': myId(ref)}).select('id').single();
        await _log(ref, row['id'], 'upload');
        ref.invalidate(_docsProvider(widget.ids.join(',')));
        if (mounted) toast(context, 'Uploaded.');
      }
    } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _open(Map<String, dynamic> d) async {
    await _log(ref, d['id'], 'open');
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _DocViewer(doc: d, studentName: widget.student['full_name'] ?? '', onAction: (a) => _log(ref, d['id'], a))));
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Remove this document?'), content: Text('“${d['title']}” will be removed from the list. The removal is recorded.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove'))]));
    if (ok != true) return;
    try {
      await db.from('student_document').update({'deleted_at': DateTime.now().toUtc().toIso8601String()}).eq('id', d['id']);
      await _log(ref, d['id'], 'delete');
      ref.invalidate(_docsProvider(widget.ids.join(',')));
    } catch (e) { if (mounted) toast(context, _msg(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ref.watch(_docsProvider(widget.ids.join(','))).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(_msg(e))),
      data: (docs) => _pad([
        Panel(title: 'Documents', trailing: FilledButton.icon(onPressed: busy ? null : _upload, icon: const Icon(Icons.upload_file_rounded, size: 18), label: Text(busy ? 'Uploading…' : 'Upload')),
          child: docs.isEmpty
              ? Text('No documents yet. Upload the signed TC, marksheet or certificate as a PDF or photo — it is then ready to print or share any time, even years later.', style: TextStyle(color: cs.onSurfaceVariant))
              : Column(children: [for (final d in docs) ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: CircleAvatar(backgroundColor: Brand.blueTint, child: Icon((d['file_path'] as String).toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_rounded : Icons.image_rounded, color: Brand.blue)),
                  title: Text(d['title'] ?? docKinds[d['kind']] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${docKinds[d['kind']] ?? ''} · ${_dmy(d['uploaded_at'])}${d['uploader'] != null ? ' · ${d['uploader']['display_name']}' : ''}${d['student_id'] != widget.student['id'] ? ' · earlier admission' : ''}'),
                  trailing: PopupMenuButton<String>(onSelected: (v) => v == 'del' ? _delete(d) : _open(d), itemBuilder: (_) => const [
                    PopupMenuItem(value: 'open', child: Text('Open · Print · Share')), PopupMenuItem(value: 'del', child: Text('Remove'))]),
                  onTap: () => _open(d),
                )])),
        const NoteBox('Only the office, accounts, IT, the Principal and the Vice Principal can see these documents. Every upload, open, print and share is recorded.', icon: Icons.lock_rounded),
      ]),
    );
  }
}

/// Shows the document with Print and Share buttons (a photo is placed on an A4 page).
class _DocViewer extends StatelessWidget {
  final Map<String, dynamic> doc; final String studentName; final void Function(String) onAction;
  const _DocViewer({required this.doc, required this.studentName, required this.onAction});

  Future<Uint8List> _bytes() async {
    final path = doc['file_path'] as String;
    final raw = await db.storage.from('files').download(path);
    if (path.toLowerCase().endsWith('.pdf')) return raw;
    final d = pw.Document();
    final img = pw.MemoryImage(raw);
    d.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(24), build: (_) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain))));
    return d.save();
  }

  @override
  Widget build(BuildContext context) {
    final name = '${studentName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}-${(doc['title'] ?? 'document').toString().replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}.pdf';
    return Scaffold(
      appBar: AppBar(title: Text('${doc['title']} · $studentName')),
      body: PdfPreview(
        build: (_) => _bytes(), pdfFileName: name,
        canChangePageFormat: false, canChangeOrientation: false, canDebug: false, allowPrinting: true, allowSharing: true,
        onPrinted: (_) => onAction('print'), onShared: (_) => onAction('share'),
        loadingWidget: const Center(child: CircularProgressIndicator()),
        onError: (context, e) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not open the file.\n$e', textAlign: TextAlign.center))),
      ),
    );
  }
}

// ---------------------------------------------------------------- bus
class _BusTab extends ConsumerWidget {
  final Map<String, dynamic> r;
  const _BusTab({required this.r});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = r['transport_enrolment'];
    final t = te is List ? (te.isEmpty ? null : te.first) : te;
    return _pad([
      Panel(title: 'School bus', trailing: OutlinedButton.icon(onPressed: () async {
        final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => StudentEditor(studentId: r['id']));
        if (saved == true) ref.invalidate(_recordProvider(r['id']));
      }, icon: const Icon(Icons.edit_rounded, size: 18), label: const Text('Change')), child: t == null
          ? const Text('Does not take the school bus.')
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${t['route']?['name'] ?? ''} · ${t['route']?['bus_reg_no'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 4),
              Text('Stop: ${t['stop']?['name'] ?? ''}'),
            ])),
    ]);
  }
}


// ================================================================== a student leaves during the year
class LeavingDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> student;
  const LeavingDialog({super.key, required this.student});
  @override
  ConsumerState<LeavingDialog> createState() => _LeavingDialogState();
}

class _LeavingDialogState extends ConsumerState<LeavingDialog> {
  DateTime day = DateTime.now();
  String reason = 'Transfer (TC)';
  final other = TextEditingController();
  final files = <String, String>{};        // kind → uploaded path
  bool busy = false;
  String get sid => widget.student['id'];

  Future<void> _pick(String kind) async {
    setState(() => busy = true);
    try {
      final p = await pickAndUpload(context, 'documents/$sid', ext: const ['pdf', 'jpg', 'jpeg', 'png', 'webp']);
      if (p != null) setState(() => files[kind] = p);
    } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _confirm() async {
    if (reason == 'Other' && other.text.trim().isEmpty) { toast(context, 'Please write the reason.'); return; }
    setState(() => busy = true);
    try {
      final me = myId(ref);
      const titles = {'tc': 'Transfer Certificate (TC)', 'conduct': 'Conduct certificate', 'other': 'Leaving document'};
      for (final e in files.entries) {
        final row = await db.from('student_document').insert({'student_id': sid, 'kind': e.key, 'title': titles[e.key], 'file_path': e.value,
          'file_name': e.value.split('/').last.replaceFirst(RegExp(r'^\d+_'), ''), 'uploaded_by': me}).select('id').single();
        await _log(ref, row['id'], 'upload');
      }
      await db.rpc('student_leave', params: {'p_student': sid, 'p_date': DateFormat('yyyy-MM-dd').format(day), 'p_reason': reason == 'Other' ? other.text.trim() : reason});
      try { await callFunction(ref, 'password', {'action': 'signout_all', 'student_id': sid}); } catch (_) {}
      if (!mounted) return;
      Navigator.pop(context, true);
      toast(context, '${widget.student['full_name']} moved to Past students.${files.containsKey('tc') ? '' : ' Upload the TC later from Documents.'}');
    } catch (e) { if (mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
  }

  @override
  Widget build(BuildContext context) {
    Widget slot(String kind, String label) => Padding(padding: const EdgeInsets.only(bottom: 8), child: OutlinedButton.icon(
      onPressed: busy ? null : () => _pick(kind),
      icon: Icon(files.containsKey(kind) ? Icons.check_circle_rounded : Icons.upload_file_rounded, size: 18, color: files.containsKey(kind) ? Brand.green : null),
      label: Align(alignment: Alignment.centerLeft, child: Text(files.containsKey(kind) ? '$label ✓ ${files[kind]!.split('/').last.replaceFirst(RegExp(r'^\d+_'), '')}' : label, overflow: TextOverflow.ellipsis)),
    ));
    return AlertDialog(
      title: Text('${widget.student['full_name']} is leaving'),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${widget.student['admission_no']} · records are kept for ever', style: const TextStyle(color: Brand.muted)),
        const SizedBox(height: 14),
        const Text('LAST DAY', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6)),
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () async {
          final d = await showDatePicker(context: context, initialDate: day, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 90)));
          if (d != null) setState(() => day = d);
        }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(DateFormat('EEE d MMMM yyyy').format(day)))),
        const SizedBox(height: 12),
        const Text('REASON', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final x in const ['Transfer (TC)', 'Moving city', 'Other']) ChoiceChip(label: Text(x), selected: reason == x, onSelected: (_) => setState(() => reason = x))]),
        if (reason == 'Other') Padding(padding: const EdgeInsets.only(top: 8), child: TextField(controller: other, decoration: const InputDecoration(labelText: 'Reason'))),
        const SizedBox(height: 12),
        const Text('CERTIFICATES (signed and scanned — PDF or photo)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6)),
        const SizedBox(height: 6),
        slot('tc', 'Transfer Certificate (TC)'),
        slot('conduct', 'Conduct certificate'),
        slot('other', 'Another document (optional)'),
        const NoteBox('After confirming: the student moves to Past students and the family is signed out. Fees, marks, report cards and documents stay. Certificates can also be uploaded later.'),
      ]))),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _confirm, child: Text(busy ? 'Please wait…' : 'Confirm — student has left')),
      ],
    );
  }
}

class _CertsDialog extends ConsumerWidget {
  const _CertsDialog();

  Future<void> _upload(BuildContext context, WidgetRef ref, Map<String, dynamic> st, String kind) async {
    try {
      final p = await pickAndUpload(context, 'documents/${st['id']}', ext: const ['pdf', 'jpg', 'jpeg', 'png', 'webp']);
      if (p == null) return;
      final row = await db.from('student_document').insert({'student_id': st['id'], 'kind': kind, 'title': docKinds[kind], 'file_path': p,
        'file_name': p.split('/').last.replaceFirst(RegExp(r'^\d+_'), ''), 'uploaded_by': myId(ref)}).select('id').single();
      await _log(ref, row['id'], 'upload');
      ref.invalidate(_certsProvider);
    } catch (e) { if (context.mounted) toast(context, _msg(e)); }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final c = ref.watch(_certsProvider);
    return AlertDialog(
      title: const Text('Certificates still to give'),
      content: SizedBox(width: 620, child: c.when(
        loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text(_msg(e)),
        data: (m) {
          final rows = List<Map<String, dynamic>>.from(m['pending'] ?? const []);
          if (rows.isEmpty) return Text('All done — every student who left has a TC and conduct certificate. (${m['done'] ?? 0} this year.)');
          return SingleChildScrollView(child: Column(children: [
            for (final st in rows) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: CardRow(children: [
              Avatar(_initials(st['full_name'] ?? ''), size: 38),
              const SizedBox(width: 10),
              Expanded(child: InkWell(onTap: () => openStudentRecord(context, st['id']), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${st['full_name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text([st['admission_no'], if (st['class'] != null) st['class'], 'left ${_dmy(st['left_on'])}', if (st['leaving_reason'] != null) st['leaving_reason']].join(' · '), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ]))),
              if (st['has_tc'] != true) FilledButton(onPressed: () => _upload(context, ref, st, 'tc'), child: const Text('Upload TC')),
              if (st['has_conduct'] != true) OutlinedButton(onPressed: () => _upload(context, ref, st, 'conduct'), child: const Text('Upload conduct')),
            ])),
            const SizedBox(height: 8),
            Text('${m['done'] ?? 0} done in the last two years.', style: TextStyle(color: cs.onSurfaceVariant)),
          ]));
        },
      )),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    );
  }
}
