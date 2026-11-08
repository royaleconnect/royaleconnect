import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/config.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/school_docs.dart' show PdfDocScreen;
import '../core/theme.dart';
import '../screens/family_screens.dart' show StorageImage;
import '../widgets/common.dart' show Avatar, Pill, NoteBox;
import 'staff_data.dart';
import 'staff_shell.dart';

/// Class logins: the class teacher sees her own class — each child's first password to read out on a call
/// ("ana@8919"), or "Changed by family ✓" once the family has set their own (then nobody can see it).
/// Reset gives a new first password. "Print slips" prints the whole class, 10 to a page.
/// The office / IT can open any class.

final classLoginsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, sectionId) async {
  ref.cacheFor();
  return Map<String, dynamic>.from(await db.rpc('class_logins', params: {'p_section': sectionId}) as Map);
});

class ClassLoginsScreen extends ConsumerStatefulWidget {
  const ClassLoginsScreen({super.key});
  @override
  ConsumerState<ClassLoginsScreen> createState() => _ClassLoginsScreenState();
}

class _ClassLoginsScreenState extends ConsumerState<ClassLoginsScreen> {
  String? sectionId; bool busy = false;

  Future<void> _reset(Map<String, dynamic> st) async {
    setState(() => busy = true);
    final done = await resetFirstPassword(context, ref, '${st['id']}', '${st['name'] ?? ''}', familyChanged: st['state'] == 'changed');
    if (done) ref.invalidate(classLoginsProvider(sectionId!));
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value;
    final cs = Theme.of(context).colorScheme;
    final me = s?.staff?['id'];
    final office = (s?.hasRole('office') ?? false) || (s?.hasRole('it_admin') ?? false);
    final secsAsync = ref.watch(mySectionsProvider);
    final secs = secsAsync.value ?? const <Map<String, dynamic>>[];
    final list = office ? secs : [for (final x in secs) if (x['class_teacher_id'] == me) x];
    if (sectionId == null && list.isNotEmpty) sectionId = list.first['id'] as String;
    final data = sectionId == null ? null : ref.watch(classLoginsProvider(sectionId!));
    final label = '${data?.value?['label'] ?? (list.where((x) => x['id'] == sectionId).map(sectionLabel).firstOrNull ?? '')}';

    return StaffPage(title: 'Class logins', subtitle: 'First passwords for your class. Read one out on a call, reset a forgotten one, or print slips.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (list.length > 1) Panel(padding: const EdgeInsets.all(12), child: PickField<String>(label: 'Class', value: sectionId,
            items: [for (final x in list) DropdownMenuItem(value: x['id'] as String, child: Text(sectionLabel(x)))], onChanged: (v) => setState(() => sectionId = v))),
        if (secsAsync.hasValue && list.isEmpty) const NoteBox('First passwords are looked after by the class teacher. You are not class teacher of a class this year.')
        else if (data == null || data.isLoading) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
        else if (data.hasError) NoteBox(friendlyError(data.error))
        else Builder(builder: (_) {
          final kids = [for (final x in (data.value!['students'] as List? ?? const [])) Map<String, dynamic>.from(x)];
          final changed = kids.where((k) => k['state'] == 'changed').length;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Panel(padding: const EdgeInsets.fromLTRB(14, 6, 8, 6), child: kids.isEmpty
                ? Padding(padding: const EdgeInsets.all(12), child: Text('No students in this class yet.', style: TextStyle(color: cs.onSurfaceVariant)))
                : Column(children: [for (final (i, k) in kids.indexed) ...[
                    if (i > 0) Divider(height: 1, color: cs.outline.withValues(alpha: .4)),
                    _LoginRow(k: k, busy: busy, onReset: () => _reset(k)),
                  ]])),
            if (kids.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(
              '${kids.length} students${changed > 0 ? ' · $changed changed by family' : ''}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
            if (kids.isNotEmpty) OutlinedButton.icon(onPressed: busy ? null : () async {
                setState(() => busy = true);
                await printClassSlips(context, ref, sectionId!, label);
                if (mounted) setState(() => busy = false);
              },
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              icon: const Icon(Icons.print_rounded), label: Text('Print slips for $label')),
            const SizedBox(height: 12),
            Text('“Changed by family ✓” means the family has set their own password — nobody at school can see it. Reset gives a new first password if they forget it.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ]);
        }),
      ]));
  }
}

class _LoginRow extends StatelessWidget {
  final Map<String, dynamic> k; final bool busy; final VoidCallback onReset;
  const _LoginRow({required this.k, required this.busy, required this.onReset});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = '${k['name'] ?? ''}';
    final photo = k['photo'] as String?;
    final initials = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final Widget status = switch (k['state']) {
      'first' => Container(
          margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: Brand.gold.withValues(alpha: .16), borderRadius: BorderRadius.circular(8), border: Border.all(color: Brand.gold.withValues(alpha: .5))),
          child: SelectableText('🔑 ${k['password']}', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: .6))),
      'changed' => const Padding(padding: EdgeInsets.only(top: 4), child: Pill('Changed by family ✓', fg: Brand.green, bg: Brand.greenTint)),
      _ => const Padding(padding: EdgeInsets.only(top: 4), child: Pill('No first password yet', fg: Brand.amber, bg: Brand.amberTint)),
    };
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
      (photo != null && photo.isNotEmpty) ? StorageImage(photo, width: 42, height: 42, radius: BorderRadius.circular(14)) : Avatar(initials, size: 42),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text('${k['admission_no'] ?? ''}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        Align(alignment: Alignment.centerLeft, child: status),
      ])),
      TextButton(onPressed: busy ? null : onReset, style: TextButton.styleFrom(foregroundColor: Brand.crimson),
        child: const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.refresh_rounded), Text('Reset', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700))])),
    ]));
  }
}

