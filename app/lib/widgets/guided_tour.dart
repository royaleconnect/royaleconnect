import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/session.dart';
import '../core/data.dart' show viewOnlyMode;
import '../core/theme.dart';

/// A short guided tour: a soft dimmed backdrop and one card at a time with Next / Back / Skip.
/// Shown once per phone (or browser) for each kind of user, the first time they sign in.
/// It can be taken again from Help → "Take the tour again".
///
/// Roles: 'family', 'teacher', 'office', 'leader' (IT admin, Principal, Vice Principal).

class TourStep {
  final String title, text;
  final IconData icon;
  /// optional: the part of the screen to light up (a plain centred card is shown when it is not on screen)
  final GlobalKey? target;
  const TourStep(this.title, this.text, this.icon, {this.target});
}

/// Which tour a signed-in person gets.
String tourRoleFor(Session s) {
  if (!s.isStaff) return 'family';
  if (s.hasRole('it_admin') || s.hasRole('principal') || s.hasRole('vice_principal')) return 'leader';
  if (s.isOffice || s.hasRole('accounts')) return 'office';
  return 'teacher';
}

const tourSteps = <String, List<TourStep>>{
  'family': [
    TourStep('Welcome to Royale Connect', 'A quick look around — it takes less than a minute. The top of Home, “Needs you today”, shows only what needs you: a fee due, a form to sign, a reply. When it says “All done”, you can relax.', Icons.home_rounded),
    TourStep('Everything else, one tap away', 'Below that, the tiles open the timetable, calendar, exams, photos and more.', Icons.grid_view_rounded),
    TourStep('Diary and My list', 'Diary shows each day’s homework and class notes. Tap the star on anything you want to remember — it goes to My list, and you can tick it off when it is done.', Icons.menu_book_rounded),
    TourStep('Attendance and leave', 'See your child’s attendance month by month. Asking for leave takes two taps — the class teacher is told at once.', Icons.fact_check_rounded),
    TourStep('Fees', 'See what is due, pay online with UPI or card, and download every receipt.', Icons.account_balance_wallet_rounded),
    TourStep('Profile', 'Tap Profile for the ID card, Help & feedback, and Call school office. You can take this tour again from Help.', Icons.person_rounded),
  ],
  'teacher': [
    TourStep('Today', 'Your first page shows what needs you first: parent messages, leave requests, and classes still waiting for today’s diary.', Icons.today_rounded),
    TourStep('Diary', 'Post homework once. “Also send to” sends the same note to your other sections of the same grade — they are ticked for you.', Icons.menu_book_rounded),
    TourStep('Attendance', 'Class teachers: everyone starts as present. Just tap the children who are absent, then Save. Families of absent children get a gentle note.', Icons.fact_check_rounded),
    TourStep('Exams & marks', 'Portions, marks entry and report cards are together under Exams & marks.', Icons.grading_rounded),
    TourStep('Messages', 'Reply to parents here. Sent something by mistake? Press and hold your message to edit or delete it, within 2 days.', Icons.chat_bubble_rounded),
    TourStep('Honours', 'Toppers, Student Council and Houses live under Honours. Stuck anywhere? Help is at the bottom of the menu.', Icons.emoji_events_rounded),
  ],
  'office': [
    TourStep('Approvals', 'Everything waiting for a yes or no is in one place: leave, notices from teachers and receipt changes.', Icons.task_alt_rounded),
    TourStep('Fees & receipts', 'Record a payment, print the receipt, and see who still owes fees. Reminders to families go by themselves.', Icons.account_balance_wallet_rounded),
    TourStep('Students', 'Find any student by name, admission number or a parent’s phone. The full record opens with one tap.', Icons.people_alt_rounded),
    TourStep('Notices', 'Send to the whole school, a grade, a section or bus families. Unsend within 10 minutes, edit later (families see “Updated”), and keep an important notice on top until a date.', Icons.campaign_rounded),
    TourStep('Help is always here', 'Help, at the bottom of the menu, has short answers. You can take this tour again from there.', Icons.help_outline_rounded),
  ],
  'leader': [
    TourStep('The whole school at a glance', 'Your first page shows students, today’s attendance, fees and notices — and the Data checker, which lists anything missing, like a photo or a phone number.', Icons.dashboard_rounded),
    TourStep('School setup', 'School setup has tabs: Staff, Classes & fees, and Sections on/off — switch a section of the family app on or off for everyone.', Icons.tune_rounded),
    TourStep('Bin and Branches', 'Deleted something by mistake? The Bin keeps everything for 30 days — bring it back with one tap. Branches is ready for the day a new branch opens.', Icons.delete_outline_rounded),
    TourStep('Principal’s Desk', 'A message from the Principal to all families, beautifully presented, from Principal’s Desk.', Icons.auto_awesome_rounded),
    TourStep('Weekly summary', 'Every Monday at 8 am: “Your week at Royale” — five lines about the week, and what needs you. Tap it to open.', Icons.insights_rounded),
    TourStep('The small dot', 'The dot at the top of your first page shows the app’s health. Green: all is well. Amber or red: tap it to see what to check.', Icons.circle),
  ],
};

