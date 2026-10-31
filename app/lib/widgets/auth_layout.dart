import 'package:flutter/material.dart';
import '../core/config.dart';
import '../core/theme.dart';
import 'common.dart';
import 'royal_motion.dart' show staggered, GoldParticles;
import 'royal_extras.dart' show LivingSilk;

/// Frame for the sign-in pages (parents, staff, set-password). Always fills the whole screen:
///   • laptop / wide tablet (900 px+): red school panel on the left, the form centred on the right
///   • upright tablet: red header across the top, the form centred below
///   • phone: red header on top, form below (as before)
class AuthLayout extends StatelessWidget {
  final String title, subtitle;
  final String? eyebrow, formTitle, formSubtitle;
  final Widget? topAction;            // close button, or "Parent / student sign in"
  final List<Widget> children;        // the form
  const AuthLayout({super.key, required this.title, required this.subtitle, required this.children, this.eyebrow, this.formTitle, this.formSubtitle, this.topAction});

  static Widget monogram(double size) => Container(
        padding: EdgeInsets.all(size * .22),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * .3)),
        child: Image.asset('assets/images/monogram.png', width: size),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(body: LayoutBuilder(builder: (context, c) {
      final split = c.maxWidth >= 900;
      final form = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (split && formTitle != null) ...[
          Text(formTitle!, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          if (formSubtitle != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(formSubtitle!, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant))),
          const SizedBox(height: 26),
        ],
        ...staggered(children, startMs: 200, stepMs: 70),
      ]);

      if (split) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(flex: 11, child: _BrandPanel(title: title, subtitle: subtitle, eyebrow: eyebrow, topAction: topAction)),
          Container(width: 4, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00C9A24A), Brand.gold2, Brand.gold, Color(0x00C9A24A)]))),
          Expanded(flex: 10, child: SafeArea(child: Center(child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: form),
          )))),
        ]);
      }

      final tablet = c.maxWidth > 600;
      return Column(children: [
        BrandHeader(
          padding: tablet ? const EdgeInsets.fromLTRB(40, 24, 40, 34) : const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [monogram(28), const Spacer(), if (topAction != null) topAction!]),
            const SizedBox(height: 18),
            if (eyebrow != null) ...[Eyebrow(eyebrow!, color: Colors.white), const SizedBox(height: 6)],
            Text(title, style: t.headlineMedium?.copyWith(color: Colors.white, fontSize: tablet ? 38 : 30)),
            const SizedBox(height: 6),
            Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: .92), fontSize: tablet ? 17 : 15, height: 1.4)),
          ]),
        ),
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, tablet ? 36 : 24, 20, 32),
          child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: form)),
        )),
      ]);
    }));
  }
}

/// Left half on a laptop: the school's red panel, full height.
class _BrandPanel extends StatelessWidget {
  final String title, subtitle; final String? eyebrow; final Widget? topAction;
  const _BrandPanel({required this.title, required this.subtitle, this.eyebrow, this.topAction});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget ring(double size, Color c) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c)));
    return ClipRect(child: LivingSilk(
      child: Stack(children: [
        const Positioned.fill(child: GoldParticles(count: 40, maxRadius: 1.8, speed: .7)),
        Positioned(right: -180, bottom: -180, child: ring(560, Colors.white.withValues(alpha: .13))),
        Positioned(right: -120, bottom: -120, child: ring(440, Brand.gold2.withValues(alpha: .22))),
        SafeArea(child: LayoutBuilder(builder: (context, c) => Padding(
          padding: const EdgeInsets.fromLTRB(64, 52, 56, 48),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [AuthLayout.monogram(42), const Spacer(), if (topAction != null) topAction!]),
            const SizedBox(height: 32),
            if (eyebrow != null) ...[Eyebrow(eyebrow!, color: Colors.white), const SizedBox(height: 8)],
            Text(title, style: t.headlineMedium?.copyWith(color: Colors.white, fontSize: c.maxWidth > 640 ? 58 : 46, height: 1.08)),
            const SizedBox(height: 16),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: .92), fontSize: 19, height: 1.5))),
            const Spacer(),
            if (c.maxHeight > 560) Wrap(spacing: 26, runSpacing: 10, children: [
              for (final f in const ['Notices & diary', 'Fees & receipts', 'Live school bus', 'Report cards'])
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('✦ ', style: TextStyle(color: Brand.gold2, fontSize: 14)),
                  Text(f, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                ]),
            ]),
            const SizedBox(height: 16),
            Text('${AppConfig.schoolName} · Kalyan Nagar', style: TextStyle(color: Colors.white.withValues(alpha: .78), fontSize: 13)),
          ]),
        ))),
      ]),
    ));
  }
}
