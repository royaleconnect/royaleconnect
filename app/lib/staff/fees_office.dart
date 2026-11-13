import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/school_docs.dart' show openReceiptPdf;
import '../core/theme.dart';
import '../core/xlsx_writer.dart';
import '../widgets/common.dart';
import '../widgets/royal_extras.dart' show ShimmerPage;
import 'office_reports.dart' show ReportTable, wideTable, printReport;
import 'staff_data.dart';
import 'staff_shell.dart';

/// Fees desk extras for the office and accounts:
///   • Fee reports with Excel download (Payments · Month wise · Dues · Cancelled receipts · Concessions)
///   • "Remind everyone who hasn't paid" (once a day)
///   • Recent payments with "Cancel receipt…" (reason → the Principal approves in Approvals)
///   • Fee type of a student (Regular / RTE / Staff ward / Special) and, for RTE, waiving the fees still to come

String _msg(Object e) => e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');
String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String _dmy(String? iso) => iso == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());
String _dmt(String? iso) => iso == null ? '' : DateFormat('d MMM, h:mm a').format(DateTime.parse(iso).toLocal());
const _feeRoles = ['accounts', 'office', 'it_admin', 'principal', 'vice_principal'];
bool _feeStaff(Session? s) => s != null && _feeRoles.any(s.hasRole);

// ================================================================== fee type (RTE etc.)
const feeCategories = {'regular': 'Regular', 'rte': 'RTE', 'staff_ward': 'Staff ward', 'special': 'Special fee'};

/// Small pill for a non-regular fee type (nothing for Regular).
class FeeCategoryPill extends StatelessWidget {
  final String? category;
  const FeeCategoryPill(this.category, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = category ?? 'regular';
    if (c == 'regular') return const SizedBox.shrink();
    final (fg, bg) = switch (c) { 'rte' => (Brand.violet, Brand.violetTint), 'staff_ward' => (Brand.blue, Brand.blueTint), _ => (Brand.amber, Brand.amberTint) };
    return Pill(feeCategories[c] ?? c, fg: fg, bg: bg);
  }
}

final _feeCategoryProvider = FutureProvider.autoDispose.family<String, String>((ref, studentId) async {
  ref.cacheFor();
  final r = await db.from('student').select('fee_category').eq('id', studentId).maybeSingle();
  return (r?['fee_category'] ?? 'regular') as String;
});

/// Shown above a student's fees: the fee type (office / accounts can change it) and, for RTE students,
/// "Waive fees still to come" (one tap, a reason, written in the activity log).
class FeeCategoryBar extends ConsumerWidget {
  final String studentId;
  final VoidCallback? onChanged;
  const FeeCategoryBar({super.key, required this.studentId, this.onChanged});

  Future<void> _change(BuildContext context, WidgetRef ref, String cur) async {
    String pick = cur;
    final ok = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: const Text('Fee type'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [for (final e in feeCategories.entries) ChoiceChip(label: Text(e.value), selected: pick == e.key, onSelected: (_) => set(() => pick = e.key))]),
        const SizedBox(height: 10),
        const Text('This only marks the student. Fee amounts do not change by themselves.', style: TextStyle(fontSize: 12.5)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
    )));
    if (ok != true || pick == cur) return;
    try {
      await db.rpc('set_fee_category', params: {'p_student': studentId, 'p_category': pick});
      ref.invalidate(_feeCategoryProvider(studentId));
      onChanged?.call();
      if (context.mounted) toast(context, 'Fee type saved: ${feeCategories[pick]}.');
    } catch (e) { if (context.mounted) toast(context, _msg(e)); }
  }

  Future<void> _waive(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController(text: 'RTE admission');
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Waive fees still to come?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Every unpaid fee of this student due today or later is marked “waived”. Fees already overdue are not touched.'),
        const SizedBox(height: 12),
        TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Waive'))],
    ));
    if (ok != true) return;
    try {
      final r = Map<String, dynamic>.from(await db.rpc('waive_future_fees', params: {'p_student': studentId, 'p_reason': reason.text.trim()}) as Map);
      onChanged?.call();
      if (context.mounted) toast(context, r['rows'] == 0 ? 'No fees still to come.' : '${r['rows']} fees (${inr(r['amount'] as num)}) waived.');
    } catch (e) { if (context.mounted) toast(context, _msg(e)); }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    final cat = ref.watch(_feeCategoryProvider(studentId)).value;
    if (cat == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final can = _feeStaff(s) && !(s?.viewOnly ?? false);
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text('Fee type:', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
      cat == 'regular' ? const Pill('Regular', fg: Brand.muted, bg: Brand.surface2) : FeeCategoryPill(cat),
      if (can) TextButton(onPressed: () => _change(context, ref, cat), child: const Text('Change')),
      if (can && cat == 'rte') OutlinedButton.icon(onPressed: () => _waive(context, ref), icon: const Icon(Icons.volunteer_activism_rounded, size: 18), label: const Text('Waive fees still to come')),
    ]));
  }
}

