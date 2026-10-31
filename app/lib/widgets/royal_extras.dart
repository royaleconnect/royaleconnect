import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'royal_motion.dart';

/// Royal Edition, part 2: shimmer loading, the living header, the sun / moon, the gold ring, press effect,
/// spotlight and twinkles, the report-card envelope, the full-screen birthday and the festival celebrations.

// ================================================================== gold shimmer loading
/// Instead of a spinning circle: three soft bars with a gold light running over them.
class GoldLoading extends StatefulWidget {
  final int lines;
  const GoldLoading({super.key, this.lines = 3});
  @override
  State<GoldLoading> createState() => _GoldLoadingState();
}

class _GoldLoadingState extends State<GoldLoading> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF2A272D) : const Color(0xFFECE5D8);
    final hi = dark ? const Color(0xFF5A4A2A) : const Color(0xFFF8E9C2);
    return Center(child: Padding(padding: const EdgeInsets.all(20), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: AnimatedBuilder(animation: c, builder: (_, __) {
      final m = -0.5 + c.value * 2;
      return ShaderMask(blendMode: BlendMode.srcATop,
        shaderCallback: (r) => LinearGradient(colors: [base, hi, base], stops: [(m - .25).clamp(0.0, 1.0), m.clamp(0.0, 1.0), (m + .25).clamp(0.0, 1.0)]).createShader(r),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < widget.lines; i++) Container(height: i == 0 ? 16 : 12, width: i == 0 ? 220 : (i.isOdd ? 320 : 260), margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(8))),
        ]),
      );
    }))));
  }
}

// ================================================================== the living header
/// The crimson header slowly moves like silk, with a soft light drifting across it.
class LivingSilk extends StatefulWidget {
  final Widget child; final List<Color> colors;
  const LivingSilk({super.key, required this.child, this.colors = const [Color(0xFFC4161E), Color(0xFF9A0F15), Color(0xFF6E080D)]});
  @override
  State<LivingSilk> createState() => _LivingSilkState();
}

class _LivingSilkState extends State<LivingSilk> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: widget.colors)), child: widget.child);
    return AnimatedBuilder(animation: c, child: widget.child, builder: (_, child) {
      final a = c.value * 2 * math.pi;
      return DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment(-1 + .3 * math.sin(a), -1 + .3 * math.cos(a)), end: Alignment(1 - .3 * math.sin(a), 1 - .3 * math.cos(a)), colors: widget.colors, stops: const [0, .55, 1])),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: RadialGradient(center: Alignment(-1.2 + 2.4 * ((c.value * 1.0) % 1), -.6 + .4 * math.sin(a * 2)), radius: .9,
              colors: [const Color(0xFFFFD9A0).withValues(alpha: .16), Colors.transparent])),
          child: child),
      );
    });
  }
}

// ================================================================== sun / moon by the greeting
/// Morning: a sun with slowly turning rays · afternoon: a warm sun · evening: a crescent moon with twinkling stars.
class TimeOfDayIcon extends StatefulWidget {
  final double size;
  const TimeOfDayIcon({super.key, this.size = 30});
  @override
  State<TimeOfDayIcon> createState() => _TimeOfDayIconState();
}

class _TimeOfDayIconState extends State<TimeOfDayIcon> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().hour;
    final night = h >= 18 || h < 5;
    return SizedBox(width: widget.size, height: widget.size, child: AnimatedBuilder(animation: c, builder: (_, __) => CustomPaint(painter: _SkyPainter(c.value, night))));
  }
}

