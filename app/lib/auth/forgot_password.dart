import 'package:flutter/material.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../core/config.dart';

/// "Forgot password?" for families: admission number + the phone number registered with the school.
/// The class teacher gets the request and gives a new password slip. Nothing else to choose.
Future<void> showForgotPassword(BuildContext context, {String admission = ''}) =>
    showDialog(context: context, builder: (_) => _ForgotPasswordDialog(admission: admission));

class _ForgotPasswordDialog extends StatefulWidget {
  final String admission;
  const _ForgotPasswordDialog({required this.admission});
  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final adm = TextEditingController(text: widget.admission);
  final phone = TextEditingController();
  bool busy = false;
  String? error, done;

  Future<void> _send() async {
    if (adm.text.trim().isEmpty || phone.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => error = 'Please type the admission number and the 10-digit phone number.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final r = Map<String, dynamic>.from(await db.rpc('password_help_request', params: {'p_admission': adm.text.trim(), 'p_phone': phone.text.trim()}) as Map);
      setState(() { if (r['ok'] == true) { done = r['message']; } else { error = r['message']; } });
    } catch (e) {
      setState(() => error = 'Could not send just now. Please check the internet and try again, or call the school office: ${AppConfig.officePhonesShort}.');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (done != null) {
      return AlertDialog(
        icon: Icon(Icons.mark_email_read_rounded, color: context.tone(Brand.green), size: 40),
        title: const Text('Request sent'),
        content: Text(done!, textAlign: TextAlign.center),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      );
    }
    return AlertDialog(
      title: const Text('Forgot password?'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Type the admission number and the phone number registered with the school. The class teacher will give you a new password.', style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 14),
        TextField(controller: adm, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Admission number', hintText: 'e.g. LK/10/2014')),
        const SizedBox(height: 12),
        TextField(controller: phone, keyboardType: TextInputType.phone, onSubmitted: (_) => busy ? null : _send(), decoration: const InputDecoration(labelText: 'Registered phone number', hintText: '10 digits')),
        if (error != null) Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Brand.crimsonTint, borderRadius: BorderRadius.circular(12)),
            child: Text(error!, style: const TextStyle(color: Brand.crimsonDeep, fontWeight: FontWeight.w700, fontSize: 13))),
      ]))),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : _send, child: Text(busy ? 'Please wait…' : 'Send request')),
      ],
    );
  }
}
