import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/auth_layout.dart';
import '../widgets/common.dart';
import 'session.dart';

/// Driver / bus assistant, first sign-in: the password from the school was for first use only.
/// Six or more letters or numbers; not case-sensitive (the server stores it in small letters).
class CrewSetPasswordScreen extends ConsumerStatefulWidget {
  const CrewSetPasswordScreen({super.key});
  @override
  ConsumerState<CrewSetPasswordScreen> createState() => _CrewSetPasswordScreenState();
}

class _CrewSetPasswordScreenState extends ConsumerState<CrewSetPasswordScreen> {
  final a = TextEditingController(), b = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() { a.dispose(); b.dispose(); super.dispose(); }

  Future<void> _save() async {
    final p = a.text.trim();
    if (p.length < 6) { setState(() => error = 'Use at least 6 letters or numbers.'); return; }
    if (p.toLowerCase() != b.text.trim().toLowerCase()) { setState(() => error = "The two passwords don't match."); return; }
    setState(() { busy = true; error = null; });
    try {
      await ref.read(sessionProvider.notifier).changeStaffPassword(p);
      if (mounted) context.go('/driver');
    } on AuthError catch (e) {
      setState(() => error = e.message);
    } catch (e) {
      setState(() => error = friendlyError(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
        eyebrow: 'First sign-in',
        title: 'Choose your own password',
        subtitle: 'The password from the school was for the first sign-in only. Choose one only you know.',
        formTitle: 'New password',
        children: [
          TextField(controller: a, obscureText: true, keyboardType: TextInputType.visiblePassword, decoration: const InputDecoration(labelText: 'New password', hintText: '6 or more letters or numbers')),
          const SizedBox(height: 12),
          TextField(controller: b, obscureText: true, keyboardType: TextInputType.visiblePassword, decoration: const InputDecoration(labelText: 'Type it again')),
          const SizedBox(height: 16),
          if (error != null)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(error!, style: TextStyle(color: context.tone(Brand.crimsonDeep), fontWeight: FontWeight.w700))),
          PrimaryButton('Save and continue', busy: busy, onPressed: _save),
          const SizedBox(height: 10),
          TextButton(onPressed: () => ref.read(sessionProvider.notifier).signOut(), child: const Text('Sign out')),
        ],
      );
}
