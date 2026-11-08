import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth/session.dart';
import '../core/config.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/school_docs.dart' show openReceiptPdf;
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_extras.dart' show GoldLoading;
export 'receipt_screen.dart' show ReceiptScreen;

/// Choose what to pay → Razorpay → confirm → receipt.
/// Rules (as agreed with the school): overdue items are always included; a late fee is locked to its instalment;
/// no partial amounts; paying ahead is allowed.
class PayScreen extends ConsumerStatefulWidget {
  const PayScreen({super.key});
  @override
  ConsumerState<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends ConsumerState<PayScreen> {
  final chosen = <String>{};
  bool _preset = false;   // what is due now is ticked once, when the fees first arrive
  bool busy = false; String? error;
  Razorpay? _rz;
  String? _paymentId;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _rz = Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess)
        ..on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) => setState(() { busy = false; error = r.message ?? 'Payment was not completed.'; }))
        ..on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
    }
  }

  @override
  void dispose() { _rz?.clear(); super.dispose(); }

  Map<String, String> _headers(Session s) => {'content-type': 'application/json', 'apikey': AppConfig.supabaseAnonKey, 'authorization': 'Bearer ${s.token}'};

  Future<void> _start(FeeSummary f) async {
    final s = ref.read(sessionProvider).value!;
    setState(() { busy = true; error = null; });
    try {
      // everything that is ticked: overdue (always), chosen instalments, and the late fees riding on them
      final ids = <String>{...f.overdue.map((r) => r.id), ...chosen};
      for (final r in f.unpaid) { if (r.isLate && r.parentId != null && ids.contains(r.parentId)) ids.add(r.id); }
      final r = await http.post(Uri.parse('${AppConfig.functionsUrl}/razorpay-order'), headers: _headers(s),
          body: jsonEncode({'student_id': s.active!.id, 'fee_ledger_ids': ids.toList(), 'channel': kIsWeb ? 'web' : 'app'}));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode >= 400) throw AuthError(j['error'] ?? 'Could not start the payment.');
      _paymentId = j['payment_id'];
      if (kIsWeb) {
        await launchUrl(Uri.parse(j['url']), webOnlyWindowName: '_self');   // hosted Razorpay page; returns to /pay/done
        return;
      }
      _rz!.open({
        'key': j['key_id'], 'order_id': j['order_id'], 'amount': (j['amount'] * 100).round(), 'currency': 'INR',
        'name': j['name'], 'description': j['description'], 'prefill': j['prefill'],
        'theme': {'color': '#B5121A'}, 'retry': {'enabled': true, 'max_count': 1},
      });
    } on AuthError catch (e) { setState(() { busy = false; error = e.message; }); }
    catch (e) { setState(() { busy = false; error = friendlyError(e); }); }
  }

  Future<void> _onSuccess(PaymentSuccessResponse r) async {
    final s = ref.read(sessionProvider).value!;
    try {
      final res = await http.post(Uri.parse('${AppConfig.functionsUrl}/razorpay-webhook'), headers: _headers(s),
          body: jsonEncode({'payment_id': _paymentId, 'razorpay_order_id': r.orderId, 'razorpay_payment_id': r.paymentId, 'razorpay_signature': r.signature}));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode >= 400) throw AuthError(j['error']);
      ref.invalidate(feesProvider);
      if (mounted) context.pushReplacement('/receipt/$_paymentId');
    } catch (e) {
      setState(() { busy = false; error = e is AuthError ? e.message : 'Payment made, but confirmation is pending. It will show in Receipts within a few minutes.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fees = ref.watch(feesProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(8, 4, 20, 16), child: Row(children: [
        IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/'), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), tooltip: 'Back'),
        const Text('Pay fees', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      ])),
      Expanded(child: fees.when(
        loading: () => const GoldLoading(),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (f) {
          // what is due now (overdue + due within a week, or else the next instalment) comes ticked — the same amount
          // the Pay button on Home and on the Fees page showed; anything not yet due stays unticked
          if (!_preset) { _preset = true; chosen.addAll(feesDueNow(f, orNext: true).where((r) => !r.overdue && !r.isLate).map((r) => r.id)); }
          // overdue always in; late fees follow their instalment
          final forced = f.overdue.map((r) => r.id).toSet();
          final optional = f.unpaid.where((r) => !r.overdue && !r.isLate).toList();
          final selected = {...forced, ...chosen};
          for (final r in f.unpaid) { if (r.isLate && r.parentId != null && selected.contains(r.parentId)) selected.add(r.id); }
          final rows = f.unpaid.where((r) => selected.contains(r.id)).toList();
          final total = rows.fold<num>(0, (a, r) => a + r.amount);
          return Column(children: [
            Expanded(child: ListView(padding: const EdgeInsets.all(20), children: [
              Padding(padding: const EdgeInsets.only(bottom: 14), child: Text('What is due is already ticked.', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
              if (f.overdue.isNotEmpty) ...[
                Eyebrow('Overdue · included', color: context.tone(Brand.crimsonDeep)), const SizedBox(height: 8),
                for (final r in f.overdue) _row(r, true, null, cs),
                const SizedBox(height: 16),
              ],
              if (optional.isNotEmpty) ...[
                Eyebrow(f.overdue.isEmpty ? 'Fees' : 'Other fees', color: cs.onSurfaceVariant), const SizedBox(height: 8),
                for (final r in optional) _row(r, chosen.contains(r.id), (v) => setState(() => v ? chosen.add(r.id) : chosen.remove(r.id)), cs,
                    late: f.unpaid.where((l) => l.isLate && l.parentId == r.id).fold<num>(0, (a, l) => a + l.amount)),
              ],
              const SizedBox(height: 12),
              const NoteBox('Each instalment is paid in full together with any late fee on it. A receipt is issued instantly and the amount reflects in the school office the same day.'),
            ])),
            Container(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
              decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outline))),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(error!, style: TextStyle(color: context.tone(Brand.crimsonDeep), fontWeight: FontWeight.w700, fontSize: 13))),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${rows.length} item${rows.length == 1 ? '' : 's'}', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                  Text(inr(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 10),
                PrimaryButton(total == 0 ? 'Select something to pay' : 'Pay ${inr(total)} securely', icon: Icons.lock_rounded, busy: busy, onPressed: total == 0 ? null : () => _start(f)),
                const SizedBox(height: 6),
                Text('UPI · Cards · Net banking · Powered by Razorpay', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
          ]);
        })),
    ]));
  }

  Widget _row(FeeRow r, bool on, ValueChanged<bool>? onChanged, ColorScheme cs, {num late = 0}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Material(
      color: cs.surface, borderRadius: BorderRadius.circular(16),
      child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onChanged == null ? null : () => onChanged(!on), child: Padding(padding: const EdgeInsets.fromLTRB(8, 10, 16, 10), child: Row(children: [
        Checkbox(value: on, onChanged: onChanged == null ? null : (v) => onChanged(v ?? false), activeColor: Brand.crimson),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.title, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('Due ${DateFormat('d MMM yyyy').format(DateTime.parse(r.dueOn))}${r.overdue ? ' · overdue' : r.daysUntil() > 7 ? ' · not yet due' : ''}${late > 0 ? ' · includes late fee ${inr(late)}' : ''}', style: TextStyle(fontSize: 12, color: r.overdue ? Brand.crimsonDeep : cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ])),
        Text(inr(r.amount + late), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ])))));
}

