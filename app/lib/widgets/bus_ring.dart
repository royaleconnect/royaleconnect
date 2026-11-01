import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The gold countdown ring on the live bus card: minutes to your stop in the middle; the ring empties as the bus nears
/// (full at 20 minutes or more). The number and the ring move smoothly between position updates.
class BusCountdownRing extends StatelessWidget {
  final int minutes; final double size;
  const BusCountdownRing({super.key, required this.minutes, this.size = 76});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: minutes.toDouble()), duration: const Duration(milliseconds: 900), curve: Curves.easeOutCubic,
      builder: (_, v, __) => SizedBox(width: size, height: size, child: RepaintBoundary(child: CustomPaint(
        painter: _Ring((v / 20).clamp(0.0, 1.0), cs.outline.withValues(alpha: .35)),
        child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(minutes <= 0 ? 'Now' : '${v.round()}', style: TextStyle(fontSize: minutes <= 0 ? size * .22 : size * .3, fontWeight: FontWeight.w800, height: 1.05, color: cs.onSurface)),
          if (minutes > 0) Text('min', style: TextStyle(fontSize: size * .14, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
        ])),
      ))),
    );
  }
}

class _Ring extends CustomPainter {
  final double v; final Color track;
  _Ring(this.v, this.track);
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width * .09, r = Rect.fromLTWH(w / 2, w / 2, s.width - w, s.height - w);
    canvas.drawArc(r, 0, 2 * math.pi, false, Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = w);
    if (v <= 0) return;
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * v, false, Paint()
      ..shader = const SweepGradient(colors: [Color(0xFFC9A24A), Color(0xFFF6E2A6), Color(0xFFC9A24A)], transform: GradientRotation(-math.pi / 2)).createShader(r)
      ..style = PaintingStyle.stroke..strokeWidth = w..strokeCap = StrokeCap.round);
  }
  @override
  bool shouldRepaint(_Ring o) => o.v != v || o.track != track;
}
