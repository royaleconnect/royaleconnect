import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../core/brand_images.dart' show logoClear;
import '../core/cache.dart';
import '../core/data.dart';
import '../core/school_docs.dart' show PdfDocScreen;
import '../core/theme.dart';
import '../widgets/common.dart';
import 'staff_shell.dart';
import '../auth/session.dart';
import '../core/errors.dart';

/// goes up each time a certificate is printed, so an open student record refreshes (TC issued date, mother tongue…)
final certificateIssuedTick = StateProvider<int>((_) => 0);

/// Certificates — the office prints a Transfer Certificate, Study, Bonafide or No-dues certificate.
/// Find the student → tap the certificate → the form looks like the paper; what the app knows is filled in,
/// the rest are boxes to type in → Print / PDF. Every printed certificate gets a number and its exact
/// words are kept, so a reprint is the same paper.

String _msg(Object e) => e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');
String _dmyShort(String? iso) => iso == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());
String _ddmmyyyy(DateTime d) => DateFormat('dd-MM-yyyy').format(d);
String _initials(String n) => n.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

// ------------------------------------------------------------------ the four certificates
class CertKind {
  final String key, title, short; final IconData icon;
  const CertKind(this.key, this.title, this.short, this.icon);
}
const certKinds = [
  CertKind('tc', 'Transfer Certificate', 'Transfer Certificate', Icons.logout_rounded),
  CertKind('study', 'Study Certificate', 'Study', Icons.menu_book_rounded),
  CertKind('bonafide', 'Bonafide Certificate', 'Bonafide', Icons.verified_rounded),
  CertKind('nodues', 'No Dues Certificate', 'No dues', Icons.task_alt_rounded),
];
CertKind certKindOf(String k) => certKinds.firstWhere((c) => c.key == k, orElse: () => certKinds[1]);

// ------------------------------------------------------------------ words (date of birth, class)
const _ord = ['', 'First', 'Second', 'Third', 'Fourth', 'Fifth', 'Sixth', 'Seventh', 'Eighth', 'Ninth', 'Tenth', 'Eleventh', 'Twelfth',
  'Thirteenth', 'Fourteenth', 'Fifteenth', 'Sixteenth', 'Seventeenth', 'Eighteenth', 'Nineteenth', 'Twentieth', 'Twenty First', 'Twenty Second',
  'Twenty Third', 'Twenty Fourth', 'Twenty Fifth', 'Twenty Sixth', 'Twenty Seventh', 'Twenty Eighth', 'Twenty Ninth', 'Thirtieth', 'Thirty First'];
const _ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen',
  'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
String _two(int n) => n < 20 ? _ones[n] : '${_tens[n ~/ 10]}${n % 10 > 0 ? ' ${_ones[n % 10]}' : ''}';
String _numWords(int n) {
  if (n == 0) return 'Zero';
  final parts = <String>[];
  if (n >= 1000) { parts.add('${_two(n ~/ 1000)} Thousand'); n %= 1000; }
  if (n >= 100) { parts.add('${_ones[n ~/ 100]} Hundred'); n %= 100; }
  if (n > 0) parts.add(_two(n));
  return parts.join(' ');
}
/// 14-03-2012 → "Fourteenth March Two Thousand Twelve"
String dobInWords(DateTime d) => '${_ord[d.day]} ${DateFormat('MMMM').format(d)} ${_numWords(d.year)}';