class _SkyPainter extends CustomPainter {
  final double t; final bool night;
  _SkyPainter(this.t, this.night);
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero), r = s.width * .26;
    if (!night) {
      final ray = Paint()..color = const Color(0xFFFFD36E)..strokeWidth = s.width * .07..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final a = t * 2 * math.pi + i * math.pi / 4;
        final pulse = 1 + .12 * math.sin(t * 2 * math.pi * 3 + i);
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r * 1.45, c + Offset(math.cos(a), math.sin(a)) * r * 1.85 * pulse, ray);
      }
      canvas.drawCircle(c, r * 1.25, Paint()..color = const Color(0x55FFD36E)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(c, r, Paint()..shader = const RadialGradient(colors: [Color(0xFFFFF1B8), Color(0xFFFFC23D)]).createShader(Rect.fromCircle(center: c, radius: r)));
    } else {
      final moon = Path()..addOval(Rect.fromCircle(center: c, radius: r * 1.3));
      final cut = Path()..addOval(Rect.fromCircle(center: c + Offset(r * .7, -r * .45), radius: r * 1.15));
      canvas.drawPath(Path.combine(PathOperation.difference, moon, cut), Paint()..color = const Color(0xFFFFF1C9));
      for (final (i, p) in [const Offset(.82, .22), const Offset(.9, .62), const Offset(.62, .1)].indexed) {
        final tw = .4 + .6 * (.5 + .5 * math.sin(t * 2 * math.pi * 4 + i * 2));
        canvas.drawCircle(Offset(p.dx * s.width, p.dy * s.height), s.width * .035 * (1 + tw), Paint()..color = Colors.white.withValues(alpha: tw));
      }
    }
  }
  @override
  bool shouldRepaint(_SkyPainter o) => true;
}

// ================================================================== gold progress ring
/// A ring that fills with gold up to [percent], with the number counting up in the middle.
class GoldRing extends StatelessWidget {
  final double percent; final double size; final Color track; final Color? textColor;
  const GoldRing(this.percent, {super.key, this.size = 64, this.track = const Color(0x22C9A24A), this.textColor});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: percent.clamp(0, 100) / 100), duration: Duration(milliseconds: reduceMotion(context) ? 0 : 1600), curve: Curves.easeOutCubic,
        builder: (_, v, __) => SizedBox(width: size, height: size, child: CustomPaint(painter: _RingPainter(v, track), child: Center(child: Text('${(v * 100).round()}%',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * .24, color: textColor ?? Theme.of(context).colorScheme.onSurface))))),
      );
}

class _RingPainter extends CustomPainter {
  final double v; final Color track;
  _RingPainter(this.v, this.track);
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width * .1, r = Rect.fromLTWH(w / 2, w / 2, s.width - w, s.height - w);
    canvas.drawArc(r, 0, 2 * math.pi, false, Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = w);
    if (v <= 0) return;
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * v, false, Paint()
      ..shader = const SweepGradient(colors: [Color(0xFFC9A24A), Color(0xFFF6E2A6), Color(0xFFC9A24A)], transform: GradientRotation(-math.pi / 2)).createShader(r)
      ..style = PaintingStyle.stroke..strokeWidth = w..strokeCap = StrokeCap.round);
  }
  @override
  bool shouldRepaint(_RingPainter o) => o.v != v;
}

// ================================================================== press effect
/// The child presses in a little when touched (with a light tap feel on phones).
class PressScale extends StatefulWidget {
  final Widget child; final bool enabled;
  const PressScale({super.key, required this.child, this.enabled = true});
  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool down = false;
  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: widget.enabled ? (_) { setState(() => down = true); HapticFeedback.lightImpact(); } : null,
        onPointerUp: (_) => setState(() => down = false), onPointerCancel: (_) => setState(() => down = false),
        child: AnimatedScale(scale: down ? .965 : 1, duration: const Duration(milliseconds: 120), curve: Curves.easeOut, child: widget.child),
      );
}

// ================================================================== spotlight + twinkles (Star of the month)
class Spotlight extends StatefulWidget {
  final Widget child;
  const Spotlight({super.key, required this.child});
  @override
  State<Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<Spotlight> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(animation: c, builder: (_, __) => CustomPaint(painter: _TwinklePainter(c.value))))),
        ShineSweep(delay: const Duration(milliseconds: 600), every: const Duration(milliseconds: 4500), child: widget.child),
      ]);
}

