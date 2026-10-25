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
import '../core/theme.dart';
import '../widgets/common.dart';

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
    catch (_) { setState(() { busy = false; error = 'Could not reach the school server.'; }); }
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
        IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
        const Text('Pay fees', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      ])),
      Expanded(child: fees.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (f) {
          // overdue always in; late fees follow their instalment
          final forced = f.overdue.map((r) => r.id).toSet();
          final optional = f.unpaid.where((r) => !r.overdue && !r.isLate).toList();
          final selected = {...forced, ...chosen};
          for (final r in f.unpaid) { if (r.isLate && r.parentId != null && selected.contains(r.parentId)) selected.add(r.id); }
          final rows = f.unpaid.where((r) => selected.contains(r.id)).toList();
          final total = rows.fold<num>(0, (a, r) => a + r.amount);
          return Column(children: [
            Expanded(child: ListView(padding: const EdgeInsets.all(20), children: [
              if (f.overdue.isNotEmpty) ...[
                const Eyebrow('Overdue · included', color: Brand.crimsonDeep), const SizedBox(height: 8),
                for (final r in f.overdue) _row(r, true, null, cs),
                const SizedBox(height: 16),
              ],
              if (optional.isNotEmpty) ...[
                Eyebrow('Pay ahead', color: cs.onSurfaceVariant), const SizedBox(height: 8),
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
                if (error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(error!, style: const TextStyle(color: Brand.crimsonDeep, fontWeight: FontWeight.w700, fontSize: 13))),
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
          Text('Due ${DateFormat('d MMM yyyy').format(DateTime.parse(r.dueOn))}${late > 0 ? ' · includes late fee ${inr(late)}' : ''}', style: TextStyle(fontSize: 12, color: r.overdue ? Brand.crimsonDeep : cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ])),
        Text(inr(r.amount + late), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ])))));
}

/// Landing route for the web payment link (`/pay/done?payment_id=…`) and the in-app success screen (`/receipt/:id`).
class ReceiptScreen extends ConsumerWidget {
  final String paymentId;
  const ReceiptScreen({super.key, required this.paymentId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(paymentProvider(paymentId));
    final cs = Theme.of(context).colorScheme;
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(8, 4, 20, 16), child: Row(children: [
        IconButton(onPressed: () => context.go('/fees'), icon: const Icon(Icons.close_rounded, color: Colors.white)),
        const Text('Receipt', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      ])),
      Expanded(child: p.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (m) {
          if (m == null) return const Center(child: Text('Receipt not found.'));
          final ok = m['status'] == 'success';
          return ListView(padding: const EdgeInsets.all(20), children: [
            Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(22)), child: Column(children: [
              Container(width: 64, height: 64, alignment: Alignment.center, decoration: BoxDecoration(color: ok ? Brand.greenTint : Brand.amberTint, shape: BoxShape.circle), child: Icon(ok ? Icons.check_rounded : Icons.hourglass_top_rounded, color: ok ? Brand.green : Brand.amber, size: 34)),
              const SizedBox(height: 14),
              Text(ok ? 'Payment received' : 'Confirming payment…', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(ok ? 'Receipt ${m['receipt_no']}' : 'This usually takes under a minute. Pull down to refresh.', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 18),
              Text(inr(m['amount'] as num), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -.5)),
              if (m['paid_at'] != null) Text(DateFormat('d MMMM yyyy, h:mm a').format(DateTime.parse(m['paid_at']).toLocal()), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              const Divider(height: 32),
              for (final l in (m['payment_line'] as List)) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
                Expanded(child: Text(l['fee_ledger']['title'], style: const TextStyle(fontWeight: FontWeight.w700))), Text(inr(l['amount'] as num))])),
              const Divider(height: 32),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Mode', style: TextStyle(color: cs.onSurfaceVariant)), Text((m['mode'] as String).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700))]),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Reference', style: TextStyle(color: cs.onSurfaceVariant)), Text(m['gateway_payment_id'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))]),
            ])),
            const SizedBox(height: 14),
            if (ok) OutlinedButton.icon(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF receipts arrive with the next update.'))), icon: const Icon(Icons.download_rounded), label: const Text('Download PDF receipt')),
            const SizedBox(height: 10),
            PrimaryButton('Back to fees', onPressed: () => context.go('/fees')),
          ]);
        })),
    ]));
  }
}

class ReceiptsScreen extends ConsumerWidget {
  const ReceiptsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(paymentsProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(8, 4, 20, 16), child: Row(children: [
        IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
        const Text('Payments & receipts', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      ])),
      Expanded(child: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (rows) => rows.isEmpty ? const Center(child: Text('No payments yet.')) : ListView.separated(padding: const EdgeInsets.all(20), itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, i) {
          final m = rows[i];
          return Material(color: cs.surface, borderRadius: BorderRadius.circular(16), child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: const Icon(Icons.receipt_long_rounded, color: Brand.green),
            title: Text(m['receipt_no'] ?? 'Pending', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(m['paid_at'] == null ? m['status'] : DateFormat('d MMM yyyy').format(DateTime.parse(m['paid_at']).toLocal())),
            trailing: Text(inr(m['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            onTap: () => context.push('/receipt/${m['id']}'),
          ));
        }))),
    ]));
  }
}