/// Reset one child's password to a new first password ("ana@8919") and show it big. Used here, on Students and for
/// "forgot password" requests. Allowed for the child's class teacher, the office and IT (the database checks).
/// Returns true when a new password was made.
Future<bool> resetFirstPassword(BuildContext context, WidgetRef ref, String studentId, String name, {bool familyChanged = false}) async {
  if (familyChanged) {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Reset $name?'),
      content: const Text('The family has set their own password. It will stop working, and their phones are signed out. Reset only if they asked for it.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Reset'))],
    ));
    if (ok != true) return false;
  }
  try {
    final r = Map<String, dynamic>.from(await db.rpc('class_login_reset', params: {'p_student': studentId}) as Map);
    HapticFeedback.mediumImpact();
    if (context.mounted) await showFirstPassword(context, '${r['name'] ?? name}', '${r['password']}');
    return true;
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
    return false;
  }
}

/// The new first password, big, to read out on the phone.
Future<void> showFirstPassword(BuildContext context, String name, String password) => showModalBottomSheet<void>(
  context: context, showDragHandle: true, isScrollControlled: true,
  builder: (c) {
    final cs = Theme.of(c).colorScheme;
    return SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
      const SizedBox(height: 4),
      Text('New first password', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Text('Read this to the parent on the call. They choose their own password at the first sign-in.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 18),
      Container(padding: const EdgeInsets.symmetric(vertical: 18), decoration: BoxDecoration(color: Brand.gold.withValues(alpha: .14), borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.gold.withValues(alpha: .6))),
        child: SelectableText(password, textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'monospace', fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 2))),
      const SizedBox(height: 18),
      FilledButton(onPressed: () => Navigator.pop(c), style: FilledButton.styleFrom(backgroundColor: Brand.crimson, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('Done')),
    ])));
  },
);

/// "Print slips for VIII-B": children with no first password yet (and not using the app) get one, then every child
/// with a first password gets a slip. Families who set their own password need no slip. Usable from any staff page.
Future<void> printClassSlips(BuildContext context, WidgetRef ref, String sectionId, String label) async {
  try {
    var data = Map<String, dynamic>.from(await db.rpc('class_logins', params: {'p_section': sectionId}) as Map);
    List<Map<String, dynamic>> kids() => [for (final x in (data['students'] as List? ?? const [])) Map<String, dynamic>.from(x)];
    final missing = kids().where((k) => k['state'] == 'none').length;
    if (missing > 0) {
      if (!context.mounted) return;
      final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: Text('Make $missing first ${missing == 1 ? 'password' : 'passwords'}?'),
        content: Text('$missing ${missing == 1 ? 'child has' : 'children have'} no first password yet. New ones are made now and printed. Any older slip for ${missing == 1 ? 'this child' : 'them'} stops working.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Make and print'))],
      ));
      if (ok != true) return;
      await db.rpc('class_logins_fill', params: {'p_section': sectionId});
      data = Map<String, dynamic>.from(await db.rpc('class_logins', params: {'p_section': sectionId}) as Map);
      ref.invalidate(classLoginsProvider(sectionId));
    }
    final slips = [for (final k in kids()) if (k['state'] == 'first') PasswordSlip('${k['name']}', 'Class ${data['label'] ?? label}', 'Admission no. ${k['admission_no']}', '${k['password']}')];
    if (!context.mounted) return;
    if (slips.isEmpty) { toast(context, 'Every family in $label already uses their own password — no slips needed.'); return; }
    await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PdfDocScreen(
      title: 'Password slips · ${data['label'] ?? label} (${slips.length})',
      fileName: 'RCIS-password-slips-${'${data['label'] ?? label}'.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '')}.pdf',
      make: () => passwordSlipsPdf(slips, staff: false),
    )));
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
  }
}

// ------------------------------------------------------------------ password slips PDF (A4, 10 per page) — also used by Import from Excel
class PasswordSlip {
  final String title, line1, line2, password;
  const PasswordSlip(this.title, this.line1, this.line2, this.password);
}

Future<Uint8List> passwordSlipsPdf(List<PasswordSlip> slips, {required bool staff}) async {
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
  final steps = staff
      ? ['Open $site (or the Royale Connect app).', 'Tap “School staff? Sign in here” — your school email and this password.', 'Choose your own password.']
      : ['Open $site (or the Royale Connect app).', 'Sign in with the admission number and this password.', 'Choose your own password. Same login for both parents. Keep this slip private.'];

  pw.Widget slip(PasswordSlip s) => pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 8),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: line, width: .6, style: pw.BorderStyle.dashed)),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(AppConfig.schoolName, style: pw.TextStyle(font: bold, fontSize: 8.5, color: crimson)),
      pw.Text('Royale Connect · first password', style: const pw.TextStyle(fontSize: 7.5, color: grey)),
      pw.SizedBox(height: 5),
      pw.Text(s.title, style: pw.TextStyle(font: bold, fontSize: 12.5), maxLines: 1),
      pw.Text('${s.line1}   ·   ${s.line2}', style: const pw.TextStyle(fontSize: 8.5), maxLines: 1),
      pw.SizedBox(height: 5),
      pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF6F3EE), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Text('Password:  ${s.password}', style: pw.TextStyle(font: bold, fontSize: 14, letterSpacing: 1.2))),
      pw.Spacer(),
      for (final (i, t) in steps.indexed) pw.Text('${i + 1}. $t', style: const pw.TextStyle(fontSize: 7, color: grey), maxLines: 2),
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