class _TwinklePainter extends CustomPainter {
  final double t; _TwinklePainter(this.t);
  static final _pts = List.generate(14, (i) { final r = math.Random(i * 31); return [r.nextDouble(), r.nextDouble(), r.nextDouble() * 6.28, .6 + r.nextDouble()]; });
  @override
  void paint(Canvas canvas, Size s) {
    // a soft beam of light from the top
    final beam = Path()..moveTo(s.width * .45, -40)..lineTo(s.width * .55, -40)..lineTo(s.width * .85, s.height)..lineTo(s.width * .15, s.height)..close();
    canvas.drawPath(beam, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFFFFE7A8).withValues(alpha: .35 + .1 * math.sin(t * 6.28)), Colors.transparent]).createShader(Offset.zero & s));
    for (final p in _pts) {
      final tw = (math.sin(t * 6.28 * 2 * p[3] + p[2]) + 1) / 2;
      final o = Offset(p[0] * s.width, p[1] * s.height), k = 3 + 5 * tw;
      final star = Path()..moveTo(o.dx, o.dy - k)..lineTo(o.dx + k * .25, o.dy - k * .25)..lineTo(o.dx + k, o.dy)..lineTo(o.dx + k * .25, o.dy + k * .25)
        ..lineTo(o.dx, o.dy + k)..lineTo(o.dx - k * .25, o.dy + k * .25)..lineTo(o.dx - k, o.dy)..lineTo(o.dx - k * .25, o.dy - k * .25)..close();
      canvas.drawPath(star, Paint()..color = const Color(0xFFE8B84A).withValues(alpha: .25 + .6 * tw));
    }
  }
  @override
  bool shouldRepaint(_TwinklePainter o) => true;
}

/// A soft pulsing ring (e.g. around "your stop" on the bus map).
class PulseRing extends StatefulWidget {
  final Widget child; final Color color;
  const PulseRing({super.key, required this.child, required this.color});
  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        AnimatedBuilder(animation: c, builder: (_, __) => Transform.scale(scale: 1 + c.value * 1.4, child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: widget.color.withValues(alpha: 1 - c.value), width: 3))))),
        widget.child,
      ]);
}

// ================================================================== report card envelope
/// A sealed envelope: tap it, the wax seal breaks, the flap opens and the card slides out; then [onOpen] runs.
class EnvelopeReveal extends StatefulWidget {
  final String title; final String subtitle; final VoidCallback onOpen;
  const EnvelopeReveal({super.key, required this.title, required this.subtitle, required this.onOpen});
  @override
  State<EnvelopeReveal> createState() => _EnvelopeRevealState();
}

class _EnvelopeRevealState extends State<EnvelopeReveal> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900));
  bool opened = false;
  @override
  void dispose() { c.dispose(); super.dispose(); }
  Future<void> _open() async {
    if (opened) return;
    opened = true; HapticFeedback.mediumImpact();
    if (!reduceMotion(context)) await c.forward();
    widget.onOpen();
  }
  double _i(double a, double b) => Curves.easeInOutCubic.transform(((c.value - a) / (b - a)).clamp(0.0, 1.0));
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: _open, child: AspectRatio(aspectRatio: 1.55, child: LayoutBuilder(builder: (_, box) => AnimatedBuilder(animation: c, builder: (_, __) {
        final w = box.maxWidth, h = box.maxHeight;
        final seal = 1 - _i(.0, .2), flap = _i(.15, .5), slide = _i(.45, 1);
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: const Color(0xFFE9DCC2), borderRadius: BorderRadius.circular(10)))),
          // the report card
          Positioned(left: w * .07, right: w * .07, top: h * .08 - slide * h * .55, height: h * .8, child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFFFFDF7), borderRadius: BorderRadius.circular(6), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: GoogleFonts.cormorantGaramond(fontSize: 20, fontWeight: FontWeight.w700, color: const Color(0xFF7E0A10))),
              Text(widget.subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6A5A40))),
              const Divider(),
              for (var i = 0; i < 3; i++) Container(margin: const EdgeInsets.only(top: 6), height: 7, width: w * (.55 - i * .1), decoration: BoxDecoration(color: const Color(0xFFEDE3D0), borderRadius: BorderRadius.circular(4))),
            ]))),
          // front pocket
          Positioned.fill(child: ClipPath(clipper: _PocketClip(), child: const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF3E7CF), Color(0xFFDCC9A6)]))))),
          // flap
          Positioned(left: 0, right: 0, top: 0, height: h * .58, child: Transform(alignment: Alignment.topCenter, transform: Matrix4.identity()..setEntry(3, 2, .0015)..rotateX(math.pi * flap),
              child: ClipPath(clipper: _FlapClip(), child: const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE2D1B0), Color(0xFFCDB68D)])))))),
          // wax seal
          if (seal > 0) Positioned(left: w / 2 - 26, top: h * .58 - 26, child: Opacity(opacity: seal, child: Transform.scale(scale: .6 + .4 * seal, child: Container(width: 52, height: 52, alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(center: Alignment(-.3, -.3), colors: [Color(0xFFD3333B), Color(0xFF7E0A10)]), boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6)]),
              child: Text('R', style: GoogleFonts.cormorantGaramond(fontSize: 26, fontWeight: FontWeight.w700, color: const Color(0xFFF6E2A6))))))),
          if (!opened) Positioned(left: 0, right: 0, bottom: 10, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(99)),
              child: const Text('Tap to open', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5))))),
        ]);
      }))));
}

