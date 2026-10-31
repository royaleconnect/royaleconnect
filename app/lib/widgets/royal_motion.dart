import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// "Royal Edition" motion kit: short, smooth animations used across the app.
/// Every animation respects the phone's "reduce motion" setting (it then shows the end state at once).

bool reduceMotion(BuildContext c) => MediaQuery.maybeDisableAnimationsOf(c) ?? false;

const royalGold = [Color(0xFFF6E2A6), Color(0xFFC9A24A), Color(0xFF9C7A2E)];

// ---------------------------------------------------------------- fade + rise
/// The child fades in and rises a little, after [delayMs].
class FadeRise extends StatefulWidget {
  final Widget child; final int delayMs; final int ms; final double dy;
  const FadeRise({super.key, required this.child, this.delayMs = 0, this.ms = 650, this.dy = 22});
  @override
  State<FadeRise> createState() => _FadeRiseState();
}

class _FadeRiseState extends State<FadeRise> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms));
  Timer? _t;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) { c.value = 1; return; }
    if (c.value == 0 && _t == null) _t = Timer(Duration(milliseconds: widget.delayMs), () { if (mounted) c.forward(); });
  }
  @override
  void dispose() { _t?.cancel(); c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: c, child: widget.child, builder: (_, child) {
        final v = Curves.easeOutCubic.transform(c.value);
        return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * widget.dy), child: child));
      });
}

/// Wraps each widget in a FadeRise, one after another.
List<Widget> staggered(List<Widget> xs, {int startMs = 120, int stepMs = 90}) =>
    [for (var i = 0; i < xs.length; i++) FadeRise(delayMs: startMs + i * stepMs, child: xs[i])];

// ---------------------------------------------------------------- floating gold dust
class GoldParticles extends StatefulWidget {
  final int count; final Color color; final double maxRadius; final double speed;
  const GoldParticles({super.key, this.count = 60, this.color = const Color(0xFFF6E2A6), this.maxRadius = 2.2, this.speed = 1});
  @override
  State<GoldParticles> createState() => _GoldParticlesState();
}

class _GoldParticlesState extends State<GoldParticles> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  late final List<List<double>> p;
  @override
  void initState() {
    super.initState();
    final r = math.Random(7);
    p = [for (var i = 0; i < widget.count; i++) [r.nextDouble(), r.nextDouble(), .4 + r.nextDouble() * widget.maxRadius, .006 + r.nextDouble() * .012, r.nextDouble() * 6.28]];
  }
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return const SizedBox.expand();
    return IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _DustPainter(c, p, widget.color, widget.speed)));
  }
}

class _DustPainter extends CustomPainter {
  final Animation<double> a; final List<List<double>> p; final Color color; final double speed;
  _DustPainter(this.a, this.p, this.color, this.speed) : super(repaint: a);
  @override
  void paint(Canvas canvas, Size s) {
    final t = a.value * 60;   // seconds
    final glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (final q in p) {
      final y = ((q[1] - t * q[3] * speed) % 1 + 1) % 1;
      final x = q[0] + math.sin(t * .5 + q[4]) * .015;
      final al = .25 + .35 * (.5 + .5 * math.sin(t * 1.6 + q[4] * 3));
      canvas.drawCircle(Offset(x * s.width, y * s.height), q[2] * 1.8, glow..color = color.withValues(alpha: al * .45));
      canvas.drawCircle(Offset(x * s.width, y * s.height), q[2] * .7, Paint()..color = color.withValues(alpha: al));
    }
  }
  @override
  bool shouldRepaint(_DustPainter o) => false;
}

// ---------------------------------------------------------------- light sweep
/// A band of light sweeps across the child (once after [delay], then every [every] if given).
class ShineSweep extends StatefulWidget {
  final Widget child; final Duration delay; final Duration? every; final Color shine; final int ms;
  const ShineSweep({super.key, required this.child, this.delay = Duration.zero, this.every, this.shine = const Color(0xCCFFF4D6), this.ms = 1300});
  @override
  State<ShineSweep> createState() => _ShineSweepState();
}

