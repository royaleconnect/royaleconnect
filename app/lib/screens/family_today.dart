import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/data2.dart';
import '../core/data3.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart' show inr;
import '../widgets/royal_motion.dart' show reduceMotion;
import 'my_list.dart' show diaryTabProvider;
import 'notice_extras.dart';

/// Release H — the family Home's building blocks: the one "Today · needs you" card, the birthday card, the bus line,
/// and the small rules they share (next school day, the class as it is today, the notices meant for this child).

// ---------------------------------------------------------------- shared rules
String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// The next day this child has school after today: skips Sundays, Saturdays that are off for the grade, and holidays
/// on the school calendar meant for the grade.
DateTime nextSchoolDay(List<Map<String, dynamic>> calendar, String? grade, [DateTime? from]) {
  final n = from ?? DateTime.now();
  bool holiday(DateTime d) {
    final x = _iso(d);
    return calendar.any((e) => e['kind'] == 'holiday' && (e['starts_on'] as String).compareTo(x) <= 0 &&
        ((e['ends_on'] ?? e['starts_on']) as String).compareTo(x) >= 0 && eventIsFor(e, grade));
  }
  var d = DateTime(n.year, n.month, n.day).add(const Duration(days: 1));
  for (var i = 0; i < 40; i++) {
    final open = (d.weekday < 6 || (d.weekday == 6 && isWorkingSaturday(d, grade))) && !holiday(d);
    if (open) return d;
    d = d.add(const Duration(days: 1));
  }
  return d;
}

/// 'tomorrow', 'Monday', or 'Mon 17 Nov' for a day after today.
String dayWord(DateTime d) {
  final n = DateTime.now();
  final gap = DateTime(d.year, d.month, d.day).difference(DateTime(n.year, n.month, n.day)).inDays;
  if (gap == 0) return 'today';
  if (gap == 1) return 'tomorrow';
  if (gap < 7) return DateFormat('EEEE').format(d);
  return DateFormat('EEE d MMM').format(d);
}

/// The class as it is today, from the current enrolment ('VIII-B'); after a move-up the saved sign-in still has the
/// old class, so that is only the fallback.
String classNow(WidgetRef ref, StudentRef st) {
  final sec = ref.watch(enrolmentProvider).value?['section'];
  final code = sec?['grade']?['code'] as String?;
  if (code == null) return st.cls;
  final s = shownSection(sec);
  return s == null ? code : '$code-$s';
}

/// The notices meant for the active child (a sibling's bus notices are left out) — the same list the Notices page shows.
List<Notice> familyVisibleNotices(WidgetRef ref) {
  final list = ref.watch(noticesProvider).value ?? const <Notice>[];
  final extras = ref.watch(noticeExtrasProvider).value ?? const <String, NoticeExtra>{};
  final myRoute = ref.watch(transportProvider).value?['route']?['id'] as String?;
  return familyNotices(list, extras, myRoute);
}

/// Unread notices for the active child — the badge on the bell, the Notices tile and the menu.
int unreadFamilyNotices(WidgetRef ref) => familyVisibleNotices(ref).where((n) => !n.read).length;