class _PocketClip extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()..moveTo(0, s.height * .3)..lineTo(s.width / 2, s.height * .62)..lineTo(s.width, s.height * .3)..lineTo(s.width, s.height)..lineTo(0, s.height)..close();
  @override
  bool shouldReclip(covariant CustomClipper<Path> o) => false;
}

class _FlapClip extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()..moveTo(0, 0)..lineTo(s.width, 0)..lineTo(s.width / 2, s.height)..close();
  @override
  bool shouldReclip(covariant CustomClipper<Path> o) => false;
}

// ================================================================== falling / rising emoji (festivals, birthday)
enum DriftMode { fall, rise, float, walk }

class EmojiDrift extends StatefulWidget {
  final List<String> emojis; final DriftMode mode; final int count; final double size;
  final List<Color> confetti;     // optional coloured paper (e.g. tricolour)
  final bool snow;
  const EmojiDrift({super.key, required this.emojis, this.mode = DriftMode.fall, this.count = 26, this.size = 30, this.confetti = const [], this.snow = false});
  @override
  State<EmojiDrift> createState() => _EmojiDriftState();
}

class _EmojiDriftState extends State<EmojiDrift> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();
  late final List<List<double>> p;
  late final List<TextPainter> glyphs;
  @override
  void initState() {
    super.initState();
    final r = math.Random();
    p = [for (var i = 0; i < widget.count; i++) [r.nextDouble(), r.nextDouble(), .04 + r.nextDouble() * .06, r.nextDouble() * 6.28, .7 + r.nextDouble() * .6, (r.nextDouble() * 1000).floorToDouble()]];
    glyphs = [for (final e in widget.emojis) TextPainter(text: TextSpan(text: e, style: TextStyle(fontSize: widget.size)), textDirection: TextDirection.ltr)..layout()];
  }
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return const SizedBox.shrink();
    return IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _DriftPainter(c, p, glyphs, widget.mode, widget.confetti, widget.snow)));
  }
}

class _DriftPainter extends CustomPainter {
  final Animation<double> a; final List<List<double>> p; final List<TextPainter> g; final DriftMode mode; final List<Color> confetti; final bool snow;
  _DriftPainter(this.a, this.p, this.g, this.mode, this.confetti, this.snow) : super(repaint: a);
  @override
  void paint(Canvas canvas, Size s) {
    final t = a.value * 30;
    for (final (i, q) in p.indexed) {
      final prog = (q[1] + t * q[2]) % 1;
      double x, y;
      switch (mode) {
        case DriftMode.fall: x = q[0] * s.width + math.sin(t * .8 + q[3]) * 24; y = -60 + prog * (s.height + 120);
        case DriftMode.rise: x = q[0] * s.width + math.sin(t * .7 + q[3]) * 20; y = s.height + 60 - prog * (s.height + 120);
        case DriftMode.float: x = q[0] * s.width + math.sin(t * .4 + q[3]) * 30; y = q[1] * s.height + math.cos(t * .5 + q[3]) * 26;
        case DriftMode.walk: x = -80 + prog * (s.width + 160); y = s.height - 70 - (i % 3) * 46 - (math.sin(t * 8 + q[3]).abs() * 8);
      }
      // snow and confetti alongside the emoji
      if (snow && i.isEven) { canvas.drawCircle(Offset(q[0] * s.width + math.sin(t + q[3]) * 30, ((q[4] + t * .05) % 1) * s.height), 2 + q[4] * 2, Paint()..color = Colors.white.withValues(alpha: .85)); }
      if (confetti.isNotEmpty && i % 2 == 1) {
        canvas.save(); canvas.translate(q[0] * s.width + math.cos(t + q[3]) * 40, ((q[1] + t * .07) % 1) * s.height); canvas.rotate(t * 2 + q[3]);
        canvas.drawRect(const Rect.fromLTWH(-5, -2.5, 10, 5), Paint()..color = confetti[q[5].toInt() % confetti.length]); canvas.restore();
        continue;
      }
      final glyph = g[q[5].toInt() % g.length];
      canvas.save();
      canvas.translate(x, y);
      if (mode != DriftMode.walk) canvas.rotate(math.sin(t * .9 + q[3]) * .35);
      canvas.scale(q[4]);
      glyph.paint(canvas, Offset(-glyph.width / 2, -glyph.height / 2));
      canvas.restore();
    }
  }
  @override
  bool shouldRepaint(_DriftPainter o) => false;
}

