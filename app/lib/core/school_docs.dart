import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'config.dart';
import 'data.dart' show db;

/// Fee receipts and report cards as A4 PDFs, made on the phone from the school's data.
/// Each carries a QR code that opens the public /verify page, so anyone can check it is genuine.

// ---------------------------------------------------------------- school details (from school_setting)
class SchoolInfo {
  final String name, address, email, phone, affiliation, code;
  final int internalMax;
  const SchoolInfo({required this.name, required this.address, required this.email, required this.phone, required this.affiliation, required this.code, required this.internalMax});
}

Future<SchoolInfo> loadSchoolInfo() async {
  final rows = await db.from('school_setting').select('key,value')
      .inFilter('key', ['school_name', 'school_address', 'school_email', 'school_phone', 'cbse_affiliation_no', 'cbse_school_code', 'internal_assessment_max']);
  String v(String k, String d) {
    for (final r in rows) {
      if (r['key'] == k && (r['value'] as String).trim().isNotEmpty) return (r['value'] as String).trim();
    }
    return d;
  }
  return SchoolInfo(
    name: v('school_name', AppConfig.schoolName),
    address: v('school_address', 'Kalyan Nagar · 6th ‘B’ Main, II Block, HRBR Layout, Bengaluru 560043'),
    email: v('school_email', ''),
    phone: v('school_phone', ''),
    affiliation: v('cbse_affiliation_no', ''),
    code: v('cbse_school_code', ''),
    internalMax: int.tryParse(v('internal_assessment_max', '20')) ?? 20,
  );
}

// ---------------------------------------------------------------- look
const _crimson = PdfColor.fromInt(0xFF7E0A10);
const _gold = PdfColor.fromInt(0xFFB8963E);
const _cream = PdfColor.fromInt(0xFFFAF7F1);
const _creamLine = PdfColor.fromInt(0xFFE6DCCB);
const _line = PdfColor.fromInt(0xFFECE5D8);
const _muted = PdfColor.fromInt(0xFF6B6470);
const _ink = PdfColor.fromInt(0xFF1D1A1F);
const _green = PdfColor.fromInt(0xFF1E7F4F);
const _greenTint = PdfColor.fromInt(0xFFE9F5EE);
const _goldTint = PdfColor.fromInt(0xFFFAF3E3);

class _Kit {
  final pw.Font base, bold, serif;
  final bool rupee;          // the font has the ₹ sign
  final pw.MemoryImage? logo;
  final SchoolInfo school;
  _Kit(this.base, this.bold, this.serif, this.rupee, this.logo, this.school);

  String money(num n) => '${rupee ? '₹' : 'Rs. '}${NumberFormat('#,##,##0.00', 'en_IN').format(n)}';
  String plain(num n) => NumberFormat('#,##,##0.00', 'en_IN').format(n);
}

Future<_Kit> _kit() async {
  pw.Font base, bold, serif; var rupee = true;
  try {
    base = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    serif = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSerif-Bold.ttf'));
  } catch (_) {
    base = pw.Font.helvetica(); bold = pw.Font.helveticaBold(); serif = pw.Font.timesBold(); rupee = false;
  }
  pw.MemoryImage? logo;
  try {
    logo = pw.MemoryImage((await rootBundle.load('assets/images/logo.png')).buffer.asUint8List());
  } catch (_) {}
  return _Kit(base, bold, serif, rupee, logo, await loadSchoolInfo());
}

pw.Widget _header(_Kit k, {bool contact = true}) {
  final s = k.school;
  final reach = [if (contact && s.email.isNotEmpty) s.email, if (contact && s.phone.isNotEmpty) s.phone].join(' · ');
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 10),
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _gold, width: 2))),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      if (k.logo != null) pw.Image(k.logo!, height: 50),
      pw.SizedBox(width: 12),
      pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(s.name, style: pw.TextStyle(font: k.serif, fontSize: 15.5, color: _crimson)),
        pw.SizedBox(height: 3),
        pw.Text(s.address, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
        if (reach.isNotEmpty) pw.Text(reach, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
      ])),
      if (s.affiliation.isNotEmpty) pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text('Affiliated to CBSE', style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
        pw.Text('Affiliation No. ${s.affiliation}', style: pw.TextStyle(font: k.bold, fontSize: 8)),
        if (s.code.isNotEmpty) pw.Text('School Code ${s.code}', style: pw.TextStyle(font: k.bold, fontSize: 8)),
      ]),
    ]),
  );
}

