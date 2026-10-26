import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

/// "Who are we looking at?" — shown after OTP login with several children, and from Home to switch.
class StudentsScreen extends ConsumerWidget {
  const StudentsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    if (s == null) return const SizedBox.shrink();
    final picked = ref.watch(childPickedProvider);
    Future<void> open(String id) async { await ref.read(sessionProvider.notifier).selectStudent(id); ref.read(childPickedProvider.notifier).done(); if (context.mounted) context.go('/'); }
    return Scaffold(body: Column(children: [
      BrandHeader(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (picked && s.activeStudentId != null) IconButton(onPressed: () => context.go('/'), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
          const Spacer(),
          TextButton.icon(onPressed: () => context.push('/login/add'), icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 18), label: const Text('Add a sibling', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 10),
        Text('Welcome back', style: t.headlineMedium?.copyWith(color: Colors.white)),
        const SizedBox(height: 6),
        Text('Choose whose day you would like to see.', style: TextStyle(color: Colors.white.withValues(alpha: .9))),
      ])),
      Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
        for (final st in s.students) Padding(padding: const EdgeInsets.only(bottom: 14), child: Material(color: cs.surface, borderRadius: BorderRadius.circular(22),
            child: InkWell(borderRadius: BorderRadius.circular(22), onTap: () => open(st.id),
                child: Container(padding: const EdgeInsets.fromLTRB(18, 20, 16, 20),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: Brand.gold.withValues(alpha: .55))),
                    child: Row(children: [
                      Avatar(st.initials, size: 60), const SizedBox(width: 16),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(st.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
                        const SizedBox(height: 2),
                        Text('${st.grade ?? ''} · Section ${st.section ?? ''}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                        Text(st.admissionNo, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ])),
                      Container(width: 40, height: 40, decoration: const BoxDecoration(color: Brand.crimson, shape: BoxShape.circle), child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20)),
                    ]))))),
        const SizedBox(height: 6),
        const NoteBox('Each child has their own admission number and password. You can switch children any time from Home or the menu.'),
      ])))),
    ]));
  }
}
