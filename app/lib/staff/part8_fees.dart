import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/data3.dart' show initialsOf;
import '../core/errors.dart';
import '../core/school_docs.dart' show openTablePdf, openReceiptPdf, buildFeeSlipsPdf, PdfDocScreen;
import '../core/theme.dart';
import '../core/xlsx_writer.dart';
import '../widgets/common.dart';
import '../widgets/hub_tabs.dart';
import '../widgets/royal_extras.dart' show ShimmerPage;
import 'office_reports.dart' show StatCard, statGrid, ReportTable, wideTable;
import 'staff_data.dart';
import 'staff_shell.dart';

/// Part 8 pages for fees:
///   • Record a payment — a bank transfer (NEFT / RTGS / UPI) or cheque paid to the school's account, with its reference
///   • Fee day sheet — everything collected on one day, for the cash book
///   • Concessions and scholarships — accounts asks, the Principal decides
///   • Dues by class and fee, and reminder slips to print (shown on the Fee dues page)

Widget _loading() => const ShimmerPage();
Widget _err(Object e) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e), style: const TextStyle(color: Brand.crimsonDeep)));
String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Find one student by name, admission number or a parent's phone.
class StudentPick extends ConsumerStatefulWidget {
  final Map<String, dynamic>? value; final ValueChanged<Map<String, dynamic>?> onChanged;
  const StudentPick({super.key, required this.value, required this.onChanged});
  @override
  ConsumerState<StudentPick> createState() => _StudentPickState();
}

class _StudentPickState extends ConsumerState<StudentPick> {
  final c = TextEditingController(); String q = '';
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = widget.value;
    if (v != null) {
      return Container(padding: const EdgeInsets.fromLTRB(14, 8, 6, 8), decoration: BoxDecoration(color: Brand.gold.withValues(alpha: .08), borderRadius: BorderRadius.circular(14), border: Border.all(color: Brand.gold.withValues(alpha: .5))),
        child: Row(children: [
          Avatar(initialsOf('${v['full_name']}'), size: 40), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${v['full_name']}', style: const TextStyle(fontWeight: FontWeight.w900)),
            Text('${v['admission_no'] ?? ''} · ${v['class'] ?? ''}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ])),
          TextButton(onPressed: () { c.clear(); setState(() => q = ''); widget.onChanged(null); }, child: const Text('Change')),
        ]));
    }
    final res = q.trim().length < 2 ? null : ref.watch(studentSearchProvider(q.trim()));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: c, autofocus: false, decoration: const InputDecoration(labelText: 'Student', hintText: 'Name, admission number or a parent’s phone', prefixIcon: Icon(Icons.search_rounded)),
          onChanged: (t) => setState(() => q = t)),
      if (res != null) res.when(
        loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator(minHeight: 2)),
        error: (e, _) => Padding(padding: const EdgeInsets.all(8), child: Text(friendlyError(e))),
        data: (rows) => rows.isEmpty ? Padding(padding: const EdgeInsets.all(10), child: Text('Nobody found.', style: TextStyle(color: cs.onSurfaceVariant)))
            : ConstrainedBox(constraints: const BoxConstraints(maxHeight: 240), child: ListView(shrinkWrap: true, children: [
                for (final r in rows.take(12)) ListTile(dense: true, leading: Avatar(initialsOf('${r['full_name']}'), size: 36), title: Text('${r['full_name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${r['admission_no'] ?? ''} · ${r['class'] ?? ''}'), onTap: () => widget.onChanged(r)),
              ]))),
    ]);
  }
}

// ================================================================== RECORD A PAYMENT
final _pendingProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, student) async =>
    [for (final x in (await db.rpc('fee_pending', params: {'p_student': student})) as List? ?? const []) Map<String, dynamic>.from(x as Map)]);

class RecordPaymentPage extends ConsumerStatefulWidget {
  const RecordPaymentPage({super.key});
  @override
  ConsumerState<RecordPaymentPage> createState() => _RecordPaymentPageState();
}