// ================================================================== festivals
class Festival {
  final String key, greeting, line; final List<String> emojis; final DriftMode mode; final List<Color> colors; final List<Color> confetti; final bool snow;
  final String mark;   // the big symbol on the banner
  const Festival(this.key, this.greeting, this.line, this.mark, this.emojis, this.mode, this.colors, {this.confetti = const [], this.snow = false});
}

const _tricolour = [Color(0xFFFF9933), Colors.white, Color(0xFF138808)];

const festivals = <Festival>[
  Festival('halloween', 'Happy Halloween!', 'Spooky fun from all of us at Royale Concorde', '🎃', ['🎃', '🦇', '👻', '🎃', '🍬'], DriftMode.fall, [Color(0xFFFF7A00), Color(0xFF3A1A00)]),
  Festival('diwali', 'Happy Diwali!', 'May the festival of lights fill your home with joy', '🪔', ['🪔', '✨', '🪔', '🎆', '✨'], DriftMode.rise, [Color(0xFFFFB300), Color(0xFF7A1F00)]),
  Festival('dussehra', 'Happy Dussehra!', 'May goodness always win', '🏹', ['🌼', '🏹', '🌼', '✨'], DriftMode.fall, [Color(0xFFFF8F00), Color(0xFF8E1B0A)]),
  Festival('eid', 'Eid Mubarak!', 'Wishing you peace, joy and blessings', '🌙', ['🌙', '⭐', '✨', '⭐'], DriftMode.float, [Color(0xFF0F5E4B), Color(0xFF062A24)]),
  Festival('bakrid', 'Eid al-Adha Mubarak!', 'Wishing you and your family peace and blessings', '🌙', ['🐑', '🐑', '🐑'], DriftMode.walk, [Color(0xFF0F5E4B), Color(0xFF062A24)]),
  Festival('christmas', 'Merry Christmas!', 'Warm wishes for a joyful Christmas', '🎄', ['🎄', '🎁', '❄️', '⭐'], DriftMode.fall, [Color(0xFF0E6B3A), Color(0xFF7E0A10)], snow: true),
  Festival('republic', 'Happy Republic Day!', 'Proud to be Indian', '🇮🇳', ['🇮🇳'], DriftMode.fall, [Color(0xFFFF9933), Color(0xFF138808)], confetti: _tricolour),
  Festival('independence', 'Happy Independence Day!', 'Freedom in the mind, faith in the words, pride in our souls', '🇮🇳', ['🇮🇳'], DriftMode.fall, [Color(0xFFFF9933), Color(0xFF138808)], confetti: _tricolour),
  Festival('gandhi', 'Gandhi Jayanti', 'Truth · Non-violence · Simplicity', '👓', ['🕊️', '👓', '🕊️'], DriftMode.float, [Color(0xFF6D6D6D), Color(0xFF2B2B2B)]),
  Festival('teachers', "Happy Teachers' Day!", 'Thank you, teachers, for everything you do', '🍎', ['❤️', '💐', '📚', '🍎', '💖'], DriftMode.rise, [Color(0xFFD81B60), Color(0xFF6A0F3A)]),
  Festival('children', "Happy Children's Day!", 'Keep shining, keep smiling!', '🎈', ['🎈', '🌹', '🎉', '⭐', '🎈'], DriftMode.rise, [Color(0xFF7B2FF7), Color(0xFF2E0F6B)]),
];

