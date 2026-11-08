import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/hub_tabs.dart';
import '../widgets/royal_extras.dart' show GoldLoading;
import '../widgets/royal_motion.dart';
import 'academics_screens.dart' show AppPage;
import '../widgets/r_refresh.dart';

/// Attendance for the open child: the streak, this month day by day, and the year so far.
final attendanceSummaryProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, month) async {
  ref.cacheFor();
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return null;
  final r = await db.rpc('attendance_summary', params: {'p_student': s.id, 'p_month': month});
  return r == null ? null : Map<String, dynamic>.from(r as Map);
});

String _month(DateTime d) => DateFormat('yyyy-MM-01').format(d);

/// The streak milestones: one month and two months of school days.
const streakGoals = [30, 60];

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});
  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  @override
  Widget build(BuildContext context) {
    final a = ref.watch(attendanceSummaryProvider(_month(month)));
    final cs = Theme.of(context).colorScheme;
    return AppPage(title: 'Attendance', hub: Hub.attendance, body: a.when(
      loading: () => const GoldLoading(),
      error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e), textAlign: TextAlign.center))),
      data: (d) => RRefresh(onRefresh: () async => ref.invalidate(attendanceSummaryProvider), child: ListView(padding: const EdgeInsets.all(16), children: [
        if (d == null || (d['year_days'] ?? 0) == 0)
          Padding(padding: const EdgeInsets.all(30), child: Text('Attendance will appear here once the class teacher starts marking it in the app.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)))
        else ...[
          FadeRise(child: StreakCard(streak: d['streak'] ?? 0, best: d['best'] ?? 0)),
          const SizedBox(height: 12),
          FadeRise(delayMs: 120, child: _MonthCard(month: month, days: Map<String, dynamic>.from(d['days'] ?? const {}),
              onPrev: () => setState(() => month = DateTime(month.year, month.month - 1)),
              onNext: month.isBefore(DateTime(DateTime.now().year, DateTime.now().month)) ? () => setState(() => month = DateTime(month.year, month.month + 1)) : null)),
          const SizedBox(height: 12),
          FadeRise(delayMs: 220, child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('This school year', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 12.5)),
              const SizedBox(height: 4),
              Text('${d['year_present']} of ${d['year_days']} days present', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ])),
            Text('${(((d['year_present'] ?? 0) as num) * 100 / math.max<num>(1, (d['year_days'] ?? 1) as num)).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 26, color: Brand.green)),
          ]))),
        ],
      ])),
    ));
  }
}

/// The flame card: "32 days present in a row", with the bar to the next milestone (30, then 60 days).
class StreakCard extends StatelessWidget {
  final int streak, best; final bool compact;
  const StreakCard({super.key, required this.streak, this.best = 0, this.compact = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final next = streakGoals.firstWhere((g) => g > streak, orElse: () => 0);
    final prev = streakGoals.lastWhere((g) => g <= streak, orElse: () => 0);
    final reached = streak >= 60 ? 'Two months reached' : streak >= 30 ? 'One month reached' : null;
    final frac = next == 0 ? 1.0 : ((streak - prev) / (next - prev)).clamp(0.0, 1.0);
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: dark ? [const Color(0xFF2A2017), cs.surface] : [Colors.white, const Color(0xFFFFF6E6)]),
        border: Border.all(color: dark ? const Color(0xFF4A3A22) : const Color(0xFFF1D9A8))),
      child: Row(children: [
        SizedBox(width: compact ? 46 : 60, height: compact ? 56 : 72, child: streak > 0 ? const _Flame() : Icon(Icons.local_fire_department_outlined, size: 44, color: cs.onSurfaceVariant)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            CountUp(streak.toDouble(), decimals: 0, style: TextStyle(fontSize: compact ? 30 : 40, fontWeight: FontWeight.w800, height: 1)),
            const SizedBox(width: 6),
            Text(streak == 1 ? 'day present' : 'days present in a row', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
          ]),
          if (reached != null) Padding(padding: const EdgeInsets.only(top: 6), child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), gradient: const LinearGradient(colors: [Color(0xFFF3DE9C), Color(0xFFC9A24A)])),
              child: Text('✓ $reached', style: const TextStyle(color: Color(0xFF3A2600), fontWeight: FontWeight.w800, fontSize: 11.5)))),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(9), child: TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: frac), duration: const Duration(milliseconds: 1400), curve: Curves.easeOutCubic,
              builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: dark ? const Color(0xFF3A3024) : const Color(0xFFF1E7D3), color: const Color(0xFFEE8A22)))),
          const SizedBox(height: 4),
          Text(next == 0 ? 'Amazing — two months without missing a day!' : 'Next: $next days · ${next - streak} more to go${best > streak ? ' · best $best' : ''}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF8A5A00))),
        ])),
      ]),
    );
  }
}

