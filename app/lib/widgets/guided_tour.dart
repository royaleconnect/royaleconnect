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
  /// the parts of the screen this step points at (the first one on screen is used); none = a card in the middle
  final List<String> at;
  /// skip this step when none of its parts is on screen (e.g. Bus for a student who does not take the bus)
  final bool optional;
  const TourStep(this.title, this.text, this.icon, {this.at = const [], this.optional = false});
}

/// The parts of the app a tour can point at. A screen marks a part with `TourTarget('id', child: …)`.
final _targets = <String, GlobalKey>{};
GlobalKey tourKey(String id) => _targets.putIfAbsent(id, () => GlobalKey(debugLabel: 'tour:$id'));

class TourTarget extends StatelessWidget {
  final String id; final Widget child;
  const TourTarget(this.id, {super.key, required this.child});
  @override
  Widget build(BuildContext context) => KeyedSubtree(key: tourKey(id), child: child);
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
    TourStep('Your child', 'Tap here for the profile and the ID card. With two children, tap to switch between them.', Icons.person_rounded, at: ['f-child']),
    TourStep('Needs you today', 'Only what needs you: a fee due, a notice to read, homework for tomorrow. When it says “All done”, you are free.', Icons.task_alt_rounded, at: ['f-needs']),
    TourStep('Attendance streak', 'Days present in a row. A gold celebration at 30 and 60 days.', Icons.local_fire_department_rounded, at: ['f-streak'], optional: true),
    TourStep('Notices', 'Every school notice comes here, with a notification on your phone. Urgent ones show in red at the top of Home.', Icons.campaign_rounded, at: ['f-notices', 'nav:/announcements']),
    TourStep('Diary', 'Today’s homework and notes from the teachers, plus My list to tick off what is done.', Icons.menu_book_rounded, at: ['f-diary', 'nav:/diary']),
    TourStep('Fees', 'See what is due, pay online and download receipts.', Icons.account_balance_wallet_rounded, at: ['f-fees', 'nav:/fees']),
    TourStep('Bus', 'Watch the bus live and get an alert 10 and 5 minutes before it reaches your stop.', Icons.directions_bus_rounded, at: ['f-bus', 'nav:/bus'], optional: true),
    TourStep('Help', 'Any question? Tap here, or call the school office from Profile. You can see this tour again from Help.', Icons.help_outline_rounded, at: ['f-help', 'nav:/profile']),
  ],
  'teacher': [
    TourStep('Today', 'Your first page shows what needs you first: parent messages, leave requests and classes still waiting for today’s diary.', Icons.today_rounded, at: ['nav:/staff']),
    TourStep('Diary', 'Post homework once. “Also send to” sends the same note to your other sections of the same grade — they are ticked for you.', Icons.menu_book_rounded, at: ['nav:/staff/diary']),
    TourStep('Attendance', 'Everyone starts as present. Tap only the children who are absent, then Save. Their families are told at once.', Icons.fact_check_rounded, at: ['nav:/staff/attendance'], optional: true),
    TourStep('Exams & marks', 'Portions, marks entry and report cards are together here.', Icons.grading_rounded, at: ['nav:/staff/exams']),
    TourStep('Messages', 'Reply to parents here. Sent something by mistake? Press and hold your message to edit or delete it, within 2 days.', Icons.chat_bubble_rounded, at: ['nav:/staff/messages']),
    TourStep('Find a student', 'Type 2–3 letters of a name, admission number or phone here (or press Ctrl + K).', Icons.search_rounded, at: ['staff-search'], optional: true),
    TourStep('Help', 'Short answers to every question. You can take this tour again from here.', Icons.help_outline_rounded, at: ['nav:/staff/help']),
  ],
  'office': [
    TourStep('Approvals', 'Everything waiting for a yes or no is in one place: password help, leave, receipt cancellations, certificates.', Icons.inbox_rounded, at: ['nav:/staff/approvals'], optional: true),
    TourStep('Fees & receipts', 'Record a payment, print the receipt, see who still owes fees and download reports in Excel. Reminders to families go by themselves.', Icons.account_balance_wallet_rounded, at: ['nav:/staff/fees']),
    TourStep('Students', 'Find any student by name, admission number or a parent’s phone. The full record opens with one tap.', Icons.people_alt_rounded, at: ['nav:/staff/students']),
    TourStep('Certificates', 'TC, Study, Bonafide and No dues certificates, filled in from the records, ready to print.', Icons.workspace_premium_rounded, at: ['nav:/staff/certificates'], optional: true),
    TourStep('ID cards', 'Print ID cards class by class. It glows gold when every card is ready.', Icons.badge_rounded, at: ['nav:/staff/id-cards'], optional: true),
    TourStep('Notices', 'Send to the whole school, a grade, a section or bus families. Unsend within 10 minutes; edit later.', Icons.campaign_rounded, at: ['nav:/staff/announcements']),
    TourStep('Help', 'Short answers to every question. You can take this tour again from here.', Icons.help_outline_rounded, at: ['nav:/staff/help']),
  ],
  'leader': [
    TourStep('The whole school at a glance', 'Your first page shows students, today’s attendance, fees and notices, and the Data checker, which lists anything missing, like a photo or a phone number.', Icons.dashboard_rounded, at: ['nav:/staff']),
    TourStep('The small dot', 'The dot at the top shows the app’s health. Green: all is well. Amber or red: tap it to see what to check.', Icons.circle, at: ['staff-health'], optional: true),
    TourStep('Approvals', 'Receipt cancellations and other things waiting for your yes or no.', Icons.inbox_rounded, at: ['nav:/staff/approvals'], optional: true),
    TourStep('Principal’s Desk', 'Your welcome and event messages to families and staff, shown full screen once to everyone.', Icons.auto_awesome_rounded, at: ['nav:/staff/desk'], optional: true),
    TourStep('School setup', 'Staff, classes & fees, sections on/off, the Bin (bring back anything deleted within 30 days) and branches — all as tabs here.', Icons.tune_rounded, at: ['nav:/staff/setup']),
    TourStep('Weekly summary', 'Every Monday at 8 am: “Your week at Royale”, five lines about the week and what needs you.', Icons.insights_rounded),
    TourStep('Help', 'Short answers, and the IT handbook. You can take this tour again from here.', Icons.help_outline_rounded, at: ['nav:/staff/help']),
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
  var list = [...(steps ?? tourSteps[role] ?? const <TourStep>[])];
  // a step whose part is not on this screen (e.g. Bus for a child who does not take the bus) is left out
  list = [for (final t in list) if (!t.optional || t.at.any((id) => _rectOfId(id) != null)) t];
  // the Principal's first look: a welcome with her name, then her tour
  try {
    final s = ProviderScope.containerOf(context, listen: false).read(sessionProvider).value;
    if (role == 'leader' && s != null && s.hasRole('principal') && steps == null) {
      final name = (s.staff?['name'] ?? s.staff?['display_name'] ?? '').toString();
      list.insert(0, TourStep('Welcome${name.isEmpty ? '' : ', $name'}', 'Royale Connect brings families, teachers and the office together in one place. Here is a one-minute look at what is ready for you.', Icons.auto_awesome_rounded));
    }
  } catch (_) {}
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

Rect? _rectOfId(String id) {
  final ro = _targets[id]?.currentContext?.findRenderObject();
  if (ro is! RenderBox || !ro.hasSize || !ro.attached) return null;
  final r = ro.localToGlobal(Offset.zero) & ro.size;
  return r.isEmpty ? null : r;
}

class _TourOverlay extends StatefulWidget {
  final List<TourStep> steps;
  const _TourOverlay({required this.steps});
  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> with SingleTickerProviderStateMixin {
  int i = 0;
  late final AnimationController pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  @override
  void dispose() { pulse.dispose(); super.dispose(); }
  @override
  void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => _bringIntoView()); }

  /// scroll the page so the part this step talks about is on screen, then light it up
  Future<void> _bringIntoView() async {
    for (final id in widget.steps[i].at) {
      final c = _targets[id]?.currentContext;
      if (c == null || !c.mounted) continue;
      try { await Scrollable.ensureVisible(c, alignment: .3, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic); } catch (_) {}
      break;
    }
    if (mounted) setState(() {});
  }
  void _go(int n) { setState(() => i = n); _bringIntoView(); }

  Rect? _rectOf(List<String> ids) {
    for (final id in ids) { final r = _rectOfId(id); if (r != null) return r.inflate(6); }
    // on a phone the staff menu sits behind the Menu button: point there
    if (ids.any((id) => id.startsWith('nav:/staff/'))) { final r = _rectOfId('staff-menu'); if (r != null) return r.inflate(6); }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final step = widget.steps[i];
    final last = i == widget.steps.length - 1;
    final size = MediaQuery.sizeOf(context);
    var hole = _rectOf(step.at);
    // a part that is still off the screen gets a card in the middle instead
    if (hole != null && (hole.bottom < 0 || hole.top > size.height || hole.height > size.height * .6)) hole = null;
    if (MediaQuery.of(context).disableAnimations && pulse.isAnimating) pulse.stop();
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
            if (i > 0) TextButton(onPressed: () => _go(i - 1), child: const Text('Back')),
            const SizedBox(width: 6),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 20)),
              onPressed: () => last ? Navigator.of(context).pop() : _go(i + 1),
              child: Text(last ? 'Done' : 'Next')),
          ]),
        ])),
      ),
    ));
    // the card sits under the lit-up part when there is room, otherwise in the middle
    Widget placed;
    var below = true;
    if (hole == null) {
      placed = Positioned.fill(child: Center(child: Padding(padding: const EdgeInsets.all(20), child: card)));
    } else {
      below = hole.bottom + 16 < size.height - 300;
      // on a laptop the card sits beside a menu item on the left; on a phone, under or over the lit-up part
      final side = hole.right < size.width * .35 && size.width >= 900;
      placed = side
          ? Positioned(left: hole.right + 18, top: (hole.center.dy - 90).clamp(16.0, size.height - 320), child: SizedBox(width: 400, child: card))
          : Positioned(left: 16, right: 16, top: below ? hole.bottom + 16 : null, bottom: below ? null : size.height - hole.top + 16,
              child: Align(alignment: Alignment.topCenter, child: card));
      if (side) below = false;
    }
    return Stack(children: [
      Positioned.fill(child: AnimatedBuilder(animation: pulse, builder: (_, __) => CustomPaint(
          painter: _Dim(hole, Colors.black.withValues(alpha: .58), pulse.value, cs.surface, hole == null ? null : (hole.right < size.width * .35 && size.width >= 900 ? 'right' : below ? 'down' : 'up'))))),
      placed,
    ]);
  }
}

