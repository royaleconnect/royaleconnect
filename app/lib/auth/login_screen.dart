import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../widgets/auth_layout.dart';
import '../widgets/common.dart';
import '../widgets/royal_motion.dart';
import 'session.dart';

/// Opening screen ("Heritage", animated): on every opening the gold double frame draws itself, the school logo
/// builds up piece by piece (the crest-R rises, ROYALE CONCORDE is written in, Build · Learn · Grow slides in),
/// a light sweeps across it, ROYALE CONNECT appears letter by letter and the gold lines open out — about 3.5 s.
/// Soft gold dust floats in the background. While the saved sign-in is checked a thin gold line shimmers; once we
/// know nobody is signed in, the black panel with "Get started" rises from the bottom.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  static const ivory = Color(0xFFFFFDF8), frameGold = Color(0xFFA8822F), panel = Color(0xFF14100F);

  /// Deep metallic gold text: a gradient through the letters plus a soft light edge underneath, so it reads as engraved.
  static Widget goldText(String text, TextStyle style) => Stack(alignment: Alignment.center, children: [
        Transform.translate(offset: const Offset(0, 1.2), child: Text(text, textAlign: TextAlign.center, style: style.copyWith(color: const Color(0xE6FFF0C8)))),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => _engraved.createShader(r),
          child: Text(text, textAlign: TextAlign.center, style: style.copyWith(color: Colors.white)),
        ),
      ]);
  static const _engraved = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF5E4210), Color(0xFF8C6519), Color(0xFFB88A2C), Color(0xFF7A5714), Color(0xFF4F370C)], stops: [0, .3, .52, .72, 1]);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) { c.value = 1; } else { c.forward(); }
  }

  @override
  void dispose() { c.dispose(); super.dispose(); }

  /// progress of one part of the sequence (start/end in milliseconds)
  double _p(int from, int to, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((c.value * 3600 - from) / (to - from)).clamp(0.0, 1.0));

  static const _title = 'ROYALE CONNECT';

  @override
  Widget build(BuildContext context) {
    final checking = ref.watch(sessionProvider).isLoading || !ref.watch(splashDoneProvider);   // 4-second splash on every opening
    final w = MediaQuery.sizeOf(context).width.clamp(280.0, 480.0);
    final small = GoogleFonts.manrope(fontSize: 11.5, fontWeight: FontWeight.w600);
    final logoW = w * .74;
    final titleStyle = GoogleFonts.cinzel(fontSize: w < 340 ? 23 : 26, fontWeight: FontWeight.w800, letterSpacing: 4, height: 1.25);
    Widget logo() => Image.asset('assets/images/logo_heritage.png', width: logoW,
        errorBuilder: (_, __, ___) => Image.asset('assets/images/logo.png', width: logoW));

    final frame = AnimatedBuilder(animation: c, builder: (context, _) {
      final pFrame = _p(0, 1000, Curves.easeInOutCubic);
      final pR = _p(450, 1300);                 // the crest-R and its towers rise
      final pName = _p(1050, 1950, Curves.easeInOutCubic);   // ROYALE CONCORDE written in
      final pTag = _p(1800, 2400);              // Build · Learn · Grow
      final pLines = _p(2950, 3500);
      final pTagline = _p(3150, 3600);
      return SizedBox(width: w * .84, child: CustomPaint(
        painter: _FramePainter(pFrame, SplashScreen.frameGold),
        child: Padding(padding: const EdgeInsets.fromLTRB(21, 31, 21, 27), child: Column(mainAxisSize: MainAxisSize.min, children: [
          ShineSweep(delay: const Duration(milliseconds: 2350), every: const Duration(milliseconds: 4200), child: Stack(children: [
            // 1. the R with its towers: rises from below inside its own area
            ClipPath(clipper: _RectClip((s) => Rect.fromLTRB(0, s.height * .68 * (1 - pR), s.width * .289, s.height * .68)),
                child: Opacity(opacity: pR, child: Transform.translate(offset: Offset(0, (1 - pR) * 18), child: logo()))),
            // 2. ROYALE CONCORDE: written in from left to right
            ClipPath(clipper: _RectClip.many((s) {
              final x = s.width * .79 * pName;
              return [Rect.fromLTRB(0, s.height * .68, x, s.height), if (x > s.width * .289) Rect.fromLTRB(s.width * .289, 0, x, s.height)];
            }), child: logo()),
            // 3. Build · Learn · Grow slides in from the right
            ClipPath(clipper: _RectClip((s) => Rect.fromLTRB(s.width * .79, 0, s.width, s.height)),
                child: Opacity(opacity: pTag, child: Transform.translate(offset: Offset((1 - pTag) * 16, 0), child: logo()))),
          ])),
          const SizedBox(height: 20),
          // ROYALE CONNECT, letter by letter, in engraved gold
          Stack(alignment: Alignment.center, children: [
            Transform.translate(offset: const Offset(0, 1.2), child: _letters(titleStyle.copyWith(color: const Color(0xE6FFF0C8)))),
            ShaderMask(blendMode: BlendMode.srcIn, shaderCallback: (r) => SplashScreen._engraved.createShader(r), child: _letters(titleStyle.copyWith(color: Colors.white))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Align(alignment: Alignment.centerRight, child: FractionallySizedBox(widthFactor: pLines, child: const Divider(color: SplashScreen.frameGold, thickness: 1)))),
            Opacity(opacity: pTagline, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('SCHOOL · HOME · TOGETHER', style: GoogleFonts.manrope(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 2, color: const Color(0xFF7A5A1C))))),
            Expanded(child: Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: pLines, child: const Divider(color: SplashScreen.frameGold, thickness: 1)))),
          ]),
        ])),
      ));
    });

    final footer = '${AppConfig.schoolName} · Kalyan Nagar';
    return Scaffold(
      backgroundColor: SplashScreen.ivory,
      body: Container(
        decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(0, -.25), radius: 1.1, colors: [Color(0xFFFFFDF8), Color(0xFFF3ECE0)])),
        child: Stack(children: [
          const Positioned.fill(child: GoldParticles(count: 46, color: Color(0xFFC9A24A), maxRadius: 1.8, speed: .8)),
          Column(children: [
            Expanded(child: SafeArea(bottom: false, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              frame,
              if (checking) ...[
                const SizedBox(height: 46),
                SizedBox(width: 120, child: ClipRRect(borderRadius: BorderRadius.circular(2), child: const LinearProgressIndicator(minHeight: 2, color: SplashScreen.frameGold, backgroundColor: Color(0xFFEDE2CC)))),
              ],
            ])))),
            Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              transitionBuilder: (c, a) => SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: c),
              child: checking
                  ? Padding(key: const ValueKey('s'), padding: const EdgeInsets.only(bottom: 30), child: SafeArea(top: false, child: AnimatedBuilder(animation: c,
                      builder: (_, __) => Opacity(opacity: _p(3000, 3600), child: Text(footer, textAlign: TextAlign.center, style: small.copyWith(color: const Color(0xFF6A5A40)))))))
                  : Container(
                      key: const ValueKey('w'), width: double.infinity,
                      decoration: const BoxDecoration(color: SplashScreen.panel, borderRadius: BorderRadius.vertical(top: Radius.circular(34))),
                      padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
                      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
                        ShaderMask(blendMode: BlendMode.srcIn, shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFC9A24B), Color(0xFFF0D68A), Color(0xFFC9A24B)]).createShader(r),
                            child: Text('BUILD · LEARN · GROW', style: GoogleFonts.cinzel(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2.2, color: Colors.white))),
                        const SizedBox(height: 14),
                        Material(color: Colors.transparent, child: InkWell(
                          onTap: () => context.go('/login'), borderRadius: BorderRadius.circular(14),
                          child: Ink(height: 52, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: [Color(0xFFE4C56F), Color(0xFFB8923A), Color(0xFF9A7426)], stops: [0, .55, 1])),
                              child: ShineSweep(delay: const Duration(milliseconds: 700), every: const Duration(milliseconds: 3200), child: Center(child: Text('Get started', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800, color: SplashScreen.panel))))),
                        )),
                        const SizedBox(height: 12),
                        Text(footer, textAlign: TextAlign.center, style: small.copyWith(color: const Color(0xFFEFE6D2).withValues(alpha: .9))),
                      ])),
                    ),
            ))),
          ]),
        ]),
      ),
    );
  }

  /// ROYALE CONNECT with each letter rising into place one after another
  Widget _letters(TextStyle style) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < _title.length; i++) Builder(builder: (_) {
          final v = _p(2350 + i * 45, 2350 + i * 45 + 520);
          return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: Text(_title[i], style: style)));
        }),
      ]);
}

