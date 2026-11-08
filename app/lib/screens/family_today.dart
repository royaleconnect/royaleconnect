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
import 'my_list.dart' show diaryTabProvider, myListProvider, MyListHomeColumn;
import 'now_next.dart' show nowNextText;
import 'notice_extras.dart';

/// The family Home's building blocks: the one "Your day" card, the birthday card,
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

// ---------------------------------------------------------------- YOUR DAY
bool _holidayOn(List<Map<String, dynamic>> calendar, String? grade, DateTime d) => _holidayEvent(calendar, grade, d) != null;
Map<String, dynamic>? _holidayEvent(List<Map<String, dynamic>> calendar, String? grade, DateTime d) {
  final x = _iso(d);
  for (final e in calendar) {
    if (e['kind'] == 'holiday' && (e['starts_on'] as String).compareTo(x) <= 0 && ((e['ends_on'] ?? e['starts_on']) as String).compareTo(x) >= 0 && eventIsFor(e, grade)) return e;
  }
  return null;
}
bool _schoolOn(List<Map<String, dynamic>> calendar, String? grade, DateTime d) =>
    (d.weekday < 6 || (d.weekday == 6 && isWorkingSaturday(d, grade))) && !_holidayOn(calendar, grade, d);
/// Calendar events (not holidays) on [d] for this grade — "Parent–teacher meeting".
List<String> _eventsOn(List<Map<String, dynamic>> calendar, String? grade, DateTime d) {
  final x = _iso(d);
  return [for (final e in calendar) if (e['kind'] != 'holiday' && (e['starts_on'] as String).compareTo(x) <= 0 && ((e['ends_on'] ?? e['starts_on']) as String).compareTo(x) >= 0 && eventIsFor(e, grade)) '${e['title']}'];
}
String _hm12(dynamic t) {
  final x = (t ?? '').toString();
  if (x.length < 5) return x;
  final d = DateTime.tryParse('2000-01-01 ${x.substring(0, 5)}');
  return d == null ? x.substring(0, 5) : DateFormat('h:mm a').format(d).toLowerCase();
}

/// The one "Your day" card at the top of the family Home, the same width as the festival wish:
///  * the head: School day / Holiday, the date, and one quiet line (bus pickup, today's event, now/next class, an exam soon);
///  * Needs you: the fee to pay (with Pay), homework for the next school day, new notices — or "All done for today ✨";
///  * My list: the first four items, tickable here (hidden when the list is empty).
/// Two columns when the card is wide enough; one under the other on phones.
class YourDayCard extends ConsumerStatefulWidget {
  const YourDayCard({super.key});
  @override
  ConsumerState<YourDayCard> createState() => _YourDayCardState();
}

class _YourDayCardState extends ConsumerState<YourDayCard> {
  Timer? _t;
  @override
  void initState() { super.initState(); _t = Timer.periodic(const Duration(seconds: 60), (_) { if (mounted) setState(() {}); }); }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final settings = ref.watch(appSettingsProvider).value;
    final grade = ref.watch(enrolmentProvider).value?['section']?['grade']?['code'] as String?;
    final calendar = ref.watch(calendarProvider).value ?? const <Map<String, dynamic>>[];
    final now = DateTime.now(), today = DateTime(now.year, now.month, now.day);
    final next = nextSchoolDay(calendar, grade);
    final schoolToday = _schoolOn(calendar, grade, today);
    final bus = featureOn(settings, 'bus') ? ref.watch(transportProvider).value : null;
    final stop = bus?['stop'] as Map?, route = bus?['route'] as Map?;