class _Dim extends CustomPainter {
  final Rect? hole; final Color color; final double t; final Color card; final String? arrow;
  _Dim(this.hole, this.color, [this.t = 0, this.card = Colors.white, this.arrow]);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      p.addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(14)));
      p.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(p, Paint()..color = color);
    if (hole != null) {
      final h = hole!;
      canvas.drawRRect(RRect.fromRectAndRadius(h, const Radius.circular(14)), Paint()..color = Brand.gold2..style = PaintingStyle.stroke..strokeWidth = 2.2);
      // a soft gold ring that keeps pulsing outwards
      canvas.drawRRect(RRect.fromRectAndRadius(h.inflate(2 + 10 * t), Radius.circular(14 + 10 * t)),
          Paint()..color = Brand.gold2.withValues(alpha: (1 - t) * .8)..style = PaintingStyle.stroke..strokeWidth = 2);
      // the little arrow from the card to the lit-up part
      final a = Path();
      if (arrow == 'down') { final x = h.center.dx.clamp(30.0, size.width - 30); a..moveTo(x - 9, h.bottom + 17)..lineTo(x, h.bottom + 8)..lineTo(x + 9, h.bottom + 17)..close(); }
      if (arrow == 'up') { final x = h.center.dx.clamp(30.0, size.width - 30); a..moveTo(x - 9, h.top - 17)..lineTo(x, h.top - 8)..lineTo(x + 9, h.top - 17)..close(); }
      if (arrow == 'right') { final y = h.center.dy; a..moveTo(h.right + 19, y - 9)..lineTo(h.right + 10, y)..lineTo(h.right + 19, y + 9)..close(); }
      canvas.drawPath(a, Paint()..color = card);
    }
  }
  @override
  bool shouldRepaint(_Dim o) => o.hole != hole || o.color != color || o.t != t || o.arrow != arrow;
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