class _RecordPaymentPageState extends ConsumerState<RecordPaymentPage> {
  Map<String, dynamic>? student; final picked = <String>{}; String mode = 'neft'; final refNo = TextEditingController(); DateTime paidOn = DateUtils.dateOnly(DateTime.now()); bool busy = false;
  Map<String, dynamic>? done;
  @override
  void dispose() { refNo.dispose(); super.dispose(); }

  Future<void> _save(num amount) async {
    setState(() => busy = true);
    try {
      final r = Map<String, dynamic>.from(await db.rpc('fee_record_payment', params: {'p_student': student!['id'], 'p_ledgers': picked.toList(), 'p_mode': mode, 'p_ref': refNo.text.trim(), 'p_paid_on': _iso(paidOn)}) as Map);
      ref.invalidate(_pendingProvider(student!['id'] as String));
      if (mounted) setState(() { done = {...r, 'student': student!['full_name']}; picked.clear(); refNo.clear(); busy = false; });
    } catch (e) { if (mounted) { setState(() => busy = false); toast(context, friendlyError(e)); } }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(sessionProvider).value!;
    final can = (s.hasRole('accounts') || s.hasRole('office') || s.hasRole('it_admin')) && !s.viewOnly;
    final pend = student == null ? null : ref.watch(_pendingProvider(student!['id'] as String));
    final rows = pend?.value ?? const <Map<String, dynamic>>[];
    num amount = 0;
    for (final r in rows) { if (picked.contains(r['id'])) amount += (r['amount'] as num) + ((r['late'] ?? 0) as num); }
    return StaffPage(title: 'Record a payment', hub: Hub.staffFees,
      subtitle: 'For a bank transfer (NEFT, RTGS, UPI) or a cheque paid to the school’s account. Online payments in the app are recorded by themselves.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (done != null) Panel(child: Row(children: [
          Icon(Icons.verified_rounded, color: context.tone(Brand.green), size: 30), const SizedBox(width: 12),
          Expanded(child: Text('${inr(done!['amount'] as num)} recorded for ${done!['student']} · receipt ${done!['receipt_no']}. The family has it in the app.', style: const TextStyle(fontWeight: FontWeight.w800))),
          OutlinedButton.icon(onPressed: () => openReceiptPdf(context, '${done!['payment_id']}', receiptNo: '${done!['receipt_no']}'), icon: const Icon(Icons.picture_as_pdf_rounded, size: 18), label: const Text('Receipt')),
        ])),
        Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          StudentPick(value: student, onChanged: (v) => setState(() { student = v; picked.clear(); done = null; })),
          if (student != null) ...[
            const SizedBox(height: 16),
            Text('WHICH FEE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            if (pend == null || pend.isLoading) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator(minHeight: 2))
            else if (pend.hasError) _err(pend.error!)
            else if (rows.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('Nothing is pending for this student ✓', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(Brand.green))))
            else for (final r in rows) CheckboxListTile(value: picked.contains(r['id']), dense: true, contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
                onChanged: !can ? null : (v) => setState(() => v == true ? picked.add(r['id'] as String) : picked.remove(r['id'])),
                title: Text('${r['title']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('Due ${DateFormat('d MMM yyyy').format(DateTime.parse('${r['due_on']}'))}${((r['late'] ?? 0) as num) > 0 ? ' · late fee ${inr(r['late'] as num)} is paid with it' : ''}'),
                secondary: Text(inr((r['amount'] as num) + ((r['late'] ?? 0) as num)), style: const TextStyle(fontWeight: FontWeight.w900))),
            if (rows.isNotEmpty) ...[
              const Divider(height: 26),
              PickRow(children: [
                Expanded(child: PickField<String>(label: 'Paid by', value: mode, items: const [DropdownMenuItem(value: 'neft', child: Text('NEFT / RTGS / UPI')), DropdownMenuItem(value: 'cheque', child: Text('Cheque'))],
                    onChanged: (v) => setState(() => mode = v ?? 'neft'))),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: TextField(controller: refNo, textCapitalization: TextCapitalization.characters, onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: mode == 'cheque' ? 'Cheque number' : 'Bank reference (UTR)', hintText: mode == 'cheque' ? 'e.g. 004512' : 'e.g. UTR 1234567890'))),
                const SizedBox(width: 12),
                Expanded(child: OutlinedButton.icon(onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: paidOn, firstDate: DateTime.now().subtract(const Duration(days: 120)), lastDate: DateTime.now());
                  if (d != null) setState(() => paidOn = d);
                }, icon: const Icon(Icons.event_rounded, size: 18), label: Text('Paid on ${DateFormat('d MMM').format(paidOn)}'))),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Text(picked.isEmpty ? 'Tick the fee that was paid.' : 'Amount: ${inr(amount)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: picked.isEmpty ? 14 : 18, color: picked.isEmpty ? cs.onSurfaceVariant : null))),
                FilledButton.icon(onPressed: !can || busy || picked.isEmpty || refNo.text.trim().length < 4 ? null : () => _save(amount),
                    icon: const Icon(Icons.receipt_long_rounded, size: 18), label: Text(busy ? 'Saving…' : 'Save and make the receipt')),
              ]),
            ],
          ],
        ])),
        Text('A fee is always paid in full, and a late fee goes with its instalment. The same reference cannot be used twice. The family gets the receipt in the app straight away.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

// ================================================================== FEE DAY SHEET
final _daySheetProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, day) async =>
    [for (final x in (await db.rpc('fee_day_sheet', params: {'p_day': day})) as List? ?? const []) Map<String, dynamic>.from(x as Map)]);

