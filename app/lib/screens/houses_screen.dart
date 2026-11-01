import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/data3.dart' show appSettingsProvider, featureOn, yearLabelProvider;
import '../widgets/common.dart';
import '../widgets/hub_tabs.dart';
import '../widgets/royal_extras.dart' show GoldLoading;
import '../widgets/royal_motion.dart';
import 'academics_screens.dart' show AppPage;
import '../widgets/r_refresh.dart';

/// House points: Athena, Ares, Artemis and Apollo. Four flags rise to this year's totals; the leader gets a crown.
/// Families and staff see the same board; points are added on the staff page (Honours → Houses).

const houseColors = <String, Color>{
  'Athena': Color(0xFFE9B90F),
  'Ares': Color(0xFFC8202A),
  'Artemis': Color(0xFF1E8A4C),
  'Apollo': Color(0xFF1F5FB8),
};
const houseNames = ['Athena', 'Ares', 'Artemis', 'Apollo'];

/// 'apollo ' → 'Apollo' (null when it is not one of the four houses)
String? houseNameOf(String? raw) {
  final v = (raw ?? '').trim().toLowerCase();
  for (final h in houseNames) {
    if (h.toLowerCase() == v) return h;
  }
  return null;
}

/// This year's four totals.
final houseTotalsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  ref.cacheFor();
  final rows = await db.rpc('house_points_totals') as List;
  final out = {for (final h in houseNames) h: 0};
  for (final r in rows) {
    final h = houseNameOf(r['house'] as String?);
    if (h != null) out[h] = (r['points'] as num?)?.toInt() ?? 0;
  }
  return out;
});

/// The active child's house (families).
final myHouseProvider = FutureProvider.autoDispose<String?>((ref) async {
  ref.cacheFor();
  final s = ref.watch(sessionProvider).value;
  final st = s?.active;
  if (s == null || s.isStaff || st == null) return null;
  return houseNameOf(await db.rpc('house_of', params: {'p_student': st.id}) as String?);
});

class HousesScreen extends ConsumerWidget {
  const HousesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = featureOn(ref.watch(appSettingsProvider).value, 'houses');
    final totals = ref.watch(houseTotalsProvider);
    final mine = ref.watch(myHouseProvider).value;
    final year = ref.watch(yearLabelProvider).value;
    return AppPage(title: 'Houses', hub: Hub.honours, body: !on
        ? const Padding(padding: EdgeInsets.all(20), child: NoteBox('House points are not shown in the app at the moment.'))
        : RRefresh(
            onRefresh: () async => ref.invalidate(houseTotalsProvider),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 40), children: [
              totals.when(
                loading: () => const GoldLoading(),
                error: (e, _) => const NoteBox('Could not load the house points. Pull down to try again.'),
                data: (t) => HouseFlagsBoard(totals: t, myHouse: mine, caption: year == null ? 'House points' : 'House points · $year'),
              ),
              const SizedBox(height: 16),
              if (mine != null) FadeRise(delayMs: 2400, child: Center(child: Text.rich(TextSpan(children: [
                TextSpan(text: 'Your house: ', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 15)),
                TextSpan(text: mine, style: TextStyle(color: houseTextColor(context, mine), fontSize: 15, fontWeight: FontWeight.w900)),
              ])))),
              const SizedBox(height: 14),
              Text('Points are added through the year for sports, competitions, good conduct and helping others.',
                  textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5, height: 1.5)),
            ]),
          ));
  }
}

/// House colour that reads well as text on the page (Athena's yellow is darkened on light pages).
Color houseTextColor(BuildContext context, String house) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final c = houseColors[house] ?? Colors.grey;
  if (house == 'Athena') return dark ? const Color(0xFFF2CB3A) : const Color(0xFF9A7A00);
  if (!dark) return c;
  return Color.lerp(c, Colors.white, .35)!;
}

// ================================================================== the flags board (shared with the staff page)
/// Four poles on a night-crimson stage. Flags rise to their totals when shown (and glide to new totals after a change);
/// the numbers count up with them; after the rise a gold crown settles over the leader. The flags wave gently.
class HouseFlagsBoard extends StatefulWidget {
  final Map<String, int> totals; final String? myHouse; final String? caption; final double height;
  const HouseFlagsBoard({super.key, required this.totals, this.myHouse, this.caption, this.height = 330});
  @override
  State<HouseFlagsBoard> createState() => _HouseFlagsBoardState();
}