/// "Ask the class teacher": opens the chat with this child's class teacher (or the Messages list when the class has none yet).
Future<void> openClassTeacherChat(BuildContext context, WidgetRef ref) async {
  final st = ref.read(sessionProvider).value?.active;
  if (st == null) return;
  try {
    final list = await ref.read(contactsProvider.future);
    final ct = list.where((c) => c.kind == 'class').firstOrNull;
    if (ct == null || viewOnlyMode) { if (context.mounted) context.push('/messages'); return; }
    final id = await openConversation(st.id, ct.staffId);
    if (context.mounted) context.push('/chat/$id', extra: ct.name);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

// ---------------------------------------------------------------- TODAY · NEEDS YOU
/// One card with only what needs the family: the fee to pay (with a Pay button), homework for the next school day,
/// new notices. When nothing is pending: "All done for today ✨".
class TodayNeedsCard extends ConsumerWidget {
  const TodayNeedsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final fees = ref.watch(feesProvider).value;
    final grade = ref.watch(enrolmentProvider).value?['section']?['grade']?['code'] as String?;
    final calendar = ref.watch(calendarProvider).value ?? const <Map<String, dynamic>>[];
    final next = nextSchoolDay(calendar, grade);
    final hw = ref.watch(homeworkForProvider(_iso(next))).value ?? const <String>[];
    final unread = familyVisibleNotices(ref).where((n) => !n.read).toList();
    final rows = <Widget>[];

    // 1. fee
    if (fees != null) {
      final due = feesDueNow(fees);
      if (due.isNotEmpty) {
        final amt = due.fold<num>(0, (a, r) => a + r.amount);
        final over = due.where((r) => r.overdue && !r.isLate).toList();
        final head = over.isNotEmpty ? over.first : due.firstWhere((r) => !r.isLate, orElse: () => due.first);
        final title = over.isNotEmpty ? 'Fee ${inr(amt)} overdue' : 'Fee ${inr(amt)} due ${dayWord(DateTime.parse(head.dueOn))}';
        final names = due.where((r) => !r.isLate).map((r) => r.title).toList();
        final sub = over.isNotEmpty
            ? '${names.length > 1 ? '${names.length} items' : head.title}${due.any((r) => r.isLate) ? ' + late fee' : ''} · since ${DateFormat('d MMM').format(DateTime.parse(head.dueOn))}'
            : names.join(' · ');
        rows.add(_Row(icon: '💳', tint: dark ? const Color(0xFF3A1A1C) : Brand.crimsonTint, title: title, sub: sub,
            action: _PayButton(amt, () => context.push('/pay')), onTap: () => context.push('/pay')));
      }
    }
    // 2. homework for the next school day
    if (hw.isNotEmpty) {
      final subjects = <String>{...hw}.join(' · ');
      rows.add(_Row(icon: '📖', tint: dark ? const Color(0xFF14283A) : Brand.blueTint, title: '${hw.length} homework for ${dayWord(next)}', sub: subjects,
          link: 'Diary', onTap: () { ref.read(diaryTabProvider.notifier).state = 0; context.go('/diary'); }));
    }
    // 3. new notices
    if (unread.isNotEmpty) {
      final urgent = unread.where((n) => n.urgent).toList();
      final top = urgent.isNotEmpty ? urgent.first : unread.first;
      rows.add(_Row(icon: urgent.isNotEmpty ? '⚠️' : '📣', tint: urgent.isNotEmpty ? (dark ? const Color(0xFF3A1A1C) : Brand.crimsonTint) : (dark ? const Color(0xFF3A2E14) : Brand.amberTint),
          title: '${unread.length} new notice${unread.length == 1 ? '' : 's'}', sub: '${urgent.isNotEmpty ? 'Urgent · ' : ''}${top.title}',
          link: 'Read', onTap: () => unread.length == 1 ? context.push('/notice/${top.id}') : context.go('/announcements')));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.fromLTRB(14, 12, 12, 6),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: dark ? const [Color(0xFF241D18), Color(0xFF1F1915)] : const [Colors.white, Color(0xFFFFF8EC)]),
          border: Border.all(color: dark ? const Color(0xFF4A3A22) : const Color(0xFFEADFC8)),
          boxShadow: [BoxShadow(color: Brand.crimsonDeep.withValues(alpha: dark ? .25 : .10), blurRadius: 24, offset: const Offset(0, 10))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('TODAY · NEEDS YOU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: dark ? Brand.gold2 : const Color(0xFFA8822F))),
        const SizedBox(height: 4),
        if (rows.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(0, 8, 0, 10), child: Row(children: [
          Icon(Icons.check_circle_rounded, color: context.tone(Brand.green), size: 22), const SizedBox(width: 10),
          Expanded(child: Text('All done for today ✨', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface))),
        ])),
        for (final (i, r) in rows.indexed) Container(
          decoration: BoxDecoration(border: i == rows.length - 1 ? null : Border(bottom: BorderSide(color: dark ? const Color(0xFF3A2E1E) : const Color(0xFFEDE4D3)))),
          child: r),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final String icon, title, sub; final Color tint; final Widget? action; final String? link; final VoidCallback onTap;
  const _Row({required this.icon, required this.tint, required this.title, required this.sub, this.action, this.link, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Row(children: [
      Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)),
          child: Text(icon, style: const TextStyle(fontSize: 16))),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ])),
      const SizedBox(width: 8),
      if (action != null) action!
      else if (link != null) Text('$link ›', style: TextStyle(color: context.tone(Brand.crimson), fontWeight: FontWeight.w800, fontSize: 12.5)),
    ])));
  }
}