    // ---- the head
    final String badge; final bool holiday; final String title; final parts = <String>[];
    String busBit(bool morning) {
      final eta = stop?[morning ? 'morning_eta' : 'afternoon_eta'];
      if (route == null || eta == null) return '';
      return '${route['name'] ?? 'Bus'} · ${morning ? 'pickup' : 'drop'} ${_hm12(eta)}';
    }
    if (schoolToday) {
      badge = 'School day'; holiday = false;
      title = DateFormat('EEEE, d MMMM').format(now);
      if (now.hour < 15) {
        final b = busBit(now.hour < 10);
        if (b.isNotEmpty) parts.add(b);
        parts.addAll(_eventsOn(calendar, grade, today));
        if (featureOn(settings, 'timetable')) {
          final slots = ref.watch(timetableProvider).value;
          final nn = slots == null || slots.isEmpty ? null : nowNextText(slots, now, grade: grade, calendar: calendar);
          if (nn != null) parts.add(nn.toPlainText());
        }
      } else {
        parts.add('School is over for today · next school day ${dayWord(next)}');
        parts.addAll(_eventsOn(calendar, grade, next).map((e) => '$e ${dayWord(next)}'));
      }
    } else {
      final h = _holidayEvent(calendar, grade, today);
      holiday = true;
      badge = h != null ? 'Holiday' : now.weekday == DateTime.sunday ? 'Sunday' : 'Holiday';
      final name = h != null ? '${h['title']}' : now.weekday == DateTime.sunday ? 'No school today' : 'Saturday off';
      final back = dayWord(next) == 'tomorrow' ? 'school tomorrow' : 'school reopens ${dayWord(next)}';
      title = '$name · $back';
      parts.add(DateFormat('EEEE, d MMMM').format(now));
      parts.addAll(_eventsOn(calendar, grade, next).map((e) => '$e ${dayWord(next)}'));
    }
    // an exam starting within the next 14 days
    final exams = ref.watch(examsProvider).value ?? const [];
    int days = 99; String? exam;
    for (final e in exams) {
      final d = DateTime.tryParse('${e['starts_on']}');
      if (d == null) continue;
      final n = DateTime(d.year, d.month, d.day).difference(today).inDays;
      if (n >= 0 && n <= 14 && n < days) { days = n; exam = '${e['name']}'; }
    }
    if (exam != null) parts.add('$exam ${days == 0 ? 'starts today' : days == 1 ? 'starts tomorrow' : 'in $days days'}');

    final gold = dark ? Brand.gold2 : const Color(0xFFA8822F);
    final line = dark ? const Color(0xFF3A2E1E) : const Color(0xFFEDE4D3);
    final head = Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(margin: const EdgeInsets.only(top: 1), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(99),
              color: holiday ? (dark ? const Color(0xFF3A2E14) : Brand.amberTint) : (dark ? const Color(0xFF16321F) : Brand.greenTint)),
          child: Text(badge, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: context.tone(holiday ? Brand.amber : Brand.green)))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, height: 1.3)),
        if (parts.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(parts.join(' · '), maxLines: 3, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, height: 1.4, color: cs.onSurfaceVariant))),
      ])),
    ]));

    // ---- needs you
    final rows = _needsRows(context, ref, next, dark);
    final needs = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text('NEEDS YOU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: gold))),
      if (rows.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(0, 4, 0, 8), child: Row(children: [
        Icon(Icons.check_circle_rounded, color: context.tone(Brand.green), size: 22), const SizedBox(width: 10),
        Expanded(child: Text('All done for today ✨', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: cs.onSurface))),
      ])),
      for (final (i, r) in rows.indexed) Container(
          decoration: BoxDecoration(border: i == rows.length - 1 ? null : Border(bottom: BorderSide(color: line))), child: r),
    ]);
    final hasList = (ref.watch(myListProvider).value ?? const []).isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: dark ? const [Color(0xFF241D18), Color(0xFF1F1915)] : const [Colors.white, Color(0xFFFFF8EC)]),
          border: Border.all(color: dark ? const Color(0xFF4A3A22) : const Color(0xFFEADFC8)),
          boxShadow: [BoxShadow(color: Brand.crimsonDeep.withValues(alpha: dark ? .25 : .10), blurRadius: 24, offset: const Offset(0, 10))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        Container(height: 1, color: line),
        LayoutBuilder(builder: (_, c) {
          const pad = EdgeInsets.fromLTRB(16, 8, 14, 10);
          if (!hasList) return Padding(padding: pad, child: needs);
          if (c.maxWidth >= 640) {
            return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 5, child: Padding(padding: pad, child: needs)),
              Container(width: 1, color: line),
              const Expanded(flex: 4, child: Padding(padding: EdgeInsets.fromLTRB(16, 8, 14, 10), child: MyListHomeColumn())),
            ]));
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: pad, child: needs),
            Container(height: 1, color: line),
            const Padding(padding: EdgeInsets.fromLTRB(16, 8, 14, 10), child: MyListHomeColumn()),
          ]);
        }),
      ]),
    );
  }
}

/// The rows of "Needs you": the fee to pay (with a Pay button), homework for the next school day, new notices.
List<Widget> _needsRows(BuildContext context, WidgetRef ref, DateTime next, bool dark) {
  final fees = ref.watch(feesProvider).value;
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
  return rows;
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