class _HouseFlagsBoardState extends State<HouseFlagsBoard> with TickerProviderStateMixin {
  late final AnimationController rise = AnimationController(vsync: this, duration: const Duration(milliseconds: 2300));
  late final AnimationController wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  Map<String, double> from = {for (final h in houseNames) h: 0};
  bool firstDone = false;

  @override
  void initState() {
    super.initState();
    rise.addStatusListener((s) { if (s == AnimationStatus.completed && !firstDone && mounted) setState(() => firstDone = true); });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loopWhileVisible(context, wave, reverse: true);
    if (reduceMotion(context)) { rise.value = 1; firstDone = true; }
    else if (rise.value == 0 && !rise.isAnimating) { Future.delayed(const Duration(milliseconds: 180), () { if (mounted) rise.forward(); }); }
  }

  @override
  void didUpdateWidget(covariant HouseFlagsBoard old) {
    super.didUpdateWidget(old);
    if (!_same(old.totals, widget.totals)) {
      final v = Curves.easeOutCubic.transform(rise.value);
      from = {for (final h in houseNames) h: _lerp(from[h]!, (old.totals[h] ?? 0).toDouble(), v)};
      if (reduceMotion(context)) { from = {for (final h in houseNames) h: (widget.totals[h] ?? 0).toDouble()}; rise.value = 1; } else { rise.forward(from: 0); }
    }
  }

  static bool _same(Map<String, int> a, Map<String, int> b) => houseNames.every((h) => (a[h] ?? 0) == (b[h] ?? 0));
  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  void dispose() { rise.dispose(); wave.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = widget.totals;
    final top = houseNames.map((h) => t[h] ?? 0).fold<int>(0, math.max);
    final scaleMax = math.max(10, top * 1.08);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF3B0A11), Color(0xFF1C0609), Color(0xFF120407)]),
        border: Border.all(color: const Color(0xFFE8C97A).withValues(alpha: .35)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.caption != null) Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 0), child: Text(widget.caption!.toUpperCase(),
            textAlign: TextAlign.center, style: GoogleFonts.cinzel(color: const Color(0xFFF3DE9C), fontSize: 12.5, letterSpacing: 2.4, fontWeight: FontWeight.w700))),
        SizedBox(height: widget.height, child: AnimatedBuilder(animation: rise, builder: (context, _) {
          final v = Curves.easeOutCubic.transform(rise.value);
          // the crown fades and drops in at the end of the first rise; later it simply follows the leader
          final crownT = firstDone ? 1.0 : ((rise.value - .86) / .14).clamp(0.0, 1.0);
          return LayoutBuilder(builder: (context, c) {
            const nameH = 60.0, topPad = 34.0, flagH = 34.0;
            final poleH = c.maxHeight - nameH - topPad;
            return Stack(children: [
              // plinth: a gold hairline the poles stand on
              Positioned(left: 18, right: 18, bottom: nameH - 1, child: Container(height: 2, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Color(0xFFC9A24A), Color(0xFFF3DE9C), Color(0xFFC9A24A), Colors.transparent])))),
              Row(children: [
                for (final h in houseNames) Expanded(child: Builder(builder: (_) {
                  final now = _lerp(from[h]!, (t[h] ?? 0).toDouble(), v);
                  final frac = (math.max(0.0, now) / scaleMax).clamp(0.0, 1.0);
                  final flagBottom = nameH + frac * (poleH - flagH - 6);
                  final leader = top > 0 && (t[h] ?? 0) == top;
                  final mine = widget.myHouse == h;
                  return Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
                    // pole
                    Positioned(bottom: nameH, top: topPad, child: Container(width: 4, decoration: BoxDecoration(borderRadius: BorderRadius.circular(3),
                        gradient: const LinearGradient(colors: [Color(0xFF8E8C93), Color(0xFFEDEBF2), Color(0xFF8E8C93)])))),
                    // gold knob
                    Positioned(top: topPad - 7, child: Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle,
                        gradient: RadialGradient(center: Alignment(-.3, -.3), colors: [Color(0xFFFFF1C2), Color(0xFFA8822F)])))),
                    // flag (its left edge on the pole)
                    Positioned(bottom: flagBottom, child: Transform.translate(offset: const Offset(25, 0),
                        child: RepaintBoundary(child: CustomPaint(size: const Size(46, flagH), painter: _FlagPainter(wave, houseColors[h]!, h.length))))),
                    // crown over the leader
                    if (leader && crownT > 0) Positioned(bottom: flagBottom + flagH + 4 + (1 - crownT) * 14, child: Opacity(opacity: crownT,
                        child: Transform.translate(offset: const Offset(25, 0), child: const CustomPaint(size: Size(26, 18), painter: _CrownPainter())))),
                    // name + points
                    Positioned(bottom: 0, left: 0, right: 0, height: nameH - 6, child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: mine ? BoxDecoration(color: houseColors[h]!.withValues(alpha: .9), borderRadius: BorderRadius.circular(99)) : null,
                        child: Text(h, maxLines: 1, overflow: TextOverflow.fade, softWrap: false,
                            style: TextStyle(color: mine ? (h == 'Athena' ? const Color(0xFF2A1F00) : Colors.white) : _onDark(h), fontWeight: FontWeight.w900, fontSize: 13.5)),
                      ),
                      const SizedBox(height: 2),
                      Text('${now.round()}', style: GoogleFonts.cormorantGaramond(color: const Color(0xFFF3DE9C), fontSize: 19, fontWeight: FontWeight.w700, height: 1.1)),
                    ])),
                  ]);
                })),
              ]),
            ]);
          });
        })),
      ]),
    );
  }

  static Color _onDark(String h) => switch (h) {
        'Athena' => const Color(0xFFF2CB3A),
        'Ares' => const Color(0xFFFF7A7F),
        'Artemis' => const Color(0xFF6FD39A),
        _ => const Color(0xFF8DB5F2),
      };
}

