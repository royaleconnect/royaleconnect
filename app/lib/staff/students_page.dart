import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/school_docs.dart' show openReceiptPdf, openReportCardPdf, PdfDocScreen;
import '../core/theme.dart';
import '../widgets/common.dart';
import 'school_setup.dart' show StudentEditor, setupSectionsProvider, GenderPick;
import 'staff_data.dart';
import 'staff_screens_2.dart' show StaffStudentsScreen, pickAndUpload;
import 'staff_shell.dart';
import '../core/cache.dart';
import 'certificates_page.dart' show pickCertificate, openCertificate, openCertificateReprint, certificateIssuedTick, tcDraftFor, tcFilledCount, buildCertificatePdf;
import 'class_logins.dart' show resetFirstPassword, printClassSlips;
import 'id_cards_page.dart' show openStudentIdCard;

/// Students — one page for the office (the approved Nov 2026 mock):
///   • Current students: the whole school, class by class (50 at a time), one search box (name, admission number or a parent's phone),
///     and a class picker. Past students: one line each (last class, left on, reason, TC number, fees pending).
///   • A student's page: everything on one full page — Student · Admission · Parents — with Edit details, ID card,
///     Suspend (for a while, like MCB) and Inactive (leaving: the TC is prepared, the Principal approves, then Past students).
///   • A past student's page is different: certificates and documents first, the rest folded away.
/// Teachers keep the simple class list (their own sections).
String _msg(Object e) => friendlyError(e);
String _dmy(String? iso) => iso == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());
String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
const _recordRoles = ['office', 'it_admin', 'principal', 'vice_principal', 'accounts'];
/// Who may admit and change students (the database refuses everyone else — Accounts only look).
const _editRoles = ['office', 'it_admin', 'principal', 'vice_principal'];
bool _canEdit(WidgetRef ref) => _editRoles.any(ref.watch(sessionProvider).value?.hasRole ?? (_) => false);
const _pink = Color(0xFFD6407F);

typedef _ListKey = ({String q, bool past, String filter, int limit});