class _PayButton extends StatelessWidget {
  final num amount; final VoidCallback onTap;
  const _PayButton(this.amount, this.onTap);
  @override
  Widget build(BuildContext context) => ConstrainedBox(constraints: const BoxConstraints(maxWidth: 132), child: Material(
      color: Brand.crimson, borderRadius: BorderRadius.circular(99),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(99), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: FittedBox(fit: BoxFit.scaleDown, child: Text('Pay ${inr(amount)}', maxLines: 1, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)))))));
}

// ---------------------------------------------------------------- bus line
/// "Bus 29 · Kalyan Nagar stop · pickup 7:10 · drop 3:40" — one quiet line for children on a bus (taps open Bus).
class HomeBusLine extends ConsumerWidget {
  const HomeBusLine({super.key});
  static String _hm(dynamic t) {
    final x = (t ?? '').toString();
    if (x.length < 5) return x;
    final d = DateTime.tryParse('2000-01-01 ${x.substring(0, 5)}');
    return d == null ? x.substring(0, 5) : DateFormat('h:mm').format(d);
  }
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(transportProvider).value;
    if (t == null || !featureOn(ref.watch(appSettingsProvider).value, 'bus')) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final stop = t['stop'] as Map?; final route = t['route'] as Map?;
    final parts = [
      if ((stop?['name'] ?? '').toString().isNotEmpty) '${stop!['name']}',
      if (stop?['morning_eta'] != null) 'pickup ${_hm(stop!['morning_eta'])}',
      if (stop?['afternoon_eta'] != null) 'drop ${_hm(stop!['afternoon_eta'])}',
    ];
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Material(color: cs.surface, borderRadius: BorderRadius.circular(16), child: InkWell(
      borderRadius: BorderRadius.circular(16), onTap: () => context.go('/bus'),
      child: Padding(padding: const EdgeInsets.fromLTRB(14, 11, 10, 11), child: Row(children: [
        Icon(Icons.directions_bus_rounded, size: 20, color: context.tone(Brand.blue)),
        const SizedBox(width: 10),
        Expanded(child: Text.rich(TextSpan(children: [
          TextSpan(text: '${route?['name'] ?? 'Bus'}', style: const TextStyle(fontWeight: FontWeight.w800)),
          if (parts.isNotEmpty) TextSpan(text: '  ·  ${parts.join(' · ')}', style: TextStyle(color: cs.onSurfaceVariant)),
        ]), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))),
        Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      ])),
    )));
  }
}

// ---------------------------------------------------------------- birthday
/// On the child's birthday: a crimson-and-gold card at the top of Home with a wish from the Principal and the school.
/// Gold confetti falls once a day when it is first seen, then it stays still. Nothing moves with "reduce motion".
class BirthdayHomeCard extends ConsumerStatefulWidget {
  const BirthdayHomeCard({super.key});
  @override
  ConsumerState<BirthdayHomeCard> createState() => _BirthdayHomeCardState();
}