pw.Widget _title(_Kit k, String title, String sub) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 12, bottom: 10),
  child: pw.Center(child: pw.Column(children: [
    pw.Text(title, style: pw.TextStyle(font: k.serif, fontSize: 14.5, letterSpacing: 2, color: _ink)),
    pw.SizedBox(height: 2),
    pw.Text(sub, style: pw.TextStyle(font: k.bold, fontSize: 8.5, letterSpacing: 1, color: _crimson)),
  ])),
);

pw.Widget _infoBox(_Kit k, List<(String, String)> items) {
  pw.Widget key(String t) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.5), child: pw.Text(t, style: const pw.TextStyle(fontSize: 8.5, color: _muted)));
  pw.Widget val(String t) => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.5), child: pw.Text(t, style: pw.TextStyle(font: k.bold, fontSize: 9)));
  final rows = <pw.TableRow>[];
  for (var i = 0; i < items.length; i += 2) {
    final a = items[i];
    final b = i + 1 < items.length ? items[i + 1] : ('', '');
    rows.add(pw.TableRow(children: [key(a.$1), val(a.$2), key(b.$1), val(b.$2)]));
  }
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: pw.BoxDecoration(color: _cream, border: pw.Border.all(color: _creamLine, width: .8), borderRadius: pw.BorderRadius.circular(6)),
    child: pw.Table(columnWidths: const {0: pw.FixedColumnWidth(78), 1: pw.FlexColumnWidth(), 2: pw.FixedColumnWidth(70), 3: pw.FlexColumnWidth()}, children: rows),
  );
}

pw.Widget _cell(_Kit k, String t, {pw.TextAlign align = pw.TextAlign.center, bool bold = false, PdfColor? color, double size = 9}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
  child: pw.Text(t, textAlign: align, style: pw.TextStyle(font: bold ? k.bold : k.base, fontSize: size, color: color ?? _ink)),
);

pw.TableRow _headRow(_Kit k, List<String> labels, {int leftAligned = 1}) => pw.TableRow(
  decoration: const pw.BoxDecoration(color: _crimson),
  children: [for (final (i, l) in labels.indexed) _cell(k, l, bold: true, color: PdfColors.white, size: 8, align: i < leftAligned ? pw.TextAlign.left : pw.TextAlign.center)],
);

pw.TableRow _row(_Kit k, List<String> cells, {int leftAligned = 1, bool total = false, int boldCol = -1, pw.TextAlign? lastAlign}) => pw.TableRow(
  decoration: total
      ? const pw.BoxDecoration(color: _goldTint, border: pw.Border(top: pw.BorderSide(color: _gold, width: 1.2)))
      : const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: .6))),
  children: [for (final (i, c) in cells.indexed) _cell(k, c, bold: total || i == boldCol || (i == 0 && leftAligned > 0), align: i < leftAligned ? pw.TextAlign.left : (i == cells.length - 1 && lastAlign != null ? lastAlign : pw.TextAlign.center))],
);

pw.Widget _section(_Kit k, String t) => pw.Padding(padding: const pw.EdgeInsets.only(top: 6, bottom: 4), child: pw.Text(t, style: pw.TextStyle(font: k.serif, fontSize: 10.5, color: _crimson)));

pw.Widget _verifyFoot(_Kit k, String url, List<String> lines) => pw.Container(
  padding: const pw.EdgeInsets.only(top: 8),
  decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _creamLine, width: .8))),
  child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
    pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: url, width: 56, height: 56, drawText: false),
    pw.SizedBox(width: 12),
    pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [for (final l in lines) pw.Text(l, style: const pw.TextStyle(fontSize: 8, color: _muted))])),
  ]),
);