final _listProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, _ListKey>((ref, k) async {
  ref.cacheFor();
  final f = k.filter;
  final r = await db.rpc('office_students', params: {
    'p_q': k.q.trim(), 'p_past': k.past, 'p_offset': 0, 'p_limit': k.limit,
    'p_grade': f.startsWith('g:') ? f.substring(2) : null, 'p_section': f.startsWith('s:') ? f.substring(2) : null,
  });
  return Map<String, dynamic>.from(r as Map);
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
  bool past = false; String q = ''; String filter = ''; int limit = 50;

  void _refresh() { ref.invalidate(_listProvider); ref.invalidate(_linksProvider); ref.invalidate(_certsProvider); }

  Future<void> _admit() async {
    final f = filter.startsWith('s:') ? filter.substring(2) : null;
    final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => StudentEditor(sectionId: f));
    if (saved == true) { _refresh(); ref.invalidate(setupSectionsProvider); }
  }

  void _open(String id) => openStudentRecord(context, id).then((_) => _refresh());

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    if (!_recordRoles.any(s.hasRole)) return const StaffStudentsScreen();   // teachers: their own class lists
    final cs = Theme.of(context).colorScheme;
    final narrow = isNarrow(context);
    final sections = ref.watch(setupSectionsProvider).value ?? const <Map<String, dynamic>>[];
    final links = ref.watch(_linksProvider).value ?? const [];
    final toCheck = links.where((l) => l['status'] == 'suggested').length;
    final autoLinked = links.where((l) => l['status'] == 'auto').length;
    final key = (q: q.trim().length >= 2 ? q.trim() : '', past: past, filter: past ? '' : filter, limit: limit);
    final data = ref.watch(_listProvider(key));
    final rows = [for (final x in (data.value?['rows'] as List?) ?? const []) Map<String, dynamic>.from(x as Map)];
    final total = (data.value?['total'] ?? 0) as int;

    // class picker: All · each grade (all sections) · each section
    final grades = <String, Map<String, dynamic>>{};
    for (final x in sections) { final g = x['grade'] as Map?; if (g != null) grades.putIfAbsent('${g['id']}', () => Map<String, dynamic>.from(g)); }
    final picker = PickField<String>(label: 'Class', value: filter, onChanged: (v) => setState(() { filter = v ?? ''; limit = 50; }), items: [
      const DropdownMenuItem(value: '', child: Text('All classes')),
      for (final g in grades.values) ...[
        DropdownMenuItem(value: 'g:${g['id']}', child: Text('${g['name']} – all sections', style: const TextStyle(fontWeight: FontWeight.w700))),
        for (final x in sections.where((x) => x['grade']?['id'] == g['id'])) DropdownMenuItem(value: 's:${x['id']}', child: Text('      ${g['name']} – ${x['name']}')),
      ],
    ]);

    Widget genderText(String? g) {
      final v = (g ?? '').toLowerCase();
      if (v == 'male' || v == 'boy') return Text('Boy', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(Brand.blue)));
      if (v == 'female' || v == 'girl') return Text('Girl', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(_pink)));
      return Text('—', style: TextStyle(color: cs.onSurfaceVariant));
    }
    Widget tags(Map<String, dynamic> r) => Wrap(spacing: 6, runSpacing: 4, children: [
      if (r['is_new'] == true) const Pill('NEW', fg: Brand.amber, bg: Brand.amberTint),
      if (r['suspended_till'] != null) Pill('SUSPENDED till ${DateFormat('d MMM').format(DateTime.parse(r['suspended_till']))}', fg: Brand.crimsonDeep, bg: Brand.crimsonTint),
      if (r['leaving'] == true) const Pill('LEAVING · with the Principal', fg: Brand.violet, bg: Brand.violetTint),
    ]);
    TextStyle head = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.onSurfaceVariant);

    Widget table() {
      if (rows.isEmpty) {
        return Padding(padding: const EdgeInsets.all(20), child: Text(q.trim().length >= 2 ? 'No ${past ? 'past ' : ''}student found for “${q.trim()}”.'
            : past ? 'No past students yet.' : 'No students in this class yet.', style: TextStyle(color: cs.onSurfaceVariant)));
      }
      if (narrow) {
        return Column(children: [for (final r in rows) ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 6),
          leading: Avatar(_initials(r['full_name'] ?? ''), size: 40, bg: past ? Brand.surface2 : Brand.crimsonTint, fg: past ? Brand.muted : Brand.crimsonDeep),
          title: Text(r['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(past
                ? [r['admission_no'], r['last_class'], if (r['left_on'] != null) 'left ${_dmy(r['left_on'])}', r['reason']].whereType<String>().join(' · ')
                : [r['admission_no'], r['class'], r['phone']].whereType<String>().join(' · '), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            if (!past) tags(r),
            if (past && ((r['fees_due'] ?? 0) as num) > 0) Text('Fees pending ${inr(r['fees_due'] as num)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: context.tone(Brand.crimsonDeep))),
          ]),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _open(r['id'])),
        ]);
      }
      Widget cell(Widget w, int flex) => Expanded(flex: flex, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: w));
      Widget t(String? x, {bool bold = false, Color? c}) => Text(x ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: c, fontSize: 13.5));
      final header = past
          ? [('STUDENT', 5), ('ADMISSION NO.', 3), ('LAST CLASS', 3), ('LEFT ON', 3), ('REASON', 3), ('TC NO.', 4), ('FATHER · PHONE', 4), ('FEES PENDING', 3)]
          : [('#', 1), ('STUDENT', 6), ('ADMISSION NO.', 3), ('CLASS', 3), ('GENDER', 2), ('FATHER', 4), ('PHONE', 3)];
      return Column(children: [
        Container(padding: const EdgeInsets.symmetric(vertical: 10), color: Brand.gold.withValues(alpha: .07),
            child: Row(children: [for (final (h, f) in header) cell(Text(h, style: head), f), const SizedBox(width: 60)])),
        for (final (i, r) in rows.indexed) InkWell(onTap: () => _open(r['id']), child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .6)))),
          child: Row(children: past ? [
            cell(t(r['full_name'], bold: true), 5), cell(t(r['admission_no']), 3), cell(t(r['last_class']), 3),
            cell(t(r['left_on'] == null ? null : _dmy(r['left_on'])), 3), cell(t(r['reason']), 3),
            cell(r['tc_no'] != null ? t(r['tc_no']) : r['tc_doc'] == true ? t('Uploaded') : (r['reason'] ?? '').toString().toLowerCase().startsWith('not joined')
                ? const Align(alignment: Alignment.centerLeft, child: Pill('Not needed', fg: Brand.muted, bg: Brand.surface2)) : t('Not given', c: context.tone(Brand.amber)), 4),
            cell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [t(r['father']), Text(r['phone'] ?? '', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))]), 4),
            cell(((r['fees_due'] ?? 0) as num) > 0 ? t(inr(r['fees_due'] as num), bold: true, c: context.tone(Brand.crimsonDeep)) : t('—'), 3),
            SizedBox(width: 60, child: Text('Open ›', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(Brand.crimson)))),
          ] : [
            cell(Text('${i + 1}', style: TextStyle(color: cs.onSurfaceVariant)), 1),
            cell(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [t(r['full_name'], bold: true), tags(r)]), 6),
            cell(t(r['admission_no']), 3), cell(t(r['class']), 3), cell(genderText(r['gender']), 2), cell(t(r['father']), 4), cell(t(r['phone']), 3),
            SizedBox(width: 60, child: Text('Open ›', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(Brand.crimson)))),
          ]),
        )),
      ]);
    }

    return StaffPage(
      title: 'Students',
      subtitle: 'The whole school, class by class. Search finds anyone by name, admission number or a parent’s phone.',
      actions: [
        if (_editRoles.any(s.hasRole)) OutlinedButton.icon(onPressed: () => context.go('/staff/setup'), icon: const Icon(Icons.upload_file_rounded, size: 18), label: const Text('Add from Excel')),
        if (_editRoles.any(s.hasRole)) FilledButton.icon(onPressed: _admit, icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text('New admission')),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (past) Builder(builder: (_) {
          final c = ref.watch(_certsProvider).value;
          final pending = List<Map<String, dynamic>>.from(c?['pending'] ?? const []);
          if (pending.isEmpty) return const SizedBox.shrink();
          return Panel(padding: const EdgeInsets.all(14), child: CardRow(children: [
            const Icon(Icons.assignment_late_rounded, color: Brand.amber), const SizedBox(width: 12),
            Expanded(child: Text('${pending.length} student${pending.length == 1 ? '' : 's'} still waiting for a TC or conduct certificate.', style: const TextStyle(fontWeight: FontWeight.w700))),
            FilledButton(onPressed: () async { await showDialog(context: context, builder: (_) => const _CertsDialog()); _refresh(); }, child: const Text('See the list')),
          ]));
        }),
        if (toCheck > 0 || autoLinked > 0) Panel(padding: const EdgeInsets.all(14), child: CardRow(children: [
          const Icon(Icons.link_rounded, color: Brand.amber), const SizedBox(width: 12),
          Expanded(child: Text(toCheck > 0
              ? '$toCheck re-admission${toCheck == 1 ? '' : 's'} to check — the app found an earlier admission that may be the same child.'
              : '$autoLinked re-admission${autoLinked == 1 ? ' was' : 's were'} linked to the earlier admission automatically.', style: const TextStyle(fontWeight: FontWeight.w700))),
          FilledButton(onPressed: () async { await showDialog(context: context, builder: (_) => const _LinkReview()); _refresh(); }, child: Text(toCheck > 0 ? 'Check now' : 'See')),
        ])),
        Panel(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PickRow(children: [
            Expanded(flex: 3, child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search by name, admission number or parent’s phone'),
                onChanged: (v) => setState(() { q = v; limit = 50; }))),
            const SizedBox(width: 10),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: false, label: Text('Current')), ButtonSegment(value: true, label: Text('Past students'))],
              selected: {past}, onSelectionChanged: (v) => setState(() { past = v.first; limit = 50; }), showSelectedIcon: false),
            if (!past) ...[const SizedBox(width: 10), Expanded(flex: 2, child: picker)],
          ]),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 8), child: Row(children: [
          Expanded(child: Text(data.isLoading && data.value == null ? 'Loading…'
              : '${NumberFormat.decimalPattern('en_IN').format(total)} ${past ? 'past ' : ''}student${total == 1 ? '' : 's'}${q.trim().length >= 2 ? ' found in the whole school' : ''}${rows.length < total ? ' · showing ${rows.length}' : ''}',
              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700))),
          if (!past && filter.startsWith('s:') && sections.any((x) => 's:${x['id']}' == filter)) TextButton.icon(
            onPressed: () => printClassSlips(context, ref, filter.substring(2), sectionLabel(sections.firstWhere((x) => 's:${x['id']}' == filter))),
            icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Password slips')),
        ])),
        Panel(padding: EdgeInsets.zero, child: data.when(
          loading: () => const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: Text(_msg(e), style: const TextStyle(color: Brand.crimsonDeep))),
          data: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            table(),
            if (rows.length < total) Padding(padding: const EdgeInsets.all(12), child: Center(child: OutlinedButton(
                onPressed: () => setState(() => limit += 50), child: Text('Show ${(total - rows.length).clamp(0, 50)} more')))),
          ]),
        )),
        NoteBox(past
            ? 'Past students stay here for ever. Open one for their TC, marksheet, report cards and receipts.'
            : 'Open a student for the full page. Suspend is for a few days; Inactive is for a student who is leaving — the Principal approves it.'),
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
  ref.watch(certificateIssuedTick);
  ref.cacheFor();
  final st = Map<String, dynamic>.from(await db.from('student').select(
      'id,admission_no,full_name,dob,gender,blood_group,house,admission_type,address,father_name,mother_name,guardian_name,photo_path,active,left_on,leaving_reason,tc_issued_on,previous_student_id,mother_tongue,place_of_birth,created_at,'
      'family_phone(phone,label,is_primary),transport_enrolment(route:route_id(name,bus_reg_no),stop:stop_id(name))').eq('id', id).single());
  final cls = await db.from('current_class').select('grade_name,grade_code,section_id,section_name,section_tba,year_label,roll_no').eq('student_id', id).maybeSingle();
  final prev = st['previous_student_id'] == null ? null : await db.from('student').select('id,admission_no,full_name').eq('id', st['previous_student_id']).maybeSingle();
  final later = await db.from('student').select('id,admission_no,full_name').eq('previous_student_id', id).maybeSingle();
  Map<String, dynamic> prof = const {};
  try { prof = Map<String, dynamic>.from(await db.rpc('student_profile', params: {'p_student': id}) as Map); } catch (_) {}
  Map<String, dynamic>? lastClass;
  if (cls == null) {
    try {
      final e = await db.from('enrolment').select('section:section_id(name,grade:grade_id(name,code)),academic_year:academic_year_id(label,starts_on)').eq('student_id', id);
      final l = List<Map<String, dynamic>>.from(e)..sort((a, b) => '${b['academic_year']?['starts_on']}'.compareTo('${a['academic_year']?['starts_on']}'));
      if (l.isNotEmpty) lastClass = {'name': '${l.first['section']?['grade']?['name'] ?? ''} – ${l.first['section']?['name'] ?? ''}', 'year': l.first['academic_year']?['label'], 'first_year': l.last['academic_year']?['label']};
    } catch (_) {}
  }
  return {...st, 'class': cls, 'previous': prev, 'later': later, 'profile': prof, 'last_class': lastClass,
    // one history: this admission and the earlier / later one
    'ids': [id, if (prev != null) prev['id'], if (later != null) later['id']]};
});