/// Festival days. Fixed dates every year, plus the moving festivals (from the school-holiday calendars; Eid dates depend on the moon,
/// and the celebration lasts a week, so a day's difference does not matter).
List<(String, DateTime)> _festivalDays(int y) => [
      ('republic', DateTime(y, 1, 26)), ('independence', DateTime(y, 8, 15)), ('teachers', DateTime(y, 9, 5)), ('gandhi', DateTime(y, 10, 2)),
      ('halloween', DateTime(y, 10, 31)), ('children', DateTime(y, 11, 14)), ('christmas', DateTime(y, 12, 25)),
      ...?{
        2026: [('dussehra', DateTime(2026, 10, 20)), ('diwali', DateTime(2026, 11, 8))],
        2027: [('eid', DateTime(2027, 3, 10)), ('bakrid', DateTime(2027, 5, 17)), ('dussehra', DateTime(2027, 10, 9)), ('diwali', DateTime(2027, 10, 29))],
        2028: [('eid', DateTime(2028, 2, 27)), ('bakrid', DateTime(2028, 5, 6)), ('dussehra', DateTime(2028, 9, 27)), ('diwali', DateTime(2028, 10, 17))],
      }[y],
    ];

/// The festival being celebrated today: from its day for a week (the most recent one wins).
Festival? festivalToday([DateTime? now]) {
  final d = now ?? DateTime.now();
  final today = DateTime(d.year, d.month, d.day);
  (String, DateTime)? best;
  for (final f in [..._festivalDays(d.year), ..._festivalDays(d.year - 1)]) {
    final diff = today.difference(f.$2).inDays;
    if (diff >= 0 && diff <= 6 && (best == null || f.$2.isAfter(best.$2))) best = f;
  }
  if (best == null) return null;
  return festivals.firstWhere((f) => f.key == best!.$1);
}

/// On Home (families) and Today (staff): a festive banner for the week, and the first time it is seen in a session
/// the whole screen fills with the festival's animation for a few seconds.
class FestiveBanner extends StatefulWidget {
  const FestiveBanner({super.key});
  @override
  State<FestiveBanner> createState() => _FestiveBannerState();
}

class _FestiveBannerState extends State<FestiveBanner> {
  static final _played = <String>{};
  OverlayEntry? _entry;
  late final Festival? f = festivalToday();

  @override
  void initState() {
    super.initState();
    if (f != null && !_played.contains(f!.key)) {
      _played.add(f!.key);
      WidgetsBinding.instance.addPostFrameCallback((_) => _celebrate());
    }
  }

  void _celebrate() {
    if (!mounted || f == null || reduceMotion(context)) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _entry = OverlayEntry(builder: (_) => _FadingLayer(festival: f!, onGone: () { _entry?.remove(); _entry = null; }));
    overlay.insert(_entry!);
  }

  @override
  void dispose() { _entry?.remove(); _entry = null; super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final fest = f;
    if (fest == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: GestureDetector(
      onTap: _entry == null ? _celebrate : null,
      child: Container(
        height: 92, clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: fest.colors),
            boxShadow: [BoxShadow(color: fest.colors.first.withValues(alpha: .35), blurRadius: 18, offset: const Offset(0, 6))]),
        child: Stack(children: [
          Positioned.fill(child: EmojiDrift(emojis: fest.emojis, mode: fest.mode == DriftMode.walk ? DriftMode.walk : DriftMode.float, count: 8, size: 18, confetti: fest.confetti, snow: fest.snow)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Row(children: [
            _Bob(child: Text(fest.mark, style: const TextStyle(fontSize: 44))),
            const SizedBox(width: 14),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fest.greeting, style: GoogleFonts.greatVibes(fontSize: 30, color: Colors.white, height: 1.1, shadows: const [Shadow(color: Colors.black38, blurRadius: 6)])),
              Text(fest.line, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .92), fontSize: 13, fontWeight: FontWeight.w600)),
            ])),
          ])),
        ]),
      ),
    ));
  }
}

class _Bob extends StatefulWidget {
  final Widget child; const _Bob({required this.child});
  @override
  State<_Bob> createState() => _BobState();
}