const _roman = {'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10, 'XI': 11, 'XII': 12};
const _earlyWords = {'LKG': 'Lower Kindergarten', 'LK': 'Lower Kindergarten', 'UKG': 'Upper Kindergarten', 'UK': 'Upper Kindergarten',
  'NUR': 'Nursery', 'NURSERY': 'Nursery', 'PREKG': 'Pre-Kindergarten', 'PKG': 'Pre-Kindergarten'};
(String, String) _classFigWords(String? code) {
  final c = (code ?? '').trim().toUpperCase();
  if (c.isEmpty) return ('', '');
  final n = _roman[c];
  if (n != null) return ('$n ($c)', '${_ord[n]} Standard');
  return (c, _earlyWords[c] ?? c);
}
String _noTitle(String? s) => (s ?? '').trim().replaceFirst(RegExp(r'^(mr|mrs|ms|miss|dr|smt|shri|sri)\.?\s+', caseSensitive: false), '');

// ------------------------------------------------------------------ the fields of each certificate
/// Boxes the app cannot know: shown highlighted while empty.
const _typeIn = {'belongs', 'mother_tongue', 'birth_place', 'birth_state', 'purpose', 'category', 'last_exam', 'promotion', 'games', 'remarks',
  'school_code', 'from_std', 'to_std', 'from_year', 'to_year', 'nationality', 'failed', 'ncc', 'conduct', 'reason', 'first_admission'};

const _concession = {'regular': 'No', 'rte': 'Yes, RTE (free seat)', 'staff_ward': 'Yes, staff ward concession', 'special': 'Yes, special concession'};

Map<String, String> _defaults(String kind, Map<String, dynamic> p) {
  String s(String k) => (p[k] ?? '').toString();
  final today = DateTime.tryParse(s('today')) ?? DateTime.now();
  final dob = DateTime.tryParse(s('dob'));
  final grade = s('last_grade');
  final year = p['active'] == true ? (s('current_year').isEmpty ? s('last_year') : s('current_year')) : s('last_year');
  final common = {'date': _ddmmyyyy(today), 'name': s('full_name'), 'father': _noTitle(s('father_name')), 'mother': _noTitle(s('mother_name')), 'adm': s('admission_no')};
  switch (kind) {
    case 'study':
      return {...common, 'from_std': s('first_grade'), 'to_std': grade, 'from_year': s('first_year'), 'to_year': year,
        'belongs': '', 'mother_tongue': s('mother_tongue'), 'birth_place': s('place_of_birth'), 'birth_state': ''};
    case 'bonafide':
      return {...common, 'grade': grade, 'section': s('last_section'), 'year': year,
        'dob': dob == null ? '' : '${_ddmmyyyy(dob)} (${dobInWords(dob)})', 'purpose': ''};
    case 'nodues':
      return {...common, 'grade': grade, 'section': s('last_section'), 'upto': _ddmmyyyy(today)};
    default: // tc
      final (fig, words) = _classFigWords(grade);
      final firstOn = DateTime.tryParse(s('first_admission_on'));
      final firstClass = s('first_grade_name').isNotEmpty ? s('first_grade_name') : s('first_grade');
      final firstWhen = firstOn != null ? _ddmmyyyy(firstOn) : (s('first_year').isEmpty ? '' : 'Academic year ${s('first_year')}');
      return {
        'date': _ddmmyyyy(today), 'adm': s('admission_no'), 'school_code': s('school_code'),
        'pupil': s('full_name'), 'mother': _noTitle(s('mother_name')), 'father': _noTitle(s('father_name')),
        'nationality': s('x_nationality').isEmpty ? 'Indian' : s('x_nationality'),
        'category': switch (s('x_category')) { 'SC' || 'ST' || 'OBC' => 'Yes, ${s('x_category')}', 'General' => 'No', _ => '' },
        'first_admission': [firstWhen, if (firstClass.isNotEmpty) 'Class $firstClass'].where((x) => x.isNotEmpty).join(', '),
        'dob_figures': dob == null ? '' : _ddmmyyyy(dob), 'dob_words': dob == null ? '' : dobInWords(dob),
        'class_figures': fig, 'class_words': words, 'last_exam': '', 'failed': 'No', 'subjects': s('subjects'), 'promotion': '',
        'fees_upto': s('fees_paid_upto'), 'concession': _concession[s('fee_category')] ?? 'No',
        'working_days': s('working_days'), 'present_days': s('present_days'), 'ncc': 'No', 'games': '', 'conduct': 'Good',
        'applied_on': _ddmmyyyy(today), 'issued_on': _ddmmyyyy(today), 'reason': s('leaving_reason'), 'remarks': '',
      };
  }
}

/// TC rows: number, particulars, field key(s).
const _tcRows = <(int, String, List<String>)>[
  (1, 'Name of pupil', ['pupil']),
  (2, "Mother's name", ['mother']),
  (3, "Father's/Guardian's name", ['father']),
  (4, 'Nationality', ['nationality']),
  (5, 'Whether the candidate belongs to SC/ST/OBC', ['category']),
  (6, 'Date of first admission in the school with class', ['first_admission']),
  (7, 'Date of birth according to admission register (in figures and in words)', ['dob_figures', 'dob_words']),
  (8, 'Class in which the pupil last studied (in figures and in words)', ['class_figures', 'class_words']),
  (9, 'School/Board annual examination last taken with result', ['last_exam']),
  (10, 'Whether failed, if so once/twice in the same class', ['failed']),
  (11, 'Subjects studied', ['subjects']),
  (12, 'Whether qualified for promotion to the higher class, if so to which class', ['promotion']),
  (13, 'Month up to which the pupil has paid school dues', ['fees_upto']),
  (14, 'Any fee concession availed, if so the nature of such concession', ['concession']),
  (15, 'Total no. of working days in the academic session', ['working_days']),
  (16, 'Total no. of working days pupil present in the school', ['present_days']),
  (17, 'Whether NCC Cadet/Boy Scout/Girl Guide', ['ncc']),
  (18, 'Games played or extra-curricular activities', ['games']),
  (19, 'General conduct', ['conduct']),
  (20, 'Date of application for certificate', ['applied_on']),
  (21, 'Date of issue of certificate', ['issued_on']),
  (22, 'Reasons for leaving the school', ['reason']),
  (23, 'Any other remarks', ['remarks']),
];

// ------------------------------------------------------------------ letterhead (same words as the MCB certificate)
const _schoolName = 'Royale Concorde International School';
const _schoolAddress = "6TH 'B' MAIN, HRBR LAYOUT, KALYAN NAGAR, BANGALORE-560043";
const _schoolPhones = 'Ph: 080-25435454/55 · Mob: 9535216115';
const _schoolAffiliation = 'CBSE Affiliation No: 830135';

// ================================================================== data
final certificateRecentProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  final r = await db.from('certificate_issue').select('id,kind,number,issued_at,student_id,student:student_id(full_name,admission_no)')
      .order('issued_at', ascending: false).limit(30);
  return [for (final x in r) Map<String, dynamic>.from(x)];
});