// ================================================================== recent payments + cancel receipt
final feePaymentsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  final data = await db.from('payment').select('id,amount,mode,status,receipt_no,paid_at,student:student_id(full_name,admission_no,fee_category),receipt_cancel_request(status)')
      .eq('status', 'success').order('paid_at', ascending: false).limit(100);
  return List<Map<String, dynamic>>.from(data);
});

/// Accounts / office: ask for a receipt to be cancelled (reason required). The receipt stays valid until the Principal approves.
Future<void> askCancelReceipt(BuildContext context, WidgetRef ref, Map<String, dynamic> p) async {
  final reason = TextEditingController();
  final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
    title: Text('Cancel receipt ${p['receipt_no'] ?? ''}?'),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${p['student']?['full_name'] ?? ''} · ${inr(p['amount'] as num)} · ${_dmy(p['paid_at'])}'),
      const SizedBox(height: 12),
      TextField(controller: reason, autofocus: true, maxLines: 2, decoration: const InputDecoration(labelText: 'Why should it be cancelled?')),
      const SizedBox(height: 10),
      const NoteBox('The Principal must approve. Until then the receipt stays valid. After approval the fees it paid become unpaid again.'),
    ]),
    actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send to the Principal'))],
  ));
  if (ok != true) return;
  if (reason.text.trim().length < 3) { if (context.mounted) toast(context, 'Please write the reason.'); return; }
  try {
    await db.rpc('receipt_cancel_request', params: {'p_payment': p['id'], 'p_reason': reason.text.trim()});
    ref.invalidate(feePaymentsProvider);
    if (context.mounted) toast(context, 'Sent to the Principal for approval.');
  } catch (e) { if (context.mounted) toast(context, _msg(e)); }
}

/// "Recent payments" tab of the Fees desk.
class RecentPaymentsPanel extends ConsumerWidget {
  const RecentPaymentsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(sessionProvider).value;
    return ref.watch(feePaymentsProvider).when(
      loading: () => const ShimmerPage(),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(_msg(e), style: const TextStyle(color: Brand.crimsonDeep))),
      data: (rows) => Panel(padding: const EdgeInsets.all(12), child: rows.isEmpty ? Text('No payments yet.', style: TextStyle(color: cs.onSurfaceVariant)) : Column(children: [
        for (final p in rows) Builder(builder: (_) {
          final waiting = ((p['receipt_cancel_request'] as List?) ?? const []).any((k) => k['status'] == 'pending');
          return ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            onTap: () => openReceiptPdf(context, p['id'], receiptNo: p['receipt_no']),
            leading: Icon(Icons.receipt_long_rounded, color: waiting ? Brand.amber : Brand.green),
            title: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${p['receipt_no']} · ${p['student']?['full_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
              FeeCategoryPill(p['student']?['fee_category']),
              if (waiting) const Pill('Cancel waiting for Principal', fg: Brand.amber, bg: Brand.amberTint),
            ]),
            subtitle: Text('${p['mode']} · ${_dmt(p['paid_at'])} · tap for PDF'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(inr(p['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w800)),
              if (_feeStaff(s) && !waiting) PopupMenuButton<String>(tooltip: 'More', onSelected: (_) => askCancelReceipt(context, ref, p),
                  itemBuilder: (_) => const [PopupMenuItem(value: 'cancel', child: Text('Cancel this receipt…'))]),
            ]));
        }),
      ])),
    );
  }
}