class _BobState extends State<_Bob> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: c, child: widget.child,
      builder: (_, child) => Transform.translate(offset: Offset(0, -4 * Curves.easeInOut.transform(c.value)), child: Transform.rotate(angle: (c.value - .5) * .12, child: child)));
}

/// The whole-screen festival animation: fades in, plays ~7 seconds, fades out (touches pass through).
class _FadingLayer extends StatefulWidget {
  final Festival festival; final VoidCallback onGone;
  const _FadingLayer({required this.festival, required this.onGone});
  @override
  State<_FadingLayer> createState() => _FadingLayerState();
}

class _FadingLayerState extends State<_FadingLayer> {
  double o = 0; Timer? _a, _b;
  @override
  void initState() {
    super.initState();
    _a = Timer(const Duration(milliseconds: 50), () { if (mounted) setState(() => o = 1); });
    _b = Timer(const Duration(milliseconds: 7000), () { if (mounted) setState(() => o = 0); Timer(const Duration(milliseconds: 900), widget.onGone); });
  }
  @override
  void dispose() { _a?.cancel(); _b?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final f = widget.festival;
    return IgnorePointer(child: AnimatedOpacity(opacity: o, duration: const Duration(milliseconds: 800), child: Stack(children: [
      Positioned.fill(child: EmojiDrift(emojis: f.emojis, mode: f.mode, count: f.mode == DriftMode.walk ? 9 : 28, size: f.mode == DriftMode.walk ? 40 : 32, confetti: f.confetti, snow: f.snow)),
      if (f.key == 'diwali') const Positioned(left: 0, right: 0, bottom: 0, height: 70, child: _DiyaRow()),
      if (f.key == 'eid' || f.key == 'bakrid') Positioned(right: 24, top: 70, child: Text('🌙', style: TextStyle(fontSize: 64, shadows: [Shadow(color: Colors.amber.withValues(alpha: .7), blurRadius: 30)]))),
    ])));
  }
}

/// A row of flickering diyas along the bottom (Diwali).
class _DiyaRow extends StatefulWidget {
  const _DiyaRow();
  @override
  State<_DiyaRow> createState() => _DiyaRowState();
}

class _DiyaRowState extends State<_DiyaRow> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: c, builder: (_, __) => LayoutBuilder(builder: (_, b) {
        final n = (b.maxWidth / 70).floor().clamp(4, 24);
        return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (var i = 0; i < n; i++) Transform.scale(scale: .92 + .1 * math.sin(c.value * 6.28 * 2 + i), child: Text('🪔', style: TextStyle(fontSize: 34,
              shadows: [Shadow(color: const Color(0xFFFFB300).withValues(alpha: .6 + .3 * math.sin(c.value * 6.28 * 3 + i * 1.7)), blurRadius: 22)]))),
        ]);
      }));
}

// ================================================================== the birthday, full screen once
/// On the child's birthday (or the first time the app is opened within 6 days after it), a full-screen wish:
/// balloons rise, confetti bursts and "Happy Birthday" is written in gold script. Shown once a year per child on this phone.
class BirthdayGate extends StatefulWidget {
  final Widget child; final String? studentId; final String? firstName; final String? dobIso;
  const BirthdayGate({super.key, required this.child, this.studentId, this.firstName, this.dobIso});
  @override
  State<BirthdayGate> createState() => _BirthdayGateState();
}

class _BirthdayGateState extends State<BirthdayGate> {
  bool show = false; int lateDays = 0; String? _checkedFor;

  @override
  void didUpdateWidget(covariant BirthdayGate old) { super.didUpdateWidget(old); _check(); }
  @override
  void initState() { super.initState(); _check(); }