/// The two thin gold frames, drawn as if by a pen going round (progress 0–1).
class _FramePainter extends CustomPainter {
  final double p; final Color color;
  _FramePainter(this.p, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    if (p <= 0) return;
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1;
    for (final inset in [0.5, 5.5]) {
      final r = Rect.fromLTRB(inset, inset, s.width - inset, s.height - inset);
      // start at the top middle and go round both ways, meeting at the bottom middle
      final half = Path()..moveTo(r.center.dx, r.top)..lineTo(r.right, r.top)..lineTo(r.right, r.bottom)..lineTo(r.center.dx, r.bottom);
      final other = Path()..moveTo(r.center.dx, r.top)..lineTo(r.left, r.top)..lineTo(r.left, r.bottom)..lineTo(r.center.dx, r.bottom);
      for (final path in [half, other]) {
        for (final m in path.computeMetrics()) { canvas.drawPath(m.extractPath(0, m.length * p), paint); }
      }
    }
  }
  @override
  bool shouldRepaint(_FramePainter o) => o.p != p;
}

/// Clips to one or more rectangles worked out from the child's size.
class _RectClip extends CustomClipper<Path> {
  final List<Rect> Function(Size) rects;
  _RectClip(Rect Function(Size) one) : rects = ((s) => [one(s)]);
  _RectClip.many(this.rects);
  @override
  Path getClip(Size size) { final p = Path(); for (final r in rects(size)) { p.addRect(r); } return p; }
  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => true;
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
    return AuthLayout(
      title: widget.addSibling ? 'Add a sibling' : 'Welcome back',
      subtitle: widget.addSibling ? "Enter your other child's admission number and password once." : 'Sign in once and stay signed in until you choose to sign out.',
      topAction: widget.addSibling ? IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.close_rounded, color: Colors.white), tooltip: 'Close') : null,
      formTitle: widget.addSibling ? 'Brother or sister' : 'Parent & student sign-in',
      formSubtitle: 'Use the admission number and password from the school.',
      children: [
        TextField(controller: adm, textCapitalization: TextCapitalization.characters, autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(labelText: 'Admission number', hintText: 'e.g. LK/10/2014')),
        const SizedBox(height: 6),
        Text('As on the ID card. One per student; add brothers or sisters after signing in.', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),
        TextField(controller: pw, obscureText: !showPw, autofillHints: const [AutofillHints.password], onSubmitted: (_) => _signIn(),
            decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(icon: Icon(showPw ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => showPw = !showPw)))),
        const SizedBox(height: 20),
        if (error != null) _err(error!),
        PrimaryButton(widget.addSibling ? 'Add to this phone' : 'Sign in', busy: busy, onPressed: _signIn),
        if (!widget.addSibling) ...[
          const SizedBox(height: 12),
          Text('Forgot the password? The class teacher or the school office will give you a new password slip.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          // big and easy to spot for teachers
          Padding(padding: const EdgeInsets.only(top: 14), child: Center(child: TextButton.icon(
            onPressed: () => context.go('/staff-login'),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), minimumSize: const Size(0, 52)),
            icon: const Icon(Icons.badge_outlined, size: 26),
            label: const Text('School staff? Sign in here', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ))),
        ],
        const SizedBox(height: 16),
        const NoteBox('Same login for the student and the parents — the same admission number and password work on every phone in the family. Brothers and sisters each have their own; add them once and switch between them from Home.'),
      ],
    );
  }

  void _signIn() {
    if (busy) return;
    _run(() async {
      await ref.read(sessionProvider.notifier).loginWithPassword(adm.text, pw.text, linkToExisting: widget.addSibling);
      if (mounted) context.go(widget.addSibling ? '/students' : '/');
    });
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
    return AuthLayout(
      eyebrow: 'First sign-in',
      title: 'Set your own password',
      subtitle: 'The password sent by the school was for first use only. Choose one only your family knows.',
      formTitle: 'New password',
      children: [
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
      ],
    );
  }
}