/// current and past students together (a TC is often for a student who has already left)
final _certFindProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, q) async {
  ref.cacheFor();
  if (q.trim().length < 2) return const [];
  final res = await Future.wait([
    db.rpc('find_students', params: {'p_q': q.trim(), 'p_past': false, 'p_limit': 20}),
    db.rpc('find_students', params: {'p_q': q.trim(), 'p_past': true, 'p_limit': 20}),
  ]);
  return [for (final r in res) for (final x in r as List) Map<String, dynamic>.from(x)];
});

final _prefillProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, (String, String)>((ref, k) async => certificatePrefill(k.$1, k.$2));

/// What the app knows for a certificate: the record, plus category and nationality from the student's details.
Future<Map<String, dynamic>> certificatePrefill(String studentId, String kind) async {
  final r = Map<String, dynamic>.from(await db.rpc('certificate_prefill', params: {'p_student': studentId, 'p_kind': kind}) as Map);
  try {
    final x = await db.rpc('student_extra_for_cert', params: {'p_student': studentId});
    if (x is Map) {
      for (final e in x.entries) { if (e.value != null && '${e.value}'.trim().isNotEmpty) r.putIfAbsent('x_${e.key}', () => e.value); }
    }
  } catch (_) {}
  return r;
}

/// The TC of one student, filled in from the record (the class teacher's lines start as No / Good / empty).
Future<Map<String, String>> tcDraftFor(String studentId) async => _defaults('tc', await certificatePrefill(studentId, 'tc'));

/// Lines of the TC that the app fills by itself (out of all of them).
(int, int) tcFilledCount(Map<String, String> d) {
  var filled = 0;
  for (final (_, _, keys) in _tcRows) { if (keys.every((k) => (d[k] ?? '').trim().isNotEmpty)) filled++; }
  return (filled, _tcRows.length);
}

// ================================================================== the page
class StaffCertificatesScreen extends ConsumerStatefulWidget {
  const StaffCertificatesScreen({super.key});
  @override
  ConsumerState<StaffCertificatesScreen> createState() => _StaffCertificatesScreenState();
}

class _StaffCertificatesScreenState extends ConsumerState<StaffCertificatesScreen> {
  String q = '';
  Map<String, dynamic>? picked;
  final _search = TextEditingController();

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget results() {
      if (q.trim().length < 2) {
        return Padding(padding: const EdgeInsets.all(12), child: Text('Type a name, admission number or a parent’s phone number. Past students are found too.', style: TextStyle(color: cs.onSurfaceVariant)));
      }
      return ref.watch(_certFindProvider(q)).when(
        loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text(_msg(e), style: TextStyle(color: context.tone(Brand.crimsonDeep))),
        data: (rows) => rows.isEmpty
            ? Padding(padding: const EdgeInsets.all(12), child: Text('No student found for “$q”.', style: TextStyle(color: cs.onSurfaceVariant)))
            : Column(children: [for (final r in rows.take(12)) ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                leading: Avatar(_initials(r['full_name'] ?? ''), size: 40, bg: r['active'] == true ? Brand.crimsonTint : Brand.surface2, fg: r['active'] == true ? Brand.crimsonDeep : Brand.muted),
                title: Text(r['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(_studentLine(r), style: TextStyle(color: cs.onSurfaceVariant)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => setState(() => picked = r),
              )]),
      );
    }

    Widget chosen(Map<String, dynamic> r) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Avatar(_initials(r['full_name'] ?? ''), size: 48, bg: r['active'] == true ? Brand.crimsonTint : Brand.surface2, fg: r['active'] == true ? Brand.crimsonDeep : Brand.muted),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r['full_name'] ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text(_studentLine(r), style: TextStyle(color: cs.onSurfaceVariant)),
        ])),
        TextButton(onPressed: () => setState(() => picked = null), child: const Text('Change')),
      ]),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (_, c) {
        final w = c.maxWidth >= 640 ? (c.maxWidth - 30) / 4 : (c.maxWidth - 10) / 2;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final k in certKinds) _BigButton(width: w, kind: k, onTap: () => openCertificate(context, r['id'] as String, k.key)),
        ]);
      }),
    ]);

    return StaffPage(
      title: 'Certificates',
      subtitle: 'Transfer Certificate, Study, Bonafide and No dues — filled in from the student’s record, ready to print.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(title: picked == null ? 'Find the student' : null, child: picked != null ? chosen(picked!) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _search, autofocus: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Name, admission number or parent’s phone'),
              onChanged: (v) => setState(() => q = v)),
          const SizedBox(height: 6),
          results(),
        ])),
        Panel(title: 'Issued recently', child: ref.watch(certificateRecentProvider).when(
          loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => Text(_msg(e)),
          data: (rows) => rows.isEmpty
              ? Text('Nothing printed yet. Certificates you print appear here, and can be printed again exactly the same.', style: TextStyle(color: cs.onSurfaceVariant))
              : Column(children: [for (final r in rows) ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: CircleAvatar(backgroundColor: Brand.crimsonTint, foregroundColor: Brand.crimsonDeep, child: Icon(certKindOf(r['kind']).icon, size: 20)),
                  title: Text('${certKindOf(r['kind']).title} · ${r['student']?['full_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${r['number']} · ${_dmyShort(r['issued_at'])}', style: TextStyle(color: cs.onSurfaceVariant)),
                  trailing: IconButton(tooltip: 'Print again', icon: const Icon(Icons.print_rounded), onPressed: () => openCertificateReprint(context, r['id'] as String, number: r['number'])),
                  onTap: () => openCertificateReprint(context, r['id'] as String, number: r['number']),
                )]),
        )),
        const NoteBox('Each certificate gets its own number when printed (for example RCISKN/TC/2026-27/0001). A No dues certificate can be printed only when no fees are due.'),
      ]),
    );
  }
}