pw.ThemeData _theme(_Kit k) => pw.ThemeData.withFont(base: k.base, bold: k.bold);

String _dmy(String? iso) => iso == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());

// ---------------------------------------------------------------- amount in words (Indian system)
const _ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
String _two(int n) => n < 20 ? _ones[n] : '${_tens[n ~/ 10]}${n % 10 > 0 ? ' ${_ones[n % 10]}' : ''}';
String _three(int n) => n >= 100 ? '${_ones[n ~/ 100]} Hundred${n % 100 > 0 ? ' ${_two(n % 100)}' : ''}' : _two(n);
String _words(int n) {
  final parts = <String>[];
  final crore = n ~/ 10000000; n %= 10000000;
  final lakh = n ~/ 100000; n %= 100000;
  final thousand = n ~/ 1000; n %= 1000;
  if (crore > 0) parts.add('${_words(crore)} Crore');
  if (lakh > 0) parts.add('${_two(lakh)} Lakh');
  if (thousand > 0) parts.add('${_two(thousand)} Thousand');
  if (n > 0) parts.add(_three(n));
  return parts.join(' ');
}
String rupeesInWords(num amount) {
  final r = amount.floor();
  final p = ((amount - r) * 100).round();
  return 'Rupees ${r == 0 ? 'Zero' : _words(r)}${p > 0 ? ' and ${_words(p)} Paise' : ''} only';
}

// ---------------------------------------------------------------- shared lookups
Future<Map<String, dynamic>> _student(String id) async =>
    await db.from('student').select('full_name,admission_no,dob,father_name,mother_name').eq('id', id).single();

Future<Map<String, dynamic>?> _enrolment(String studentId, String? yearId) async {
  var q = db.from('enrolment').select('is_current,section:section_id(name,grade:grade_id(id,code,name)),academic_year!inner(id,is_current,label)').eq('student_id', studentId);
  q = yearId == null ? q.eq('is_current', true) : q.eq('academic_year_id', yearId);
  return await q.maybeSingle();
}

String _cls(Map<String, dynamic>? e) => e == null ? '' : '${e['section']?['grade']?['code'] ?? ''} – ${e['section']?['name'] ?? ''}';

String verifyUrl(String kind, String id) => '${AppConfig.webUrl}/verify?$kind=$id';

// ---------------------------------------------------------------- FEE RECEIPT
const _modes = {'upi': 'UPI', 'card': 'Card', 'netbanking': 'Net banking', 'wallet': 'Wallet', 'cash': 'Cash', 'cheque': 'Cheque', 'neft': 'NEFT / bank transfer', 'other': 'Other'};

