import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'royal_motion.dart' show liteMotion;

/// A white-and-gold paper plane flies across the screen and fades (~1.2 s) — shown once when a notice is sent.
/// It never blocks taps and removes itself when done.
void showPaperPlane(BuildContext context) {
  if (liteMotion(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _PlaneFlight(onDone: () { if (entry.mounted) entry.remove(); }));
  overlay.insert(entry);
}

class _PlaneFlight extends StatefulWidget {
  final VoidCallback onDone;
  const _PlaneFlight({required this.onDone});
  @override
  State<_PlaneFlight> createState() => _PlaneFlightState();
}

class _PlaneFlightState extends State<_PlaneFlight> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
    ..addStatusListener((s) { if (s == AnimationStatus.completed) widget.onDone(); })
    ..forward();

  @override
  void dispose() { c.dispose(); super.dispose(); }

  /// Where the plane is at time t (0–1): from lower left, a gentle loop upwards, out at the top right.
  Offset _at(double t, Size s) {
    final x = -60 + (s.width + 120) * t;
    final y = s.height * (.72 - .5 * t) - math.sin(t * math.pi) * s.height * .12;
    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(child: RepaintBoundary(child: LayoutBuilder(builder: (_, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        return AnimatedBuilder(animation: c, builder: (_, __) {
          final t = Curves.easeInOutSine.transform(c.value);
          final p = _at(t, size), q = _at(math.min(1, t + .02), size);
          final angle = math.atan2(q.dy - p.dy, q.dx - p.dx);
          final fade = c.value < .12 ? c.value / .12 : c.value > .75 ? (1 - c.value) / .25 : 1.0;
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _TrailPainter([for (var i = 0; i < 9; i++) _at(math.max(0, t - .025 * (i + 1)), size)], fade))),
            Positioned(left: p.dx - 28, top: p.dy - 28, child: Opacity(opacity: fade.clamp(0.0, 1.0),
                child: Transform.rotate(angle: angle, child: const SizedBox(width: 56, height: 56, child: CustomPaint(painter: _PlanePainter()))))),
          ]);
        });
      })));
}

/// The plane, pointing right: white wings with a gold edge and a gold fold line.
class _PlanePainter extends CustomPainter {
  const _PlanePainter();
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final top = Path()..moveTo(w * .95, h * .5)..lineTo(w * .05, h * .18)..lineTo(w * .32, h * .52)..close();
    final bottom = Path()..moveTo(w * .95, h * .5)..lineTo(w * .32, h * .52)..lineTo(w * .2, h * .82)..close();
    canvas.drawShadow(top, Colors.black, 3, false);
    canvas.drawPath(bottom, Paint()..color = const Color(0xFFEDE3CF));
    canvas.drawPath(top, Paint()..color = Colors.white);
    final edge = Paint()..color = const Color(0xFFC9A24A)..style = PaintingStyle.stroke..strokeWidth = 1.6..strokeJoin = StrokeJoin.round;
    canvas.drawPath(top, edge);
    canvas.drawPath(bottom, edge);
    canvas.drawLine(Offset(w * .95, h * .5), Offset(w * .32, h * .52), edge..strokeWidth = 1.2);
  }
  @override
  bool shouldRepaint(_PlanePainter o) => false;
}

/// A short dotted gold trail behind the plane.
class _TrailPainter extends CustomPainter {
  final List<Offset> pts; final double fade;
  _TrailPainter(this.pts, this.fade);
  @override
  void paint(Canvas canvas, Size s) {
    for (final (i, p) in pts.indexed) {
      final a = (fade * (1 - i / pts.length) * .8).clamp(0.0, 1.0);
      canvas.drawCircle(p, 2.6 - i * .2, Paint()..color = const Color(0xFFC9A24A).withValues(alpha: a));
    }
  }
  @override
  bool shouldRepaint(_TrailPainter o) => true;
}
