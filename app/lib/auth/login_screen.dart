import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'session.dart';

/// Opening screen ("Heritage"): the school logo in a gold double frame, ROYALE CONNECT in engraved gold.
/// While the saved sign-in is being checked it is the 1-second splash (gold ring); once we know nobody is
/// signed in, the black panel with "Get started" rises from the bottom.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  static const ivory = Color(0xFFFFFDF8), frameGold = Color(0xFFA8822F), panel = Color(0xFF14100F);

  /// Deep metallic gold text: a gradient through the letters plus a soft light edge underneath, so it reads as engraved.
  static Widget goldText(String text, TextStyle style) => Stack(alignment: Alignment.center, children: [
        Transform.translate(offset: const Offset(0, 1.2), child: Text(text, textAlign: TextAlign.center, style: style.copyWith(color: const Color(0xE6FFF0C8)))),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFF5E4210), Color(0xFF8C6519), Color(0xFFB88A2C), Color(0xFF7A5714), Color(0xFF4F370C)], stops: [0, .3, .52, .72, 1]).createShader(r),
          child: Text(text, textAlign: TextAlign.center, style: style.copyWith(color: Colors.white)),
        ),
      ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checking = ref.watch(sessionProvider).isLoading || !ref.watch(splashDoneProvider);   // 4-second splash on every opening
    final w = MediaQuery.sizeOf(context).width.clamp(280.0, 480.0);
    final small = GoogleFonts.manrope(fontSize: 11.5, fontWeight: FontWeight.w600);
    final frame = Container(
      width: w * .84, padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(border: Border.all(color: frameGold, width: 1)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 26, 16, 22),
        decoration: BoxDecoration(border: Border.all(color: frameGold, width: 1)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // school logo, a touch deeper in colour, white background removed (made at build time by tools/make_icon.py)
          Image.asset('assets/images/logo_heritage.png', width: w * .74,
              errorBuilder: (_, __, ___) => Image.asset('assets/images/logo.png', width: w * .74)),
          const SizedBox(height: 20),
          goldText('ROYALE CONNECT', GoogleFonts.cinzel(fontSize: w < 340 ? 23 : 26, fontWeight: FontWeight.w800, letterSpacing: 4, height: 1.25)),
          const SizedBox(height: 10),
          Row(children: [
            const Expanded(child: Divider(color: frameGold, thickness: 1)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('SCHOOL · HOME · TOGETHER', style: GoogleFonts.manrope(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 2, color: const Color(0xFF7A5A1C)))),
            const Expanded(child: Divider(color: frameGold, thickness: 1)),
          ]),
        ]),
      ),
    );
    final footer = '${AppConfig.schoolName} · Kalyan Nagar';
    return Scaffold(
      backgroundColor: ivory,
      body: Container(
        decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(0, -.25), radius: 1.1, colors: [Color(0xFFFFFDF8), Color(0xFFF3ECE0)])),
        child: Column(children: [
          Expanded(child: SafeArea(bottom: false, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            frame,
            if (checking) ...[const SizedBox(height: 44), const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: frameGold, backgroundColor: Color(0xFFE8DCC2)))],
          ])))),
          Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (c, a) => SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: c),
            child: checking
                ? Padding(key: const ValueKey('s'), padding: const EdgeInsets.only(bottom: 30), child: SafeArea(top: false, child: Text(footer, textAlign: TextAlign.center, style: small.copyWith(color: const Color(0xFF6A5A40)))))
                : Container(
                    key: const ValueKey('w'), width: double.infinity,
                    decoration: const BoxDecoration(color: panel, borderRadius: BorderRadius.vertical(top: Radius.circular(34))),
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
                    child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ShaderMask(blendMode: BlendMode.srcIn, shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFC9A24B), Color(0xFFF0D68A), Color(0xFFC9A24B)]).createShader(r),
                          child: Text('BUILD · LEARN · GROW', style: GoogleFonts.cinzel(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2.2, color: Colors.white))),
                      const SizedBox(height: 14),
                      Material(color: Colors.transparent, child: InkWell(
                        onTap: () => context.go('/login'), borderRadius: BorderRadius.circular(14),
                        child: Ink(height: 52, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: [Color(0xFFE4C56F), Color(0xFFB8923A), Color(0xFF9A7426)], stops: [0, .55, 1])),
                            child: Center(child: Text('Get started', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800, color: panel)))),
                      )),
                      const SizedBox(height: 12),
                      Text(footer, textAlign: TextAlign.center, style: small.copyWith(color: const Color(0xFFEFE6D2).withValues(alpha: .9))),
                    ])),
                  ),
          ))),
        ]),
      ),
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  final bool addSibling;
  const LoginScreen({super.key, this.addSibling = false});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final adm = TextEditingController(), pw = TextEditingController();
  bool busy = false, showPw = false;
  String? error;

  Future<void> _run(Future<void> Function() f) async {
    setState(() { busy = true; error = null; });
    try { await f(); } on AuthError catch (e) { setState(() => error = e.message); } catch (e) { setState(() => error = 'Could not complete sign-in: $e'); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Column(children: [
        BrandHeader(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: Image.asset('assets/images/monogram.png', width: 28)),
            const Spacer(),
            if (widget.addSibling) IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.close_rounded, color: Colors.white)),
          ]),
          const SizedBox(height: 18),
          Text(widget.addSibling ? 'Add a sibling' : 'Welcome back', style: t.headlineMedium?.copyWith(color: Colors.white, fontSize: 30)),
          const SizedBox(height: 6),
          Text(widget.addSibling ? "Enter your other child's admission number and password once." : 'Sign in once on this phone. You stay signed in until you choose to sign out.',
              style: TextStyle(color: Colors.white.withValues(alpha: .92), fontSize: 15, height: 1.4)),
        ])),
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 32), children: [
          ...[
            TextField(controller: adm, textCapitalization: TextCapitalization.characters, autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: 'Admission number', hintText: 'e.g. LK/10/2014')),
            const SizedBox(height: 6),
            Text('As on the ID card. One per student; add brothers or sisters after signing in.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            TextField(controller: pw, obscureText: !showPw, autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(icon: Icon(showPw ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => showPw = !showPw)))),
            const SizedBox(height: 20),
            if (error != null) _err(error!),
            PrimaryButton(widget.addSibling ? 'Add to this phone' : 'Sign in', busy: busy,
                onPressed: () => _run(() async {
                  await ref.read(sessionProvider.notifier).loginWithPassword(adm.text, pw.text, linkToExisting: widget.addSibling);
                  if (mounted) context.go(widget.addSibling ? '/students' : '/');
                })),
            if (!widget.addSibling) ...[
              const SizedBox(height: 12),
              Text('Forgot the password? The class teacher or the school office will give you a new password slip.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ],
          const SizedBox(height: 22),
          const NoteBox('Same login for the student and the parents — the same admission number and password work on every phone in the family. Brothers and sisters each have their own; add them once and switch between them from Home.'),
          if (!widget.addSibling) Padding(padding: const EdgeInsets.only(top: 12), child: Center(child: TextButton.icon(onPressed: () => context.go('/staff-login'), icon: const Icon(Icons.badge_outlined, size: 18), label: const Text('School staff or bus crew? Sign in here')))),
        ])),
      ]),
    );
  }

  Widget _err(String m) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Brand.crimsonTint, borderRadius: BorderRadius.circular(12)),
      child: Text(m, style: const TextStyle(color: Brand.crimsonDeep, fontWeight: FontWeight.w700, fontSize: 13)));
}