class StudentRecordScreen extends ConsumerWidget {
  final String studentId;
  const StudentRecordScreen({super.key, required this.studentId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rec = ref.watch(_recordProvider(studentId));
    final r = rec.value;
    if (r != null && r['active'] != true) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Brand.crimsonDeep, foregroundColor: Colors.white, title: Text(r['full_name'] ?? 'Student', style: const TextStyle(fontWeight: FontWeight.w800))),
        body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000), child: _PastRecord(r: r))),
      );
    }
    return _HistoryTabs(studentId: studentId, title: r?['full_name'] ?? 'Student', rec: rec);
  }
}

/// The tabbed record (current students, and "Full history" for a past student).
class _HistoryTabs extends StatelessWidget {
  final String studentId, title; final AsyncValue<Map<String, dynamic>> rec; final bool historyOnly; final int initialTab;
  const _HistoryTabs({required this.studentId, required this.title, required this.rec, this.historyOnly = false, this.initialTab = 0});
  @override
  Widget build(BuildContext context) {
    final tabs = [if (!historyOnly) 'Details', 'Fees', 'Marks', 'Attendance', 'Documents', 'Transport'];
    return DefaultTabController(length: tabs.length, initialIndex: initialTab.clamp(0, tabs.length - 1), child: Scaffold(
      appBar: AppBar(
        backgroundColor: Brand.crimsonDeep, foregroundColor: Colors.white,
        title: Text(historyOnly ? '$title · full history' : title, style: const TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, labelColor: Colors.white, unselectedLabelColor: Colors.white70, indicatorColor: Brand.gold2,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800), tabs: [for (final t in tabs) Tab(text: t)]),
      ),
      body: rec.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_msg(e)))),
        data: (r) {
          final ids = List<String>.from(r['ids']);
          Widget page(Widget child, [double w = 900]) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: w), child: child));
          return TabBarView(children: [
            if (!historyOnly) page(_DetailsTab(r: r), 1180),
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

// ------------------------------------------------------------------ the parts of the details page
/// One label / value line. [lock] = "office only", [auto] = filled by the app.
Widget _kv(BuildContext context, String k, String? v, {bool lock = false, bool auto = false, Widget? child}) {
  final cs = Theme.of(context).colorScheme;
  final empty = (v == null || v.trim().isEmpty) && child == null;
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: .5)))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(flex: 4, child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(k, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5)),
        if (lock) const _Tag('office only', Brand.muted),
        if (auto) const _Tag('auto', Brand.green),
      ])),
      const SizedBox(width: 8),
      Expanded(flex: 6, child: Align(alignment: Alignment.centerRight, child: child ?? Text(empty ? '—' : v!, textAlign: TextAlign.right,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: empty ? cs.onSurfaceVariant.withValues(alpha: .5) : null)))),
    ]),
  );
}

class _Tag extends StatelessWidget {
  final String text; final Color c;
  const _Tag(this.text, this.c);
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: context.tone(c))));
}

/// A titled block of lines, laid out in 1–3 columns depending on the width.
class _Section extends StatelessWidget {
  final String title; final List<Widget> lines;
  const _Section(this.title, this.lines);
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
    final cols = c.maxWidth > 980 ? 3 : c.maxWidth > 640 ? 2 : 1;
    final per = (lines.length / cols).ceil();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(top: 18, bottom: 4), child: Text(title.toUpperCase(),
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 1.6, color: context.tone(Brand.gold)))),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < cols; i++) ...[
          if (i > 0) const SizedBox(width: 26),
          Expanded(child: Column(children: lines.skip(i * per).take(per).toList())),
        ],
      ]),
    ]);
  });
}

