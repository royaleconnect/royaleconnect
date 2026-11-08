import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/royal_motion.dart' show reduceMotion;

/// Morning brief: the greeting card at the top of the staff Today page. The sun rises behind a soft hill (the moon at night).
/// The counts (leave, messages, diary) are NOT repeated here — they live in the one NEEDS YOU card below it.
/// [TodayPeriods] lists today's periods. One database call: staff_morning_brief().
final morningBriefProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.cacheFor();
  final r = await db.rpc('staff_morning_brief');
  return Map<String, dynamic>.from((r as Map?) ?? const {});
});

class MorningBrief extends ConsumerStatefulWidget {
  const MorningBrief({super.key});
  @override
  ConsumerState<MorningBrief> createState() => _MorningBriefState();
}

/// Colours of the sky at one time of day.
class _MbSky {
  final List<Color> sky, hill; final Color ink, soft, chip; final bool night;
  const _MbSky(this.sky, this.hill, this.ink, this.soft, this.chip, {this.night = false});
}

class _MorningBriefState extends ConsumerState<MorningBrief> with SingleTickerProviderStateMixin {
  late final AnimationController _rise = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
  Timer? _tick;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // "Now" and "Next" move on by themselves during the day
    _tick = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _rise.value = 1;
    } else {
      _rise.forward();   // plays once; the sun stays up afterwards
    }
  }

  @override
  void dispose() { _tick?.cancel(); _rise.dispose(); super.dispose(); }

  _MbSky _skyFor(int hour, bool dark) {
    if (hour >= 19 || hour < 5) {
      return const _MbSky([Color(0xFF1B2140), Color(0xFF2D3462)], [Color(0xFF262B4F), Color(0xFF1D2142)], Colors.white, Color(0xFFC9CCE6), Color(0x2EFFFFFF), night: true);
    }
    if (dark) {
      return const _MbSky([Color(0xFF3A2A17), Color(0xFF262019)], [Color(0xFF4A3520), Color(0xFF3B2B1A)], Color(0xFFF7EBD6), Color(0xFFE8C97A), Color(0x26FFFFFF));
    }
    if (hour >= 17) {   // evening glow
      return const _MbSky([Color(0xFFF9D2B4), Color(0xFFFFEEDD)], [Color(0xFFEDC79A), Color(0xFFE2B57F)], Brand.ink, Color(0xFF8A4A00), Color(0xD9FFFFFF));
    }
    return const _MbSky([Color(0xFFFDE7C4), Color(0xFFFFF7EA)], [Color(0xFFF3D9A8), Color(0xFFEBC98C)], Brand.ink, Color(0xFF8A5A00), Color(0xD9FFFFFF));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value;
    final b = ref.watch(morningBriefProvider).value ?? const <String, dynamic>{};
    final now = DateTime.now();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sky = _skyFor(now.hour, dark);
    final greet = now.hour < 5 || now.hour >= 19 ? 'Good evening' : now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';
    final name = '${b['name'] ?? s?.staff?['name'] ?? ''}'.trim();
    final card = ClipRRect(borderRadius: BorderRadius.circular(18), child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 120), child: Stack(children: [
      Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: sky.sky)))),
      if (sky.night) const Positioned.fill(child: CustomPaint(painter: _MbStars())),
      // the sun (or moon) rises: moved with a transform, never by changing its position
      Positioned(right: 46, bottom: 18, width: 80, height: 80, child: RepaintBoundary(child: AnimatedBuilder(animation: _rise, builder: (_, child) {
        final v = Curves.easeOutCubic.transform(_rise.value);
        return Transform.translate(offset: Offset(0, 90 * (1 - v)), child: child);
      }, child: sky.night ? const CustomPaint(painter: _MbMoon()) : const DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Color(0xFFFFE38A), Color(0xFFF8B84A), Color(0x00F6A93B)], stops: [0, .55, 1])))))),
      // the soft hill in front of it
      Positioned(left: 0, right: 0, bottom: 0, height: 40, child: CustomPaint(painter: _MbHill(sky.hill))),
      Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 26), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(DateFormat('EEEE, d MMMM').format(now), style: TextStyle(fontSize: 13, color: sky.soft, fontWeight: FontWeight.w700)),
        Padding(padding: const EdgeInsets.only(right: 90), child: Text(name.isEmpty ? greet : '$greet, $name',
            style: GoogleFonts.cormorantGaramond(fontSize: MediaQuery.sizeOf(context).width < 700 ? 26 : 32, fontWeight: FontWeight.w700, color: sky.ink, height: 1.15))),
      ])),
    ])));
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: card);
  }
}

/// "Your periods today" — shown only when the timetable has periods for this teacher today.
/// The current period is outlined in gold; "Now" and "Next" move on by themselves.
class TodayPeriods extends ConsumerStatefulWidget {
  const TodayPeriods({super.key});
  @override
  ConsumerState<TodayPeriods> createState() => _TodayPeriodsState();
}

