import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'royal_extras.dart' show LivingSilk, PressScale;
import 'royal_motion.dart' show ShineSweep;

/// Red gradient header with the gold hairline, as in the prototype.
class BrandHeader extends StatelessWidget {
  final Widget child; final EdgeInsets padding; final bool hairline;
  const BrandHeader({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 24), this.hairline = true});
  @override
  Widget build(BuildContext context) => LivingSilk(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SafeArea(bottom: false, child: Padding(padding: padding, child: child)),
          if (hairline) Container(height: 3, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Brand.gold2, Brand.gold, Colors.transparent]))),
        ]),
      );
}

class Avatar extends StatelessWidget {
  final String initials; final Color bg, fg; final double size;
  const Avatar(this.initials, {super.key, this.bg = Brand.crimsonTint, this.fg = Brand.crimsonDeep, this.size = 48});
  @override
  Widget build(BuildContext context) => Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * .33)),
      child: Text(initials, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: size * .34)));
}

class Pill extends StatelessWidget {
  final String text; final Color fg, bg;
  const Pill(this.text, {super.key, required this.fg, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text.toUpperCase(), style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .4)));
}

class Eyebrow extends StatelessWidget {
  final String text; final Color? color;
  const Eyebrow(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color ?? Theme.of(context).colorScheme.onSurfaceVariant));
}

class PrimaryButton extends StatelessWidget {
  final String label; final VoidCallback? onPressed; final IconData? icon; final bool busy;
  const PrimaryButton(this.label, {super.key, this.onPressed, this.icon, this.busy = false});
  @override
  Widget build(BuildContext context) => PressScale(enabled: onPressed != null && !busy, child: ShineSweep(delay: const Duration(milliseconds: 1200), every: const Duration(milliseconds: 6000), shine: const Color(0x55FFFFFF), child: DecoratedBox(
        decoration: BoxDecoration(gradient: onPressed == null ? null : Brand.buttonGradient, color: onPressed == null ? Brand.muted.withValues(alpha: .4) : null,
            borderRadius: BorderRadius.circular(16), boxShadow: onPressed == null ? null : [BoxShadow(color: Brand.crimsonDeep.withValues(alpha: .28), blurRadius: 18, offset: const Offset(0, 6))]),
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, disabledBackgroundColor: Colors.transparent),
          onPressed: busy ? null : onPressed,
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 10)], Text(label)]),
        ),
      )));
}

class NoteBox extends StatelessWidget {
  final String text; final IconData icon; final Color? iconColor;
  const NoteBox(this.text, {super.key, this.icon = Icons.info_outline_rounded, this.iconColor});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: iconColor ?? Brand.blue), const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.5, color: cs.onSurfaceVariant))),
      ]),
    );
  }
}

String inr(num n) {
  final s = n.round().toString();
  // Indian grouping: 1,28,400
  if (s.length <= 3) return '₹$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) { parts.insert(0, rest.substring(rest.length - 2)); rest = rest.substring(0, rest.length - 2); }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '₹${parts.join(',')},$last3';
}


/// Filter chip for the red page headers (All · Holidays · Exams …). Draws its own colours, so it reads the same in
/// light and dark mode: selected = white pill with crimson text, others = translucent white with white text.
class HeaderChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const HeaderChip(this.label, {super.key, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(right: 8), child: Material(
        color: selected ? Colors.white : Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(12),
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(
          constraints: const BoxConstraints(minHeight: 40), padding: const EdgeInsets.symmetric(horizontal: 16), alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: selected ? 0 : .28))),
          child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? Brand.crimsonDeep : Colors.white)),
        )),
      ));
}
