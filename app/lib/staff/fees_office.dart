import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/school_docs.dart' show openReceiptPdf;
import '../core/theme.dart';
import '../core/xlsx_writer.dart';
import '../widgets/common.dart';
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
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
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
final _duesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, grade) async {
  ref.cacheFor();
  final r = await db.rpc('fee_report_dues', params: {'p_grade': grade.isEmpty ? null : grade});
  return [for (final x in (r as List?) ?? const []) Map<String, dynamic>.from(x as Map)];
});
final _failedProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  try { return [for (final x in (await db.rpc('fee_report_failed')) as List? ?? const []) Map<String, dynamic>.from(x as Map)]; } catch (_) { return const []; }
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

class _StaffFeeReportsScreenState extends ConsumerState<StaffFeeReportsScreen> {
  int tab = 0;               // 0 payments · 1 month wise · 2 dues · 3 cancelled · 4 concessions
  String grade = '', kind = '';
  late DateTimeRange range = () { final n = DateTime.now(); final d = DateTime(n.year, n.month, n.day); return DateTimeRange(start: DateTime(d.year, d.month, 1), end: d); }();
  bool busy = false;

  _RepKey get _key => (_iso(range.start), _iso(range.end), grade, kind);

  String get _rangeText {
    final f = DateFormat('d MMM yyyy');
    return range.start == range.end ? f.format(range.start) : '${f.format(range.start)} – ${f.format(range.end)}';
  }

  Future<void> _pickRange() async {
    final n = DateTime.now();
    final r = await showDateRangePicker(context: context, initialDateRange: range, firstDate: DateTime(n.year - 3), lastDate: DateTime(n.year, n.month, n.day), helpText: 'Choose the dates');
    if (r != null) setState(() => range = r);
  }

  String _month(String ym) => DateFormat('MMMM yyyy').format(DateTime.parse('$ym-01'));