// ================================================================== fee reports + Excel
typedef _RepKey = (String from, String to, String grade, String kind);

final _paymentsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, _RepKey>((ref, k) async {
  ref.cacheFor();
  final r = await db.rpc('fee_report_payments', params: {'p_from': k.$1, 'p_to': k.$2, 'p_grade': k.$3.isEmpty ? null : k.$3, 'p_kind': k.$4.isEmpty ? null : k.$4});
  return [for (final x in (r as List?) ?? const []) Map<String, dynamic>.from(x as Map)];
});
final _monthsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, grade) async {
  ref.cacheFor();
  final r = await db.rpc('fee_report_months', params: {'p_grade': grade.isEmpty ? null : grade});
  return [for (final x in (r as List?) ?? const []) Map<String, dynamic>.from(x as Map)];
});
final _cancelledProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, _RepKey>((ref, k) async {
  ref.cacheFor();
  final r = await db.rpc('fee_report_cancelled', params: {'p_from': k.$1, 'p_to': k.$2, 'p_grade': k.$3.isEmpty ? null : k.$3});
  return [for (final x in (r as List?) ?? const []) Map<String, dynamic>.from(x as Map)];
});
final _concessionsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, grade) async {
  ref.cacheFor();
  final r = await db.rpc('fee_report_concessions', params: {'p_grade': grade.isEmpty ? null : grade});
  return [for (final x in (r as List?) ?? const []) Map<String, dynamic>.from(x as Map)];
});

const _feeKinds = {'': 'All fees', 'tuition': 'Tuition', 'transport': 'Transport', 'misc': 'Activity / misc', 'late_fee': 'Late fee', 'other': 'Other'};
const _modeNames = {'upi': 'UPI', 'card': 'Card', 'netbanking': 'Net banking', 'wallet': 'Wallet', 'cash': 'Cash', 'cheque': 'Cheque', 'neft': 'NEFT', 'other': 'Other'};
String _mode(Object? m) => _modeNames['$m'] ?? '$m';

class StaffFeeReportsScreen extends ConsumerStatefulWidget {
  const StaffFeeReportsScreen({super.key});
  @override
  ConsumerState<StaffFeeReportsScreen> createState() => _StaffFeeReportsScreenState();
}

DateTime _yearStart() { final n = DateTime.now(); return DateTime(n.month >= 4 ? n.year : n.year - 1, 4, 1); }

final _failedTotalProvider = FutureProvider.autoDispose.family<num, _RepKey>((ref, k) async {
  ref.cacheFor();
  try { return (await db.rpc('fee_report_failed_total', params: {'p_from': k.$1, 'p_to': k.$2}) as num?) ?? 0; } catch (_) { return 0; }
});

class _StaffFeeReportsScreenState extends ConsumerState<StaffFeeReportsScreen> {
  int tab = 0;               // 0 payments · 1 month wise · 2 cancelled · 3 concessions
  String grade = '', kind = '';
  late DateTimeRange range = () { final n = DateTime.now(); return DateTimeRange(start: _yearStart(), end: DateTime(n.year, n.month, n.day)); }();
  bool busy = false;

  _RepKey get _key => (_iso(range.start), _iso(range.end), grade, kind);
  String get _yearLabel { final y = _yearStart().year; return '$y–${(y + 1) % 100}'; }
  bool get _tillDate => range.start == _yearStart() && range.end == DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  String get _rangeText {
    if (_tillDate) return 'Till date · from 1 Apr';
    final f = DateFormat('d MMM yyyy');
    return range.start == range.end ? f.format(range.start) : '${f.format(range.start)} – ${f.format(range.end)}';
  }