class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key});
  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final a = TextEditingController(), b = TextEditingController();
  bool busy = false; String? error;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(body: Column(children: [
      BrandHeader(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Eyebrow('First sign-in', color: Colors.white),
        const SizedBox(height: 6),
        Text('Set your own password', style: t.headlineMedium?.copyWith(color: Colors.white)),
        const SizedBox(height: 6),
        Text('The password sent by the school was for first use only. Choose one only your family knows.', style: TextStyle(color: Colors.white.withValues(alpha: .92), height: 1.4)),
      ])),
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 32), children: [
        TextField(controller: a, obscureText: true, decoration: const InputDecoration(labelText: 'New password', hintText: 'At least 8 characters')),
        const SizedBox(height: 16),
        TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'Repeat new password')),
        const SizedBox(height: 20),
        if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!, style: TextStyle(color: context.tone(Brand.crimsonDeep), fontWeight: FontWeight.w700))),
        PrimaryButton('Save and continue', busy: busy, onPressed: () async {
          if (a.text.length < 8) { setState(() => error = 'Use at least 8 characters.'); return; }
          if (a.text != b.text) { setState(() => error = "The two passwords don't match."); return; }
          setState(() { busy = true; error = null; });
          try { await ref.read(sessionProvider.notifier).changePassword(a.text); if (mounted) context.go('/'); }
          on AuthError catch (e) { setState(() => error = e.message); } catch (e) { setState(() => error = 'Could not complete: $e'); }
          if (mounted) setState(() => busy = false);
        }),
      ])),
    ]));
  }
}
