import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:url_launcher/url_launcher.dart';
import '../auth/session.dart';
import '../core/config.dart';
import '../core/data.dart';
import '../core/import_rules.dart';
import '../core/school_docs.dart' show PdfDocScreen;
import '../core/sheet_reader.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'school_setup.dart' show setupSectionsProvider;
import 'staff_data.dart';
import 'staff_shell.dart';

/// School setup → Import from Excel.
/// 1 choose what and upload · 2 columns matched automatically (change any) · 3 check every row (nothing saved yet)
/// · 4 import in batches, then password slips for the new people.

String _msg(Object e) => e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');

class _Slip {
  final String title, line1, line2, password;
  const _Slip(this.title, this.line1, this.line2, this.password);
}

class _Done {
  int added = 0, updated = 0;
  final failed = <Problem>[];
  final newIds = <String>[];                 // students / staff just added (for slips)
  final whoById = <String, CheckedRow>{};
  List<_Slip>? slips;
  int slipSkipped = 0;
}

class ImportTab extends ConsumerStatefulWidget {
  const ImportTab({super.key});
  @override
  ConsumerState<ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends ConsumerState<ImportTab> {
  ImpKind? kind;
  String? fileName;
  List<Sheet> sheets = [];
  int sheetIdx = 0, headerRow = 0;
  Map<String, int> mapping = {};
  // what the check compares against
  Map<String, String> students = {};
  Set<String> emails = {}, routes = {};
  SchoolClasses? classes;
  CheckResult? check;
  bool busy = false, addFees = true;
  double? progress;
  String? status;
  _Done? done;

  List<List<String>> get rows => sheets.isEmpty ? const [] : sheets[sheetIdx].rows;
  List<String> get headers => rows.isEmpty || headerRow >= rows.length ? const [] : rows[headerRow];

  void _reset({bool keepKind = true}) => setState(() {
        if (!keepKind) kind = null;
        fileName = null; sheets = []; sheetIdx = 0; headerRow = 0; mapping = {}; check = null; done = null; status = null; progress = null;
      });

  Future<void> _pick() async {
    final k = kind;
    if (k == null) return;
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx', 'xlsm', 'xls', 'csv', 'txt', 'htm', 'html'], withData: true);
    if (r == null || r.files.isEmpty || r.files.first.bytes == null) return;
    final f = r.files.first;
    setState(() { busy = true; status = 'Reading the file…'; done = null; check = null; });
    try {
      final read = readSpreadsheet(Uint8List.fromList(f.bytes!), f.name).where((s) => s.rows.any((row) => row.any((c) => c.isNotEmpty))).toList();
      if (read.isEmpty) throw const SheetError('The file is empty.');
      await _loadContext(k);
      // pick the sheet that looks most like what was chosen
      var best = 0, bestScore = -1;
      for (var i = 0; i < read.length; i++) {
        final h = findHeaderRow(read[i].rows, k);
        final score = autoMatch(read[i].rows[h], k).length;
        if (score > bestScore) { best = i; bestScore = score; }
      }
      setState(() { fileName = f.name; sheets = read; status = null; });
      _useSheet(best);
    } catch (e) {
      setState(() { status = e is SheetError ? e.message : 'Could not read the file: ${_msg(e)}'; });
    }
    if (mounted) setState(() => busy = false);
  }

  /// Everything the check compares against: admission numbers, staff emails, routes, classes.
  Future<void> _loadContext(ImpKind k) async {
    final idx = await db.rpc('admin_student_index');
    students = idx is Map ? {for (final e in idx.entries) '${e.key}': '${e.value}'} : {};
    emails = {for (final s in await db.from('staff').select('email')) '${s['email']}'.toLowerCase()};
    routes = {for (final r in await db.from('route').select('name')) '${r['name']}'.toLowerCase()};
    final secs = await db.from('section').select('id,name,grade:grade_id(id,code,name)').eq('status', 'active').eq('placeholder', false);
    classes = SchoolClasses(await ref.read(gradesProvider.future), List<Map<String, dynamic>>.from(secs));
  }

  void _useSheet(int i) {
    final k = kind!;
    sheetIdx = i;
    headerRow = findHeaderRow(rows, k);
    mapping = autoMatch(headers, k);
    _runCheck();
  }

  void _runCheck() {
    final k = kind, c = classes;
    if (k == null || c == null || rows.isEmpty) return;
    setState(() => check = checkRows(kind: k, rows: rows, headerRow: headerRow, mapping: mapping, students: students, classes: c, existingEmails: emails, existingRoutes: routes));
  }

  Future<void> _import() async {
    final k = kind!, c = check!;
    final missing = k.fields.where((f) => f.required && !mapping.containsKey(f.key)).map((f) => f.label).toList();
    if (missing.isNotEmpty) { toast(context, 'Choose the column for: ${missing.join(', ')}'); return; }
    if (c.ready.isEmpty) { toast(context, 'No rows are ready to import.'); return; }
    final result = _Done();
    setState(() { busy = true; progress = 0; status = 'Saving…'; });
    try {
      const size = 150;
      for (var at = 0; at < c.ready.length; at += size) {
        final chunk = c.ready.sublist(at, math.min(at + size, c.ready.length));
        final byLine = {for (final r in chunk) r.line: r};
        final params = <String, dynamic>{'p_rows': [for (final r in chunk) r.rec]};
        if (k.key == 'students') params['p_add_fees'] = addFees;
        final res = await db.rpc(k.rpc, params: params);
        for (final x in (res as List)) {
          final row = byLine[x['i']];
          final st = x['status'];
          if (st == 'added') {
            result.added++;
            if (x['id'] != null && row != null) { result.newIds.add(x['id']); result.whoById[x['id']] = row; }
          } else if (st == 'updated') {
            result.updated++;
          }
          if (x['error'] != null) result.failed.add(Problem(row?.line ?? x['i'], row?.who ?? '', '${x['error']}', blocking: st == 'error'));
        }
        if (mounted) setState(() => progress = (at + chunk.length) / c.ready.length);
      }
      ref.invalidate(setupSectionsProvider); ref.invalidate(staffListProvider); ref.invalidate(routesProvider); ref.invalidate(studentSearchProvider);
      setState(() { done = result; status = null; });
    } catch (e) {
      setState(() { status = 'Stopped: ${_msg(e)}. Rows saved so far are kept — fix the problem and import the same file again; nothing will be doubled.'; done = result; });
    }
    if (mounted) setState(() { busy = false; progress = null; });
  }

  Future<void> _makeSlips() async {
    final d = done!, k = kind!;
    final staffKind = k.key == 'staff';
    setState(() { busy = true; progress = 0; status = 'Making first-use passwords…'; });
    final slips = <_Slip>[];
    var skipped = 0;
    try {
      for (var at = 0; at < d.newIds.length; at += 50) {
        final ids = d.newIds.sublist(at, math.min(at + 50, d.newIds.length));
        final r = await callFunction(ref, 'password', {'action': staffKind ? 'bulk_first_use_staff' : 'bulk_first_use', 'ids': ids});
        for (final p in (r['passwords'] as List? ?? const [])) {
          final row = d.whoById[p['id']];
          if (p['password'] == null || row == null) { skipped++; continue; }
          final rec = row.rec;
          slips.add(staffKind
              ? _Slip('${rec['full_name'] ?? ''}', '${rec['email']}', 'School staff', '${p['password']}')
              : _Slip('${rec['full_name'] ?? ''}', 'Class ${classes?.label('${rec['section_id']}') ?? ''}', 'Admission no. ${rec['admission_no']}', '${p['password']}'));
        }
        if (mounted) setState(() => progress = (at + ids.length) / d.newIds.length);
      }
      // class-wise, then by name — easy to hand over to class teachers
      slips.sort((a, b) { final c = a.line1.compareTo(b.line1); return c != 0 ? c : a.title.compareTo(b.title); });
      setState(() { d.slips = slips; d.slipSkipped = skipped; status = null; });
      if (mounted) _openSlips();
    } catch (e) {
      setState(() => status = 'Could not make the passwords: ${_msg(e)}');
    }
    if (mounted) setState(() { busy = false; progress = null; });
  }

  void _openSlips() {
    final d = done!;
    final staffKind = kind?.key == 'staff';
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PdfDocScreen(
      title: 'Password slips (${d.slips!.length})',
      fileName: staffKind ? 'RCIS-staff-password-slips.pdf' : 'RCIS-password-slips.pdf',
      make: () => _slipsPdf(d.slips!, staff: staffKind),
    )));
  }

  Future<void> _copyProblems(List<Problem> list) async {
    final text = StringBuffer('Row\tWho\tProblem\n');
    for (final p in list) {
      text.writeln('${p.line}\t${p.who}\t${p.text}');
    }
    await Clipboard.setData(ClipboardData(text: text.toString()));
    if (mounted) toast(context, 'Copied ${list.length} rows — paste into Excel.');
  }

  // ------------------------------------------------------------------ screen
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    final kinds = importKinds.where((k) => k.roles.any(s.hasRole)).toList();
    final cs = Theme.of(context).colorScheme;
    final step = done != null ? 4 : check != null ? 3 : sheets.isNotEmpty ? 2 : 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(child: Wrap(spacing: 18, runSpacing: 10, children: [
        for (final (i, t) in const ['Choose & upload', 'Match columns', 'Check', 'Import & password slips'].indexed) Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 13, backgroundColor: i + 1 < step ? Brand.green : i + 1 == step ? Brand.crimson : cs.outline.withValues(alpha: .4),
              child: i + 1 < step ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
          const SizedBox(width: 8),
          Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: i + 1 == step ? cs.onSurface : cs.onSurfaceVariant)),
        ]),
      ])),

      // 1 · what and which file
      Panel(title: '1 · What are you importing?',
        trailing: kind == null ? null : TextButton.icon(
          onPressed: () => launchUrl(Uri.parse('${AppConfig.webUrl}/templates/${kind!.template}'), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Blank Excel template')),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in kinds) ChoiceChip(label: Text(k.label), selected: kind?.key == k.key, onSelected: busy ? null : (_) { _reset(); setState(() => kind = k); }),
          ]),
          if (kind != null) ...[
            const SizedBox(height: 10),
            Text(kind!.help, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            if (fileName == null)
              Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: busy ? null : _pick, icon: const Icon(Icons.upload_file_rounded), label: const Text('Choose the Excel / CSV file')))
            else
              Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: Brand.greenTint, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.description_rounded, color: Brand.green),
                  const SizedBox(width: 10),
                  Expanded(child: Text('$fileName · ${rows.length - headerRow - 1} rows', style: const TextStyle(color: Brand.green, fontWeight: FontWeight.w800))),
                  TextButton(onPressed: busy ? null : () { _reset(); _pick(); }, child: const Text('Change file')),
                ])),
            if (sheets.length > 1) Padding(padding: const EdgeInsets.only(top: 10), child: PickField<int>(label: 'Sheet', value: sheetIdx,
                items: [for (final (i, sh) in sheets.indexed) DropdownMenuItem(value: i, child: Text('${sh.name} · ${sh.rows.length} rows'))],
                onChanged: (v) { if (v != null) _useSheet(v); })),
          ],
          if (status != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(status!, style: TextStyle(fontWeight: FontWeight.w700, color: busy ? cs.onSurfaceVariant : context.tone(Brand.crimsonDeep)))),
          if (progress != null) Padding(padding: const EdgeInsets.only(top: 10), child: LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(8))),
        ])),

      // 2 · columns
      if (kind != null && sheets.isNotEmpty && done == null) Panel(
        title: '2 · Columns matched automatically',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('Headings in row ${headerRow + 1}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          IconButton(tooltip: 'Headings are higher up', onPressed: headerRow == 0 ? null : () { headerRow--; mapping = autoMatch(headers, kind!); _runCheck(); }, icon: const Icon(Icons.arrow_upward_rounded, size: 18)),
          IconButton(tooltip: 'Headings are lower down', onPressed: headerRow >= rows.length - 2 ? null : () { headerRow++; mapping = autoMatch(headers, kind!); _runCheck(); }, icon: const Icon(Icons.arrow_downward_rounded, size: 18)),
        ]),
        child: LayoutBuilder(builder: (_, c) {
          final cols = c.maxWidth > 900 ? 4 : c.maxWidth > 600 ? 3 : c.maxWidth > 380 ? 2 : 1;
          final w = (c.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final f in kind!.fields) SizedBox(width: w, child: DropdownButtonFormField<int?>(
              key: ValueKey('${f.key}-$sheetIdx-$headerRow-${mapping[f.key]}'),
              value: mapping[f.key], isExpanded: true,
              decoration: InputDecoration(labelText: '${f.label}${f.required ? ' *' : ''}', isDense: true,
                  filled: true, fillColor: mapping[f.key] == null ? (f.required ? Brand.crimsonTint : Brand.amberTint) : null),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('— not in this sheet')),
                for (final (i, h) in headers.indexed) if (h.trim().isNotEmpty) DropdownMenuItem<int?>(value: i, child: Text('“$h”', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) { setState(() { if (v == null) { mapping.remove(f.key); } else { mapping.removeWhere((_, x) => x == v); mapping[f.key] = v; } }); _runCheck(); },
            )),
          ]);
        }),
      ),

      // 3 · check
      if (check != null && done == null) _checkPanel(check!, cs),

      // 4 · done
      if (done != null) _donePanel(done!, cs),
    ]);
  }

  Widget _tile(String n, String label, Color fg, Color bg) => Expanded(child: Container(
    padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(n, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: fg)),
      Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
    ])));

  Widget _problemTable(List<Problem> list, ColorScheme cs) {
    final shown = list.take(150).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final p in shown) Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outline.withValues(alpha: .4)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 56, child: Text('Row ${p.line}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700))),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (p.who.isNotEmpty) Text(p.who, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(p.text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.tone(p.blocking ? Brand.crimsonDeep : Brand.amber))),
          ])),
        ])),
      if (list.length > shown.length) Padding(padding: const EdgeInsets.only(top: 8), child: Text('…and ${list.length - shown.length} more — use “Copy problem list” to see them all.', style: TextStyle(color: cs.onSurfaceVariant))),
    ]);
  }

  Widget _checkPanel(CheckResult c, ColorScheme cs) {
    final k = kind!;
    final missing = k.fields.where((f) => f.required && !mapping.containsKey(f.key)).map((f) => f.label).toList();
    final blocking = c.problems.where((p) => p.blocking).toList();
    final notes = c.problems.where((p) => !p.blocking).toList();
    final noun = switch (k.key) { 'students' => 'students', 'staff' => 'staff', 'sections' => 'sections', _ => 'rows' };
    return Panel(title: '3 · Check before saving — nothing is saved yet', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (missing.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: NoteBox('Choose the column for: ${missing.join(', ')}.', icon: Icons.error_outline_rounded, iconColor: Brand.crimson)),
      Row(children: [
        if (k.key != 'paid') ...[_tile('${c.newCount}', k.key == 'riders' ? 'students to put on a bus' : 'new $noun, ready', Brand.green, Brand.greenTint), const SizedBox(width: 10)],
        _tile('${c.updateCount}', k.key == 'paid' ? 'payments, ready' : 'already in the app — will be updated', Brand.blue, Brand.blueTint),
        const SizedBox(width: 10),
        _tile('${blocking.length}', 'need attention — skipped', Brand.crimsonDeep, Brand.crimsonTint),
      ]),
      if (notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${notes.length} rows will be imported with a note (shown in amber below).', style: TextStyle(color: context.tone(Brand.amber), fontWeight: FontWeight.w700, fontSize: 13))),
      if (c.problems.isNotEmpty) ...[const SizedBox(height: 10), _problemTable([...blocking, ...notes], cs)],
      const SizedBox(height: 12),
      if (k.key == 'students') CheckboxListTile(contentPadding: EdgeInsets.zero, value: addFees, onChanged: (v) => setState(() => addFees = v ?? true),
          title: const Text('Add this year’s fees from the fee plan for new students')),
      Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 10, children: [
        if (c.problems.isNotEmpty) OutlinedButton.icon(onPressed: () => _copyProblems(c.problems), icon: const Icon(Icons.copy_rounded, size: 18), label: const Text('Copy problem list')),
        OutlinedButton(onPressed: busy ? null : () => _reset(), child: const Text('Start again')),
        FilledButton.icon(onPressed: busy || missing.isNotEmpty || c.ready.isEmpty ? null : _import,
            icon: const Icon(Icons.cloud_upload_rounded, size: 18), label: Text(busy ? 'Importing…' : 'Import ${c.ready.length} ${k.key == 'paid' ? 'payments' : noun}')),
      ]),
    ]));
  }

  Widget _donePanel(_Done d, ColorScheme cs) {
    final k = kind!;
    final slipsKind = k.key == 'students' || k.key == 'staff';
    final blocking = d.failed.where((p) => p.blocking).toList();
    return Panel(title: '4 · Done', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        _tile('${d.added}', 'added', Brand.green, Brand.greenTint), const SizedBox(width: 10),
        _tile('${d.updated}', 'updated', Brand.blue, Brand.blueTint), const SizedBox(width: 10),
        _tile('${blocking.length}', 'not saved', Brand.crimsonDeep, Brand.crimsonTint),
      ]),
      if (d.failed.isNotEmpty) ...[const SizedBox(height: 10), _problemTable(d.failed, cs)],
      if (slipsKind && d.newIds.isNotEmpty) ...[
        const SizedBox(height: 14),
        NoteBox(d.slips == null
            ? '${d.newIds.length} new ${k.key == 'staff' ? 'staff' : 'students'} need a first-use password. Make the slips now — they are printed class-wise, 10 to a page, ready to cut and hand out. Each password works once; at first sign-in they choose their own.'
            : '${d.slips!.length} password slips are ready${d.slipSkipped > 0 ? ' (${d.slipSkipped} skipped — already using the app)' : ''}. Print them now: the passwords are not shown again (a new slip can always be printed from Students).'),
      ],
      const SizedBox(height: 12),
      Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 10, children: [
        if (d.failed.isNotEmpty) OutlinedButton.icon(onPressed: () => _copyProblems(d.failed), icon: const Icon(Icons.copy_rounded, size: 18), label: const Text('Copy problem list')),
        OutlinedButton(onPressed: busy ? null : () => _reset(), child: const Text('Import another file')),
        if (slipsKind && d.newIds.isNotEmpty && d.slips == null)
          FilledButton.icon(onPressed: busy ? null : _makeSlips, icon: const Icon(Icons.print_rounded, size: 18), label: Text(busy ? 'Making…' : 'Make ${d.newIds.length} password slips')),
        if (d.slips != null && d.slips!.isNotEmpty)
          FilledButton.icon(onPressed: _openSlips, icon: const Icon(Icons.picture_as_pdf_rounded, size: 18), label: const Text('Open password slips (PDF)')),
      ]),
    ]));
  }
}

