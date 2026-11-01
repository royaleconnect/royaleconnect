import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/data3.dart' show appSettingsProvider, featureOn, initialsOf;
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_extras.dart' show GoldLoading, PressScale;
import '../widgets/royal_motion.dart';
import 'academics_screens.dart' show AppPage;

/// Teachers' Day thank-you wall (family side). Open only in Teachers' Day week, 2–8 September (India time):
/// one short note to each of the child's teachers, once a year. The teacher keeps the notes on her own wall.
String _msg(Object e) => e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');

DateTime _nowIst() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
/// True during Teachers' Day week (2–8 September, India time).
bool thanksWeekNow() { final n = _nowIst(); return n.month == 9 && n.day >= 2 && n.day <= 8; }

const thanksReadyLines = ['Thank you for your patience', 'You make learning fun', 'Thank you for believing in me'];

final thanksTeachersProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.cacheFor();
  final st = ref.watch(sessionProvider).value?.active;
  if (st == null) return {'open': false, 'teachers': []};
  return Map<String, dynamic>.from(await db.rpc('thanks_my_teachers', params: {'p_student': st.id}) as Map);
});

class ThanksScreen extends ConsumerWidget {
  const ThanksScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = featureOn(ref.watch(appSettingsProvider).value, 'thanks');
    final data = ref.watch(thanksTeachersProvider);
    final st = ref.watch(sessionProvider).value?.active;
    final cs = Theme.of(context).colorScheme;
    return AppPage(title: "Teachers' Day", body: !on
        ? const Padding(padding: EdgeInsets.all(20), child: NoteBox('The thank-you wall is not open in the app at the moment.'))
        : data.when(
            loading: () => const GoldLoading(),
            error: (e, _) => Padding(padding: const EdgeInsets.all(20), child: NoteBox('Could not load your teachers. ${_msg(e)}')),
            data: (d) {
              final open = d['open'] == true;
              final teachers = List<Map<String, dynamic>>.from(d['teachers'] as List? ?? const []);
              final sent = teachers.where((t) => t['sent'] == true).length;
              return ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 40), children: [
                const _Hero(),
                const SizedBox(height: 16),
                if (!open) ...[
                  NoteBox(sent > 0
                      ? 'Thank you! You sent $sent ${sent == 1 ? 'note' : 'notes'} this year. The wall opens again on 2 September.'
                      : 'Opens on 2 September. During Teachers’ Day week (2–8 September) you can send a short thank-you to each of your child’s teachers.',
                      icon: Icons.favorite_rounded, iconColor: Brand.gold),
                ] else ...[
                  Text('Say thank you', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('One short note to each teacher. ${st == null ? '' : 'Your child’s name (${st.fullName}, ${st.cls}) is shown with it.'}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.4)),
                  const SizedBox(height: 14),
                  if (teachers.isEmpty) const NoteBox('The teachers of your child’s class are not listed yet.'),
                  for (final (i, t) in teachers.indexed) FadeRise(delayMs: 120 + i * 80, child: _TeacherCard(t, key: ValueKey(t['staff_id']))),
                ],
              ]);
            },
          ));
  }
}

class _Hero extends StatelessWidget {
  const _Hero();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4A0910), Color(0xFF240609)]),
            border: Border.all(color: const Color(0xFFE8C97A).withValues(alpha: .4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("TEACHERS' DAY · 5 SEPTEMBER", style: GoogleFonts.cinzel(color: const Color(0xFFF3DE9C), fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          GoldText('Thank you, teachers', align: TextAlign.left, style: GoogleFonts.greatVibes(fontSize: 36, height: 1.15)),
          const SizedBox(height: 4),
          Text('A few kind words mean a lot. Your note stays on the teacher’s wall.', style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 13, height: 1.4)),
        ]),
      );
}

class _TeacherCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> t;
  const _TeacherCard(this.t, {super.key});
  @override
  ConsumerState<_TeacherCard> createState() => _TeacherCardState();
}

class _TeacherCardState extends ConsumerState<_TeacherCard> {
  bool openBox = false, busy = false, flying = false;
  late bool sent = widget.t['sent'] == true;
  late String? body = widget.t['body'] as String?;
  final text = TextEditingController();

  @override
  void dispose() { text.dispose(); super.dispose(); }