String _studentLine(Map<String, dynamic> r) => [
  r['admission_no'] ?? '',
  if (r['active'] == true && r['class'] != null) r['class'],
  if (r['active'] != true) 'Past student${r['left_on'] != null ? ' · left ${_dmyShort(r['left_on'])}' : ''}',
].join(' · ');

class _BigButton extends StatelessWidget {
  final double width; final CertKind kind; final VoidCallback onTap;
  const _BigButton({required this.width, required this.kind, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(width: width, height: 104, child: Material(
      color: cs.surface, borderRadius: BorderRadius.circular(16),
      child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.gold, width: 1.4)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(kind.icon, color: context.tone(Brand.crimson), size: 28),
          const SizedBox(height: 8),
          Text(kind.short, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
        ]),
      )),
    ));
  }
}

// ================================================================== open from anywhere (Students page, leaving dialog)
/// Opens the certificate form for one student. [kind] = 'tc' | 'study' | 'bonafide' | 'nodues'.
Future<void> openCertificate(BuildContext context, String studentId, String kind) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (c) => staffTheme(c, CertificateFormScreen(studentId: studentId, kind: kind))));

/// Shows one already-issued certificate again, exactly as it was printed.
Future<void> openCertificateReprint(BuildContext context, String id, {String? number}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PdfDocScreen(
      title: 'Certificate', fileName: '${_safe(number ?? id)}.pdf',
      make: () async {
        final r = Map<String, dynamic>.from(await db.rpc('certificate_reprint', params: {'p_id': id}) as Map);
        return buildCertificatePdf(r['kind'] as String, r['number'] as String, Map<String, dynamic>.from(r['data'] as Map));
      })));

/// A small sheet to pick which certificate (for the student record and the leaving dialog).
Future<void> pickCertificate(BuildContext context, String studentId) => showModalBottomSheet(context: context, showDragHandle: true, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
  const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Which certificate?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
  for (final k in certKinds) ListTile(leading: Icon(k.icon, color: c.tone(Brand.crimson)), title: Text(k.title, style: const TextStyle(fontWeight: FontWeight.w700)),
      onTap: () { Navigator.pop(c); openCertificate(context, studentId, k.key); }),
  const SizedBox(height: 8),
])));

String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

// ================================================================== the form (looks like the paper)
class CertificateFormScreen extends ConsumerStatefulWidget {
  final String studentId, kind;
  const CertificateFormScreen({super.key, required this.studentId, required this.kind});
  @override
  ConsumerState<CertificateFormScreen> createState() => _CertificateFormScreenState();
}

class _CertificateFormScreenState extends ConsumerState<CertificateFormScreen> {
  final _c = <String, TextEditingController>{};
  bool busy = false;
  CertKind get kind => certKindOf(widget.kind);

  @override
  void dispose() { for (final c in _c.values) { c.dispose(); } super.dispose(); }

  void _ensure(Map<String, dynamic> p) {
    if (_c.isNotEmpty) return;
    _defaults(widget.kind, p).forEach((k, v) => _c[k] = TextEditingController(text: v));
  }

  Map<String, String> get _values => {for (final e in _c.entries) e.key: e.value.text.trim()};