class _TodayPeriodsState extends ConsumerState<TodayPeriods> {
  Timer? _tick;
  @override
  void initState() { super.initState(); _tick = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); }); }
  @override
  void dispose() { _tick?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final b = ref.watch(morningBriefProvider).value ?? const <String, dynamic>{};
    final periods = [for (final p in (b['periods'] as List?) ?? const []) Map<String, dynamic>.from(p as Map)];
    if (b['has_timetable'] != true || periods.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final weekday = (b['weekday'] as num?)?.toInt() ?? now.weekday;
    final cs = Theme.of(context).colorScheme;
    // Now / Next: a period lasts until the next one starts (or 40 minutes for the last one, or after a long gap)
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(String hhmm) { final p = hhmm.split(':'); return today.add(Duration(hours: int.parse(p[0]), minutes: int.parse(p[1]))); }
    final starts = [for (final p in periods) at('${p['starts_at']}')];
    final isToday = weekday == now.weekday;
    final nextIdx = isToday ? starts.indexWhere((t) => t.isAfter(now)) : -1;
    final rows = <Widget>[];
    for (var i = 0; i < periods.length; i++) {
      final st = starts[i];
      final end = i + 1 < starts.length && starts[i + 1].difference(st).inMinutes <= 90 ? starts[i + 1] : st.add(const Duration(minutes: 40));
      final isNow = isToday && !now.isBefore(st) && now.isBefore(end);
      final done = isToday && !now.isBefore(end);
      final tag = isNow ? 'Now' : done ? 'done' : i == nextIdx ? 'Next' : '';
      rows.add(_MbPeriod(time: DateFormat('h:mm a').format(st).toLowerCase(), what: [periods[i]['section'], periods[i]['subject']].where((x) => x != null && '$x'.isNotEmpty).join(' · '), tag: tag, now: isNow));
    }
    return Container(margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outline.withValues(alpha: .6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(isToday ? 'YOUR PERIODS TODAY' : 'YOUR PERIODS ON ${const ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'][(weekday - 1).clamp(0, 6)]}', style: TextStyle(fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
        ...rows,
      ]));
  }
}

class _MbPeriod extends StatelessWidget {
  final String time, what, tag; final bool now;
  const _MbPeriod({required this.time, required this.what, required this.tag, required this.now});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: now ? Brand.gold : cs.outline, width: now ? 1.5 : 1),
        boxShadow: now ? [BoxShadow(color: dark ? Brand.gold.withValues(alpha: .22) : const Color(0xFFFFF1CC), spreadRadius: 3)] : null),
      child: Row(children: [
        SizedBox(width: 70, child: Text(time, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
        Expanded(child: Text(what, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
        if (tag.isNotEmpty) Text(tag, style: now ? TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: context.tone(Brand.amber)) : TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
      ]));
  }
}

/// A soft rounded hill along the bottom of the card.
class _MbHill extends CustomPainter {
  final List<Color> colors;
  const _MbHill(this.colors);
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(0, 0, s.width, s.height);
    final path = Path()..moveTo(0, s.height)..lineTo(0, s.height * .9)
      ..cubicTo(s.width * .18, 0, s.width * .82, 0, s.width, s.height * .9)..lineTo(s.width, s.height)..close();
    canvas.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(r));
  }
  @override
  bool shouldRepaint(_MbHill o) => o.colors != colors;
}

/// A pale gold crescent with a faint glow.
class _MbMoon extends CustomPainter {
  const _MbMoon();
  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = s.width * .3;
    canvas.drawCircle(c, r * 1.7, Paint()..shader = RadialGradient(colors: [const Color(0x55F6E2A6), const Color(0x00F6E2A6)]).createShader(Rect.fromCircle(center: c, radius: r * 1.7)));
    final moon = Path.combine(PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: c, radius: r)),
        Path()..addOval(Rect.fromCircle(center: c + Offset(r * .55, -r * .35), radius: r * .9)));
    canvas.drawPath(moon, Paint()..color = const Color(0xFFF6E2A6));
  }
  @override
  bool shouldRepaint(_MbMoon o) => false;
}

/// A few still stars for the night sky.
class _MbStars extends CustomPainter {
  const _MbStars();
  static const _pts = [[.08, .22], [.2, .1], [.33, .3], [.46, .14], [.58, .26], [.66, .08], [.9, .18], [.78, .36], [.14, .5]];
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = const Color(0xB3FFFFFF);
    for (final (i, q) in _pts.indexed) { canvas.drawCircle(Offset(q[0] * s.width, q[1] * s.height), i.isEven ? 1.2 : .8, p); }
  }
  @override
  bool shouldRepaint(_MbStars o) => false;
}