Future<Uint8List> buildReceiptPdf(String paymentId) async {
  final p = await db.from('payment')
      .select('id,student_id,amount,mode,status,receipt_no,gateway,gateway_payment_id,paid_at,collected_by,payment_line(amount,fee_ledger:fee_ledger_id(title,due_on))')
      .eq('id', paymentId).single();
  if (p['status'] != 'success') throw 'This payment is not confirmed yet, so there is no receipt.';
  final sid = p['student_id'] as String;
  final k = await _kit();
  final st = await _student(sid);
  final en = await _enrolment(sid, null);
  final pending = await db.from('fee_ledger').select('amount,concession,due_on')
      .eq('student_id', sid).eq('status', 'pending').order('due_on', ascending: true);
  final balance = pending.fold<num>(0, (a, r) => a + (r['amount'] as num) - ((r['concession'] ?? 0) as num));
  final nextDue = pending.isEmpty ? null : pending.first['due_on'] as String?;
  final lines = List<Map<String, dynamic>>.from(p['payment_line'] ?? const []);
  final amount = p['amount'] as num;
  final online = p['collected_by'] == null;
  final mode = _modes[p['mode']] ?? '${p['mode']}';
  final year = '${en?['academic_year']?['label'] ?? AppConfig.academicYearLabel}';

  final doc = pw.Document(title: 'Fee receipt ${p['receipt_no']}', author: k.school.name, theme: _theme(k));
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      _header(k),
      _title(k, 'FEE RECEIPT', 'ACADEMIC YEAR $year'),
      _infoBox(k, [
        ('Receipt No.', '${p['receipt_no'] ?? ''}'), ('Date', p['paid_at'] == null ? '' : DateFormat('d MMM yyyy, h:mm a').format(DateTime.parse(p['paid_at']).toLocal())),
        ('Student', (st['full_name'] as String).toUpperCase()), ('Class', _cls(en)),
        ('Admission No.', '${st['admission_no'] ?? ''}'), ('Father', '${st['father_name'] ?? ''}'),
        ('', ''), ('Mother', '${st['mother_name'] ?? ''}'),
      ]),
      pw.SizedBox(height: 12),
      pw.Table(columnWidths: const {0: pw.FixedColumnWidth(28), 1: pw.FlexColumnWidth(), 2: pw.FixedColumnWidth(100)}, children: [
        _headRow(k, ['#', 'Particulars', 'Amount (${k.rupee ? '₹' : 'Rs.'})'], leftAligned: 2),
        for (final (i, l) in lines.indexed) _row(k, ['${i + 1}', '${l['fee_ledger']?['title'] ?? 'Fee'}', k.plain(l['amount'] as num)], leftAligned: 2, lastAlign: pw.TextAlign.right),
        if (lines.isEmpty) _row(k, ['1', 'School fees', k.plain(amount)], leftAligned: 2, lastAlign: pw.TextAlign.right),
        _row(k, ['', 'Total paid', k.plain(amount)], leftAligned: 2, total: true, lastAlign: pw.TextAlign.right),
      ]),
      pw.SizedBox(height: 12),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: pw.BoxDecoration(color: _greenTint, border: pw.Border.all(color: const PdfColor.fromInt(0xFFBFE0CC), width: .8), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Amount received', style: const pw.TextStyle(fontSize: 8, color: _muted)),
            pw.Text(k.money(amount), style: pw.TextStyle(font: k.bold, fontSize: 16, color: _green)),
            pw.Text(rupeesInWords(amount), style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ])),
          pw.Transform.rotate(angle: .2, child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _green, width: 2), borderRadius: pw.BorderRadius.circular(5)),
            child: pw.Text('PAID', style: pw.TextStyle(font: k.bold, fontSize: 18, letterSpacing: 3, color: _green)),
          )),
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Balance due for the year (as on ${DateFormat('d MMM yyyy').format(DateTime.now())})', style: const pw.TextStyle(fontSize: 8, color: _muted)),
            pw.Text(k.money(balance), style: pw.TextStyle(font: k.bold, fontSize: 16, color: balance > 0 ? _crimson : _green)),
            pw.Text(balance > 0 && nextDue != null ? 'Next instalment due: ${_dmy(nextDue)}' : 'All fees for the year are paid', style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ])),
        ]),
      ),
      pw.SizedBox(height: 12),
      pw.Table(columnWidths: const {0: pw.FixedColumnWidth(110), 1: pw.FlexColumnWidth()}, children: [
        for (final (a, b) in [
          ('Payment mode', online ? 'Online — $mode' : mode),
          if ((p['gateway_payment_id'] ?? '').toString().isNotEmpty) ('Transaction ref.', '${p['gateway_payment_id']}'),
          ('Received by', online ? 'Royale Connect app (online)' : 'School office'),
        ]) pw.TableRow(children: [
          pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: pw.Text(a, style: const pw.TextStyle(fontSize: 9, color: _muted))),
          pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2), child: pw.Text(b, style: pw.TextStyle(font: k.bold, fontSize: 9))),
        ]),
      ]),
      pw.SizedBox(height: 16),
      _verifyFoot(k, verifyUrl('p', p['id']), [
        'Scan to check this receipt on the school’s system.',
        'This is a computer-generated receipt and does not need a signature.',
        'Fees once paid are not refundable. Please keep this receipt for your records.',
      ]),
    ]),
  ));
  return doc.save();
}