class _ShineSweepState extends State<ShineSweep> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms));
  Timer? _t;
  @override
  void initState() { super.initState(); _t = Timer(widget.delay, _go); }
  void _go() {
    if (!mounted) return;
    c.forward(from: 0);
    if (widget.every != null) _t = Timer(widget.every!, _go);
  }
  @override
  void dispose() { _t?.cancel(); c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    return AnimatedBuilder(animation: c, child: widget.child, builder: (_, child) {
      final v = c.value;
      if (v == 0 || v == 1) return child!;
      final m = -0.3 + v * 1.6;
      final stops = [(m - .14).clamp(0.0, 1.0), m.clamp(0.0, 1.0), (m + .14).clamp(0.0, 1.0)];
      return ShaderMask(blendMode: BlendMode.srcATop, shaderCallback: (r) => LinearGradient(
          begin: const Alignment(-1, -.35), end: const Alignment(1, .35),
          colors: [Colors.transparent, widget.shine, Colors.transparent], stops: stops).createShader(r), child: child);
    });
  }
}

// ---------------------------------------------------------------- confetti
/// One burst of gold, crimson and ivory confetti from [origin] (0–1 of the area). Plays once when shown.
class ConfettiBurst extends StatefulWidget {
  final int count; final Alignment origin; final int ms;
  const ConfettiBurst({super.key, this.count = 120, this.origin = const Alignment(0, -.2), this.ms = 2600});
  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms))..forward();
  late final List<List<double>> p;
  static const cols = [Color(0xFFF6E2A6), Color(0xFFC9A24A), Color(0xFFE8C97A), Color(0xFFC4161E), Color(0xFFFFF6DC)];
  @override
  void initState() {
    super.initState();
    final r = math.Random();
    p = [for (var i = 0; i < widget.count; i++) [(r.nextDouble() - .5) * 2.2, -r.nextDouble() * 2.4 - .5, 4 + r.nextDouble() * 7, r.nextDouble() * 6, (r.nextDouble() - .5) * 14, (r.nextDouble() * 5).floorToDouble()]];
  }
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return const SizedBox.shrink();
    return IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _ConfettiPainter(c, p, widget.origin)));
  }
}

class _ConfettiPainter extends CustomPainter {
  final Animation<double> a; final List<List<double>> p; final Alignment o;
  _ConfettiPainter(this.a, this.p, this.o) : super(repaint: a);
  @override
  void paint(Canvas canvas, Size s) {
    final t = a.value * 2.6;
    final ox = (o.x + 1) / 2 * s.width, oy = (o.y + 1) / 2 * s.height;
    final fade = (1 - a.value).clamp(0.0, 1.0);
    for (final q in p) {
      final x = ox + q[0] * s.width * .45 * t;
      final y = oy + q[1] * s.height * .35 * t + .5 * s.height * .55 * t * t;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(q[3] + q[4] * t);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: q[2], height: q[2] * .45), Paint()..color = _ConfettiBurstState.cols[q[5].toInt()].withValues(alpha: fade));
      canvas.restore();
    }
  }
  @override
  bool shouldRepaint(_ConfettiPainter o) => false;
}

// ---------------------------------------------------------------- counting number
/// Counts up from 0 to [value] (e.g. 98.4 → "98.4%").
class CountUp extends StatelessWidget {
  final double value; final int decimals; final String suffix; final TextStyle? style; final int ms;
  const CountUp(this.value, {super.key, this.decimals = 1, this.suffix = '', this.style, this.ms = 1400});
  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return Text('${value.toStringAsFixed(decimals)}$suffix', style: style);
    return TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: value), duration: Duration(milliseconds: ms), curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text('${v.toStringAsFixed(decimals)}$suffix', style: style));
  }
}

// ---------------------------------------------------------------- stamp
/// A rubber stamp that lands with a thump (e.g. PAID).
class StampIn extends StatelessWidget {
  final String text; final Color color; final int delayMs;
  const StampIn(this.text, {super.key, this.color = const Color(0xFF1E7F4F), this.delayMs = 400});
  @override
  Widget build(BuildContext context) {
    final stamp = Transform.rotate(angle: -.24, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(border: Border.all(color: color, width: 4), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 30, letterSpacing: 4)),
    ));
    if (reduceMotion(context)) return Opacity(opacity: .9, child: stamp);
    return FutureBuilder(future: Future.delayed(Duration(milliseconds: delayMs)), builder: (_, snap) {
      if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
      return TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 520), curve: Curves.easeOutBack,
          builder: (_, v, child) => Opacity(opacity: (v * 1.4).clamp(0.0, .9), child: Transform.scale(scale: 3 - 2 * v, child: child)), child: stamp);
    });
  }
}