/// A plain coloured swallow-tail flag with a soft sheen, waving gently.
class _FlagPainter extends CustomPainter {
  final Animation<double> a; final Color color; final int seed;
  _FlagPainter(this.a, this.color, this.seed) : super(repaint: a);
  @override
  void paint(Canvas canvas, Size s) {
    final ph = Curves.easeInOut.transform(a.value) * 2 - 1;     // -1 … 1
    double dy(double x) => math.sin(x / s.width * math.pi * 1.4 + seed) * 2.6 * ph * (x / s.width);
    final p = Path()..moveTo(0, 0);
    const n = 8;
    for (var i = 1; i <= n; i++) { final x = s.width * i / n; p.lineTo(x, s.height * .06 * i / n + dy(x)); }
    p.lineTo(s.width * .86, s.height * .5 + dy(s.width * .86));
    for (var i = n; i >= 0; i--) { final x = s.width * i / n; p.lineTo(x, s.height - s.height * .06 * i / n + dy(x)); }
    p.close();
    canvas.drawPath(p, Paint()..color = color);
    // a moving sheen gives the cloth some depth
    final sheen = Paint()..shader = LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
        colors: [Colors.black.withValues(alpha: .18), Colors.white.withValues(alpha: .16 + .08 * ph), Colors.black.withValues(alpha: .10), Colors.white.withValues(alpha: .10)],
        stops: const [0, .35, .7, 1]).createShader(Offset.zero & s);
    canvas.drawPath(p, sheen);
  }
  @override
  bool shouldRepaint(_FlagPainter o) => o.color != color;
}

/// A small gold crown (painted, so it looks the same on every phone).
class _CrownPainter extends CustomPainter {
  const _CrownPainter();
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final p = Path()
      ..moveTo(w * .06, h * .92)..lineTo(w * .02, h * .28)..lineTo(w * .3, h * .55)..lineTo(w * .5, h * .08)
      ..lineTo(w * .7, h * .55)..lineTo(w * .98, h * .28)..lineTo(w * .94, h * .92)..close();
    canvas.drawPath(p, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFFFFF1C2), Color(0xFFE8C97A), Color(0xFFA8822F)]).createShader(Offset.zero & s));
    canvas.drawPath(p, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = const Color(0xFF7A5A18));
    for (final x in [.02, .5, .98]) {
      canvas.drawCircle(Offset(w * x, h * (x == .5 ? .08 : .28)), 2.2, Paint()..color = const Color(0xFFFFF6DC));
    }
  }
  @override
  bool shouldRepaint(_CrownPainter o) => false;
}