class _BirthdayHomeCardState extends ConsumerState<BirthdayHomeCard> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4300));
  String? _checked;
  final _pieces = <List<double>>[];

  @override
  void dispose() { c.dispose(); super.dispose(); }

  Future<void> _maybePlay(String studentId) async {
    final now = DateTime.now();
    final key = 'rc_bday_card_${studentId}_${now.year}-${now.month}-${now.day}';
    if (_checked == key) return;
    _checked = key;
    if (reduceMotion(context)) return;
    final p = await SharedPreferences.getInstance();
    if (p.getBool(key) == true) return;
    await p.setBool(key, true);
    final r = math.Random();
    _pieces..clear()..addAll([for (var i = 0; i < 70; i++) [r.nextDouble(), -r.nextDouble(), 4 + r.nextDouble() * 7, .5 + r.nextDouble() * .5, r.nextDouble() * 6, (r.nextDouble() - .5) * .2, (r.nextDouble() * 5).floorToDouble()]]);
    if (mounted) c.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value;
    final st = s?.active;
    final settings = ref.watch(appSettingsProvider).value;
    if (st == null || !featureOn(settings, 'birthdays') || !isBirthday(ref.watch(profileProvider).value?['dob'] as String?)) return const SizedBox.shrink();
    if (s?.viewOnly != true) _maybePlay(st.id);
    final first = st.fullName.trim().split(RegExp(r'\s+')).first;
    final principal = (settings?['principal_name'] ?? '').trim().isEmpty ? 'Mrs. Rekha Vinod' : settings!['principal_name']!.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 14), clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: Brand.gold),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF8E0D13), Color(0xFF4A0508)]),
          boxShadow: [BoxShadow(color: Brand.crimsonDeep.withValues(alpha: .3), blurRadius: 22, offset: const Offset(0, 10))]),
      child: Stack(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('🎂', style: TextStyle(fontSize: 30)),
          const SizedBox(height: 2),
          Text('Happy Birthday, $first!', style: GoogleFonts.cinzel(fontSize: 19, fontWeight: FontWeight.w700, color: const Color(0xFFF6E3A1))),
          const SizedBox(height: 6),
          Text('Wishing you a wonderful year ahead, full of learning and joy.', style: TextStyle(fontSize: 13, height: 1.45, color: Colors.white.withValues(alpha: .92))),
          Text('— $principal and everyone at Royale Concorde', style: TextStyle(fontSize: 12.5, height: 1.45, fontStyle: FontStyle.italic, color: Colors.white.withValues(alpha: .85))),
        ])),
        Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: AnimatedBuilder(animation: c, builder: (_, __) =>
            c.isAnimating ? CustomPaint(painter: _GoldFall(_pieces, c.value)) : const SizedBox.shrink())))),
      ]),
    );
  }
}

/// Gold paper pieces falling through the card (like the approved mock): drift side to side and turn as they fall.
class _GoldFall extends CustomPainter {
  final List<List<double>> p; final double t;
  _GoldFall(this.p, this.t);
  static const _cols = [Color(0xFFF6E3A1), Color(0xFFE2BE6A), Colors.white, Color(0xFFC9A24A), Color(0xFFF3DA92)];
  @override
  void paint(Canvas canvas, Size s) {
    final frames = t * 260;   // the mock's 260 frames
    final paint = Paint();
    for (final q in p) {
      final y = q[1] * s.height + frames * (1 + q[3] * 1.5);
      if (y < -10 || y > s.height + 10) continue;
      final x = q[0] * s.width + math.sin(frames / 20 + q[4]) * 6;
      paint.color = _cols[q[6].toInt() % _cols.length].withValues(alpha: t > .85 ? (1 - t) / .15 : 1);
      canvas.save(); canvas.translate(x, y); canvas.rotate(q[4] + q[5] * frames);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: q[2], height: q[2] / 2), paint);
      canvas.restore();
    }
  }
  @override
  bool shouldRepaint(_GoldFall o) => o.t != t;
}