String? _gradeRoman(Map<String, dynamic>? cls) => cls?['grade_code'] as String?;
const _romanN = {'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10, 'XI': 11, 'XII': 12};
/// 2nd language: Grade I – X. 3rd language: Grade VI – IX this year (VI – X from 2027-28, as the batch moves up).
(bool, bool) _languagesFor(Map<String, dynamic>? cls) {
  final n = _romanN[_gradeRoman(cls) ?? ''] ?? 0;
  final yearStart = int.tryParse(RegExp(r'^\d{4}').stringMatch('${cls?['year_label'] ?? ''}') ?? '') ?? DateTime.now().year;
  final top3 = (9 + (yearStart - 2026)).clamp(9, 10);
  return (n >= 1 && n <= 10, n >= 6 && n <= top3);
}

class _DetailsTab extends ConsumerWidget {
  final Map<String, dynamic> r;
  const _DetailsTab({required this.r});

  void _reload(WidgetRef ref) { ref.invalidate(_recordProvider(r['id'])); ref.invalidate(_listProvider); }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final cls = r['class'] as Map<String, dynamic>?;
    final prof = Map<String, dynamic>.from(r['profile'] ?? const {});
    final x = Map<String, dynamic>.from(prof['extra'] ?? const {});
    final phones = List<Map<String, dynamic>>.from(r['family_phone'] ?? const []);
    String? phoneOf(String label) => phones.where((p) => '${p['label']}'.toLowerCase().startsWith(label)).map((p) => '${p['phone']}').firstOrNull;
    final otherPhones = phones.where((p) => !'${p['label']}'.toLowerCase().startsWith('father') && !'${p['label']}'.toLowerCase().startsWith('mother')).toList();
    final canEdit = _canEdit(ref) && prof['can_edit'] != false;
    final susp = prof['suspension'] as Map?;
    final leaving = prof['leaving'] as Map?;
    final classText = cls == null ? null : '${cls['grade_name']}${cls['section_tba'] == true ? ' · section to be announced' : ' – ${cls['section_name'] ?? ''}'} (${cls['year_label']})';
    final te = r['transport_enrolment']; final t = te is List ? (te.isEmpty ? null : te.first) : te;
    final sib = [for (final s in (prof['siblings'] as List?) ?? const []) Map<String, dynamic>.from(s as Map)];
    final match = prof['staff_match'] as Map?;
    final login = prof['last_login'] as Map?;
    final (show2, show3) = _languagesFor(cls);
    final narrow = isNarrow(context);

    Future<void> edit() async {
      final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => StudentEditor(studentId: r['id']));
      if (saved == true) _reload(ref);
    }

    Widget staffChild() {
      final yes = x['staff_child'] == true, no = x['staff_child'] == false;
      if (yes) return Text('Yes${match != null ? ' · ${match['name']}' : ''} ✓', style: const TextStyle(fontWeight: FontWeight.w800));
      if (match != null && !no) {
        return Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${match['name']}?', style: const TextStyle(fontWeight: FontWeight.w800)),
          if (canEdit) FilledButton.tonal(style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () async {
            try { await db.rpc('student_extra_save', params: {'p_student': r['id'], 'p': {'staff_child': true, 'staff_child_staff_id': match['staff_id']}}); _reload(ref); if (context.mounted) toast(context, 'Marked as staff child ✓'); }
            catch (e) { if (context.mounted) toast(context, _msg(e)); }
          }, child: const Text('Confirm')),
          if (canEdit) TextButton(style: TextButton.styleFrom(visualDensity: VisualDensity.compact), onPressed: () async {
            try { await db.rpc('student_extra_save', params: {'p_student': r['id'], 'p': {'staff_child': false}}); _reload(ref); } catch (e) { if (context.mounted) toast(context, _msg(e)); }
          }, child: const Text('No')),
        ]);
      }
      return Text(no ? 'No' : '—', style: TextStyle(fontWeight: FontWeight.w800, color: no ? null : cs.onSurfaceVariant.withValues(alpha: .5)));
    }

    Widget parentCard(String who, IconData icon, String? name, String? phone, String pre) => Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Icon(icon, size: 18, color: context.tone(Brand.gold)), const SizedBox(width: 8), Text(who, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))]),
        _kv(context, 'Name', name), _kv(context, 'Phone', phone), _kv(context, 'Email', x['${pre}_email']),
        _kv(context, 'Education', x['${pre}_education']), _kv(context, 'Occupation', x['${pre}_occupation']),
        if (prof['can_edit'] == true) _kv(context, 'Annual income', x['${pre}_income'], lock: true),
      ]),
    );

    final guardianSet = (r['guardian_name'] ?? '').toString().isNotEmpty || (x['guardian_phone'] ?? '').toString().isNotEmpty;

    return _pad([
      // ---------- header: who, status, the four buttons
      Panel(padding: const EdgeInsets.all(18), child: CardRow(children: [
        Container(width: 74, height: 74, alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: LinearGradient(colors: [Brand.crimsonTint, Brand.gold.withValues(alpha: .25)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              border: Border.all(color: Brand.gold.withValues(alpha: .5))),
          child: Text(_initials(r['full_name'] ?? ''), style: const TextStyle(fontFamily: 'serif', fontSize: 26, fontWeight: FontWeight.w800, color: Brand.crimsonDeep))),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r['full_name'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text([r['admission_no'], if (classText != null) classText, if (cls?['roll_no'] != null) 'Roll ${cls!['roll_no']}'].join(' · '), style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (susp != null) Pill('SUSPENDED till ${_dmy(susp['till'])} · ${susp['reason']}', fg: Brand.crimsonDeep, bg: Brand.crimsonTint)
            else const Pill('STUDYING HERE', fg: Brand.green, bg: Brand.greenTint),
            if (leaving != null) Pill('LEAVING · waiting for the Principal (${leaving['reason']})', fg: Brand.violet, bg: Brand.violetTint),
            if (x['staff_child'] == true) const Pill('STAFF CHILD', fg: Brand.amber, bg: Brand.amberTint),
          ]),
        ])),
        if (canEdit) OutlinedButton.icon(onPressed: edit, icon: const Icon(Icons.edit_rounded, size: 18), label: const Text('Edit details')),
        OutlinedButton.icon(onPressed: () => openStudentIdCard(context, r['id'], sectionId: cls?['section_id']), icon: const Icon(Icons.badge_rounded, size: 18), label: const Text('ID card')),
        if (canEdit && susp == null && leaving == null) FilledButton.tonalIcon(
          style: FilledButton.styleFrom(backgroundColor: Brand.amberTint, foregroundColor: Brand.amber),
          onPressed: () async { if (await showDialog<bool>(context: context, builder: (_) => _SuspendDialog(student: r)) == true) _reload(ref); },
          icon: const Icon(Icons.pause_circle_rounded, size: 18), label: const Text('Suspend')),
        if (canEdit && susp != null) OutlinedButton.icon(onPressed: () async {
          try { await db.rpc('student_suspend_end', params: {'p_student': r['id']}); _reload(ref); if (context.mounted) toast(context, '${r['full_name']} is back in class ✓'); }
          catch (e) { if (context.mounted) toast(context, _msg(e)); }
        }, icon: const Icon(Icons.play_circle_rounded, size: 18), label: const Text('End suspension')),
        if (canEdit && leaving == null) FilledButton.icon(
          onPressed: () async {
            final done = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _InactiveDialog(student: r, decide: prof['can_decide'] == true));
            if (done == true) { _reload(ref); ref.invalidate(_certsProvider); }
          },
          icon: const Icon(Icons.logout_rounded, size: 18), label: const Text('Inactive')),
      ])),
      if (r['previous'] != null || r['later'] != null) Panel(padding: const EdgeInsets.all(12), child: Column(children: [
        if (r['previous'] != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.history_rounded, color: Brand.amber),
            title: Text('Earlier admission: ${r['previous']['admission_no']}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: const Text('Same child — fees, marks and documents of both are shown here.'),
            trailing: const Icon(Icons.open_in_new_rounded), onTap: () => openStudentRecord(context, r['previous']['id'])),
        if (r['later'] != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.update_rounded, color: Brand.green),
            title: Text('Re-admitted as ${r['later']['admission_no']}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: const Text('The family now signs in with the new admission number.'),
            trailing: const Icon(Icons.open_in_new_rounded), onTap: () => openStudentRecord(context, r['later']['id'])),
      ])),

      // ---------- the full page
      Panel(padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Section('Student', [
          _kv(context, 'Full name', r['full_name']),
          _kv(context, 'Date of birth', r['dob'] == null ? null : _dmy(r['dob'])),
          _kv(context, 'Gender', null, child: GenderPick(value: r['gender'])),
          _kv(context, 'Blood group', r['blood_group']),
          _kv(context, 'Nationality', x['nationality'] ?? 'Indian'),
          _kv(context, 'Mother tongue', r['mother_tongue']),
          if (show2) _kv(context, '2nd language', x['second_language']),
          if (show3) _kv(context, '3rd language', x['third_language']),
          _kv(context, 'Place of birth', r['place_of_birth']),
          if (prof['can_edit'] == true) _kv(context, 'Religion', x['religion'], lock: true),
          if (prof['can_edit'] == true) _kv(context, 'Category', x['category'], lock: true),
          _kv(context, 'House', r['house']),
        ]),
        _Section('Admission', [
          _kv(context, 'Admission number', r['admission_no']),
          _kv(context, 'Application number', x['application_no']),
          _kv(context, 'Admission date', x['admission_date'] == null ? null : _dmy(x['admission_date'])),
          _kv(context, 'Admission type', r['admission_type']),
          _kv(context, 'Class', classText),
          _kv(context, 'Transport', t == null ? 'No school transport' : '${t['route']?['name'] ?? ''} · ${t['stop']?['name'] ?? ''}'),
          _kv(context, 'Siblings', sib.isEmpty ? 'None' : null, auto: true, child: sib.isEmpty ? null : Wrap(alignment: WrapAlignment.end, spacing: 6, children: [
            for (final s in sib) ActionChip(visualDensity: VisualDensity.compact, label: Text('${s['full_name']}${s['class'] != null ? ' · ${s['class']}' : s['active'] == true ? '' : ' · past'}'),
                onPressed: () => openStudentRecord(context, s['id'])),
          ])),
          _kv(context, 'Staff child', null, auto: true, child: staffChild()),
          _kv(context, 'Address', r['address']),
          _kv(context, 'Last sign-in', login?['at'] == null ? 'Never signed in yet' : '${DateFormat('d MMM yyyy, h:mm a').format(DateTime.parse(login!['at']).toLocal())}${login['platform'] != null ? ' · ${const {'android': 'Android', 'ios': 'iPhone', 'web': 'Web'}[login['platform']] ?? login['platform']}' : ''}', auto: true),
          _kv(context, 'Status', susp != null ? 'Suspended till ${_dmy(susp['till'])}' : 'Studying here', auto: true),
          if (otherPhones.isNotEmpty) _kv(context, 'Other phones', otherPhones.map((p) => '${p['phone']}${p['label'] != null ? ' (${p['label']})' : ''}').join(', ')),
        ]),
        Padding(padding: const EdgeInsets.only(top: 18, bottom: 8), child: Text('PARENTS', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 1.6, color: context.tone(Brand.gold)))),
        Builder(builder: (_) {
          final cards = [
            parentCard('Father', Icons.person_rounded, r['father_name'], phoneOf('father'), 'father'),
            parentCard('Mother', Icons.person_2_rounded, r['mother_name'], phoneOf('mother'), 'mother'),
            if (guardianSet) Container(padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [Icon(Icons.shield_rounded, size: 18, color: context.tone(Brand.gold)), const SizedBox(width: 8), const Text('Guardian', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))]),
                _kv(context, 'Name', r['guardian_name']), _kv(context, 'Relation', x['guardian_relation']), _kv(context, 'Phone', x['guardian_phone']), _kv(context, 'Email', x['guardian_email']),
              ]))
            else if (canEdit) InkWell(borderRadius: BorderRadius.circular(16), onTap: edit, child: Container(height: 120, alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.gold.withValues(alpha: .6), style: BorderStyle.solid)),
              child: Text('+ Add guardian (only if needed)', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(Brand.gold))))),
          ];
          if (narrow) return Column(children: [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: c)]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final (i, c) in cards.indexed) ...[if (i > 0) const SizedBox(width: 14), Expanded(child: c)]]);
        }),
        if (canEdit) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Tap Edit details to change anything. The green “auto” lines fill themselves. Name, date of birth and parents’ names go to the Principal first.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
      ])),

      // ---------- history, certificates, sign-in
      Panel(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: _HistoryTile(rows: [for (final h in (prof['history'] as List?) ?? const []) Map<String, dynamic>.from(h as Map)])),
      Panel(title: 'Certificates', child: CardRow(children: [
        Expanded(child: Text('Print a Transfer Certificate, Study, Bonafide or No dues certificate — filled in from this record.', style: TextStyle(color: cs.onSurfaceVariant))),
        const SizedBox(width: 10),
        FilledButton.icon(onPressed: () => pickCertificate(context, r['id'] as String), icon: const Icon(Icons.workspace_premium_rounded, size: 18), label: const Text('Issue certificate')),
      ])),
      Panel(title: 'Sign-in', child: Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: () => resetFirstPassword(context, ref, '${r['id']}', '${r['full_name'] ?? ''}'), icon: const Icon(Icons.key_rounded, size: 18), label: const Text('New password slip')),
        OutlinedButton.icon(onPressed: () async {
          try { await callFunction(ref, 'password', {'action': 'signout_all', 'student_id': r['id']}); if (context.mounted) toast(context, 'Signed out of every phone.'); } catch (e) { if (context.mounted) toast(context, _msg(e)); }
        }, icon: const Icon(Icons.phonelink_erase_rounded, size: 18), label: const Text('Sign out all phones')),
        if (r['previous'] == null && _canEdit(ref)) OutlinedButton.icon(onPressed: () => _linkByHand(context, ref), icon: const Icon(Icons.link_rounded, size: 18), label: const Text('Link an earlier admission')),
      ])),
    ]);
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

