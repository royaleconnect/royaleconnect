import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/session.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'academics_screens.dart' show AppPage;

/// Settings → Change password: the current password, the new one twice, Save. (Not the first-sign-in screen.)
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final cur = TextEditingController(), a = TextEditingController(), b = TextEditingController();
  bool busy = false, show = false; String? error;

  @override
  void dispose() { cur.dispose(); a.dispose(); b.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (cur.text.isEmpty) { setState(() => error = 'Please type your current password.'); return; }
    if (a.text.length < 8) { setState(() => error = 'Use at least 8 characters for the new password.'); return; }
    if (a.text != b.text) { setState(() => error = "The two new passwords don't match."); return; }
    if (a.text == cur.text) { setState(() => error = 'The new password is the same as the current one.'); return; }
    setState(() { busy = true; error = null; });
    try {
      await ref.read(sessionProvider.notifier).changePassword(a.text, current: cur.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed. Use the new one next time you sign in.')));
      context.canPop() ? context.pop() : context.go('/settings');
    } on AuthError catch (e) {
      setState(() => error = e.message);
    } catch (e) {
      setState(() => error = friendlyError(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value;
    final cs = Theme.of(context).colorScheme;
    InputDecoration deco(String label, {String? hint}) => InputDecoration(labelText: label, hintText: hint,
        suffixIcon: IconButton(tooltip: show ? 'Hide' : 'Show', onPressed: () => setState(() => show = !show), icon: Icon(show ? Icons.visibility_off_rounded : Icons.visibility_rounded)));
    return AppPage(title: 'Change password', body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        if (s?.active != null) Text('For ${s!.active!.fullName}’s sign-in', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        TextField(controller: cur, obscureText: !show, autofillHints: const [AutofillHints.password], decoration: deco('Current password')),
        const SizedBox(height: 14),
        TextField(controller: a, obscureText: !show, autofillHints: const [AutofillHints.newPassword], decoration: deco('New password', hint: 'At least 8 characters')),
        const SizedBox(height: 14),
        TextField(controller: b, obscureText: !show, decoration: deco('Repeat new password'), onSubmitted: (_) => busy ? null : _save()),
        const SizedBox(height: 18),
        if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!, style: TextStyle(color: context.tone(Brand.crimsonDeep), fontWeight: FontWeight.w700))),
        PrimaryButton('Save new password', icon: Icons.lock_rounded, busy: busy, onPressed: s?.viewOnly == true ? null : _save),
        const SizedBox(height: 14),
        Text('Forgot the current password? Ask the class teacher or the school office to reset it.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, height: 1.45)),
      ],
    ))));
  }
}
