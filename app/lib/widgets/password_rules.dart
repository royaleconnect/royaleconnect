import 'package:flutter/material.dart';
import '../core/theme.dart';

/// The password a person just signed in with (kept in memory only, until they choose their own),
/// so the new one can't be the same as the first one from the school.
String? signedInWithPassword;

/// The four simple rules for a new password — not too hard, not too easy. Names and symbols are fine.
///   at least 8 characters · letters and a number · not the first password / not 12345678-type · typed the same twice
List<(bool, String)> passwordRules(String p, String again, {String? old}) {
  final low = p.toLowerCase();
  final easy = RegExp(r'^(12345678|123456789|1234567890|87654321|11111111|00000000|password\d*|qwerty\d*|abcd1234|1234abcd|abc12345|admin\d*)$');
  final first = (old ?? signedInWithPassword ?? '').toLowerCase();
  return [
    (p.length >= 8, 'At least 8 characters (symbols are fine)'),
    (RegExp(r'[A-Za-z]').hasMatch(p) && RegExp(r'\d').hasMatch(p), 'Has letters and a number'),
    (p.isNotEmpty && !easy.hasMatch(low) && (first.isEmpty || low != first), 'Not the first password, and not an easy one like 12345678'),
    (p.isNotEmpty && p == again, 'Both match'),
  ];
}

bool passwordOk(String p, String again, {String? old}) => passwordRules(p, again, old: old).every((r) => r.$1);

/// The ticks under the two password boxes; they turn green as each rule is met.
class PasswordRulesView extends StatelessWidget {
  final TextEditingController a, b; final String? old;
  const PasswordRulesView(this.a, this.b, {super.key, this.old});
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Listenable.merge([a, b]), builder: (context, _) {
    final soft = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final r in passwordRules(a.text, b.text, old: old)) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(r.$1 ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 17, color: r.$1 ? Brand.green : soft),
        const SizedBox(width: 8),
        Expanded(child: Text(r.$2, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: r.$1 ? Brand.green : soft))),
      ])),
    ]);
  });
}