  Future<void> _pickRange() async {
    final n = DateTime.now();
    final r = await showDateRangePicker(context: context, initialDateRange: range, firstDate: DateTime(n.year - 3), lastDate: DateTime(n.year, n.month, n.day), helpText: 'Choose the dates');
    if (r != null) setState(() => range = r);
  }

  String _month(String ym) => DateFormat('MMMM yyyy').format(DateTime.parse('$ym-01'));
  String _paidBy(Map r) => r['by'] == 'Online' ? 'Online · ${_mode(r['mode'])}' : 'Office · ${_mode(r['mode'])}';
  num _sum(List<Map<String, dynamic>> l, String k) => l.fold<num>(0, (a, r) => a + ((r[k] ?? 0) as num));

  // the same rows feed the screen, the Excel file and the print-out
  (String, List<String>, List<List<String>>, List<(String, String)>) _sheet(List<Map<String, dynamic>> rows) {
    switch (tab) {
      case 0:
        final cancelled = ref.read(_cancelledProvider(_key)).value ?? const <Map<String, dynamic>>[];
        final failed = ref.read(_failedTotalProvider(_key)).value ?? 0;
        final col = _sum(rows, 'amount'), can = kind.isEmpty ? _sum(cancelled, 'amount') : 0;
        return ('Payments${kind.isEmpty ? '' : ' - ${_feeKinds[kind]}'}',
          ['Receipt no.', 'Date', 'Student', 'Class', 'Admission no.', 'Father', 'Fee', 'Paid by', 'Transaction ID', 'Amount'],
          [for (final r in rows) ['${r['receipt_no']}', _dmy(r['date']), '${r['student']}', '${r['class'] ?? ''}', '${r['admission_no'] ?? ''}', '${r['father'] ?? ''}',
            '${r['fees'] ?? feeCategories[r['fee_category']] ?? ''}', _paidBy(r), '${r['txn'] ?? ''}', inr(r['amount'] as num)]],
          [('Collected', inr(col)), ('Cancelled receipts', '- ${inr(can)}'), ('Failed payments (not counted)', inr(failed)), ('Net collection', inr(col - can))]);
      case 1:
        return ('Month wise', ['Month', 'UPI', 'Card / net banking', 'Cash / other', 'Cancelled', 'Net', 'Receipts'],
          [for (final r in rows.reversed) [_month(r['month']), inr(r['upi'] as num), inr(r['card'] as num), inr(r['other'] as num),
            ((r['cancelled'] ?? 0) as num) > 0 ? '- ${inr(r['cancelled'] as num)}' : '-', inr((r['upi'] as num) + (r['card'] as num) + (r['other'] as num)), '${r['receipts']}']],
          [('Total', inr(_sum(rows, 'upi') + _sum(rows, 'card') + _sum(rows, 'other')))]);
      case 2:
        return ('Cancelled receipts', ['Receipt no.', 'Paid on', 'Cancelled on', 'Student', 'Class', 'Reason', 'Asked by', 'Approved by', 'Amount'],
          [for (final r in rows) ['${r['receipt_no']}', _dmy(r['paid_on']), _dmy(r['cancelled_on']), '${r['student']}', '${r['class'] ?? ''}', '${r['reason'] ?? ''}',
            '${r['asked_by'] ?? '-'}', '${r['approved_by'] ?? '-'}', inr(r['amount'] as num)]],
          [('Total cancelled', inr(_sum(rows, 'amount')))]);
      default:
        return ('Concessions', ['Student', 'Admission no.', 'Class', 'Type', 'Note', 'Concession', 'Waived'],
          [for (final r in rows) ['${r['student']}', '${r['admission_no'] ?? ''}', '${r['class'] ?? ''}', feeCategories[r['fee_category']] ?? 'Regular', '${r['note'] ?? ''}',
            inr((r['concession'] ?? 0) as num), inr((r['waived'] ?? 0) as num)]],
          [('Total given up this year', inr(_sum(rows, 'concession') + _sum(rows, 'waived')))]);
    }
  }

