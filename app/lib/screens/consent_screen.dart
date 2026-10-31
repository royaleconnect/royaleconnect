import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/data3.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_motion.dart' show ConfettiBurst;

/// Asked once, at the family's first sign-in (India's Digital Personal Data Protection law).
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});
  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool ticked = false, busy = false;

  Future<void> _agree() async {
    setState(() => busy = true);
    try {
      await db.rpc('give_consent');
      ref.invalidate(consentGivenProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save. Please check the internet and try again.\n$e')));
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget point(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 7, color: Brand.crimson)), const SizedBox(width: 10),
      Expanded(child: Text(t, style: const TextStyle(fontSize: 14.5, height: 1.45))),
    ]));
    return Scaffold(body: Column(children: [
      BrandHeader(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        const Text('Before you start', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('A one-time step required by India’s data protection law', style: TextStyle(color: Colors.white.withValues(alpha: .9))),
      ])),
      Expanded(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: ListView(padding: const EdgeInsets.all(20), children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('How the school uses your child’s information', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          point('Only for school work: classes, homework, fees, the school bus, report cards and messages with teachers.'),
          point('Never sold, and never shared for advertising.'),
          point('Kept safely. Only the staff who need it for their work can see it.'),
          point('You can ask the school office to see or correct it at any time.'),
          TextButton(onPressed: () => showPrivacyNotice(context), style: TextButton.styleFrom(padding: EdgeInsets.zero), child: const Text('Read the full privacy notice ›', style: TextStyle(fontWeight: FontWeight.w800))),
        ])),
        const SizedBox(height: 14),
        Material(color: cs.surface, borderRadius: BorderRadius.circular(18), child: CheckboxListTile(
          value: ticked, onChanged: busy ? null : (v) => setState(() => ticked = v ?? false),
          controlAffinity: ListTileControlAffinity.leading, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('I am the parent / guardian, and I agree to the school using my child’s information as described.', style: TextStyle(fontWeight: FontWeight.w700)),
        )),
        const SizedBox(height: 16),
        FilledButton(onPressed: ticked && !busy ? _agree : null, child: Text(busy ? 'Saving…' : 'I agree — continue')),
        const SizedBox(height: 8),
        Center(child: Text('Asked only once. Saved with today’s date.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
        const SizedBox(height: 18),
        Center(child: TextButton(onPressed: () => ref.read(sessionProvider.notifier).signOut(), child: const Text('Not now — sign out'))),
      ])))),
    ]));
  }
}

void showPrivacyNotice(BuildContext context) => showDialog(context: context, builder: (c) => AlertDialog(
  title: const Text('Privacy notice'),
  content: const SizedBox(width: 520, child: SingleChildScrollView(child: Text(
    'Royale Concorde International School (“the school”) uses Royale Connect to run day-to-day school work with families.\n\n'
    'What we keep: the student’s name, admission number, date of birth, class, photo (only if you allow photos), parents’ names and phone numbers, address, '
    'fees and receipts, marks and report cards, attendance, the school bus stop, and messages between you and the school.\n\n'
    'Why: to teach and look after your child, to keep you informed, to collect fees and give receipts, to run the school bus safely, and as the law requires (for example CBSE records).\n\n'
    'Who can see it: only school staff who need it for their work (for example the class teacher sees their own class). Private messages between a parent and a teacher are not read by anyone else. '
    'We never sell it or use it for advertising.\n\n'
    'How long: while your child studies here, and afterwards only as long as school records must be kept (certificates, marks and fee records).\n\n'
    'Your rights: you can ask the school office to see your child’s information, to correct it, or to raise a concern. You can also ask about this notice at the school office.\n\n'
    'Agreeing: you agree once, at your first sign-in. If you do not agree, please speak to the school office.',
    style: TextStyle(height: 1.5),
  ))),
  actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
));

/// The birthday greeting at the top of Home.
class BirthdayCard extends StatelessWidget {
  final String name;
  const BirthdayCard(this.name, {super.key});
  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [_card(), const Positioned(left: 0, right: 0, top: -40, height: 260, child: ConfettiBurst(count: 90, origin: Alignment(0, -.2), ms: 3200))]);

  Widget _card() => Container(
    margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFF6E0), Color(0xFFFFE3E3)]), border: Border.all(color: Brand.gold, width: 2), borderRadius: BorderRadius.circular(20)),
    child: Column(children: [
      const Text('🎂 🎈', style: TextStyle(fontSize: 34)),
      const SizedBox(height: 4),
      Text('Happy Birthday, ${name.split(' ').first}!', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Brand.crimsonDeep)),
      const SizedBox(height: 6),
      const Text('Wishing you a joyful year full of learning, friends and success.\n— The Principal and teachers, Royale Concorde', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.45, color: Color(0xFF4A3A2A))),
    ]),
  );
}
