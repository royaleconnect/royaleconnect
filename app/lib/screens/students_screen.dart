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
    return Scaffold(body: Column(children: [
      BrandHeader(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (s.activeStudentId != null) IconButton(onPressed: () => context.go('/'), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
          const Spacer(),
          TextButton.icon(onPressed: () => context.push('/login/add'), icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 18), label: const Text('Add a sibling', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 10),
        Text('Who are we looking at?', style: t.headlineMedium?.copyWith(color: Colors.white)),
        const SizedBox(height: 6),
        Text('${s.students.length} ${s.students.length == 1 ? 'student' : 'students'} on this phone. Switch any time from Home.', style: TextStyle(color: Colors.white.withValues(alpha: .9))),
      ])),
      Expanded(child: ListView(padding: const EdgeInsets.all(20), children: [
        for (final st in s.students) Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(color: cs.surface, borderRadius: BorderRadius.circular(18),
            child: InkWell(borderRadius: BorderRadius.circular(18), onTap: () async { await ref.read(sessionProvider.notifier).selectStudent(st.id); if (context.mounted) context.go('/'); },
                child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                  Avatar(st.initials), const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(st.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text('${st.grade ?? ''} ${st.section ?? ''} · ${st.admissionNo}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ])),
                  if (st.id == s.activeStudentId) const Pill('Active', fg: Brand.green, bg: Brand.greenTint) else Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                ]))))),
        const SizedBox(height: 10),
        const NoteBox('Each child has their own admission number and password. Parents and the student share the same login.'),
      ])),
    ]));
  }
}