  Future<void> _download(List<Map<String, dynamic>> rows) async {
    final className = grade.isEmpty ? 'All' : ((ref.read(gradesProvider).value ?? const []).where((g) => g['id'] == grade).firstOrNull?['code'] ?? '');
    final (name, head, data, totals) = _sheet(rows);
    const top = 'Royale Concorde International School, Kalyan Nagar';
    final dates = tab == 0 || tab == 2 ? '${_iso(range.start)}-to-${_iso(range.end)}' : 'as-on-${_iso(DateTime.now())}';
    setState(() => busy = true);
    try {
      await saveBytes(buildXlsx(name.length > 30 ? name.substring(0, 30) : name, head, [
        [top, for (var i = 1; i < head.length; i++) null],
        for (final r in data) [for (final c in r) c],
        for (final (k, v) in totals) [k, for (var i = 2; i < head.length; i++) null, v],
      ], widths: [for (final h in head) h == 'Fee' || h == 'Reason' || h == 'Note' ? 34.0 : h == 'Student' || h == 'Father' || h == 'Transaction ID' ? 24.0 : 14.0]),
        'RCIS-fees-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-$className-$dates.xlsx');
    } catch (e) { if (mounted) toast(context, 'Could not save the file: ${_msg(e)}'); }
    if (mounted) setState(() => busy = false);
  }

