import 'dart:ui' show PathMetric;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import 'royal_motion.dart' show reduceMotion;

/// The six friendly drawings used on empty pages.
enum EmptyKind { homework, messages, bus, calendar, notices, photos }

/// A friendly empty page: a gold line drawing that draws itself once, a short title and one kind line.
///   EmptyState(kind: EmptyKind.homework, title: 'No homework today', line: 'Enjoy your evening.')
/// [compact] = smaller drawing, for use inside a card or panel.
class EmptyState extends StatefulWidget {
  final EmptyKind kind; final String title; final String? line; final bool compact;
  const EmptyState({super.key, required this.kind, required this.title, this.line, this.compact = false});
  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));
  late final Animation<double> _draw = CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _c.value = 1;
    } else {
      _c.forward();   // plays once and stays drawn
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = widget.compact ? 96.0 : 132.0;
    final textIn = CurvedAnimation(parent: _c, curve: const Interval(.45, 1, curve: Curves.easeOut));
    return Center(child: Padding(padding: EdgeInsets.all(widget.compact ? 16 : 32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      RepaintBoundary(child: CustomPaint(size: Size(w, w * 100 / 120), painter: _LineArtPainter(widget.kind, _draw))),
      SizedBox(height: widget.compact ? 6 : 10),
      FadeTransition(opacity: textIn, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(widget.title, textAlign: TextAlign.center, style: GoogleFonts.cormorantGaramond(fontSize: widget.compact ? 19 : 23, fontWeight: FontWeight.w700, color: cs.onSurface, height: 1.2)),
        if (widget.line != null && widget.line!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: Text(widget.line!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.45, color: cs.onSurfaceVariant)))),
      ])),
    ])));
  }
}

/// Draws the outline of the chosen picture up to [progress] (0 → nothing, 1 → whole drawing). Drawn on a 120 × 100 grid.
class _LineArtPainter extends CustomPainter {
  final EmptyKind kind; final Animation<double> progress;
  _LineArtPainter(this.kind, this.progress) : super(repaint: progress);

  static final Map<EmptyKind, Path> _cache = {};

  static Path _build(EmptyKind k) {
    final p = Path();
    void rrect(double x, double y, double w, double h, double r) => p.addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)));
    void line(List<double> pts, {bool close = false}) {
      p.moveTo(pts[0], pts[1]);
      for (var i = 2; i < pts.length; i += 2) { p.lineTo(pts[i], pts[i + 1]); }
      if (close) p.close();
    }
    void circle(double x, double y, double r) => p.addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
    void star(double x, double y) => line([x, y, x + 2, y + 4, x + 6, y + 6, x + 2, y + 8, x, y + 12, x - 2, y + 8, x - 6, y + 6, x - 2, y + 4], close: true);
    switch (k) {
      case EmptyKind.homework:   // open book under a crescent moon
        line([20, 70, 60, 80, 100, 70, 100, 30, 60, 40, 20, 30], close: true);
        line([60, 40, 60, 80]);
        p.moveTo(92, 8);
        p.arcToPoint(const Offset(104, 24), radius: const Radius.circular(12), largeArc: true, clockwise: false);
        p.arcToPoint(const Offset(92, 8), radius: const Radius.circular(9), largeArc: true, clockwise: true);
        p.close();
        star(28, 16);
      case EmptyKind.messages:   // envelope with three little rays
        rrect(22, 30, 76, 50, 6);
        line([22, 34, 60, 60, 98, 34]);
        line([60, 8, 60, 18]);
        line([48, 12, 52, 18]);
        line([72, 12, 68, 18]);
      case EmptyKind.bus:        // school bus on the road, a small sun
        rrect(20, 30, 80, 44, 10);
        line([28, 40, 92, 40, 92, 54, 28, 54], close: true);
        circle(38, 78, 7);
        circle(82, 78, 7);
        line([14, 88, 106, 88]);
        p.moveTo(96, 14);
        p.arcToPoint(const Offset(96, 28), radius: const Radius.circular(8), clockwise: true);
        line([96, 10, 96, 6]);
        line([106, 21, 110, 21]);
        line([86, 21, 82, 21]);
      case EmptyKind.calendar:   // calendar page with a tick
        rrect(24, 24, 72, 60, 8);
        line([24, 42, 96, 42]);
        line([44, 16, 44, 30]);
        line([76, 16, 76, 30]);
        line([48, 62, 56, 70, 72, 54]);
      case EmptyKind.notices:    // bell with two sparkles
        p.moveTo(60, 18);
        p.cubicTo(46, 18, 38, 28, 38, 42);
        p.lineTo(38, 58);
        p.lineTo(30, 68);
        p.lineTo(90, 68);
        p.lineTo(82, 58);
        p.lineTo(82, 42);
        p.cubicTo(82, 28, 74, 18, 60, 18);
        p.close();
        p.moveTo(52, 72);
        p.arcToPoint(const Offset(68, 72), radius: const Radius.circular(8), clockwise: false);
        line([60, 10, 60, 18]);
        line([92, 22, 98, 18]);
        line([94, 34, 101, 34]);
        star(24, 14);
      case EmptyKind.photos:     // photo frame: hills and a sun
        rrect(22, 26, 76, 56, 8);
        line([28, 74, 46, 54, 58, 66, 68, 58, 92, 74]);
        circle(78, 42, 6);
        star(104, 8);
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _cache.putIfAbsent(kind, () => _build(kind));
    final s = size.width / 120;
    canvas.save();
    canvas.scale(s, s);
    final paint = Paint()
      ..color = Brand.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final t = progress.value.clamp(0.0, 1.0);
    if (t >= 1) {
      canvas.drawPath(path, paint);
    } else if (t > 0) {
      // every stroke starts together and draws at the same speed (short strokes finish first), like ink
      const speed = 400.0;
      for (final PathMetric m in path.computeMetrics()) {
        final len = (speed * t).clamp(0.0, m.length);
        if (len > 0) canvas.drawPath(m.extractPath(0, len), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LineArtPainter o) => o.kind != kind;
}