  Future<void> _download(List<Map<String, dynamic>> rows) async {
    final className = grade.isEmpty ? 'All' : ((ref.read(gradesProvider).value ?? const []).where((g) => g['id'] == grade).firstOrNull?['code'] ?? '');
    final String name; final List<String> head; final List<List<Object?>> data; final List<double> widths;
    const top = 'Royale Concorde International School, Kalyan Nagar';
    switch (tab) {
      case 0:
        name = 'Payments${kind.isEmpty ? '' : ' - ${_feeKinds[kind]}'}'; head = ['Receipt no', 'Date', 'Student', 'Admission no', 'Class', 'Amount (₹)', 'Mode', 'Paid', 'Advance', 'Fee type'];
        widths = [20, 12, 26, 14, 9, 13, 12, 9, 9, 12];
        data = [[top, null, null, null, null, null, null, null, null, null],
          for (final r in rows) [r['receipt_no'], r['date'], r['student'], r['admission_no'], r['class'], r['amount'], _mode(r['mode']), r['by'], r['advance'] == true ? 'Yes' : '', feeCategories[r['fee_category']] ?? '']];
        data.add(['', '', 'Total', '', '', rows.fold<num>(0, (a, r) => a + (r['amount'] as num)), '', '', '', '']);
      case 1:
        name = 'Month wise'; head = ['Month', 'UPI (₹)', 'Card / net banking (₹)', 'Other (₹)', 'Cancelled (₹)', 'Net (₹)', 'Receipts'];
        widths = [18, 14, 20, 12, 14, 14, 10];
        data = [[top, null, null, null, null, null, null],
          for (final r in rows) [_month(r['month']), r['upi'], r['card'], r['other'], r['cancelled'], (r['upi'] as num) + (r['card'] as num) + (r['other'] as num), r['receipts']]];
      case 2:
        name = 'Dues'; head = ['Student', 'Admission no', 'Class', 'Phones', 'This year (₹)', 'Late fee (₹)', 'Last year (₹)', 'Total due (₹)', 'Due since', 'Fees due', 'Fee type'];
        widths = [26, 14, 9, 34, 13, 12, 12, 13, 12, 50, 12];
        data = [[top, null, null, null, null, null, null, null, null, null, null],
          for (final r in rows) [r['student'], r['admission_no'], r['class'], r['phones'], (r['overdue'] as num) - ((r['last_year'] ?? 0) as num), r['late_fee'], r['last_year'], r['overdue'], r['first_due'], r['items'], feeCategories[r['fee_category']] ?? '']];
        data.add(['Grand total', '', '', '', null, rows.fold<num>(0, (a, r) => a + ((r['late_fee'] ?? 0) as num)), rows.fold<num>(0, (a, r) => a + ((r['last_year'] ?? 0) as num)),
          rows.fold<num>(0, (a, r) => a + (r['overdue'] as num)), '', '', '']);
      case 3:
        name = 'Cancelled receipts'; head = ['Receipt no', 'Paid on', 'Cancelled on', 'Student', 'Class', 'Amount (₹)', 'Mode', 'Reason', 'Asked by', 'Approved by'];
        widths = [20, 12, 12, 26, 9, 13, 11, 40, 18, 18];
        data = [[top, null, null, null, null, null, null, null, null, null],
          for (final r in rows) [r['receipt_no'], r['paid_on'], r['cancelled_on'], r['student'], r['class'], r['amount'], _mode(r['mode']), r['reason'], r['asked_by'], r['approved_by']]];
      default:
        name = 'Concessions'; head = ['Student', 'Admission no', 'Class', 'Fee type', 'Concession (₹)', 'Waived (₹)', 'Note'];
        widths = [26, 14, 9, 14, 14, 12, 40];
        data = [[top, null, null, null, null, null, null],
          for (final r in rows) [r['student'], r['admission_no'], r['class'], feeCategories[r['fee_category']] ?? '', r['concession'], r['waived'], r['note']]];
    }
    final dates = tab == 2 || tab == 4 || tab == 1 ? 'as-on-${_iso(DateTime.now())}' : '${_iso(range.start)}-to-${_iso(range.end)}';
    setState(() => busy = true);
    try {
      await saveBytes(buildXlsx(name.length > 30 ? name.substring(0, 30) : name, head, data, widths: widths), 'RCIS-fees-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-$className-$dates.xlsx');
    } catch (e) { if (mounted) toast(context, 'Could not save the file: ${_msg(e)}'); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _remindAll() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Remind everyone who hasn’t paid?'),
      content: const Text('Every family with an overdue fee (all classes) gets one notification with the amount overdue. This can be sent once a day.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send reminders'))],
    ));
    if (ok != true) return;
    try {
      final n = await db.rpc('fee_remind_overdue');
      if (mounted) toast(context, 'Reminder sent to $n ${n == 1 ? 'family' : 'families'} ✓');
    } catch (e) { if (mounted) toast(context, _msg(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grades = ref.watch(gradesProvider).value ?? const <Map<String, dynamic>>[];
    final AsyncValue<List<Map<String, dynamic>>> data = switch (tab) {
      0 => ref.watch(_paymentsProvider(_key)), 1 => ref.watch(_monthsProvider(grade)), 2 => ref.watch(_duesProvider(grade)),
      3 => ref.watch(_cancelledProvider(_key)), _ => ref.watch(_concessionsProvider(grade)) };
    final rows = data.value ?? const <Map<String, dynamic>>[];
    final narrow = isNarrow(context);
    final dated = tab == 0 || tab == 3;

    return StaffPage(title: 'Fee reports', subtitle: 'Payments, month by month, dues, cancelled receipts and concessions — download any of them as an Excel file.', body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: SegmentedButton<int>(showSelectedIcon: false, segments: [
        const ButtonSegment(value: 0, label: Text('Payments')),
        ButtonSegment(value: 1, label: Text(narrow ? 'Months' : 'Month wise')),
        const ButtonSegment(value: 2, label: Text('Dues')),
        ButtonSegment(value: 3, label: Text(narrow ? 'Cancelled' : 'Cancelled receipts')),
        const ButtonSegment(value: 4, label: Text('Concessions')),
      ], selected: {tab}, onSelectionChanged: (v) => setState(() => tab = v.first))),
      const SizedBox(height: 14),
      Panel(padding: const EdgeInsets.all(12), child: PickRow(children: [
        if (dated) Expanded(child: OutlinedButton.icon(onPressed: _pickRange, icon: const Icon(Icons.date_range_rounded, size: 18), label: Text(_rangeText, overflow: TextOverflow.ellipsis)))
        else Expanded(child: Text(tab == 2 ? 'Overdue as on today' : 'This school year', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
        const SizedBox(width: 12),
        Expanded(child: PickField<String>(label: 'Class', value: grade, items: [
          const DropdownMenuItem(value: '', child: Text('All classes')),
          for (final g in grades) DropdownMenuItem(value: g['id'] as String, child: Text(g['name'] ?? g['code'] ?? '')),
        ], onChanged: (v) => setState(() => grade = v ?? ''))),
        if (tab == 0) ...[const SizedBox(width: 12), Expanded(child: PickField<String>(label: 'Fee', value: kind,
            items: [for (final e in _feeKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => setState(() => kind = v ?? '')))],
        const SizedBox(width: 12),
        FilledButton.icon(onPressed: busy || data.isLoading || rows.isEmpty ? null : () => _download(rows), icon: const Icon(Icons.download_rounded, size: 18), label: Text(busy ? 'Please wait…' : 'Excel')),
      ])),
      data.when(
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
        error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(_msg(e), style: const TextStyle(color: Brand.crimsonDeep))),
        data: (rows) => switch (tab) { 0 => _payments(rows), 1 => _months(rows), 2 => _dues(rows), 3 => _cancelled(rows), _ => _concessions(rows) },
      ),
    ]));
  }

  Widget _empty(String t) => Panel(child: Text(t, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)));
  Widget _sub(String t) => Text(t, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant));
  Widget _total(String label, num v, {Color? c, bool big = false}) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
    Expanded(child: Text(label, style: TextStyle(fontWeight: big ? FontWeight.w900 : FontWeight.w600))),
    Text(inr(v), style: TextStyle(fontWeight: FontWeight.w900, fontSize: big ? 17 : 14, color: c == null ? null : context.tone(c))),
  ]));

  Widget _payments(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _empty('No receipts on these dates${kind.isEmpty ? '' : ' for ${_feeKinds[kind]}'}.');
    final total = rows.fold<num>(0, (a, r) => a + (r['amount'] as num));
    final byMode = <String, num>{};
    for (final r in rows) { byMode[_mode(r['mode'])] = (byMode[_mode(r['mode'])] ?? 0) + (r['amount'] as num); }
    final adv = rows.where((r) => r['advance'] == true).length;
    final cancelled = ref.watch(_cancelledProvider(_key)).value ?? const <Map<String, dynamic>>[];
    final cAmt = cancelled.fold<num>(0, (a, r) => a + (r['amount'] as num));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(padding: const EdgeInsets.all(16), child: Column(children: [
        _total('Collected · ${rows.length} receipts${kind.isEmpty ? '' : ' · ${_feeKinds[kind]} part only'}', total),
        for (final e in byMode.entries) Padding(padding: const EdgeInsets.only(left: 12), child: _total('   ${e.key}', e.value)),
        if (kind.isEmpty) _total('Cancelled (approved by the Principal)', -cAmt, c: Brand.crimsonDeep),
        const Divider(),
        _total('Net', total - (kind.isEmpty ? cAmt : 0), big: true, c: Brand.green),
        if (adv > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Align(alignment: Alignment.centerLeft, child: _sub('$adv paid ahead of the due date — marked “Advance”.'))),
      ])),
      Panel(padding: const EdgeInsets.all(12), child: Column(children: [
        for (final r in rows) ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${r['student']} · ${r['class'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)), FeeCategoryPill(r['fee_category']),
            if (r['advance'] == true) const Pill('Advance', fg: Brand.blue, bg: Brand.blueTint)]),
          subtitle: _sub('${r['receipt_no']} · ${_dmy(r['date'])} · ${_mode(r['mode'])} · ${r['by']}${kind.isNotEmpty && r['total'] != r['amount'] ? ' · receipt ${inr(r['total'] as num)}' : ''}'),
          trailing: Text(inr(r['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w800)),
          onTap: () => openReceiptPdf(context, r['id'], receiptNo: r['receipt_no'])),
      ])),
    ]);
  }

  Widget _months(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _empty('Nothing yet this school year.');
    final cs = Theme.of(context).colorScheme;
    num s(String k) => rows.fold<num>(0, (a, r) => a + ((r[k] ?? 0) as num));
    Widget cell(String t, {bool b = false, bool right = true, Color? c}) => Expanded(child: Text(t, textAlign: right ? TextAlign.right : TextAlign.left,
        style: TextStyle(fontWeight: b ? FontWeight.w900 : FontWeight.w600, color: c == null ? null : context.tone(c), fontSize: 13.5)));
    Widget line(List<Widget> cells, {bool head = false}) => Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(color: head ? Brand.gold.withValues(alpha: .08) : null, border: head ? null : Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .6)))),
        child: Row(children: cells));
    final table = Column(children: [
      line([cell('MONTH', b: true, right: false), cell('UPI', b: true), cell('CARD / NET BANKING', b: true), cell('CANCELLED', b: true), cell('NET', b: true)], head: true),
      for (final r in rows.reversed) line([
        cell(_month(r['month']), right: false), cell(inr(r['upi'] as num)), cell(inr((r['card'] as num) + (r['other'] as num))),
        cell(((r['cancelled'] ?? 0) as num) > 0 ? '− ${inr(r['cancelled'] as num)}' : '—', c: Brand.crimsonDeep),
        cell(inr((r['upi'] as num) + (r['card'] as num) + (r['other'] as num)), b: true)]),
      line([cell('Total', b: true, right: false), cell(inr(s('upi')), b: true), cell(inr(s('card') + s('other')), b: true), cell(s('cancelled') > 0 ? '− ${inr(s('cancelled'))}' : '—', b: true, c: Brand.crimsonDeep),
        cell(inr(s('upi') + s('card') + s('other')), b: true, c: Brand.green)]),
    ]);
    return Panel(padding: const EdgeInsets.all(12), child: isNarrow(context) ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: 640, child: table)) : table);
  }

  Widget _dues(List<Map<String, dynamic>> rows) {
    final s = ref.watch(sessionProvider).value;
    final failed = ref.watch(_failedProvider).value ?? const <Map<String, dynamic>>[];
    final total = rows.fold<num>(0, (a, r) => a + (r['overdue'] as num));
    final late = rows.fold<num>(0, (a, r) => a + ((r['late_fee'] ?? 0) as num));
    final last = rows.fold<num>(0, (a, r) => a + ((r['last_year'] ?? 0) as num));
    final lastRows = rows.where((r) => ((r['last_year'] ?? 0) as num) > 0).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_feeStaff(s) && !(s?.viewOnly ?? false)) Panel(padding: const EdgeInsets.all(12), child: CardRow(children: [
        const Icon(Icons.notifications_active_rounded, color: Brand.amber), const SizedBox(width: 10),
        Expanded(child: _sub('Families are reminded by themselves 3 days before each due date. Use this for everyone who is already late.')),
        const SizedBox(width: 10),
        FilledButton.icon(onPressed: _remindAll, icon: const Icon(Icons.send_rounded, size: 18), label: const Text('Remind all who haven’t paid')),
      ])),
      if (rows.isEmpty) _empty('No overdue fees ✓')
      else ...[
        Panel(padding: const EdgeInsets.all(16), child: Column(children: [
          _total('This year · ${rows.length} students', total - last),
          _total('   of which late fee', late, c: Brand.amber),
          if (last > 0) _total('Pending from last year · ${lastRows.length} students', last),
          const Divider(),
          _total('Grand total', total, big: true, c: Brand.crimsonDeep),
        ])),
        Panel(title: '${rows.length} students · ${inr(total)} overdue', padding: const EdgeInsets.all(12), child: Column(children: [
          for (final r in rows) ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${r['student']} · ${r['class'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)), FeeCategoryPill(r['fee_category']),
              if (((r['last_year'] ?? 0) as num) > 0) Pill('Last year ${inr(r['last_year'] as num)}', fg: Brand.violet, bg: Brand.violetTint)]),
            subtitle: _sub('${r['items'] ?? ''}${(r['phones'] ?? '').toString().isNotEmpty ? '\n${r['phones']}' : ''}'),
            isThreeLine: (r['phones'] ?? '').toString().isNotEmpty,
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(inr(r['overdue'] as num), style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(Brand.crimsonDeep))),
              if (((r['late_fee'] ?? 0) as num) > 0) _sub('late fee ${inr(r['late_fee'] as num)}') else _sub('since ${_dmy(r['first_due'])}'),
            ])),
        ])),
      ],
      if (failed.isNotEmpty) Panel(title: 'Online payment did not go through · last 30 days', padding: const EdgeInsets.all(12), child: Column(children: [
        for (final f in failed) ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: const Icon(Icons.error_outline_rounded, color: Brand.amber),
          title: Text('${f['student']} · ${f['class'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: _sub('${_dmt(f['at'])}${f['phone'] != null ? ' · ${f['phone']}' : ''} · not paid since'),
          trailing: Text(inr(f['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w800))),
      ])),
    ]);
  }

  Widget _cancelled(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _empty('No receipts were cancelled on these dates.');
    return Panel(title: '${rows.length} cancelled · ${inr(rows.fold<num>(0, (a, r) => a + (r['amount'] as num)))}', padding: const EdgeInsets.all(12), child: Column(children: [
      for (final r in rows) ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('${r['receipt_no']} · ${r['student']} · ${r['class'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: _sub('Reason: ${r['reason']}\nPaid ${_dmy(r['paid_on'])} · cancelled ${_dmy(r['cancelled_on'])} · asked by ${r['asked_by'] ?? '—'} · approved by ${r['approved_by'] ?? '—'}'),
        isThreeLine: true,
        trailing: Text(inr(r['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.lineThrough))),
    ]));
  }

  Widget _concessions(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return _empty('No concessions this year.');
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) { groups.putIfAbsent('${r['fee_category'] ?? 'regular'}', () => []).add(r); }
    final conc = rows.fold<num>(0, (a, r) => a + ((r['concession'] ?? 0) as num));
    final waived = rows.fold<num>(0, (a, r) => a + ((r['waived'] ?? 0) as num));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(padding: const EdgeInsets.all(16), child: Column(children: [
        for (final e in groups.entries) _total('${e.key == 'regular' ? 'Other concessions (early-bird, sibling…)' : feeCategories[e.key] ?? e.key} · ${e.value.length} students',
            e.value.fold<num>(0, (a, r) => a + ((r['concession'] ?? 0) as num) + ((r['waived'] ?? 0) as num))),
        const Divider(),
        _total('Total given up this year', conc + waived, big: true, c: Brand.violet),
      ])),
      Panel(padding: const EdgeInsets.all(12), child: Column(children: [
        for (final r in rows) ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('${r['student']} · ${r['class'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)), FeeCategoryPill(r['fee_category'])]),
          subtitle: (r['note'] ?? '').toString().isEmpty ? null : _sub('${r['note']}'),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(inr(((r['concession'] ?? 0) as num) + ((r['waived'] ?? 0) as num)), style: const TextStyle(fontWeight: FontWeight.w800)),
            if (((r['waived'] ?? 0) as num) > 0) _sub('waived ${inr(r['waived'] as num)}'),
          ])),
      ])),
    ]);
  }
}