// ---------------------------------------------------------------- REPORT CARD
class _Grades {
  final List<Map<String, dynamic>> scale;
  _Grades(this.scale);
  String of(num pct) {
    for (final g in scale) {
      if (pct >= (g['min_pct'] as num) && pct <= (g['max_pct'] as num) + .0001) return g['grade_label'];
    }
    if (scale.isNotEmpty) return pct > 100 ? scale.first['grade_label'] : scale.last['grade_label'];
    return pct >= 91 ? 'A1' : pct >= 81 ? 'A2' : pct >= 71 ? 'B1' : pct >= 61 ? 'B2' : pct >= 51 ? 'C1' : pct >= 41 ? 'C2' : pct >= 33 ? 'D' : 'E';
  }
  String legend() {
    if (scale.isEmpty) return '91–100 A1 · 81–90 A2 · 71–80 B1 · 61–70 B2 · 51–60 C1 · 41–50 C2 · 33–40 D · below 33 E';
    return scale.map((g) => (g['min_pct'] as num) <= 0 ? 'below ${_n(g['max_pct'] as num, up: true)} ${g['grade_label']}' : '${_n(g['min_pct'] as num)}–${_n(g['max_pct'] as num)} ${g['grade_label']}').join(' · ');
  }
  static String _n(num v, {bool up = false}) => (up ? v.ceil() : v.floor()).toString();
}

String _fmt(num? v) => v == null ? '—' : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1));