// ---------------------------------------------------------------- SVG path text → Path
/// Reads simple SVG path data (M, L, Q, C, Z, absolute) — what our signature and logo tracings use.
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLQCZmlqcz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0; String cmd = 'M';
  double n() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (RegExp(r'^[A-Za-z]$').hasMatch(tokens[i])) cmd = tokens[i++].toUpperCase();
    switch (cmd) {
      case 'M': path.moveTo(n(), n()); cmd = 'L'; break;
      case 'L': path.lineTo(n(), n()); break;
      case 'Q': path.quadraticBezierTo(n(), n(), n(), n()); break;
      case 'C': path.cubicTo(n(), n(), n(), n(), n(), n()); break;
      case 'Z': path.close(); break;
      default: i++;
    }
  }
  return path;
}

// ---------------------------------------------------------------- handwriting
/// Draws pen strokes one after another like a real pen, with a glowing nib at the tip; then the ink fills in.
class AnimatedSignature extends StatefulWidget {
  final List<String> paths; final Rect bounds; final Color color; final bool start; final int ms; final VoidCallback? onDone; final bool nib;
  final bool instant;   // show it already written (after Skip)
  const AnimatedSignature({super.key, required this.paths, required this.bounds, this.color = const Color(0xFFF3DA95), this.start = true, this.ms = 3200, this.onDone, this.nib = true, this.instant = false});
  @override
  State<AnimatedSignature> createState() => _AnimatedSignatureState();
}

class _AnimatedSignatureState extends State<AnimatedSignature> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms));
  late final List<Path> ps = [for (final d in widget.paths) parseSvgPath(d)];
  bool _started = false;
  @override
  void initState() { super.initState(); c.addStatusListener((s) { if (s == AnimationStatus.completed) widget.onDone?.call(); }); }
  @override
  void didChangeDependencies() { super.didChangeDependencies(); _maybeStart(); }
  @override
  void didUpdateWidget(covariant AnimatedSignature old) { super.didUpdateWidget(old); _maybeStart(); }
  void _maybeStart() {
    if (!widget.start || _started) return;
    _started = true;
    if (widget.instant || reduceMotion(context)) { c.value = 1; WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone?.call()); } else { c.forward(); }
  }
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AspectRatio(aspectRatio: widget.bounds.width / widget.bounds.height,
      child: CustomPaint(painter: _SigPainter(c, ps, widget.bounds, widget.color, widget.nib)));
}

class _SigPainter extends CustomPainter {
  final Animation<double> a; final List<Path> ps; final Rect b; final Color color; final bool nib;
  late final List<double> lens = [for (final p in ps) p.computeMetrics().fold(0.0, (s, m) => s + m.length)];
  _SigPainter(this.a, this.ps, this.b, this.color, this.nib) : super(repaint: a);
  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / b.width;
    canvas.save();
    canvas.scale(k);
    canvas.translate(-b.left, -b.top);
    final total = lens.fold(0.0, (x, y) => x + y);
    // the first 82% of the time writes the strokes, the rest lets the ink fill in
    final drawn = (a.value / .82).clamp(0.0, 1.0) * total;
    final fill = ((a.value - .78) / .22).clamp(0.0, 1.0);
    final stroke = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2 / k * 1.6..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..color = color;
    var used = 0.0; Offset? tip;
    for (var i = 0; i < ps.length; i++) {
      if (fill > 0) canvas.drawPath(ps[i], Paint()..color = color.withValues(alpha: fill));
      final left = drawn - used;
      if (left <= 0) break;
      if (left >= lens[i]) {
        canvas.drawPath(ps[i], stroke);
      } else {
        var rem = left;
        for (final m in ps[i].computeMetrics()) {
          if (rem <= 0) break;
          final l = math.min(rem, m.length);
          canvas.drawPath(m.extractPath(0, l), stroke);
          tip = m.getTangentForOffset(l)?.position;
          rem -= m.length;
        }
      }
      used += lens[i];
    }
    if (nib && tip != null && a.value < .82) {
      canvas.drawCircle(tip, 7 / k, Paint()..color = const Color(0xFFFFE6A8).withValues(alpha: .55)..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 / k));
      canvas.drawCircle(tip, 2.4 / k, Paint()..color = const Color(0xFFFFF8E6));
    }
    canvas.restore();
  }
  @override
  bool shouldRepaint(_SigPainter o) => false;
}

// ---------------------------------------------------------------- gold text
/// Text filled with a metallic gold gradient.
class GoldText extends StatelessWidget {
  final String text; final TextStyle style; final TextAlign align;
  const GoldText(this.text, {super.key, required this.style, this.align = TextAlign.center});
  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0xFFF6E2A6), Color(0xFFC9A24A), Color(0xFFF3DC9A), Color(0xFFB08A35)], stops: [0, .45, .7, 1]).createShader(r),
        child: Text(text, textAlign: align, style: style.copyWith(color: Colors.white)),
      );
}