class FeeDaySheetPage extends ConsumerStatefulWidget {
  const FeeDaySheetPage({super.key});
  @override
  ConsumerState<FeeDaySheetPage> createState() => _FeeDaySheetPageState();
}

class _FeeDaySheetPageState extends ConsumerState<FeeDaySheetPage> {
  DateTime day = DateUtils.dateOnly(DateTime.now());
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final data = ref.watch(_daySheetProvider(_iso(day)));
    final title = DateFormat('EEEE, d MMMM yyyy').format(day);
    return StaffPage(title: 'Fee day sheet', hub: Hub.staffFees, subtitle: 'Everything collected on one day, ready to print for the cash book.',
      body: data.when(loading: _loading, error: (e, _) => _err(e), data: (rows) {
        num sum(bool Function(Map<String, dynamic>) f) => rows.where(f).fold<num>(0, (a, r) => a + (r['amount'] as num));
        final total = sum((_) => true), online = sum((r) => r['mode'] == 'Online');
        String time(Map<String, dynamic> r) => DateFormat('h:mm a').format(DateTime.parse('${r['at']}').toLocal());
        const head = ['Time', 'Receipt', 'Mode', 'Student', 'Class', 'Fee', 'Reference', 'Amount'];
        final table = [for (final r in rows) [time(r), '${r['receipt_no'] ?? ''}', '${r['mode']}', '${r['student']}', '${r['class'] ?? ''}', '${r['fee'] ?? ''}', '${r['ref'] ?? ''}', inr(r['amount'] as num)]];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Panel(padding: const EdgeInsets.all(12), child: PickRow(children: [
            IconButton(onPressed: () => setState(() => day = day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left_rounded), tooltip: 'Day before'),
            Expanded(child: OutlinedButton.icon(onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: day, firstDate: DateTime.now().subtract(const Duration(days: 730)), lastDate: DateTime.now());
              if (d != null) setState(() => day = d);
            }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(title))),
            IconButton(onPressed: day.isBefore(DateUtils.dateOnly(DateTime.now())) ? () => setState(() => day = day.add(const Duration(days: 1))) : null, icon: const Icon(Icons.chevron_right_rounded), tooltip: 'Next day'),
            const SizedBox(width: 8),
            OutlinedButton.icon(onPressed: rows.isEmpty ? null : () async {
              try { await saveBytes(buildXlsx('Day sheet', head, [for (final (i, r) in table.indexed) [...r.take(7), rows[i]['amount']], ['Total · ${rows.length} receipts', null, null, null, null, null, null, total]],
                  widths: [10, 18, 18, 26, 9, 34, 22, 13]), 'RCIS-fee-day-sheet-${_iso(day)}.xlsx'); }
              catch (e) { if (context.mounted) toast(context, 'Could not save the file: ${friendlyError(e)}'); }
            }, icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Excel')),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: rows.isEmpty ? null : () => openTablePdf(context, title: 'Fee day sheet', sub: title, head: head, rows: table, leftAligned: 7, landscape: true,
                flex: [1.3, 2.4, 2.2, 3.4, 1.2, 4.2, 2.6, 1.8], total: ['Total · ${rows.length} receipts', '', '', '', '', '', '', inr(total)]),
                icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Print')),
          ])),
          statGrid(context, [
            StatCard('Collected', total, money: inr(total)),
            StatCard('Receipts', rows.length),
            StatCard('Online', online, money: inr(online)),
            StatCard('Bank transfer / cheque', total - online, money: inr(total - online)),
          ]),
          if (rows.isEmpty) Panel(child: Text('Nothing was collected on this day.', style: TextStyle(color: cs.onSurfaceVariant)))
          else Panel(padding: const EdgeInsets.all(10), child: wideTable(context, ReportTable(
            cols: const [('Time', 2, false), ('Receipt', 3, false), ('Mode', 3, false), ('Student', 4, false), ('Class', 2, false), ('Fee', 5, false), ('Reference', 3, false), ('Amount', 2, true)],
            rows: [
              for (final (i, r) in rows.indexed) [Text(table[i][0]), Text(table[i][1], style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                Pill('${r['mode']}', fg: r['mode'] == 'Online' ? Brand.green : Brand.amber, bg: r['mode'] == 'Online' ? Brand.greenTint : Brand.amberTint),
                Text('${r['student']}', style: const TextStyle(fontWeight: FontWeight.w800)), Text('${r['class'] ?? ''}'), Text('${r['fee'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                Text('${r['ref'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)), Text(inr(r['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w900))],
              [Text('Total · ${rows.length} receipts'), const Text(''), const Text(''), const Text(''), const Text(''), const Text(''), const Text(''), Text(inr(total))],
            ], totals: {rows.length}, onTap: [for (final r in rows) () => openReceiptPdf(context, '${r['id']}', receiptNo: '${r['receipt_no']}')]), min: 980)),
        ]);
      }),
    );
  }
}

// ================================================================== CONCESSIONS AND SCHOLARSHIPS
final concessionsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => Map<String, dynamic>.from(await db.rpc('concession_list') as Map));
const _kinds = ['Sibling concession', 'Management concession', 'Staff child', 'Scholarship', 'Other'];

