import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_extras.dart' show GoldLoading;

class FeesScreen extends ConsumerWidget {
  const FeesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(sessionProvider).value!.active!;
    final fees = ref.watch(feesProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Column(children: [
        BrandHeader(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), hairline: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(onPressed: () => context.go('/'), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
            const Expanded(child: Text('Fees', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
                child: const Text('2026-27', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
          ]),
          const SizedBox(height: 8),
          Row(children: [Avatar(st.initials, bg: Colors.white, fg: Brand.crimsonDeep, size: 32), const SizedBox(width: 10), Text('${st.fullName} · ${st.cls}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))]),
        ])),
        Expanded(child: fees.when(
          loading: () => const GoldLoading(),
          error: (e, _) => Center(child: Text('Could not load fees.\n$e', textAlign: TextAlign.center)),
          data: (f) => RefreshIndicator(onRefresh: () async => ref.invalidate(feesProvider), child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 110), children: [
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: Brand.crimsonDeep.withValues(alpha: .12), blurRadius: 30, offset: const Offset(0, 10))]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Balance for the year', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)), Text(inr(f.balance), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.5))]),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('Paid so far', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)), RichText(text: TextSpan(style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Brand.green), children: [TextSpan(text: inr(f.paidAmount)), TextSpan(text: ' of ${inr(f.total)}', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))]))]),
                    ]),
                    const SizedBox(height: 12),
                    ClipRRect(borderRadius: BorderRadius.circular(5), child: SizedBox(height: 10, child: Row(children: [
                      Expanded(flex: f.pct, child: Container(color: Brand.green)),
                      if (f.overdue.isNotEmpty) Expanded(flex: ((f.overdue.fold<num>(0, (a, r) => a + r.amount) / (f.total == 0 ? 1 : f.total)) * 100).round().clamp(1, 100), child: Container(color: Brand.crimson)),
                      Expanded(flex: (100 - f.pct).clamp(0, 100), child: Container(color: cs.surfaceContainerHighest)),
                    ]))),
                    const SizedBox(height: 10),
                    Row(children: [_legend('Paid', Brand.green, cs), const SizedBox(width: 16), _legend('Overdue', Brand.crimson, cs), const SizedBox(width: 16), _legend('Not yet due', cs.surfaceContainerHighest, cs)]),
                  ])),
              const SizedBox(height: 14),
              if (f.overdue.isNotEmpty) _section(context, 'Overdue', Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFF6B6B) : Brand.crimsonDeep, f.overdue, border: true),
              if (f.dueSoon.isNotEmpty) _section(context, 'Due soon', Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF2B84B) : Brand.amber, f.dueSoon),
              if (f.upcoming.isNotEmpty) _section(context, 'Upcoming', cs.onSurfaceVariant, f.upcoming),
              Material(color: cs.surface, borderRadius: BorderRadius.circular(18), child: InkWell(onTap: () => context.push('/receipts'), borderRadius: BorderRadius.circular(18), child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                Icon(Icons.check_rounded, color: context.tone(Brand.green)), const SizedBox(width: 10),
                Expanded(child: Text('${f.paidRows.where((r) => !r.isLate).length} payments made · receipts', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ])))),
              if (f.unpaid.isEmpty) const Padding(padding: EdgeInsets.only(top: 14), child: NoteBox("Nothing left to pay for this year. Next year's fee structure appears here in March.")),
            ]),
          ])),
        )),
      ]),
      bottomSheet: fees.value == null || fees.value!.unpaid.isEmpty ? null : Container(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outline))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Builder(builder: (_) {
            final f = fees.value!; final sel = f.overdue.isNotEmpty ? f.overdue : [f.unpaid.first];
            final amt = sel.fold<num>(0, (a, r) => a + r.amount);
            return PrimaryButton('${f.overdue.isNotEmpty ? 'Pay overdue amount' : 'Pay next instalment'}   ${inr(amt)}', onPressed: () => context.push('/pay'));
          }),
          TextButton(onPressed: () => context.push('/pay'), child: const Text('Choose other items to pay')),
        ]),
      ),
    );
  }

  Widget _legend(String l, Color c, ColorScheme cs) => Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2), border: Border.all(color: cs.outline, width: .5))), const SizedBox(width: 6), Text(l, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))]);

  Widget _section(BuildContext context, String title, Color color, List<FeeRow> rows, {bool border = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Eyebrow(title, color: color)),
      for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 8), child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18), border: border ? Border.all(color: const Color(0xFFF3C8C8), width: 1.5) : null),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (r.note != null) Text(r.note!, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            Text(r.overdue ? 'Due ${DateFormat('d MMM yyyy').format(DateTime.parse(r.dueOn))}' : 'Due ${DateFormat('d MMM').format(DateTime.parse(r.dueOn))}${r.daysUntil() <= 30 ? ' · ${r.daysUntil()} days left' : ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ])),
          Text(inr(r.amount), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
      )),
    ]));
  }
}