Future<Uint8List> buildReportCardPdf(String reportCardId) async {
  final rc = await db.from('report_card')
      .select('id,student_id,academic_year_id,term,status,working_days,days_present,height_cm,weight_kg,remarks,co_scholastic,published_at,academic_year:academic_year_id(label)')
      .eq('id', reportCardId).single();
  final sid = rc['student_id'] as String;
  final yearId = rc['academic_year_id'] as String;
  final term = rc['term'] as String;
  final k = await _kit();
  final st = await _student(sid);
  final en = await _enrolment(sid, yearId);
  final grades = _Grades(List<Map<String, dynamic>>.from(await db.from('grading_scale').select('min_pct,max_pct,grade_label').eq('academic_year_id', yearId).order('min_pct', ascending: false)));

  // which exam(s) this card is about: a term card ("Term I") uses that term's main exam; a test card uses the exam of that name.
  // Families cannot read raw marks, so they come through report_card_data (only for a card the viewer may see).
  final data = Map<String, dynamic>.from(await db.rpc('report_card_data', params: {'rc_id': reportCardId}) as Map);
  final exams = List<Map<String, dynamic>>.from(data['exams'] ?? const []);
  final byName = exams.where((e) => '${e['name']}'.toLowerCase() == term.toLowerCase()).toList();
  final isTest = byName.isNotEmpty;
  final inTerm = exams.where((e) => '${e['term']}'.toLowerCase() == term.toLowerCase()).toList()
    ..sort((a, b) => (b['max_marks'] as num).compareTo(a['max_marks'] as num));
  final exam = isTest ? byName.first : (inTerm.isEmpty ? null : inTerm.first);
  final maxMarks = (exam?['max_marks'] as num?) ?? 100;
  final im = isTest ? 0 : k.school.internalMax.clamp(0, maxMarks.toInt()).toInt();
  final marks = [for (final m in List<Map<String, dynamic>>.from(data['marks'] ?? const [])) if (m['exam_id'] == exam?['id']) {...m, 'subject': {'id': m['subject_id'], 'name': m['subject']}}];
  final papers = [for (final p in List<Map<String, dynamic>>.from(data['papers'] ?? const [])) if (p['exam_id'] == exam?['id']) {...p, 'subject': {'id': p['subject_id'], 'name': p['subject']}}];
  // subject order: exam timetable first, then any other subject that has marks
  final subjects = <String, String>{};
  for (final p in papers) { if (p['subject'] != null) subjects[p['subject']['id']] = p['subject']['name']; }
  for (final m in marks) { if (m['subject'] != null) subjects.putIfAbsent(m['subject']['id'], () => m['subject']['name']); }

  final rows = <List<String>>[];
  num sumI = 0, sumE = 0, sumT = 0; var counted = 0;
  for (final s in subjects.entries) {
    final m = marks.where((x) => x['subject']?['id'] == s.key).firstOrNull;
    final absent = m?['absent'] == true;
    final i = m?['internal'] as num?, e = m?['external'] as num?;
    if (isTest) {
      final t = (i ?? 0) + (e ?? 0);
      if (absent) { rows.add([s.value, 'AB', '—']); continue; }
      if (m == null || (i == null && e == null)) { rows.add([s.value, '—', '—']); continue; }
      rows.add([s.value, _fmt(t), grades.of(t * 100 / maxMarks)]);
      sumT += t; counted++;
    } else {
      if (absent) { rows.add([s.value, _fmt(i), 'AB', '—', '—']); continue; }
      if (m == null || e == null) { rows.add([s.value, _fmt(i), '—', '—', 'Not assessed']); continue; }
      final t = (i ?? 0) + e;
      rows.add([s.value, _fmt(i), _fmt(e), _fmt(t), grades.of(t * 100 / maxMarks)]);
      sumI += i ?? 0; sumE += e; sumT += t; counted++;
    }
  }
  final pct = counted == 0 ? 0 : sumT * 100 / (counted * maxMarks);

  final co = rc['co_scholastic'] is Map ? Map<String, dynamic>.from(rc['co_scholastic']) : <String, dynamic>{};
  co.remove('Work Education');   // not part of RCIS's co-scholastic areas
  final wd = rc['working_days'] as num?, dp = rc['days_present'] as num?;
  final year = '${rc['academic_year']?['label'] ?? AppConfig.academicYearLabel}';

  final doc = pw.Document(title: 'Report card – ${st['full_name']} – $term', author: k.school.name, theme: _theme(k));
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 34, 40, 30),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      _header(k, contact: false),
      _title(k, 'PERFORMANCE RECORD', '${term.toUpperCase()} · $year'),
      _infoBox(k, [
        ('Name', (st['full_name'] as String).toUpperCase()), ('Class', _cls(en)),
        ('Admission No.', '${st['admission_no'] ?? ''}'), ('Date of birth', st['dob'] == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(st['dob']))),
        ('Father', '${st['father_name'] ?? ''}'), ('Mother', '${st['mother_name'] ?? ''}'),
      ]),
      _section(k, 'Scholastic areas'),
      if (rows.isEmpty) pw.Text('Marks for this ${isTest ? 'test' : 'term'} have not been entered yet.', style: const pw.TextStyle(fontSize: 9, color: _muted))
      else pw.Table(
        columnWidths: isTest
            ? const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.4), 2: pw.FlexColumnWidth(1.2)}
            : const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.3), 2: pw.FlexColumnWidth(1.3), 3: pw.FlexColumnWidth(1.3), 4: pw.FlexColumnWidth(1.4)},
        children: [
          isTest
              ? _headRow(k, ['Subject', 'Marks (${_fmt(maxMarks)})', 'Grade'])
              : _headRow(k, ['Subject', 'Internal ($im)', 'Term exam (${_fmt(maxMarks - im)})', 'Total (${_fmt(maxMarks)})', 'Grade']),
          for (final r in rows) _row(k, r, boldCol: isTest ? 1 : 3),
          if (counted > 0) isTest
              ? _row(k, ['Overall', '${_fmt(sumT)} / ${_fmt(counted * maxMarks)}', '${pct.toStringAsFixed(1)}% · ${grades.of(pct)}'], total: true)
              : _row(k, ['Overall', '${_fmt(sumI)} / ${counted * im}', '${_fmt(sumE)} / ${_fmt(counted * (maxMarks - im))}', '${_fmt(sumT)} / ${_fmt(counted * maxMarks)}', '${pct.toStringAsFixed(1)}% · ${grades.of(pct)}'], total: true),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          _section(k, 'Co-scholastic areas'),
          if (co.isEmpty) pw.Text('—', style: const pw.TextStyle(fontSize: 9, color: _muted))
          else pw.Table(columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1)}, children: [
            _headRow(k, ['Activity', 'Grade']),
            for (final e in co.entries) _row(k, [e.key, '${e.value}']),
          ]),
        ])),
        pw.SizedBox(width: 14),
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          _section(k, 'Attendance & health'),
          pw.Table(columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(1.4)}, children: [
            _headRow(k, ['Item', 'Value']),
            _row(k, ['Working days', _fmt(wd)]),
            _row(k, ['Days present', dp == null ? '—' : (wd != null && wd > 0 ? '${_fmt(dp)} (${(dp * 100 / wd).toStringAsFixed(1)}%)' : _fmt(dp))]),
            _row(k, ['Height', rc['height_cm'] == null ? '—' : '${_fmt(rc['height_cm'] as num)} cm']),
            _row(k, ['Weight', rc['weight_kg'] == null ? '—' : '${_fmt(rc['weight_kg'] as num)} kg']),
          ]),
        ])),
      ]),
      if ((rc['remarks'] ?? '').toString().trim().isNotEmpty) ...[
        _section(k, 'Class teacher’s remarks'),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: pw.BoxDecoration(color: _cream, border: pw.Border.all(color: _creamLine, width: .8), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Text('${rc['remarks']}'.trim(), style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 2)),
        ),
      ],
      pw.SizedBox(height: 34),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        for (final s in ['Class Teacher', 'Principal', 'Parent']) pw.Container(
          width: 130, padding: const pw.EdgeInsets.only(top: 4),
          decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _muted, width: .6))),
          child: pw.Text(s, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
        ),
      ]),
      pw.SizedBox(height: 12),
      pw.Text('Grading scale: ${grades.legend()} · Co-scholastic: A outstanding, B very good, C fair', style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
      pw.Spacer(),
      _verifyFoot(k, verifyUrl('c', rc['id']), [
        'Scan to check this report card on the school’s system.',
        'Issued through Royale Connect${rc['published_at'] == null ? '' : ' on ${_dmy(rc['published_at'])}'}.',
      ]),
    ]),
  ));
  return doc.save();
}