class _Flame extends StatefulWidget {
  const _Flame();
  @override
  State<_Flame> createState() => _FlameState();
}

class _FlameState extends State<_Flame> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  @override
  void didChangeDependencies() { super.didChangeDependencies(); loopWhileVisible(context, c, reverse: true); }
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => RepaintBoundary(child: AnimatedBuilder(animation: c, builder: (_, __) {
        final t = Curves.easeInOut.transform(c.value);
        return Transform(alignment: Alignment.bottomCenter, transform: Matrix4.diagonal3Values(1 + .04 * t, 1 - .04 * t, 1)..rotateZ((t - .5) * .06),
            child: CustomPaint(painter: _FlamePainter()));
      }));
}

class _FlamePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final outer = Path()..moveTo(w * .5, h * .04)..cubicTo(w * .58, h * .26, w * .86, h * .36, w * .86, h * .64)..arcToPoint(Offset(w * .14, h * .64), radius: Radius.circular(w * .36), clockwise: true)
      ..cubicTo(w * .14, h * .48, w * .27, h * .4, w * .31, h * .27)..cubicTo(w * .38, h * .38, w * .42, h * .42, w * .45, h * .44)..cubicTo(w * .48, h * .3, w * .47, h * .16, w * .5, h * .04)..close();
    canvas.drawPath(outer, Paint()..shader = const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xFFE2401A), Color(0xFFFF9A2E), Color(0xFFFFD66B)]).createShader(Offset.zero & s));
    final inner = Path()..moveTo(w * .5, h * .5)..cubicTo(w * .55, h * .6, w * .66, h * .64, w * .66, h * .74)..arcToPoint(Offset(w * .34, h * .74), radius: Radius.circular(w * .16), clockwise: true)..cubicTo(w * .34, h * .66, w * .44, h * .62, w * .5, h * .5)..close();
    canvas.drawPath(inner, Paint()..color = const Color(0xFFFFE9A6));
  }
  @override
  bool shouldRepaint(_FlamePainter o) => false;
}

class _MonthCard extends StatelessWidget {
  final DateTime month; final Map<String, dynamic> days; final VoidCallback onPrev; final VoidCallback? onNext;
  const _MonthCard({required this.month, required this.days, required this.onPrev, this.onNext});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month), count = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday - 1;   // Monday first
    Color? colour(String? st) => switch (st) { 'present' => Brand.green, 'late' => const Color(0xFFE0A21B), 'absent' => Brand.crimson, 'leave' => Brand.violet, _ => null };
    return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Column(children: [
      Row(children: [
        IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded)),
        Expanded(child: Text(DateFormat('MMMM yyyy').format(month), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded)),
      ]),
      Row(children: [for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S']) Expanded(child: Center(child: Text(d, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))))]),
      const SizedBox(height: 6),
      GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 6, crossAxisSpacing: 6, children: [
        for (var i = 0; i < lead; i++) const SizedBox.shrink(),
        for (var d = 1; d <= count; d++) Builder(builder: (_) {
          final st = days[DateFormat('yyyy-MM-dd').format(DateTime(month.year, month.month, d))] as String?;
          final c = colour(st);
          return Container(alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: c?.withValues(alpha: .16), border: c == null ? null : Border.all(color: c, width: 1.6)),
              child: Text('$d', style: TextStyle(fontSize: 12.5, fontWeight: c == null ? FontWeight.w500 : FontWeight.w800, color: c ?? cs.onSurfaceVariant)));
        }),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 6, alignment: WrapAlignment.center, children: [
        for (final (l, c) in [('Present', Brand.green), ('Late', const Color(0xFFE0A21B)), ('Absent', Brand.crimson), ('Leave', Brand.violet)])
          Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: c)), const SizedBox(width: 5), Text(l, style: const TextStyle(fontSize: 12))]),
      ]),
    ]));
  }
}