/// "Change history · who changed what" (folded; newest first).
class _HistoryTile extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _HistoryTile({required this.rows});
  static const _what = {'student.add': 'Admitted', 'student.edit': 'Details changed', 'student.corrected': 'Corrected (Principal approved)', 'student.correction_asked': 'Correction sent to the Principal',
    'student.left': 'Left the school', 'student.inactive': 'Made inactive', 'student.leaving_asked': 'Leaving sent to the Principal', 'student.leaving_declined': 'Leaving not approved',
    'student.suspended': 'Suspended', 'student.suspension_ended': 'Suspension ended', 'tc.approved': 'TC approved', 'tc.asked': 'TC sent to the Principal', 'student.brought_back': 'Brought back'};
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String v(dynamic x) => x == null || '$x'.isEmpty ? '—' : RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('$x') ? DateFormat('d MMM yyyy').format(DateTime.parse('$x')) : '$x';
    return Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent), child: ExpansionTile(
      leading: Icon(Icons.history_rounded, color: context.tone(Brand.gold)),
      title: const Text('Change history · who changed what', style: TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(rows.isEmpty ? 'Nothing changed yet' : 'Last: ${_what[rows.first['action']] ?? rows.first['action']} · ${DateFormat('d MMM yyyy').format(DateTime.parse(rows.first['at']).toLocal())}',
          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        for (final h in rows) Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6, right: 12), decoration: const BoxDecoration(color: Brand.gold, shape: BoxShape.circle)),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_what[h['action']] ?? '${h['action']}', style: const TextStyle(fontWeight: FontWeight.w800)),
            for (final c in (h['changes'] as List?) ?? const []) Text('${c['field']}: ${v(c['from'])} → ${v(c['to'])}', style: const TextStyle(fontSize: 13)),
            if (h['detail'] is Map && (h['detail']['reason'] != null)) Text('Reason: ${h['detail']['reason']}', style: const TextStyle(fontSize: 13)),
            Text('${h['by']} · ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.parse(h['at']).toLocal())}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ])),
        ])),
      ],
    ));
  }
}