class ReceiptsScreen extends ConsumerWidget {
  const ReceiptsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(paymentsProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(8, 4, 20, 16), child: Row(children: [
        IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/fees'), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), tooltip: 'Back'),
        const Text('Payments & receipts', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      ])),
      Expanded(child: list.when(
        loading: () => const GoldLoading(),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (rows) => rows.isEmpty ? const Center(child: Text('No payments yet.')) : ListView.separated(padding: const EdgeInsets.all(20), itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, i) {
          final m = rows[i];
          final cancelled = m['status'] == 'cancelled' || m['cancelled_at'] != null;
          final when = m['paid_at'] == null ? '${m['status']}' : DateFormat('d MMM yyyy').format(DateTime.parse(m['paid_at']).toLocal());
          return Material(color: cs.surface, borderRadius: BorderRadius.circular(16), child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: Icon(cancelled ? Icons.block_rounded : Icons.receipt_long_rounded, color: cancelled ? cs.onSurfaceVariant : Brand.green),
            title: Row(children: [
              Flexible(child: Text(m['receipt_no'] ?? 'Pending', style: TextStyle(fontWeight: FontWeight.w800, decoration: cancelled ? TextDecoration.lineThrough : null))),
              if (cancelled) ...[const SizedBox(width: 8), const Pill('Cancelled', fg: Brand.crimson, bg: Brand.crimsonTint)],
            ]),
            // a cancelled receipt says why, so the family is not left guessing
            subtitle: Text(cancelled ? '$when · ${(m['cancel_reason'] ?? '').toString().trim().isEmpty ? 'Cancelled by the school office' : 'Reason: ${m['cancel_reason']}'}' : when),
            trailing: Text(inr(m['amount'] as num), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cancelled ? cs.onSurfaceVariant : null, decoration: cancelled ? TextDecoration.lineThrough : null)),
            onTap: () { if (cancelled) return; if (m['status'] == 'success') { openReceiptPdf(context, m['id'], receiptNo: m['receipt_no']); } else { context.push('/receipt/${m['id']}'); } },
          ));
        }))),
    ]));
  }
}