  Future<void> _print() async {
    final v = _values;
    final empty = v.entries.where((e) => e.value.isEmpty).length;
    if (empty > 0) {
      final go = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: const Text('Some boxes are empty'),
        content: Text('$empty box${empty == 1 ? ' is' : 'es are'} still empty (shown in yellow). They will print as blank lines.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Fill them')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Print anyway'))],
      ));
      if (go != true) return;
    }
    setState(() => busy = true);
    // a TC is a legal paper: the office asks, the Principal approves (Principal and IT issue directly)
    final se = ref.read(sessionProvider).value;
    if (widget.kind == 'tc' && !(se?.hasRole('principal') ?? false) && !(se?.hasRole('it_admin') ?? false)) {
      try {
        await db.rpc('tc_request', params: {'p_student': widget.studentId, 'p_data': v, 'p_note': v['reason']});
        if (!mounted) return;
        Navigator.pop(context); toast(context, 'Sent to the Principal ✓ · You will be told when the TC is approved.');
      } catch (e) { if (mounted) { setState(() => busy = false); toast(context, friendlyError(e)); } }
      return;
    }
    try {
      final number = await db.rpc('certificate_issue', params: {'p_student': widget.studentId, 'p_kind': widget.kind, 'p_data': v}) as String;
      ref.invalidate(certificateRecentProvider);
      ref.read(certificateIssuedTick.notifier).state++;   // the student record shows the new TC date at once
      if (!mounted) return;
      final data = Map<String, dynamic>.from(v);
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PdfDocScreen(
        title: '${kind.title} · $number', fileName: '${_safe(number)}.pdf', make: () => buildCertificatePdf(widget.kind, number, data))));
    } catch (e) {
      if (mounted) { toast(context, _msg(e)); setState(() => busy = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pre = ref.watch(_prefillProvider((widget.studentId, widget.kind)));
    final dues = (pre.value?['dues_now'] ?? 0) as num;
    final blocked = widget.kind == 'nodues' && dues > 0;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Brand.crimsonDeep, foregroundColor: Colors.white,
        title: Text(kind.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (pre.hasValue && !blocked) Padding(padding: const EdgeInsets.only(right: 12), child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Brand.gold, foregroundColor: Brand.ink),
            onPressed: busy ? null : _print,
            icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.print_rounded, size: 18),
            label: const Text('Print / PDF'))),
        ],
      ),
      body: pre.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_msg(e), textAlign: TextAlign.center))),
        data: (p) {
          _ensure(p);
          return ListView(padding: const EdgeInsets.fromLTRB(14, 16, 14, 40), children: [
            Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (blocked) Container(
                margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Brand.amberTint, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.amber.withValues(alpha: .5))),
                child: Row(children: [
                  const Icon(Icons.account_balance_wallet_rounded, color: Brand.amber), const SizedBox(width: 12),
                  Expanded(child: Text('Fees still due: ${_inr(dues)} — collect first.\nThe No dues certificate can be printed once every fee due till today is paid.',
                      style: const TextStyle(color: Brand.ink, fontWeight: FontWeight.w700, height: 1.4))),
                ]),
              )
              else Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Check the details. Yellow boxes are for you to fill in; every box can be changed. The number is given when you print.',
                  style: TextStyle(color: cs.onSurfaceVariant))),
              _paper(context),
            ]))),
          ]);
        },
      ),
    );
  }

  // ---------------------------------------------------------------- paper look
  Widget _box(String key, {double? width, String hint = ''}) {
    final c = _c[key]!;
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(width: width, child: ValueListenableBuilder<TextEditingValue>(valueListenable: c, builder: (_, v, __) {
      final empty = v.text.trim().isEmpty;
      return TextField(
        controller: c, textAlign: TextAlign.center, maxLength: 160,
        style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface, fontSize: 14.5),
        decoration: InputDecoration(
          isDense: true, counterText: '', hintText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          filled: true, fillColor: empty ? (dark ? Brand.amber.withValues(alpha: .25) : Brand.amberTint) : Colors.transparent,
          border: UnderlineInputBorder(borderSide: BorderSide(color: cs.outline)),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: empty || _typeIn.contains(key) ? Brand.gold : cs.outline, width: 1.2)),
          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Brand.crimson, width: 2)),
        ),
      );
    }));
  }

  /// One line: words and boxes flowing like the printed paragraph.
  Widget _flow(List<Object> parts) {
    final cs = Theme.of(context).colorScheme;
    final ts = TextStyle(fontSize: 15, height: 1.5, color: cs.onSurface);
    final kids = <Widget>[];
    for (final (i, p) in parts.indexed) {
      if (p is String) {
        for (final w in p.split(' ')) { if (w.isNotEmpty) kids.add(Text('$w ', style: ts)); }
      } else {
        // no gap before a comma or full stop that follows the box
        final next = i + 1 < parts.length ? parts[i + 1] : null;
        final tight = next is String && RegExp(r'^[,.]').hasMatch(next);
        kids.add(Padding(padding: EdgeInsets.only(left: 2, right: tight ? 0 : 6), child: p as Widget));
      }
    }
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 6, children: kids));
  }

  Widget _labelled(String label, String key) {
    final cs = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(label, style: TextStyle(fontSize: 15, color: cs.onSurface)), const SizedBox(width: 12), Expanded(child: _box(key)),
    ]));
  }

  Widget _paper(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget center(String t, {double size = 17}) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(t, textAlign: TextAlign.center,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, letterSpacing: 1, color: cs.onSurface)));
    final head = Row(children: [
      Image.memory(logoClear, height: 76, gaplessPlayback: true),
      const SizedBox(width: 12),
      Expanded(child: Column(children: [
        Text(_schoolName, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.onSurface)),
        const SizedBox(height: 4),
        Text(_schoolAddress, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        Text(_schoolAffiliation, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        Text(_schoolPhones, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ])),
      const SizedBox(width: 30),
    ]);
    final date = Align(alignment: Alignment.centerRight, child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text('Date ', style: TextStyle(fontSize: 15, color: cs.onSurface)), _box('date', width: 130)]));
    Widget signs(List<String> names) => Padding(padding: const EdgeInsets.only(top: 40), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final n in names) Flexible(child: Text(n, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant))),
    ]));
    const trueLine = 'The Above details are true and correct to the best of my knowledge.';

    final List<Widget> body;
    switch (widget.kind) {
      case 'study':
        body = [
          date,
          const SizedBox(height: 8),
          center('STUDY CERTIFICATE'), center('TO WHOMSOEVER IT MAY CONCERN', size: 15.5),
          const SizedBox(height: 14),
          _labelled('This is to Certify that Sri/ Kum', 'name'),
          _labelled('D/o / S/o of Mr :', 'father'),
          _labelled('and Mrs :', 'mother'),
          _flow(['has Studied from', _box('from_std', width: 120), 'standard to', _box('to_std', width: 120), 'standard in our']),
          _flow(['institution from', _box('from_year', width: 120), 'to', _box('to_year', width: 120), 'Academic Years']),
          _flow(['He / She Belongs to', _box('belongs', width: 170), 'and the Mother Tongue of the']),
          _flow(['Candidate is', _box('mother_tongue', width: 150), 'as per the admission register of the institution']),
          _flow(['This is further to certify that his/her place birth is', _box('birth_place', width: 160), 'in the state of']),
          _flow([_box('birth_state', width: 170), 'as per our Records']),
          const SizedBox(height: 6),
          _flow([trueLine]),
          signs(['Head of the Institution', 'School Seal']),
        ];
      case 'bonafide':
        body = [
          date,
          const SizedBox(height: 8),
          center('BONAFIDE CERTIFICATE'), center('TO WHOMSOEVER IT MAY CONCERN', size: 15.5),
          const SizedBox(height: 14),
          _flow(['This is to certify that Sri/ Kum', _box('name', width: 240), ', D/o / S/o of Mr', _box('father', width: 220), 'and Mrs', _box('mother', width: 220),
            ', bearing Admission No.', _box('adm', width: 150), ', is a bonafide student of our institution, studying in Grade', _box('grade', width: 70), 'Section', _box('section', width: 60),
            'during the academic year', _box('year', width: 100), '. His/Her date of birth as per our records is', _box('dob', width: 340),
            '. This certificate is issued on his/her request for the purpose of', _box('purpose', width: 260, hint: 'e.g. passport'), '.']),
          const SizedBox(height: 6),
          _flow([trueLine]),
          signs(['Head of the Institution', 'School Seal']),
        ];
      case 'nodues':
        body = [
          date,
          const SizedBox(height: 8),
          center('NO DUES CERTIFICATE'), center('TO WHOMSOEVER IT MAY CONCERN', size: 15.5),
          const SizedBox(height: 14),
          _flow(['This is to certify that Sri/ Kum', _box('name', width: 240), ', D/o / S/o of Mr', _box('father', width: 220), ', Admission No.', _box('adm', width: 150),
            ', of Grade', _box('grade', width: 70), 'Section', _box('section', width: 60), ', has paid all the fees due to the institution up to', _box('upto', width: 130),
            'and there are no dues pending against him/her in the school records.']),
          const SizedBox(height: 6),
          _flow([trueLine]),
          signs(['Head of the Institution', 'School Seal']),
        ];
      default:
        body = [
          center('TRANSFER CERTIFICATE'),
          const SizedBox(height: 6),
          Wrap(spacing: 18, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('TC No.: given when printed', style: TextStyle(color: cs.onSurfaceVariant)),
            Row(mainAxisSize: MainAxisSize.min, children: [Text('Admission No.: ', style: TextStyle(color: cs.onSurface)), _box('adm', width: 150)]),
            Row(mainAxisSize: MainAxisSize.min, children: [Text('School Code: ', style: TextStyle(color: cs.onSurface)), _box('school_code', width: 110)]),
            Row(mainAxisSize: MainAxisSize.min, children: [Text('Date: ', style: TextStyle(color: cs.onSurface)), _box('date', width: 120)]),
          ]),
          const SizedBox(height: 10),
          for (final (n, label, keys) in _tcRows) Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outline.withValues(alpha: .35)))),
            child: LayoutBuilder(builder: (_, c) {
              final narrow = c.maxWidth < 560;
              final lab = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 28, child: Text('$n.', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface))),
                Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: cs.onSurface))),
              ]);
              final val = keys.length == 1 ? _box(keys.first) : Row(children: [
                Expanded(flex: 2, child: _box(keys[0], hint: 'in figures')), const SizedBox(width: 8), Expanded(flex: 3, child: _box(keys[1], hint: 'in words'))]);
              return narrow
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [lab, Padding(padding: const EdgeInsets.only(left: 28), child: val)])
                  : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(flex: 5, child: lab), const SizedBox(width: 10), Expanded(flex: 5, child: val)]);
            }),
          ),
          signs(['Class Teacher', 'Checked by\n(State full name and designation)', 'Principal']),
        ];
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 30),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: Brand.gold.withValues(alpha: .7), width: 1.2),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, const SizedBox(height: 18), ...body]),
    );
  }
}