// ================================================================== a past student: documents first, the rest folded
class _PastRecord extends ConsumerWidget {
  final Map<String, dynamic> r;
  const _PastRecord({required this.r});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final prof = Map<String, dynamic>.from(r['profile'] ?? const {});
    final x = Map<String, dynamic>.from(prof['extra'] ?? const {});
    final ids = List<String>.from(r['ids']);
    final tc = prof['tc'] as Map?;
    final last = r['last_class'] as Map?;
    final phones = List<Map<String, dynamic>>.from(r['family_phone'] ?? const []);
    final canBack = _canEdit(ref) && r['left_on'] != null && DateTime.now().difference(DateTime.parse(r['left_on'])).inDays <= 30;
    final notJoined = '${r['leaving_reason'] ?? ''}'.toLowerCase().startsWith('not joined');
    final docs = ref.watch(_docsProvider(ids.join(','))).value ?? const <Map<String, dynamic>>[];
    final cards = ref.watch(_attendanceProvider(ids.join(','))).value ?? const <Map<String, dynamic>>[];
    final fees = ref.watch(_feesProvider(ids.join(','))).value;
    final pending = fees == null ? 0 : fees.$1.where((l) => l['status'] == 'pending').fold<num>(0, (a, l) => a + (l['amount'] as num) - ((l['concession'] ?? 0) as num));
    Widget stat(String k, String v, [String? sub]) => Expanded(child: Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4), Text(v, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        if (sub != null) Text(sub, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ])));
    Widget doc(IconData icon, String title, String sub, VoidCallback? open) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: Brand.crimsonTint, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: Brand.crimsonDeep, size: 20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(sub, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      trailing: open == null ? null : Text('Open ›', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(Brand.crimson))),
      onTap: open);
    final father = r['father_name'] as String?;
    final fphone = phones.where((p) => '${p['label']}'.toLowerCase().startsWith('father')).map((p) => p['phone']).firstOrNull ?? phones.firstOrNull?['phone'];
    final joined = RegExp(r'(\d{4})$').stringMatch('${r['admission_no'] ?? ''}');
    final leftYear = r['left_on'] == null ? null : DateTime.parse(r['left_on']).year;

    return _pad([
      Panel(padding: const EdgeInsets.all(18), child: CardRow(children: [
        Container(width: 70, height: 70, alignment: Alignment.center, decoration: BoxDecoration(color: Brand.surface2, borderRadius: BorderRadius.circular(22)),
            child: Text(_initials(r['full_name'] ?? ''), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Brand.muted))),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r['full_name'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          Text([r['admission_no'], if (last != null) 'last class ${last['name']}', if (r['left_on'] != null) 'left ${_dmy(r['left_on'])}'].join(' · '), style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            const Pill('PAST STUDENT', fg: Brand.muted, bg: Brand.surface2),
            if (tc != null) Pill('TC ${tc['number']}', fg: Brand.green, bg: Brand.greenTint),
            if (pending > 0) Pill('FEES PENDING ${inr(pending)}', fg: Brand.crimsonDeep, bg: Brand.crimsonTint),
            if (r['later'] != null) Pill('RE-ADMITTED AS ${r['later']['admission_no']}', fg: Brand.blue, bg: Brand.blueTint),
          ]),
        ])),
        if (tc != null) OutlinedButton.icon(onPressed: () => openCertificateReprint(context, tc['id'], number: tc['number']), icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Print TC again'))
        else if (!notJoined) OutlinedButton.icon(onPressed: () => openCertificate(context, r['id'], 'tc'), icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Make the TC')),
        if (canBack) FilledButton.icon(onPressed: () async {
          try { await db.rpc('student_bring_back', params: {'p_student': r['id']}); try { await db.rpc('fees_bring_back', params: {'p_student': r['id']}); } catch (_) {}
            ref.invalidate(_recordProvider(r['id'])); ref.invalidate(_listProvider); if (context.mounted) toast(context, '${r['full_name']} is active again ✓'); }
          catch (e) { if (context.mounted) toast(context, _msg(e)); }
        }, icon: const Icon(Icons.undo_rounded, size: 18), label: const Text('Re-admit')),
      ])),
      if (r['later'] != null) Panel(padding: const EdgeInsets.all(12), child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.update_rounded, color: Brand.green),
          title: Text('Studying again as ${r['later']['admission_no']}', style: const TextStyle(fontWeight: FontWeight.w700)), trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () => openStudentRecord(context, r['later']['id']))),
      Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(children: [
        stat('Reason', '${r['leaving_reason'] ?? 'Left the school'}'), const SizedBox(width: 12),
        stat('Father', father ?? '—', fphone), const SizedBox(width: 12),
        stat('Years here', '${joined ?? last?['first_year'] ?? '—'} – ${leftYear ?? ''}', joined == null ? null : 'joined $joined'),
      ])),
      Panel(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent), child: ExpansionTile(
        initiallyExpanded: true,
        leading: Icon(Icons.folder_special_rounded, color: context.tone(Brand.gold)),
        title: const Text('Certificates & documents', style: TextStyle(fontWeight: FontWeight.w800)),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        children: [
          if (tc != null) doc(Icons.description_rounded, 'Transfer Certificate', '${tc['number']} · issued ${_dmy(tc['issued_at'])}', () => openCertificateReprint(context, tc['id'], number: tc['number']))
          else doc(Icons.description_rounded, 'Transfer Certificate', notJoined ? 'Not needed (never joined)' : 'Not made yet', notJoined ? null : () => openCertificate(context, r['id'], 'tc')),
          for (final d in docs) doc((d['file_path'] as String).toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_rounded : Icons.image_rounded, '${d['title'] ?? docKinds[d['kind']] ?? 'Document'}',
              '${docKinds[d['kind']] ?? ''} · uploaded ${_dmy(d['uploaded_at'])}',
              () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _DocViewer(doc: d, studentName: r['full_name'] ?? '', onAction: (a) => _log(ref, d['id'], a))))),
          for (final c in cards.where((c) => c['status'] == 'published' || c['status'] == 'locked'))
            doc(Icons.auto_stories_rounded, 'Report card · ${c['term']}', '${c['academic_year']?['label'] ?? ''}', () => openReportCardPdf(context, c['id'], name: '${c['term']}')),
          if (fees != null && fees.$2.isNotEmpty) doc(Icons.receipt_long_rounded, 'Fee receipts', '${fees.$2.length} receipts · ${pending > 0 ? '${inr(pending)} pending' : 'nothing pending'}', null),
          for (final p in fees?.$2 ?? const <Map<String, dynamic>>[]) Padding(padding: const EdgeInsets.only(left: 56), child: ListTile(dense: true,
              title: Text('${p['receipt_no'] ?? 'Receipt'} · ${inr(p['amount'] as num)}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(_dmy(p['paid_at'])),
              trailing: const Icon(Icons.picture_as_pdf_rounded, size: 18), onTap: () => openReceiptPdf(context, p['id'], receiptNo: p['receipt_no']))),
          if (_canEdit(ref)) Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (c) => staffTheme(c,
              _HistoryTabs(studentId: r['id'], title: r['full_name'] ?? '', rec: AsyncValue.data(r), historyOnly: true, initialTab: 3)))),
              icon: const Icon(Icons.upload_file_rounded, size: 18), label: const Text('Upload a document'))),
        ],
      ))),
      Panel(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent), child: ExpansionTile(
        leading: Icon(Icons.person_search_rounded, color: context.tone(Brand.gold)),
        title: const Text('All student & parent details', style: TextStyle(fontWeight: FontWeight.w800)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          _Section('Student', [
            _kv(context, 'Full name', r['full_name']), _kv(context, 'Date of birth', r['dob'] == null ? null : _dmy(r['dob'])),
            _kv(context, 'Gender', null, child: GenderPick(value: r['gender'])), _kv(context, 'Blood group', r['blood_group']),
            _kv(context, 'Mother tongue', r['mother_tongue']), _kv(context, 'Nationality', x['nationality'] ?? 'Indian'),
            if (prof['can_edit'] == true) _kv(context, 'Religion', x['religion'], lock: true),
            if (prof['can_edit'] == true) _kv(context, 'Category', x['category'], lock: true),
            _kv(context, 'Application number', x['application_no']), _kv(context, 'Admission date', x['admission_date'] == null ? null : _dmy(x['admission_date'])),
            _kv(context, 'Address', r['address']),
          ]),
          _Section('Parents', [
            _kv(context, 'Father', r['father_name']), _kv(context, 'Mother', r['mother_name']),
            for (final p in phones) _kv(context, '${p['label'] ?? 'Phone'}', '${p['phone']}'),
            _kv(context, 'Father’s email', x['father_email']), _kv(context, 'Mother’s email', x['mother_email']),
            if ((r['guardian_name'] ?? '').toString().isNotEmpty) _kv(context, 'Guardian', r['guardian_name']),
          ]),
        ],
      ))),
      Panel(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: ListTile(
        leading: Icon(Icons.insights_rounded, color: context.tone(Brand.gold)),
        title: const Text('Marks, attendance & fees history', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('Every year as it was, read-only', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (c) => staffTheme(c,
            _HistoryTabs(studentId: r['id'], title: r['full_name'] ?? '', rec: AsyncValue.data(r), historyOnly: true)))),
      )),
      Panel(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: _HistoryTile(rows: [for (final h in (prof['history'] as List?) ?? const []) Map<String, dynamic>.from(h as Map)])),
      NoteBox('Read-only record, kept for ever.${canBack ? ' Re-admit brings the student back into the same class (within 30 days of leaving).' : ''}', icon: Icons.lock_rounded),
    ]);
  }
}

