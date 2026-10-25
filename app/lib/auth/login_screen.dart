import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'session.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        Expanded(child: Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/images/logo.png', width: 280),
          const SizedBox(height: 28),
          Container(width: 44, height: 3, decoration: BoxDecoration(color: Brand.gold, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 10),
          Text(AppConfig.appName, style: t.headlineLarge?.copyWith(fontSize: 34, color: Brand.ink), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text('FOR PARENTS, STUDENTS & TEACHERS', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 2.4, color: Brand.muted)),
        ])))),
        Container(
          decoration: const BoxDecoration(gradient: Brand.headerGradient, borderRadius: BorderRadius.vertical(top: Radius.circular(36))),
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 40),
          child: SafeArea(top: false, child: Column(children: [
            const Text('Fees, notices, class diary and report cards — all in one place for your family.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 17, height: 1.45, fontWeight: FontWeight.w500)),
            const SizedBox(height: 20),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Brand.crimsonDeep), onPressed: () => context.go('/login'), child: const Text('Get started')),
            const SizedBox(height: 14),
            Text('${AppConfig.schoolName} · Kalyan Nagar, Bengaluru', style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 12)),
          ])),
        ),
      ]),
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
  int tab = 0; // 0 = admission number, 1 = mobile OTP
  final adm = TextEditingController(), pw = TextEditingController(), phone = TextEditingController(), otp = TextEditingController();
  bool busy = false, otpSent = false, showPw = false;
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
          if (!widget.addSibling) ...[
            Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [for (final (i, l) in ['Admission number', 'Mobile OTP'].indexed) Expanded(child: GestureDetector(onTap: () => setState(() { tab = i; error = null; }),
                    child: Container(height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: tab == i ? cs.surface : Colors.transparent, borderRadius: BorderRadius.circular(11)),
                        child: Text(l, style: TextStyle(fontWeight: FontWeight.w700, color: tab == i ? cs.onSurface : cs.onSurfaceVariant)))))])),
            const SizedBox(height: 22),
          ],
          if (tab == 0 || widget.addSibling) ...[
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
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                TextButton(onPressed: () => setState(() => tab = 1), child: const Text('Forgot password? Use OTP')),
                Text('Office: ${AppConfig.officePhone}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
            ],
          ] else ...[
            TextField(controller: phone, keyboardType: TextInputType.phone, autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(labelText: 'Registered mobile number', prefixText: '+91  ', hintText: '10-digit number')),
            const SizedBox(height: 6),
            Text("Either parent's number on the school record works. All children on that number are added at once.", style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            if (otpSent) ...[
              const SizedBox(height: 16),
              TextField(controller: otp, keyboardType: TextInputType.number, maxLength: 6, autofillHints: const [AutofillHints.oneTimeCode],
                  style: const TextStyle(letterSpacing: 6, fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(labelText: '6-digit OTP sent by SMS', counterText: '')),
            ],
            const SizedBox(height: 20),
            if (error != null) _err(error!),
            PrimaryButton(otpSent ? 'Verify & sign in' : 'Send OTP', busy: busy,
                onPressed: () => _run(() async {
                  final n = ref.read(sessionProvider.notifier);
                  if (!otpSent) { await n.requestOtp(phone.text); setState(() => otpSent = true); return; }
                  await n.loginWithOtp(phone.text, otp.text);
                  if (mounted) context.go('/');
                })),
            if (otpSent) TextButton(onPressed: busy ? null : () => _run(() => ref.read(sessionProvider.notifier).requestOtp(phone.text)), child: const Text('Resend code')),
          ],
          const SizedBox(height: 22),
          const NoteBox('Same login for the student and the parents — the same admission number and password work on every phone in the family. Brothers and sisters each have their own; add them once and switch between them from Home.'),
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
        if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!, style: const TextStyle(color: Brand.crimsonDeep, fontWeight: FontWeight.w700))),
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