String _inr(num n) => '₹${NumberFormat('#,##,##0', 'en_IN').format(n)}';

// ================================================================== PDF (A4)
class _CertKit {
  final pw.Font base, bold;
  final pw.MemoryImage logo;
  _CertKit(this.base, this.bold, this.logo);
}

Future<_CertKit> _certKit() async {
  pw.Font base, bold;
  try {
    base = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  } catch (_) {
    base = pw.Font.helvetica(); bold = pw.Font.helveticaBold();
  }
  return _CertKit(base, bold, pw.MemoryImage(logoClear));
}

const _pInk = PdfColor.fromInt(0xFF1D1A1F);
const _pMuted = PdfColor.fromInt(0xFF6B6470);
const _pLine = PdfColor.fromInt(0xFF8A8590);

/// Makes the A4 PDF of a certificate from the exact values printed (also used for reprints).
Future<Uint8List> buildCertificatePdf(String kind, String number, Map<String, dynamic> data) async {
  final k = await _certKit();
  final doc = pw.Document(title: '${certKindOf(kind).title} $number', author: _schoolName);
  _addCertificate(doc, k, kind, number, data);
  return doc.save();
}

/// Many certificates in one PDF (for example every Grade X TC), one after the other.
Future<Uint8List> buildManyCertificatesPdf(String title, List<(String kind, String number, Map<String, dynamic> data)> items) async {
  final k = await _certKit();
  final doc = pw.Document(title: title, author: _schoolName);
  for (final (kind, number, data) in items) { _addCertificate(doc, k, kind, number, data); }
  return doc.save();
}