  Future<void> _send() async {
    final st = ref.read(sessionProvider).value?.active;
    final b = text.text.trim();
    if (st == null) return;
    if (b.isEmpty) { _toast('Please write a few words, or tap one of the ready lines.'); return; }
    setState(() => busy = true);
    try {
      await db.rpc('thanks_send', params: {'p_student': st.id, 'p_staff': widget.t['staff_id'], 'p_body': b});
      if (!mounted) return;
      setState(() { flying = true; busy = false; });
      await Future.delayed(Duration(milliseconds: reduceMotion(context) ? 0 : 1100));
      if (!mounted) return;
      setState(() { sent = true; body = b; openBox = false; flying = false; });
      ref.invalidate(thanksTeachersProvider);
    } catch (e) {
      if (mounted) { setState(() => busy = false); _toast(_msg(e)); }
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = widget.t;
    final name = t['name'] as String? ?? '';
    final sub = [if (t['class_teacher'] == true) 'Class teacher', if ((t['subjects'] ?? '').toString().isNotEmpty) t['subjects']].join(' · ');
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Material(
      color: cs.surface, borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: sent || busy || flying ? null : () => setState(() => openBox = !openBox),
        child: AnimatedSize(duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic, alignment: Alignment.topCenter, child: Stack(clipBehavior: Clip.none, children: [
          Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Avatar(initialsOf(name.replaceAll(RegExp(r'^(Mr|Mrs|Ms|Dr|Miss)\.?\s+', caseSensitive: false), '')), size: 44,
                  bg: sent ? const Color(0xFFFBEFD0) : Brand.crimsonTint, fg: sent ? const Color(0xFF8A6A1E) : Brand.crimsonDeep),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                if (sub.isNotEmpty) Text(sub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
              ])),
              if (sent) const Pill('Sent ✓', fg: Color(0xFF6B4F12), bg: Color(0xFFFBEFD0))
              else Icon(openBox ? Icons.expand_less_rounded : Icons.edit_note_rounded, color: context.tone(Brand.crimson)),
            ]),
            if (sent && body != null) Padding(padding: const EdgeInsets.only(top: 10), child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: const LinearGradient(colors: [Color(0xFFFFFBEF), Color(0xFFFBEFD0)]), border: Border.all(color: const Color(0xFFEBD39A))),
              child: Text('“$body”', style: GoogleFonts.cormorantGaramond(fontSize: 17, fontStyle: FontStyle.italic, color: const Color(0xFF3A2A08), fontWeight: FontWeight.w600)),
            )),
            if (openBox && !sent) ...[
              const SizedBox(height: 12),
              TextField(controller: text, maxLength: 200, minLines: 2, maxLines: 4, enabled: !busy && !flying, textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: 'Write a thank-you to ${name.isEmpty ? 'your teacher' : name}…')),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final l in thanksReadyLines) ActionChip(label: Text(l, style: const TextStyle(fontSize: 12.5)), onPressed: busy || flying ? null : () => setState(() {
                  text.text = l; text.selection = TextSelection.collapsed(offset: l.length);
                })),
              ]),
              const SizedBox(height: 12),
              _GoldSendButton(busy: busy || flying, onTap: _send),
            ],
          ])),
          if (flying) const Positioned.fill(child: IgnorePointer(child: _PaperPlane())),
        ])),
      ),
    ));
  }
}

class _GoldSendButton extends StatelessWidget {
  final bool busy; final VoidCallback onTap;
  const _GoldSendButton({required this.busy, required this.onTap});
  @override
  Widget build(BuildContext context) => PressScale(enabled: !busy, child: Material(color: Colors.transparent, child: InkWell(
        onTap: busy ? null : onTap, borderRadius: BorderRadius.circular(14),
        child: Ink(height: 48, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(colors: [Color(0xFFE8C97A), Color(0xFFC9A24A), Color(0xFF9C7A2E)]),
            boxShadow: [BoxShadow(color: const Color(0xFF9C7A2E).withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, 5))]),
          child: Center(child: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF3A2600)))
              : const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.send_rounded, color: Color(0xFF3A2600), size: 19), SizedBox(width: 8),
                  Text('Send thank-you', style: TextStyle(color: Color(0xFF3A2600), fontWeight: FontWeight.w900, fontSize: 15)),
                ])),
        ),
      )));
}

/// A gold paper plane flies up and away, leaving a short trail of gold sparks.
class _PaperPlane extends StatelessWidget {
  const _PaperPlane();
  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return const SizedBox.shrink();
    return LayoutBuilder(builder: (_, c) => TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 1050), curve: Curves.easeInCubic,
      builder: (_, v, __) {
        final start = Offset(c.maxWidth * .5, c.maxHeight - 34);
        final end = Offset(c.maxWidth + 40, -60);
        final pos = Offset.lerp(start, end, v)!;
        return Stack(clipBehavior: Clip.none, children: [
          for (var k = 1; k <= 6; k++) Builder(builder: (_) {
            final tv = (v - k * .05).clamp(0.0, 1.0);
            final p = Offset.lerp(start, end, tv)!;
            return Positioned(left: p.dx - 3 + math.sin(k * 1.7) * 6, top: p.dy + 6, child: Opacity(opacity: (1 - v) * (1 - k / 7),
                child: Container(width: 6 - k * .6, height: 6 - k * .6, decoration: const BoxDecoration(color: Color(0xFFF3DE9C), shape: BoxShape.circle))));
          }),
          Positioned(left: pos.dx - 16, top: pos.dy - 16, child: Opacity(opacity: (1.2 - v).clamp(0.0, 1.0),
              child: Transform.rotate(angle: -.55, child: const Icon(Icons.send_rounded, size: 32, color: Color(0xFFC9A24A))))),
        ]);
      },
    ));
  }
}

/// Family Home: a gold banner shown only during Teachers' Day week.
class ThanksHomeBanner extends ConsumerWidget {
  const ThanksHomeBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    if (s == null || s.isStaff || s.active == null || !thanksWeekNow() || !featureOn(ref.watch(appSettingsProvider).value, 'thanks')) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: ShineSweep(delay: const Duration(milliseconds: 900), every: const Duration(seconds: 7), child: Material(
      color: Colors.transparent,
      child: InkWell(onTap: () => context.push('/thanks'), borderRadius: BorderRadius.circular(18), child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFF6DC), Color(0xFFF3DE9C), Color(0xFFE8C97A)]),
            border: Border.all(color: const Color(0xFFC9A24A))),
        child: Row(children: [
          const Icon(Icons.favorite_rounded, color: Color(0xFFB5121A)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("TEACHERS' DAY WEEK", style: GoogleFonts.cinzel(color: const Color(0xFF6B4F12), fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
            const Text('Say thank you to your teachers ›', style: TextStyle(color: Color(0xFF3A2600), fontWeight: FontWeight.w900, fontSize: 15.5)),
          ])),
        ]),
      )),
    )));
  }
}