// ------------------------------------------------------------------ password slips PDF (A4, 10 per page)
Future<Uint8List> _slipsPdf(List<_Slip> slips, {required bool staff}) async {
  pw.Font base, bold;
  try {
    base = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  } catch (_) {
    base = pw.Font.helvetica();
    bold = pw.Font.helveticaBold();
  }
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: base, bold: bold), title: 'Royale Connect password slips');
  const crimson = PdfColor.fromInt(0xFF9A0F15), grey = PdfColor.fromInt(0xFF625E66), line = PdfColor.fromInt(0xFFB8B2A8);
  final site = AppConfig.webUrl.replaceFirst('https://', '');

  pw.Widget slip(_Slip s) => pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 8),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: line, width: .6, style: pw.BorderStyle.dashed)),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(AppConfig.schoolName, style: pw.TextStyle(font: bold, fontSize: 8.5, color: crimson)),
      pw.Text('Royale Connect · first-use password', style: const pw.TextStyle(fontSize: 7.5, color: grey)),
      pw.SizedBox(height: 6),
      pw.Text(s.title, style: pw.TextStyle(font: bold, fontSize: 12.5), maxLines: 1),
      pw.Text('${s.line1}   ·   ${s.line2}', style: const pw.TextStyle(fontSize: 8.5), maxLines: 1),
      pw.SizedBox(height: 6),
      pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF6F3EE), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Text('Password:  ${s.password}', style: pw.TextStyle(font: bold, fontSize: 14, letterSpacing: 1.2))),
      pw.Spacer(),
      pw.Text(staff
          ? 'Open Royale Connect (app or $site) → “School staff? Sign in here” → your school email and this password → choose your own password.'
          : 'Open Royale Connect (app or $site) → sign in with the admission number and this password → choose your own password. Same login for both parents. Keep this slip private.',
          style: const pw.TextStyle(fontSize: 7, color: grey)),
    ]),
  );

  for (var at = 0; at < slips.length; at += 10) {
    final page = slips.sublist(at, math.min(at + 10, slips.length));
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(20),
      build: (_) => pw.Column(children: [
        for (var r = 0; r < 5; r++) pw.Expanded(child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          for (var c = 0; c < 2; c++) pw.Expanded(child: r * 2 + c < page.length ? slip(page[r * 2 + c]) : pw.SizedBox()),
        ])),
      ]),
    ));
  }
  return doc.save();
}