// ================================================================== Suspend: for a while, comes back by itself
class _SuspendDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> student;
  const _SuspendDialog({required this.student});
  @override
  ConsumerState<_SuspendDialog> createState() => _SuspendDialogState();
}

class _SuspendDialogState extends ConsumerState<_SuspendDialog> {
  static const _reasons = ['Discipline', 'Fees pending', 'Long leave', 'Medical', 'Other'];
  String reason = 'Discipline'; final other = TextEditingController();
  DateTime from = DateTime.now(), till = DateTime.now().add(const Duration(days: 3));
  bool busy = false;

  Future<void> _save() async {
    final why = reason == 'Other' ? other.text.trim() : reason;
    if (why.length < 2) { toast(context, 'Please write the reason.'); return; }
    setState(() => busy = true);
    try {
      await db.rpc('student_suspend', params: {'p_student': widget.student['id'], 'p_from': _iso(from), 'p_till': _iso(till), 'p_reason': why});
      if (!mounted) return;
      Navigator.pop(context, true);
      toast(context, '${widget.student['full_name']} is suspended till ${DateFormat('d MMM').format(till)}. Comes back by itself.');
    } catch (e) { if (mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
  }

  @override
  Widget build(BuildContext context) {
    Widget day(String label, DateTime d, ValueChanged<DateTime> set) => Expanded(child: OutlinedButton.icon(onPressed: () async {
      final x = await showDatePicker(context: context, initialDate: d, firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 365)));
      if (x != null) setState(() => set(x));
    }, icon: const Icon(Icons.event_rounded, size: 18), label: Text('$label ${DateFormat('d MMM yyyy').format(d)}')));
    return AlertDialog(
      title: Text('Suspend ${widget.student['full_name']} for a while?'),
      content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Temporarily barred, as in MCB. The child is shown as Suspended to the teachers. Nothing is deleted, and the child comes back by itself after the Till date (or earlier with one tap).'),
        const SizedBox(height: 14),
        const Text('REASON', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final x in _reasons) ChoiceChip(label: Text(x), selected: reason == x, onSelected: (_) => setState(() => reason = x))]),
        if (reason == 'Other') Padding(padding: const EdgeInsets.only(top: 8), child: TextField(controller: other, decoration: const InputDecoration(labelText: 'Reason'))),
        const SizedBox(height: 14),
        Row(children: [day('From', from, (d) { from = d; if (till.isBefore(d)) till = d; }), const SizedBox(width: 8), day('Till', till, (d) => till = d.isBefore(from) ? from : d)]),
      ])),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Brand.amber), onPressed: busy ? null : _save, child: Text(busy ? 'Please wait…' : 'Suspend')),
      ],
    );
  }
}

// ================================================================== Inactive: leaving — the TC is prepared, the Principal approves
class _InactiveDialog extends ConsumerStatefulWidget {
  final Map<String, dynamic> student; final bool decide;
  const _InactiveDialog({required this.student, required this.decide});
  @override
  ConsumerState<_InactiveDialog> createState() => _InactiveDialogState();
}

class _InactiveDialogState extends ConsumerState<_InactiveDialog> {
  static const _reasons = ['Applied for TC', 'Moving city', 'Not joined', 'Discontinued', 'Other'];
  String reason = 'Applied for TC'; final other = TextEditingController();
  DateTime day = DateTime.now();
  Map<String, String>? tc; Map<String, dynamic>? fees; bool busy = false;
  String get sid => widget.student['id'];
  String get _why => reason == 'Other' ? other.text.trim() : reason;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try { final d = await tcDraftFor(sid); if (mounted) setState(() => tc = d); } catch (_) { if (mounted) setState(() => tc = const {}); }
    _loadFees();
  }

  Future<void> _loadFees() async {
    setState(() => fees = null);
    try {
      final r = await db.rpc('leaving_fees', params: {'p_student': sid, 'p_last': _iso(day)});
      if (mounted) setState(() => fees = r == null ? const {} : Map<String, dynamic>.from(r as Map));
    } catch (_) { if (mounted) setState(() => fees = const {}); }
  }

  Map<String, String> get _tcNow => {...?tc, 'reason': _why, 'applied_on': DateFormat('dd-MM-yyyy').format(DateTime.now()), 'issued_on': DateFormat('dd-MM-yyyy').format(DateTime.now())};

  Future<void> _preview() => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PdfDocScreen(
      title: 'TC (draft) · ${widget.student['full_name']}', fileName: 'TC-draft.pdf', make: () => buildCertificatePdf('tc', 'DRAFT', _tcNow))));

  Future<void> _send() async {
    if (_why.length < 2) { toast(context, 'Please write the reason.'); return; }
    setState(() => busy = true);
    try {
      final notJoined = reason == 'Not joined';
      final r = Map<String, dynamic>.from(await db.rpc('leaving_request', params: {'p_student': sid, 'p_last': _iso(day), 'p_reason': _why, 'p_tc': notJoined || tc == null || tc!.isEmpty ? null : _tcNow}) as Map);
      if (r['status'] == 'done') { try { await callFunction(ref, 'password', {'action': 'signout_all', 'student_id': sid}); } catch (_) {} }
      if (!mounted) return;
      Navigator.pop(context, true);
      toast(context, r['status'] == 'done'
          ? '${widget.student['full_name']} moved to Past students${r['number'] != null ? ' · TC ${r['number']}' : ''} ✓'
          : 'Sent to the Principal ✓ · ${widget.student['full_name']} moves to Past students when she approves.');
    } catch (e) { if (mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final due = (fees?['due'] ?? 0) as num;
    final (filled, all) = tc == null ? (0, 0) : tcFilledCount(_tcNow);
    Widget step(bool ok, String title, String sub, {Widget? action, Color? warn}) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 24, height: 24, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: (warn ?? Brand.green).withValues(alpha: .14)),
          child: Icon(ok ? Icons.check_rounded : Icons.priority_high_rounded, size: 15, color: context.tone(warn ?? Brand.green))),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), Text(sub, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))])),
      if (action != null) action,
    ]));
    return AlertDialog(
      title: Text('Make ${widget.student['full_name']} inactive (leaving)'),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.decide ? 'Same as MCB’s Inactive: the student has left. You are the Principal, so this is done at once.'
            : 'Same as MCB’s Inactive: the student has left. The app prepares the TC; the student moves to Past students when the Principal approves.', style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 14),
        const Text('REASON FOR LEAVING', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final x in _reasons) ChoiceChip(label: Text(x), selected: reason == x, onSelected: (_) => setState(() => reason = x))]),
        if (reason == 'Other') Padding(padding: const EdgeInsets.only(top: 8), child: TextField(controller: other, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Reason'))),
        const SizedBox(height: 10),
        if (reason != 'Not joined') step(tc != null, 'Transfer Certificate prepared', tc == null ? 'Filling it in…' : '$filled of $all lines filled from the record · the number comes when it is approved',
            action: tc == null ? null : TextButton(onPressed: _preview, child: const Text('Preview')))
        else step(true, 'No TC needed', 'The child never joined.'),
        if (fees == null) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
        else if (due > 0) step(false, 'Fees: ${inr(due)} pending', widget.decide ? 'Approving lets the student leave with these unpaid.' : 'Collect first, or the Principal can approve with a note.', warn: Brand.crimson)
        else step(true, 'No fees due up to the last day', ((fees?['future'] ?? 0) as num) > 0 ? 'Fees after the last day (${inr(fees!['future'] as num)}) are cancelled by themselves.' : 'Nothing after the last day either.'),
        step(true, 'Last day ${DateFormat('d MMM yyyy').format(day)}', 'Attendance and future fees stop after this.',
            action: TextButton(onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: day, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now().add(const Duration(days: 90)));
              if (d != null) { setState(() => day = d); _loadFees(); }
            }, child: const Text('Change'))),
        const SizedBox(height: 6),
        const NoteBox('Nothing is deleted: fees, marks, report cards and documents stay. The family is signed out once it is done.'),
      ]))),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: busy || fees == null ? null : _send, child: Text(busy ? 'Please wait…' : widget.decide ? 'Approve — move to Past students' : 'Send to the Principal')),
      ],
    );
  }
}

