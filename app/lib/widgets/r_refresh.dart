import 'dart:math' as math;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show HapticFeedback;
import '../core/brand_images.dart' show monogramClear;
import 'royal_motion.dart' show loopWhileVisible;

/// Pull to refresh with the school's R — a drop-in for RefreshIndicator:
///   RRefresh(onRefresh: () async => ref.invalidate(x), child: ListView(...))
/// As you pull, the official R monogram comes down and turns like a gold coin; it keeps turning while refreshing,
/// then "Updated just now ✓". Works with touch, and with a mouse drag on the website and laptops.
/// The list inside should be a normal scrolling list (ListView / CustomScrollView) without its own physics.
class RRefresh extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  const RRefresh({super.key, required this.onRefresh, required this.child});
  @override
  State<RRefresh> createState() => _RRefreshState();
}

enum _Phase { idle, refreshing, done }

class _RRefreshState extends State<RRefresh> with TickerProviderStateMixin {
  static const _trigger = 72.0, _hold = 64.0, _max = 120.0;
  late final AnimationController _pos = AnimationController.unbounded(vsync: this);   // how far the page is pulled down (px)
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _dragging = false, _armedBuzz = false;
  _Phase _phase = _Phase.idle;

  @override
  void dispose() { _pos.dispose(); _spin.dispose(); super.dispose(); }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical || _phase != _Phase.idle) return false;
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0 && n.metrics.extentBefore == 0) {
      _dragging = true;
      _set(_pos.value + (-n.overscroll) * .6 * (1 - _pos.value / (_max * 1.6)));   // a little resistance as it goes
    } else if (n is ScrollUpdateNotification && _dragging && (n.scrollDelta ?? 0) > 0) {
      _set(_pos.value - n.scrollDelta!);                                           // pushed back up
    } else if ((n is ScrollEndNotification || (n is UserScrollNotification && n.direction == ScrollDirection.idle)) && _dragging) {
      _release();
    }
    return false;
  }

  void _set(double v) {
    _pos.value = v.clamp(0.0, _max);
    final armed = _pos.value >= _trigger;
    if (armed != _armedBuzz) { _armedBuzz = armed; if (armed) HapticFeedback.selectionClick(); setState(() {}); }
  }

  Future<void> _release() async {
    _dragging = false;
    if (_pos.value < _trigger) { _armedBuzz = false; await _pos.animateTo(0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic); return; }
    setState(() => _phase = _Phase.refreshing);
    _pos.animateTo(_hold, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    loopWhileVisible(context, _spin);
    // at least one full turn, so a quick refresh still looks deliberate
    await Future.wait([widget.onRefresh().catchError((_) {}), Future<void>.delayed(const Duration(milliseconds: 800))]);
    if (!mounted) return;
    _spin.stop(); _spin.value = 0;
    setState(() => _phase = _Phase.done);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    await _pos.animateTo(0, duration: const Duration(milliseconds: 420), curve: Curves.easeInOutCubic);
    if (mounted) setState(() { _phase = _Phase.idle; _armedBuzz = false; });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final gold = dark ? const Color(0xFFE2C178) : const Color(0xFFA8822F);
    final behavior = ScrollConfiguration.of(context).copyWith(
      dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus},
      physics: const ClampingScrollPhysics(), overscroll: false,   // the same pull on every phone, tablet and laptop
    );
    return ClipRect(child: ScrollConfiguration(behavior: behavior, child: NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(children: [
        AnimatedBuilder(animation: _pos, builder: (_, child) => Transform.translate(offset: Offset(0, _pos.value), child: child), child: widget.child),
        Positioned(left: 0, right: 0, top: 0, child: IgnorePointer(child: RepaintBoundary(child: AnimatedBuilder(animation: Listenable.merge([_pos, _spin]), builder: (_, __) {
          final d = _pos.value;
          if (d <= 0.5) return const SizedBox.shrink();
          final angle = _phase == _Phase.refreshing ? _spin.value * 2 * math.pi : _phase == _Phase.done ? 0.0 : d * 4 * math.pi / 180;
          final scale = .6 + math.min(d, 90) / 225;
          final label = switch (_phase) {
            _Phase.refreshing => 'Refreshing…',
            _Phase.done => 'Updated just now ✓',
            _ => d >= _trigger ? 'Release to refresh' : d > 10 ? 'Pull to refresh' : '',
          };
          return SizedBox(height: d, child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Transform.scale(scale: scale, child: Transform(alignment: Alignment.center, transform: Matrix4.identity()..setEntry(3, 2, .0015)..rotateY(angle),
                child: Image.memory(monogramClear, width: 40, height: 46, fit: BoxFit.contain, gaplessPlayback: true))),
            if (label.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 10),
                child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: gold))),
          ])));
        })))),
      ]),
    )));
  }
}