void _addCertificate(pw.Document doc, _CertKit k, String kind, String number, Map<String, dynamic> data) {
  String v(String key) => (data[key] ?? '').toString().trim();
  final theme = pw.ThemeData.withFont(base: k.base, bold: k.bold);
  const fs = 11.5;
  final tsN = pw.TextStyle(font: k.base, fontSize: fs, color: _pInk);
  final tsB = pw.TextStyle(font: k.bold, fontSize: fs, color: _pInk);

  final head = pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
    pw.SizedBox(width: 80, child: pw.Image(k.logo, height: 80)),
    pw.SizedBox(width: 8),
    pw.Expanded(child: pw.Column(children: [
      pw.Text(_schoolName, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: k.bold, fontSize: 18, color: _pInk)),
      pw.SizedBox(height: 4),
      pw.Text(_schoolAddress, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: k.base, fontSize: 11, color: _pInk)),
      pw.SizedBox(height: 2),
      pw.Text(_schoolAffiliation, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: k.base, fontSize: 11, color: _pInk)),
      pw.Text(_schoolPhones, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: k.base, fontSize: 10, color: _pInk)),
    ])),
    pw.SizedBox(width: 88),
  ]);

  // a value sitting on a dotted line
  pw.Widget box(String t, {double? width, pw.TextAlign align = pw.TextAlign.center}) => pw.Container(
    width: width,
    padding: const pw.EdgeInsets.only(left: 4, right: 4, bottom: 1),
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _pLine, width: .8, style: pw.BorderStyle.dotted))),
    child: pw.Text(t.isEmpty ? ' ' : t, textAlign: align, style: tsB),
  );
  pw.Widget line(List<Object> parts) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 9), child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
    for (final p in parts)
      if (p is String) pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 3), child: pw.Text(p, style: tsN))
      else p as pw.Widget,
  ]));
  pw.Widget grow(String key, [int flex = 1]) => pw.Expanded(flex: flex, child: box(v(key)));
  pw.Widget labelled(String label, String key) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 9), child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
    pw.SizedBox(width: 190, child: pw.Text(label, style: tsN)), pw.Expanded(child: box(v(key))),
  ]));
  pw.Widget title(String t) => pw.Padding(padding: const pw.EdgeInsets.only(top: 6, bottom: 6), child: pw.Center(child: pw.Text(t, style: pw.TextStyle(font: k.bold, fontSize: 14, letterSpacing: 1, color: _pInk))));
  final dateRow = pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
    pw.Text('Date ', style: tsN), box(v('date'), width: 90)]);
  pw.Widget signs(List<String> names) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
    for (final n in names) pw.Text(n, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: k.bold, fontSize: 11.5, color: _pInk)),
  ]);
  final ref = pw.Text('Certificate No. $number', style: pw.TextStyle(font: k.base, fontSize: 8, color: _pMuted));
  const trueLine = 'The Above details are true and correct to the best of my knowledge.';

  // paragraph certificates: words flow, values bold and underlined
  pw.Widget para(List<Object> parts) {
    final spans = <pw.InlineSpan>[];
    for (final (i, p) in parts.indexed) {
      if (p is String) { spans.add(pw.TextSpan(text: p)); continue; }
      final next = i + 1 < parts.length ? parts[i + 1] : null;
      final t = (p as _V).text;
      spans.add(const pw.TextSpan(text: ' '));
      spans.add(pw.TextSpan(text: t.isEmpty ? '                              ' : t,
          style: tsB.copyWith(decoration: pw.TextDecoration.underline, decorationStyle: pw.TextDecorationStyle.solid, decorationColor: _pLine)));
      if (!(next is String && RegExp(r'^[,.]').hasMatch(next))) spans.add(const pw.TextSpan(text: ' '));
    }
    return pw.RichText(textAlign: pw.TextAlign.justify, text: pw.TextSpan(style: tsN.copyWith(lineSpacing: 9), children: spans));
  }
  _V val(String key) => _V(v(key));

  pw.Page shortPage(List<pw.Widget> children) => pw.Page(
    pageFormat: PdfPageFormat.a4, theme: theme, margin: const pw.EdgeInsets.fromLTRB(46, 40, 46, 34),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [head, pw.SizedBox(height: 14), ...children]),
  );

  switch (kind) {
    case 'study':
      doc.addPage(shortPage([
        dateRow,
        pw.SizedBox(height: 10),
        title('STUDY CERTIFICATE'),
        pw.SizedBox(height: 6),
        title('TO WHOMSOEVER IT MAY CONCERN'),
        pw.SizedBox(height: 22),
        labelled('This is to Certify that Sri/ Kum', 'name'),
        labelled('D/o / S/o of Mr :', 'father'),
        labelled('and Mrs :', 'mother'),
        line(['has Studied from', grow('from_std'), 'standard to', grow('to_std'), 'standard in our']),
        line(['institution from', grow('from_year'), 'to', grow('to_year'), 'Academic Years']),
        line(['He / She Belongs to', grow('belongs'), 'and the Mother Tongue of the']),
        line(['Candidate is', grow('mother_tongue'), 'as per the admission register of the institution']),
        line(['This is further to certify that his/her place birth is', grow('birth_place'), 'in the state of']),
        line([pw.SizedBox(width: 150, child: box(v('birth_state'))), 'as per our Records']),
        pw.SizedBox(height: 6),
        pw.Text(trueLine, style: tsN),
        pw.Spacer(),
        signs(['Head of the Institution', 'School Seal']),
        pw.SizedBox(height: 26),
        ref,
      ]));
    case 'bonafide':
      doc.addPage(shortPage([
        dateRow,
        pw.SizedBox(height: 10),
        title('BONAFIDE CERTIFICATE'),
        pw.SizedBox(height: 6),
        title('TO WHOMSOEVER IT MAY CONCERN'),
        pw.SizedBox(height: 26),
        para(['This is to certify that Sri/ Kum', val('name'), ', D/o / S/o of Mr', val('father'), 'and Mrs', val('mother'), ', bearing Admission No.', val('adm'),
          ', is a bonafide student of our institution, studying in Grade', val('grade'), 'Section', val('section'), 'during the academic year', val('year'),
          '. His/Her date of birth as per our records is', val('dob'), '. This certificate is issued on his/her request for the purpose of', val('purpose'), '.']),
        pw.SizedBox(height: 18),
        pw.Text(trueLine, style: tsN),
        pw.Spacer(),
        signs(['Head of the Institution', 'School Seal']),
        pw.SizedBox(height: 26),
        ref,
      ]));
    case 'nodues':
      doc.addPage(shortPage([
        dateRow,
        pw.SizedBox(height: 10),
        title('NO DUES CERTIFICATE'),
        pw.SizedBox(height: 6),
        title('TO WHOMSOEVER IT MAY CONCERN'),
        pw.SizedBox(height: 26),
        para(['This is to certify that Sri/ Kum', val('name'), ', D/o / S/o of Mr', val('father'), ', Admission No.', val('adm'), ', of Grade', val('grade'), 'Section', val('section'),
          ', has paid all the fees due to the institution up to', val('upto'), 'and there are no dues pending against him/her in the school records.']),
        pw.SizedBox(height: 18),
        pw.Text(trueLine, style: tsN),
        pw.Spacer(),
        signs(['Head of the Institution', 'School Seal']),
        pw.SizedBox(height: 26),
        ref,
      ]));
    default: // TC
      final small = pw.TextStyle(font: k.base, fontSize: 9.5, color: _pInk);
      final smallB = pw.TextStyle(font: k.bold, fontSize: 9.5, color: _pInk);
      pw.Widget cell(String t, pw.TextStyle s, {pw.TextAlign align = pw.TextAlign.left}) =>
          pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3.6), child: pw.Text(t, style: s, textAlign: align));
      pw.Widget valCell(String t) => pw.Container(
        margin: const pw.EdgeInsets.symmetric(vertical: 2.5),
        padding: const pw.EdgeInsets.only(left: 3, bottom: 1),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _pLine, width: .7, style: pw.BorderStyle.dotted))),
        child: pw.Text(t.isEmpty ? ' ' : t, style: smallB),
      );
      String rowValue(List<String> keys) {
        if (keys.length == 1) return v(keys.first);
        final a = v(keys[0]), b = v(keys[1]);
        if (a.isEmpty && b.isEmpty) return '';
        return '$a${b.isEmpty ? '' : '  ($b)'}';
      }
      pw.Widget info(String label, String value) => pw.Row(mainAxisSize: pw.MainAxisSize.min, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text('$label ', style: small), pw.Container(
          constraints: const pw.BoxConstraints(minWidth: 70),
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _pLine, width: .7)),
          child: pw.Text(value.isEmpty ? ' ' : value, style: smallB)),
      ]);
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4, theme: theme, margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 30),
        build: (_) => [
          head,
          pw.SizedBox(height: 8),
          pw.Divider(color: _pLine, thickness: .8),
          title('TRANSFER CERTIFICATE'),
          pw.SizedBox(height: 4),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            info('TC No.', number), info('Admission No.', v('adm')),
          ]),
          pw.SizedBox(height: 6),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            info('Affiliation No.', '830135'), info('School Code', v('school_code')),
          ]),
          pw.SizedBox(height: 10),
          pw.Table(
            columnWidths: const {0: pw.FixedColumnWidth(22), 1: pw.FlexColumnWidth(5), 2: pw.FixedColumnWidth(8), 3: pw.FlexColumnWidth(4.4)},
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.bottom,
            children: [
              for (final (n, label, keys) in _tcRows) pw.TableRow(children: [
                cell('$n.', small, align: pw.TextAlign.right), cell(label, small), cell(':', small), valCell(rowValue(keys)),
              ]),
            ],
          ),
          pw.SizedBox(height: 46),
          signs(['Class Teacher', 'Checked by\n(State full name and designation)', 'Principal']),
          pw.SizedBox(height: 16),
          pw.Text('Date: ${v('issued_on').isEmpty ? v('date') : v('issued_on')}', style: small),
        ],
      ));
  }
}

class _V { final String text; const _V(this.text); }