// ---------------------------------------------------------------- viewer (download · share · print)
class PdfDocScreen extends StatefulWidget {
  final String title, fileName;
  final Future<Uint8List> Function() make;
  const PdfDocScreen({super.key, required this.title, required this.fileName, required this.make});
  @override
  State<PdfDocScreen> createState() => _PdfDocScreenState();
}

class _PdfDocScreenState extends State<PdfDocScreen> {
  late final Future<Uint8List> _doc = widget.make();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: PdfPreview(
      build: (_) => _doc,
      pdfFileName: widget.fileName,
      canChangePageFormat: false,
      canChangeOrientation: false,
      canDebug: false,
      allowPrinting: true,
      allowSharing: true,
      loadingWidget: const Center(child: CircularProgressIndicator()),
      onError: (context, e) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not make the PDF.\n$e', textAlign: TextAlign.center))),
    ),
  );
}

String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

void openReceiptPdf(BuildContext context, String paymentId, {String? receiptNo}) => Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => PdfDocScreen(title: 'Fee receipt', fileName: 'RCIS-receipt-${_safe(receiptNo ?? paymentId)}.pdf', make: () => buildReceiptPdf(paymentId)),
));

void openReportCardPdf(BuildContext context, String reportCardId, {String? name}) => Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => PdfDocScreen(title: 'Report card', fileName: 'RCIS-report-card-${_safe(name ?? reportCardId)}.pdf', make: () => buildReportCardPdf(reportCardId)),
));
