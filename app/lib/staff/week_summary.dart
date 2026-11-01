import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_motion.dart' show FadeRise, GoldText;
import '../widgets/royal_extras.dart' show CountUpText, GoldLoading;
import 'staff_shell.dart';

/// Route '/staff/week' — "Your week at Royale": five lines about last week for the Principal (and IT).
/// The Monday 8 am notification opens this page.

final weekSummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.cacheFor();
  return Map<String, dynamic>.from(await db.rpc('week_summary', params: {'p_week_start': null}) as Map);
});

String _money(num v) {
  if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)} L';
  return inr(v);
}
num _n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
String _pct(num v) => v == v.roundToDouble() ? '${v.toInt()}%' : '${v.toStringAsFixed(1)}%';

class WeekSummaryScreen extends ConsumerWidget {
  const WeekSummaryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    final cs = Theme.of(context).colorScheme;
    if (s == null || !(s.hasRole('principal') || s.hasRole('it_admin') || s.hasRole('vice_principal'))) {
      return const StaffPage(title: 'Your week at Royale', body: Panel(child: Text('This summary is for the Principal.')));
    }
    final w = ref.watch(weekSummaryProvider);
    return StaffPage(
      title: 'Your week at Royale',
      subtitle: w.value == null ? 'Last week, in five lines' : '${w.value!['dates']} · last week, in five lines',
      body: w.when(
        loading: () => const Padding(padding: EdgeInsets.all(32), child: GoldLoading()),
        error: (e, _) => Panel(child: Text('Could not load the summary: $e', style: const TextStyle(color: Brand.crimsonDeep))),
        data: (d) {
          final att = d['attendance'] == null ? null : _n(d['attendance']);
          final prev = d['attendance_prev'] == null ? null : _n(d['attendance_prev']);
          final change = att != null && prev != null ? att - prev : null;
          final needs = [for (final x in (d['needs'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
          final read = d['notices_read'] == null ? null : _n(d['notices_read']);
          final lines = <Widget>[
            _Line(icon: Icons.fact_check_rounded, colour: Brand.green,
                big: att == null ? '—' : _pct(att),
                text: att == null ? 'No attendance was taken last week.'
                    : 'present${change == null ? '' : change.abs() < .05 ? ' · same as the week before' : ' · ${change > 0 ? 'up' : 'down'} ${_pct(change.abs())} from the week before'}',
                onTap: () => context.go('/staff/attendance')),
            _Line(icon: Icons.account_balance_wallet_rounded, colour: Brand.blue,
                big: _money(_n(d['fees'])), text: 'fees collected · ${_money(_n(d['due']))} still due', onTap: () => context.go('/staff/fees')),
            _Line(icon: Icons.campaign_rounded, colour: Brand.violet,
                big: '${_n(d['notices']).toInt()}', text: _n(d['notices']) == 0 ? 'notices sent' : 'notice${_n(d['notices']) == 1 ? '' : 's'} sent${read == null ? '' : ' · ${_pct(read)} read by families'}',
                onTap: () => context.go('/staff/announcements')),
            _Line(icon: Icons.celebration_rounded, colour: Brand.amber,
                big: '${_n(d['events']).toInt()}', text: 'event${_n(d['events']) == 1 ? '' : 's'} · ${_n(d['birthdays']).toInt()} birthdays · ${_n(d['photos']).toInt()} class photos'),
            _NeedsLine(needs: needs),
          ];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18), margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(gradient: Brand.headerGradient, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                GoldText('Your week at Royale', align: TextAlign.left, style: Theme.of(context).textTheme.headlineSmall!.copyWith(fontSize: 24)),
                const SizedBox(height: 4),
                Text('${d['dates']}', style: TextStyle(color: Colors.white.withValues(alpha: .9), fontWeight: FontWeight.w600)),
              ]),
            ),
            for (final (i, l) in lines.indexed) FadeRise(delayMs: 80 * i, dy: 12, child: l),
            Text('Comes every Monday at 8 am.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ]);
        },
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon; final Color colour; final String big, text; final VoidCallback? onTap;
  const _Line({required this.icon, required this.colour, required this.big, required this.text, this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(color: cs.surface, borderRadius: BorderRadius.circular(18), child: InkWell(
      borderRadius: BorderRadius.circular(18), onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outline.withValues(alpha: .6))),
        child: Row(children: [
          Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: context.tone(colour).withValues(alpha: .13), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: context.tone(colour))),
          const SizedBox(width: 14),
          CountUpText(big, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: context.tone(colour))),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14, color: cs.onSurface))),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ]),
      ),
    )));
  }
}

class _NeedsLine extends StatelessWidget {
  final List<Map<String, dynamic>> needs;
  const _NeedsLine({required this.needs});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Brand.gold.withValues(alpha: .7), width: 1.4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: Brand.gold.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.push_pin_rounded, color: Brand.gold)),
          const SizedBox(width: 14),
          const Text('Needs you', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        if (needs.isEmpty) Text('Nothing is waiting for you. ✓', style: TextStyle(fontSize: 14, color: context.tone(Brand.green), fontWeight: FontWeight.w700)),
        for (final n in needs) InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: n['route'] == null ? null : () => context.go('${n['route']}'),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [
            const Icon(Icons.circle, size: 8, color: Brand.crimson),
            const SizedBox(width: 10),
            Expanded(child: Text('${n['label']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ])),
        ),
      ]),
    );
  }
}
