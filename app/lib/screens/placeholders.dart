import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/session.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

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
        leading: Icon(i, color: color ?? Brand.crimsonDeep), title: Text(l, style: TextStyle(fontWeight: FontWeight.w700, color: color)), subtitle: sub == null ? null : Text(sub),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded), onTap: onTap);
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(8, 4, 20, 16), child: Row(children: [
        IconButton(onPressed: () => context.go('/'), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
        const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      ])),
      Expanded(child: ListView(padding: const EdgeInsets.all(20), children: [
        Container(decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Column(children: [
          row(Icons.people_alt_rounded, 'Students on this phone', sub: '${s?.students.length ?? 0} added', onTap: () => context.push('/students')),
          const Divider(height: 1),
          row(Icons.password_rounded, 'Change password', sub: 'For the active student', onTap: () => context.push('/set-password')),
          const Divider(height: 1),
          row(Icons.notifications_active_rounded, 'Notifications', sub: 'Quiet hours 9 pm – 6 am · urgent alerts always come through'),
          const Divider(height: 1),
          row(Icons.rate_review_rounded, 'Feedback to the school', onTap: () => context.push('/feedback')),
        ])),
        const SizedBox(height: 14),
        Container(padding: const EdgeInsets.fromLTRB(16, 12, 16, 14), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Row(children: [
          const Icon(Icons.contrast_rounded, color: Brand.crimson), const SizedBox(width: 16),
          const Expanded(child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.w700))),
          const ThemeChoice(),
        ])),
        const SizedBox(height: 14),
        Container(decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Column(children: [
          row(Icons.call_rounded, 'School office', sub: AppConfig.officePhone),
          const Divider(height: 1),
          row(Icons.logout_rounded, 'Sign out of this phone', color: Brand.crimson, onTap: () async { await ref.read(sessionProvider.notifier).signOut(); if (context.mounted) context.go('/login'); }),
        ])),
        const SizedBox(height: 18),
        Center(child: Text('${AppConfig.appName} · ${AppConfig.schoolName}\nVersion ${AppConfig.version}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
      ])),
    ]));
  }
}