class ConcessionsPage extends ConsumerWidget {
  const ConcessionsPage({super.key});

  Future<void> _ask(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const _AskDialog());
    if (ok == true) ref.invalidate(concessionsProvider);
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, Map<String, dynamic> r, bool approve) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text(approve ? 'Approve ${inr(r['amount'] as num)} for ${r['student']}?' : 'Not approve?'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${r['kind']} · ${r['reason']}'),
        const SizedBox(height: 10),
        if (approve) const Text('The amount is taken off the fees this student still has to pay, tuition first. It cannot be undone from here.')
        else TextField(controller: note, decoration: const InputDecoration(labelText: 'A short note for accounts (optional)')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(approve ? 'Approve' : 'Not approve'))]));
    if (ok != true) return;
    try {
      await db.rpc('concession_decide', params: {'p_id': r['id'], 'p_approve': approve, 'p_note': note.text.trim()});
      ref.invalidate(concessionsProvider);
      if (context.mounted) toast(context, approve ? 'Approved ✓ — the fees are updated.' : 'Marked as not approved.');
    } catch (e) { if (context.mounted) toast(context, friendlyError(e)); }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final data = ref.watch(concessionsProvider);
    return StaffPage(title: 'Concessions', hub: Hub.staffFees,
      subtitle: 'Concessions and scholarships for one student at a time. Accounts asks, the Principal decides, and every one is kept with its reason.',
      actions: [if (data.value?['can_ask'] == true) FilledButton.icon(onPressed: () => _ask(context, ref), icon: const Icon(Icons.add_rounded), label: const Text('Ask for a concession'))],
      body: data.when(loading: _loading, error: (e, _) => _err(e), data: (d) {
        final rows = List<Map<String, dynamic>>.from(d['rows'] ?? const []);
        final by = Map<String, dynamic>.from(d['by_kind'] ?? const {});
        final given = (d['given'] ?? 0) as num, billed = (d['billed'] ?? 0) as num;
        final waiting = rows.where((r) => r['status'] == 'pending').length;
        final top = by.entries.toList()..sort((a, b) => (b.value as num).compareTo(a.value as num));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          statGrid(context, [
            StatCard('Given this year', given, money: inr(given), sub: billed > 0 ? '${(given * 100 / billed).toStringAsFixed(1)}% of the fees billed' : null),
            for (final e in top.take(2)) StatCard(e.key, e.value as num, money: inr(e.value as num)),
            StatCard('Waiting for the Principal', waiting, tone: waiting > 0 ? Brand.amber : null),
          ]),
          if (rows.isEmpty) Panel(child: Text('No concession has been asked for this year.', style: TextStyle(color: cs.onSurfaceVariant)))
          else Panel(padding: const EdgeInsets.all(10), child: wideTable(context, ReportTable(
            cols: const [('Kind', 3, false), ('Student', 4, false), ('Class', 2, false), ('Amount', 2, true), ('Reason', 5, false), ('Status', 2, false), ('', 4, true)],
            rows: [for (final r in rows) [
              Text('${r['kind']}'), Text('${r['student']}', style: const TextStyle(fontWeight: FontWeight.w800)), Text('${r['class'] ?? ''}'),
              Text(inr(r['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w900)),
              Text('${r['reason']}${r['asked_by'] != null ? ' · ${r['asked_by']}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              switch ('${r['status']}') { 'approved' => Pill('Approved', fg: Brand.green, bg: Brand.greenTint), 'rejected' => Pill('Not approved', fg: Brand.muted, bg: Brand.surface2), _ => Pill('Waiting', fg: Brand.amber, bg: Brand.amberTint) },
              r['status'] == 'pending' && d['can_decide'] == true ? Wrap(spacing: 6, children: [
                TextButton(onPressed: () => _decide(context, ref, r, false), child: const Text('No')),
                FilledButton(onPressed: () => _decide(context, ref, r, true), child: const Text('Approve')),
              ]) : const SizedBox(),
            ]]), min: 900)),
          Text('“Given this year” also counts concessions that were set with the fee plan. A scholarship works the same way as a concession: it is taken off the fees still to pay.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ]);
      }),
    );
  }
}

class _AskDialog extends StatefulWidget {
  const _AskDialog();
  @override
  State<_AskDialog> createState() => _AskDialogState();
}

class _AskDialogState extends State<_AskDialog> {
  Map<String, dynamic>? student; String kind = _kinds[1]; final amount = TextEditingController(), reason = TextEditingController(); bool busy = false;
  @override
  void dispose() { amount.dispose(); reason.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ask for a concession or scholarship'),
    content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudentPick(value: student, onChanged: (v) => setState(() => student = v)),
      const SizedBox(height: 12),
      PickField<String>(label: 'Kind', value: kind, items: [for (final k in _kinds) DropdownMenuItem(value: k, child: Text(k))], onChanged: (v) => setState(() => kind = v ?? kind)),
      const SizedBox(height: 12),
      TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₹)')),
      const SizedBox(height: 12),
      TextField(controller: reason, minLines: 2, maxLines: 3, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Reason', hintText: 'e.g. Second child in the school')),
      const SizedBox(height: 8),
      Text('It goes to the Principal. Nothing changes in the fees until it is approved.', style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: busy || student == null ? null : () async {
        setState(() => busy = true);
        try {
          await db.rpc('concession_ask', params: {'p_student': student!['id'], 'p_kind': kind, 'p_amount': num.tryParse(amount.text.trim().replaceAll(',', '')), 'p_reason': reason.text.trim()});
          if (context.mounted) { toast(context, 'Sent to the Principal ✓'); Navigator.pop(context, true); }
        } catch (e) { if (context.mounted) { setState(() => busy = false); toast(context, friendlyError(e)); } }
      }, child: Text(busy ? 'Sending…' : 'Send to the Principal')),
    ],
  );
}

// ================================================================== DUES BY CLASS AND FEE (a panel on the Fee dues page)
final duesMatrixProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async =>
    [for (final x in (await db.rpc('fee_dues_matrix')) as List? ?? const []) Map<String, dynamic>.from(x as Map)]);

class DuesMatrixPanel extends ConsumerWidget {
  /// Opens the students of one class (the page's own filter).
  final ValueChanged<String> onGrade;
  const DuesMatrixPanel({super.key, required this.onGrade});

  Future<void> _slips(BuildContext context) async {
    try {
      final rows = [for (final x in (await db.rpc('fee_report_dues', params: {'p_grade': null})) as List? ?? const []) Map<String, dynamic>.from(x as Map)];
      if (!context.mounted) return;
      if (rows.isEmpty) { toast(context, 'Nobody has a fee overdue ✓'); return; }
      final slips = [for (final r in rows) (student: '${r['student']}', cls: '${r['class'] ?? ''}', adm: '${r['admission_no'] ?? ''}', items: '${r['items'] ?? ''}', amount: (r['overdue'] ?? 0) as num)];
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PdfDocScreen(title: 'Fee reminder slips', fileName: 'RCIS-fee-reminder-slips.pdf', make: () => buildFeeSlipsPdf(slips))));
    } catch (e) { if (context.mounted) toast(context, friendlyError(e)); }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ref.watch(duesMatrixProvider).when(loading: () => const SizedBox(), error: (e, _) => const SizedBox(), data: (rows) {
      if (rows.isEmpty) return const SizedBox();
      num s(String k) => rows.fold<num>(0, (a, r) => a + ((r[k] ?? 0) as num));
      num t(Map<String, dynamic> r) => ((r['tuition'] ?? 0) as num) + ((r['transport'] ?? 0) as num) + ((r['other'] ?? 0) as num);
      final mx = rows.map(t).fold<num>(1, (a, b) => a > b ? a : b);
      Widget money(num v, {bool bold = false}) => Text(v == 0 ? '—' : inr(v), style: TextStyle(fontWeight: bold ? FontWeight.w900 : null));
      return Panel(title: 'By class and fee · due today', trailing: OutlinedButton.icon(onPressed: () => _slips(context), icon: const Icon(Icons.content_cut_rounded, size: 18), label: const Text('Reminder slips (print)')),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          wideTable(context, ReportTable(
            cols: const [('Class', 3, false), ('Students', 2, true), ('Tuition', 3, true), ('Transport', 3, true), ('Other', 3, true), ('Total due', 3, true), ('', 3, false)],
            rows: [
              for (final r in rows) [Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w800)), Text('${r['students']}'), money((r['tuition'] ?? 0) as num), money((r['transport'] ?? 0) as num), money((r['other'] ?? 0) as num), money(t(r), bold: true),
                ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: t(r) / mx, minHeight: 8, backgroundColor: cs.surfaceContainerHighest, valueColor: const AlwaysStoppedAnimation(Brand.gold)))],
              [const Text('Total'), Text('${s('students')}'), money(s('tuition')), money(s('transport')), money(s('other')), money(s('tuition') + s('transport') + s('other'), bold: true), const Text('')],
            ], totals: {rows.length}, onTap: [for (final r in rows) () => onGrade('${r['grade_id']}')]), min: 760),
          const SizedBox(height: 8),
          Text('Tap a class to see its students below. “Other” is activity fees and late fees. Reminder slips print eight to a page, one for each family with a fee overdue.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ]));
    });
  }
}
