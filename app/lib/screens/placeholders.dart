import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/session.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/data3.dart' show requestAccountDeletion;
import '../core/errors.dart';

/// Screens that exist in the approved prototype but whose data is wired in the next pass.
/// Each one is a real route today so navigation, deep links and the shell are complete.
class ComingSoonScreen extends StatelessWidget {
  final String title, note; final IconData icon;
  const ComingSoonScreen({super.key, required this.title, required this.note, this.icon = Icons.auto_awesome_rounded});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(8, 4, 20, 16), child: Row(children: [
        if (context.canPop()) IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)) else const SizedBox(width: 12),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      ])),
      Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 72, height: 72, alignment: Alignment.center, decoration: BoxDecoration(color: Brand.crimsonTint, borderRadius: BorderRadius.circular(24)), child: Icon(icon, color: Brand.crimsonDeep, size: 32)),
        const SizedBox(height: 18),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(note, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, height: 1.5)),
      ])))),
    ]));
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    final cs = Theme.of(context).colorScheme;
    Widget row(IconData i, String l, {String? sub, VoidCallback? onTap, Color? color}) => ListTile(
        leading: Icon(i, color: color ?? context.tone(Brand.crimsonDeep)), title: Text(l, style: TextStyle(fontWeight: FontWeight.w700, color: color)), subtitle: sub == null ? null : Text(sub),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded), onTap: onTap);
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(8, 4, 20, 16), child: Row(children: [
        IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/'), tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
        const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      ])),
      Expanded(child: ListView(padding: const EdgeInsets.all(20), children: [
        Container(decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Column(children: [
          row(Icons.people_alt_rounded, 'Students on this phone', sub: '${s?.students.length ?? 0} added', onTap: () => context.push('/students')),
          const Divider(height: 1),
          row(Icons.password_rounded, 'Change password', sub: 'For the active student', onTap: () => context.push('/change-password')),
          const Divider(height: 1),
          row(Icons.rate_review_rounded, 'Feedback to the school', onTap: () => context.push('/feedback')),
          const Divider(height: 1),
          row(Icons.privacy_tip_outlined, 'Privacy policy', sub: 'What we keep, why, and who sees it', onTap: () => context.push('/privacy')),
        ])),
        const SizedBox(height: 14),
        Container(padding: const EdgeInsets.fromLTRB(16, 12, 16, 14), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.contrast_rounded, color: Brand.crimson), SizedBox(width: 16), Expanded(child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.w700)))]),
          const SizedBox(height: 10),
          const SizedBox(width: double.infinity, child: ThemeChoice()),
          const SizedBox(height: 6),
          Text('Automatic: dark from 6:15 pm to 6:15 am, light in the day.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ])),
        const SizedBox(height: 14),
        Container(decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Column(children: [
          row(Icons.call_rounded, 'School office', sub: AppConfig.officePhonesShort, onTap: () => launchUrl(Uri.parse('tel:${AppConfig.officePhone}'))),
          const Divider(height: 1),
          if (s?.active != null && s?.viewOnly != true) ...[
            row(Icons.person_remove_outlined, 'Request account deletion', sub: 'The school office will contact you', onTap: () => _askDeletion(context, s!.active!)),
            const Divider(height: 1),
          ],
          row(Icons.logout_rounded, 'Sign out of this phone', color: Brand.crimson, onTap: () async { await ref.read(sessionProvider.notifier).signOut(); if (context.mounted) context.go('/login'); }),
        ])),
        const SizedBox(height: 18),
        Center(child: Text('${AppConfig.appName} · ${AppConfig.schoolName}\nVersion ${AppConfig.version}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
      ])),
    ]));
  }
}

/// Settings → Request account deletion: one confirm (with an optional note); the office gets the request and calls back.
Future<void> _askDeletion(BuildContext context, StudentRef st) async {
  final note = TextEditingController();
  final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
    title: const Text('Request account deletion'),
    content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('We will send a request to the school office for ${st.fullName}’s Royale Connect account. The office will call you to confirm before anything is deleted.\n\n'
          'Official school records (admission, marks, certificates) are kept as the law requires.', style: const TextStyle(height: 1.45)),
      const SizedBox(height: 12),
      TextField(controller: note, maxLines: 2, maxLength: 300, decoration: const InputDecoration(labelText: 'Anything the office should know? (optional)')),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(backgroundColor: Brand.crimson), child: const Text('Send request')),
    ],
  ));
  final text = note.text.trim();
  note.dispose();
  if (ok != true || !context.mounted) return;
  try {
    await requestAccountDeletion(st.id, text.isEmpty ? null : text);
    if (context.mounted) {
      await showDialog<void>(context: context, builder: (c) => AlertDialog(
        icon: const Icon(Icons.mark_email_read_rounded, color: Brand.green, size: 36),
        title: const Text('Request sent'),
        content: const Text('The school office will contact you.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ));
    }
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}