  void _print(List<Map<String, dynamic>> rows) {
    final (name, head, data, totals) = _sheet(rows);
    printReport(context, '$name · ${tab == 0 || tab == 2 ? _rangeText : _yearLabel}', head, data, totals: totals);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grades = ref.watch(gradesProvider).value ?? const <Map<String, dynamic>>[];
    final AsyncValue<List<Map<String, dynamic>>> data = switch (tab) {
      0 => ref.watch(_paymentsProvider(_key)), 1 => ref.watch(_monthsProvider(grade)),
      2 => ref.watch(_cancelledProvider(_key)), _ => ref.watch(_concessionsProvider(grade)) };
    final rows = data.value ?? const <Map<String, dynamic>>[];
    final narrow = isNarrow(context);
    final dated = tab == 0 || tab == 2;
    final can = !(busy || data.isLoading || rows.isEmpty);

    return StaffPage(title: 'Fee reports', subtitle: 'School year $_yearLabel · every receipt, month by month, cancelled receipts and concessions.',
      actions: [
        OutlinedButton.icon(onPressed: can ? () => _print(rows) : null, icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Print')),
        FilledButton.icon(onPressed: can ? () => _download(rows) : null, icon: const Icon(Icons.download_rounded, size: 18), label: Text(busy ? 'Please wait…' : 'Excel')),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(padding: const EdgeInsets.all(14), child: PickRow(children: [
        Expanded(child: InputDecorator(decoration: const InputDecoration(labelText: 'Year'), child: Text(_yearLabel, style: const TextStyle(fontWeight: FontWeight.w800)))),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: dated
            ? OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)), onPressed: _pickRange, icon: const Icon(Icons.date_range_rounded, size: 18), label: Text(_rangeText, overflow: TextOverflow.ellipsis))
            : InputDecorator(decoration: const InputDecoration(labelText: 'Dates'), child: const Text('Whole school year', style: TextStyle(fontWeight: FontWeight.w700)))),
        const SizedBox(width: 12),
        Expanded(child: PickField<String>(label: 'Class', value: grade, items: [
          const DropdownMenuItem(value: '', child: Text('All classes')),
          for (final g in grades) DropdownMenuItem(value: g['id'] as String, child: Text(g['name'] ?? g['code'] ?? '')),
        ], onChanged: (v) => setState(() => grade = v ?? ''))),
        if (tab == 0) ...[const SizedBox(width: 12), Expanded(child: PickField<String>(label: 'Fee', value: kind,
            items: [for (final e in _feeKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => setState(() => kind = v ?? '')))],
      ])),
      const SizedBox(height: 4),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: SegmentedButton<int>(showSelectedIcon: false, segments: [
        const ButtonSegment(value: 0, label: Text('Payments')),
        ButtonSegment(value: 1, label: Text(narrow ? 'Months' : 'Month wise')),
        ButtonSegment(value: 2, label: Text(narrow ? 'Cancelled' : 'Cancelled receipts')),
        const ButtonSegment(value: 3, label: Text('Concessions')),
      ], selected: {tab}, onSelectionChanged: (v) => setState(() => tab = v.first))),
      const SizedBox(height: 16),
      data.when(
        loading: () => const ShimmerPage(),
        error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(_msg(e), style: const TextStyle(color: Brand.crimsonDeep))),
        data: (rows) => _table(rows, cs),
      ),
      const SizedBox(height: 6),
      Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => GoRouter.of(context).go('/staff/fees/dues'),
          icon: const Icon(Icons.pending_actions_rounded, size: 18), label: const Text('What is still to be paid → Fee dues'))),
    ]));
  }

  Widget _empty(String t) => Panel(child: Text(t, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)));

  Widget _table(List<Map<String, dynamic>> rows, ColorScheme cs) {
    if (rows.isEmpty) {
      return _empty(switch (tab) { 0 => 'No receipts on these dates${kind.isEmpty ? '' : ' for ${_feeKinds[kind]}'}.', 1 => 'Nothing yet this school year.',
        2 => 'No receipts were cancelled on these dates.', _ => 'No concessions this year.' });
    }
    Widget two(String a, String b) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(a, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
      if (b.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(b, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)))]);
    Text t(Object? v, {int lines = 1}) => Text('${v ?? ''}', maxLines: lines, overflow: TextOverflow.ellipsis);
    Text money(num v, {bool b = true, Color? c, bool strike = false}) => Text(inr(v), style: TextStyle(fontWeight: b ? FontWeight.w900 : FontWeight.w600,
        color: c == null ? null : context.tone(c), decoration: strike ? TextDecoration.lineThrough : null));

    switch (tab) {
      case 0:
        final cancelled = ref.watch(_cancelledProvider(_key)).value ?? const <Map<String, dynamic>>[];
        final failed = ref.watch(_failedTotalProvider(_key)).value ?? 0;
        final col = _sum(rows, 'amount'), can = kind.isEmpty ? _sum(cancelled, 'amount') : 0;
        Widget tot(String k, String v, {Color? c, bool big = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w600, fontSize: big ? 15 : 13.5))),
          Text(v, style: TextStyle(fontWeight: FontWeight.w900, fontSize: big ? 20 : 14, color: c == null ? null : context.tone(c)))]));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Panel(title: '${rows.length} receipts', padding: const EdgeInsets.all(14), child: wideTable(context, ReportTable(
            cols: const [('Receipt no.', 3, false), ('Date', 2, false), ('Student', 4, false), ('Admission no.', 3, false), ('Father', 3, false),
              ('Fee', 4, false), ('Paid by', 3, false), ('Transaction ID', 3, false), ('Amount', 3, true)],
            rows: [for (final r in rows) [
              t(r['receipt_no']), t(_dmy(r['date'])), two('${r['student']}', '${r['class'] ?? ''}'), t(r['admission_no']), t(r['father']),
              t(r['fees'] ?? feeCategories[r['fee_category']] ?? '', lines: 2), t(_paidBy(r)),
              Text('${r['txn'] ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              money(r['amount'] as num)]],
            onTap: [for (final r in rows) () => openReceiptPdf(context, r['id'], receiptNo: r['receipt_no'])]), min: 1100)),
          Align(alignment: Alignment.centerRight, child: Container(width: 380, margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: BoxDecoration(color: Brand.gold.withValues(alpha: .06), borderRadius: BorderRadius.circular(18), border: Border.all(color: Brand.gold.withValues(alpha: .3))),
            child: Column(children: [
              tot('Collected', inr(col)),
              if (kind.isEmpty) tot('Cancelled receipts', '− ${inr(can)}', c: Brand.crimsonDeep),
              tot('Failed payments (not counted)', inr(failed), c: Brand.amber),
              const Divider(height: 18),
              tot('Net collection', inr(col - can), c: Brand.green, big: true),
            ]))),
        ]);
      case 1:
        return Panel(padding: const EdgeInsets.all(14), child: wideTable(context, ReportTable(
          cols: const [('Month', 4, false), ('UPI', 3, true), ('Card / net banking', 3, true), ('Cash / other', 3, true), ('Cancelled', 3, true), ('Net', 3, true), ('Receipts', 2, true)],
          rows: [
            for (final r in rows.reversed) [Text(_month(r['month']), style: const TextStyle(fontWeight: FontWeight.w700)), money(r['upi'] as num, b: false), money(r['card'] as num, b: false),
              money(r['other'] as num, b: false), ((r['cancelled'] ?? 0) as num) > 0 ? Text('− ${inr(r['cancelled'] as num)}', style: TextStyle(color: context.tone(Brand.crimsonDeep))) : const Text('—'),
              money((r['upi'] as num) + (r['card'] as num) + (r['other'] as num)), t(r['receipts'])],
            [const Text('Total'), money(_sum(rows, 'upi')), money(_sum(rows, 'card')), money(_sum(rows, 'other')),
              Text(_sum(rows, 'cancelled') > 0 ? '− ${inr(_sum(rows, 'cancelled'))}' : '—', style: TextStyle(color: context.tone(Brand.crimsonDeep))),
              money(_sum(rows, 'upi') + _sum(rows, 'card') + _sum(rows, 'other'), c: Brand.green), t(_sum(rows, 'receipts'))],
          ], totals: {rows.length}), min: 820));
      case 2:
        return Panel(title: '${rows.length} cancelled · ${inr(_sum(rows, 'amount'))}', padding: const EdgeInsets.all(14), child: wideTable(context, ReportTable(
          cols: const [('Receipt no.', 3, false), ('Paid / cancelled', 3, false), ('Student', 4, false), ('Reason', 5, false), ('Asked / approved by', 4, false), ('Amount', 3, true)],
          rows: [for (final r in rows) [t(r['receipt_no']), two(_dmy(r['paid_on']), 'cancelled ${_dmy(r['cancelled_on'])}'), two('${r['student']}', '${r['class'] ?? ''}'),
            t(r['reason'], lines: 2), two('${r['asked_by'] ?? '—'}', 'approved by ${r['approved_by'] ?? '—'}'), money(r['amount'] as num, strike: true)]]), min: 960));
      default:
        return Panel(title: '${rows.length} students · ${inr(_sum(rows, 'concession') + _sum(rows, 'waived'))} given up this year', padding: const EdgeInsets.all(14), child: wideTable(context, ReportTable(
          cols: const [('Student', 4, false), ('Admission no.', 3, false), ('Type', 3, false), ('Note', 5, false), ('Concession', 3, true), ('Waived', 2, true)],
          rows: [
            for (final r in rows) [two('${r['student']}', '${r['class'] ?? ''}'), t(r['admission_no']), FeeCategoryPill(r['fee_category']), t(r['note'], lines: 2),
              money((r['concession'] ?? 0) as num), ((r['waived'] ?? 0) as num) > 0 ? money(r['waived'] as num, b: false) : const Text('—')],
            [const Text('Total'), const Text(''), const Text(''), const Text(''), money(_sum(rows, 'concession'), c: Brand.violet), money(_sum(rows, 'waived'), b: false)],
          ], totals: {rows.length}), min: 900));
    }
  }
}