String _key(String role) => 'rc_tour_done_$role';
final _shownThisRun = <String>{};

/// Call once the first screen after sign-in is on screen. Shows the tour only the first time on this device for this role.
/// Never shown while an admin is using "View as family".
Future<void> maybeShowTour(BuildContext context, String role) async {
  if (viewOnlyMode || _shownThisRun.contains(role) || !tourSteps.containsKey(role)) return;
  _shownThisRun.add(role);
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_key(role)) == true) return;
  await Future<void>.delayed(const Duration(milliseconds: 900));   // let the first page settle
  if (!context.mounted) return;
  await showTour(context, role);
}

/// Always shows the tour (Help → "Take the tour again"). Marks it as seen when it closes (finished or skipped).
Future<void> showTour(BuildContext context, String role, {List<TourStep>? steps}) async {
  final list = steps ?? tourSteps[role] ?? const <TourStep>[];
  if (list.isEmpty) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Tour',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => _TourOverlay(steps: list),
    transitionBuilder: (_, a, __, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
  );
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_key(role), true);
}

class _TourOverlay extends StatefulWidget {
  final List<TourStep> steps;
  const _TourOverlay({required this.steps});
  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  int i = 0;

  Rect? _rectOf(GlobalKey? k) {
    final ro = k?.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) return null;
    final o = ro.localToGlobal(Offset.zero);
    return (o & ro.size).inflate(6);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final step = widget.steps[i];
    final last = i == widget.steps.length - 1;
    final hole = _rectOf(step.target);
    final size = MediaQuery.sizeOf(context);
    final card = ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Material(
      color: cs.surface, elevation: 10, shadowColor: Colors.black38, borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: Brand.gold.withValues(alpha: .55), width: 1.2)),
        child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: Column(key: ValueKey(i), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(width: 42, height: 42, alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Brand.gold2, Brand.gold])),
                child: Icon(step.icon, color: Brand.crimsonDeep, size: step.icon == Icons.circle ? 14 : 22)),
            const SizedBox(width: 12),
            Expanded(child: Text(step.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
          ]),
          const SizedBox(height: 12),
          Text(step.text, style: TextStyle(fontSize: 14.5, height: 1.5, color: cs.onSurface)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < widget.steps.length; k++) AnimatedContainer(
              duration: const Duration(milliseconds: 200), margin: const EdgeInsets.symmetric(horizontal: 3),
              width: k == i ? 18 : 7, height: 7,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: k == i ? Brand.crimson : cs.outline.withValues(alpha: .7))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            if (!last) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Skip')),
            const Spacer(),
            if (i > 0) TextButton(onPressed: () => setState(() => i--), child: const Text('Back')),
            const SizedBox(width: 6),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 20)),
              onPressed: () => last ? Navigator.of(context).pop() : setState(() => i++),
              child: Text(last ? 'Done' : 'Next')),
          ]),
        ])),
      ),
    ));
    // the card sits under the lit-up part when there is room, otherwise in the middle
    Widget placed;
    if (hole == null) {
      placed = Positioned.fill(child: Center(child: Padding(padding: const EdgeInsets.all(20), child: card)));
    } else {
      final below = hole.bottom + 16 < size.height - 260;
      placed = Positioned(left: 16, right: 16, top: below ? hole.bottom + 14 : null, bottom: below ? null : size.height - hole.top + 14,
          child: Align(alignment: Alignment.topCenter, child: card));
    }
    return Stack(children: [
      Positioned.fill(child: CustomPaint(painter: _Dim(hole, Colors.black.withValues(alpha: .55)))),
      placed,
    ]);
  }
}

class _Dim extends CustomPainter {
  final Rect? hole; final Color color;
  _Dim(this.hole, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      p.addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(14)));
      p.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(p, Paint()..color = color);
    if (hole != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(14)), Paint()..color = Brand.gold..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }
  @override
  bool shouldRepaint(_Dim o) => o.hole != hole || o.color != color;
}

/// For Help: "Take the tour again".
class TakeTourAgainButton extends ConsumerWidget {
  const TakeTourAgainButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    if (s == null || s.viewOnly) return const SizedBox.shrink();
    return Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
      onPressed: () => showTour(context, tourRoleFor(s)),
      icon: const Icon(Icons.tour_rounded, size: 18),
      label: const Text('Take the tour again'),
    ));
  }
}