  Future<void> _check() async {
    final id = widget.studentId, dob = DateTime.tryParse(widget.dobIso ?? '');
    if (id == null || dob == null || _checkedFor == '$id${widget.dobIso}') return;
    _checkedFor = '$id${widget.dobIso}';
    final now = DateTime.now(), today = DateTime(now.year, now.month, now.day);
    int late = -1;
    for (final y in [now.year, now.year - 1]) {
      var b = DateTime(y, dob.month, dob.day);
      if (dob.month == 2 && dob.day == 29 && b.month != 2) b = DateTime(y, 2, 28);
      final d = today.difference(b).inDays;
      if (d >= 0 && d <= 6) { late = d; break; }
    }
    if (late < 0) return;
    final p = await SharedPreferences.getInstance();
    final key = 'rc_bday_${id}_${today.year - (today.month < dob.month ? 1 : 0)}';
    if (p.getBool(key) == true) return;
    await p.setBool(key, true);
    if (mounted) setState(() { show = true; lateDays = late; });
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (show) Positioned.fill(child: TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 700),
            builder: (_, v, c) => Opacity(opacity: v, child: c),
            child: _BirthdayScreen(name: widget.firstName ?? '', belated: lateDays > 0, onClose: () => setState(() => show = false)))),
      ]);
}

class _BirthdayScreen extends StatelessWidget {
  final String name; final bool belated; final VoidCallback onClose;
  const _BirthdayScreen({required this.name, required this.belated, required this.onClose});
  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF140506),
        child: Stack(children: [
          const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(center: Alignment(0, -.6), radius: 1.3, colors: [Color(0xFF5A0B12), Color(0xFF2A070B), Color(0xFF110405)])))),
          const Positioned.fill(child: GoldParticles(count: 50)),
          const Positioned.fill(child: EmojiDrift(emojis: ['🎈', '🎈', '🎉', '🎁', '🎈'], mode: DriftMode.rise, count: 22, size: 42)),
          const Positioned.fill(child: ConfettiBurst(count: 160, origin: Alignment(0, -.3), ms: 3400)),
          SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const FadeRise(delayMs: 300, child: Text('🎂', style: TextStyle(fontSize: 84))),
            const SizedBox(height: 10),
            FadeRise(delayMs: 700, child: GoldText(belated ? 'Happy belated birthday,' : 'Happy Birthday,', style: GoogleFonts.greatVibes(fontSize: 50, height: 1.2))),
            FadeRise(delayMs: 1100, child: GoldText('$name!', style: GoogleFonts.greatVibes(fontSize: 64, height: 1.15))),
            const SizedBox(height: 16),
            FadeRise(delayMs: 1600, child: Text('Wishing you a wonderful year full of learning, friends and success.\n— Your Principal and teachers, Royale Concorde', textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 16, height: 1.6, color: const Color(0xFFEAD9BD)))),
            const SizedBox(height: 30),
            FadeRise(delayMs: 2200, child: FilledButton(onPressed: onClose,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE8C97A), foregroundColor: const Color(0xFF2B1608), minimumSize: const Size(200, 52), shape: const StadiumBorder()),
                child: const Text('Thank you! 💛'))),
          ])))),
        ]),
      );
}

// ================================================================== numbers that count up
/// "1,649", "86%", "₹3,42,500" count up from zero; anything else is shown as it is.
class CountUpText extends StatelessWidget {
  final String value; final TextStyle? style;
  const CountUpText(this.value, {super.key, this.style});
  static String _indian(int n) {
    final s = n.toString();
    if (s.length <= 3) return s;
    final last = s.substring(s.length - 3); var rest = s.substring(0, s.length - 3); final parts = <String>[];
    while (rest.length > 2) { parts.insert(0, rest.substring(rest.length - 2)); rest = rest.substring(0, rest.length - 2); }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last';
  }
  @override
  Widget build(BuildContext context) {
    final m = RegExp(r'^(₹\s?)?([\d,]+)(%?)$').firstMatch(value.trim());
    if (m == null || reduceMotion(context)) return Text(value, style: style);
    final n = int.tryParse(m.group(2)!.replaceAll(',', ''));
    if (n == null) return Text(value, style: style);
    final western = m.group(2)!.contains(',') && !RegExp(r'\d,\d\d,').hasMatch(m.group(2)!) && m.group(2)!.split(',').skip(1).every((g) => g.length == 3);
    return TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: n.toDouble()), duration: const Duration(milliseconds: 1300), curve: Curves.easeOutCubic,
        builder: (_, v, __) {
          final x = v.round();
          final txt = !m.group(2)!.contains(',') ? '$x' : western ? x.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',') : _indian(x);
          return Text('${m.group(1) ?? ''}$txt${m.group(3)}', style: style);
        });
  }
}