// ---------------------------------------------------------------- fees
final _feesProvider = FutureProvider.autoDispose.family<(List<Map<String, dynamic>>, List<Map<String, dynamic>>), String>((ref, idsKey) async {
  ref.cacheFor();
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
  ref.cacheFor();
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
  ref.cacheFor();
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
      const NoteBox('Day-by-day attendance is on the Attendance page. These totals come from the report cards.', icon: Icons.info_outline_rounded),
    ]),
  );
}

// ---------------------------------------------------------------- documents: uploaded by the office, never made by the app
const docKinds = {'tc': 'Transfer Certificate (TC)', 'marksheet': 'Marksheet', 'conduct': 'Conduct certificate', 'bonafide': 'Bonafide / Study certificate', 'birth': 'Birth certificate', 'other': 'Other'};

final _docsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, idsKey) async {
  ref.cacheFor();
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

// ---------------------------------------------------------------- transport
class _BusTab extends ConsumerWidget {
  final Map<String, dynamic> r;
  const _BusTab({required this.r});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = r['transport_enrolment'];
    final t = te is List ? (te.isEmpty ? null : te.first) : te;
    return _pad([
      Panel(title: 'Transport', trailing: OutlinedButton.icon(onPressed: () async {
        final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => StudentEditor(studentId: r['id']));
        if (saved == true) ref.invalidate(_recordProvider(r['id']));
      }, icon: const Icon(Icons.edit_rounded, size: 18), label: const Text('Change')), child: t == null
          ? const Text('Does not use school transport.')
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
  String reason = 'Applied for TC';
  final other = TextEditingController();
  final files = <String, String>{};        // kind → uploaded path
  bool busy = false;
  String get sid => widget.student['id'];
  static const _reasons = ['Applied for TC', 'Moving city', 'Not joined', 'Discontinued', 'Other'];
  // fees: what is still to pay up to the last day (blocks leaving unless the Principal approves) and what comes after (cancelled)
  Map<String, dynamic>? fees;
  bool principalOk = false;

  @override
  void initState() { super.initState(); _loadFees(); }

  Future<void> _loadFees() async {
    setState(() => fees = null);
    try {
      final r = await db.rpc('leaving_fees', params: {'p_student': sid, 'p_last': DateFormat('yyyy-MM-dd').format(day)});
      if (mounted) setState(() => fees = r == null ? const {} : Map<String, dynamic>.from(r as Map));
    } catch (_) { if (mounted) setState(() => fees = const {}); }
  }

  num get _due => (fees?['due'] ?? 0) as num;
  bool get _canOverride { final s = ref.read(sessionProvider).value; return s != null && (s.hasRole('principal') || s.hasRole('it_admin')); }
  bool get _blocked => fees == null || (_due > 0 && !principalOk);

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
    if (_blocked) return;
    setState(() => busy = true);
    try {
      final last = DateFormat('yyyy-MM-dd').format(day);
      // fees after the last day are cancelled (refused by the database if fees up to the last day are unpaid, unless the Principal approves)
      await db.rpc('cancel_future_fees', params: {'p_student': sid, 'p_after': last, 'p_override': principalOk});
      try {
        await db.rpc('student_leave', params: {'p_student': sid, 'p_date': last, 'p_reason': reason == 'Other' ? other.text.trim() : reason});
      } catch (e) {
        try { await db.rpc('fees_bring_back', params: {'p_student': sid}); } catch (_) {}
        rethrow;
      }
      final me = myId(ref);
      const titles = {'tc': 'Transfer Certificate (TC)', 'conduct': 'Conduct certificate', 'other': 'Leaving document'};
      for (final e in files.entries) {
        final row = await db.from('student_document').insert({'student_id': sid, 'kind': e.key, 'title': titles[e.key], 'file_path': e.value,
          'file_name': e.value.split('/').last.replaceFirst(RegExp(r'^\d+_'), ''), 'uploaded_by': me}).select('id').single();
        await _log(ref, row['id'], 'upload');
      }
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
          if (d != null) { setState(() { day = d; principalOk = false; }); _loadFees(); }
        }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(DateFormat('EEE d MMMM yyyy').format(day)))),
        const SizedBox(height: 12),
        const Text('REASON', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [for (final x in _reasons) ChoiceChip(label: Text(x), selected: reason == x, onSelected: (_) => setState(() => reason = x))]),
        if (reason == 'Other') Padding(padding: const EdgeInsets.only(top: 8), child: TextField(controller: other, decoration: const InputDecoration(labelText: 'Reason'))),
        const SizedBox(height: 12),
        const Text('FEES', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6)),
        const SizedBox(height: 6),
        _feesBox(),
        const SizedBox(height: 12),
        const Text('CERTIFICATES (signed and scanned — PDF or photo)', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6)),
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => openCertificate(context, sid, 'tc'), icon: const Icon(Icons.print_rounded, size: 18), label: const Text('No TC yet? Print it from the app'))),
        slot('tc', 'Transfer Certificate (TC)'),
        slot('conduct', 'Conduct certificate'),
        slot('other', 'Another document (optional)'),
        const NoteBox('After confirming: the student moves to Past students and the family is signed out. Fees, marks, report cards and documents stay. Certificates can also be uploaded later.'),
      ]))),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: busy || _blocked ? null : _confirm, child: Text(busy ? 'Please wait…' : 'Confirm — student has left')),
      ],
    );
  }

  Widget _feesBox() {
    final cs = Theme.of(context).colorScheme;
    if (fees == null) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
    final future = (fees!['future'] ?? 0) as num;
    final items = List<Map<String, dynamic>>.from(((fees!['due_items'] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)));
    final later = future > 0 ? 'Fees after the last day (${inr(future)}) will be cancelled automatically.' : 'No fees after the last day.';
    if (_due <= 0) {
      return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Brand.green.withValues(alpha: .08), borderRadius: BorderRadius.circular(12)),
          child: Text('Nothing due up to the last day ✓  $later', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)));
    }
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Brand.crimson.withValues(alpha: .08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Brand.crimson)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Fees still due: ${inr(_due)}. Collect first, or ask the Principal to approve.', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(Brand.crimsonDeep))),
        const SizedBox(height: 4),
        for (final x in items) Text('• ${x['title']} · ${inr(x['amount'] as num)} · due ${_dmy(x['due_on'])}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(later, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        if (_canOverride) CheckboxListTile(contentPadding: EdgeInsets.zero, dense: true, controlAffinity: ListTileControlAffinity.leading, value: principalOk,
            onChanged: busy ? null : (v) => setState(() => principalOk = v ?? false),
            title: const Text('Principal approves: let the student leave with these fees unpaid', style: TextStyle(fontWeight: FontWeight.w700))),
      ]));
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
