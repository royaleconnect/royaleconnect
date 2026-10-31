import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/data2.dart';
import '../core/data3.dart';
import 'consent_screen.dart' show BirthdayCard;
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_motion.dart';
import 'desk_screen.dart' show DeskHomeCard;
import '../widgets/royal_extras.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value!;
    final st = s.active!;
    final fees = ref.watch(feesProvider);
    final notices = ref.watch(noticesProvider);
    final unread = ref.watch(unreadMessagesProvider).value ?? 0;
    final transport = ref.watch(transportProvider).value;
    final calendar = ref.watch(calendarProvider).value ?? const [];
    final enrol = ref.watch(enrolmentProvider).value;
    final gradeCode = enrol?['section']?['grade']?['code'] as String?;
    // the class as it is today (after a move-up the saved sign-in still has the old one)
    final cls = gradeCode == null ? st.cls : (shownSection(enrol?['section']) == null ? '$gradeCode · section to be announced' : '$gradeCode-${shownSection(enrol?['section'])}');
    final settings = ref.watch(appSettingsProvider).value;
    bool on(String k) => featureOn(settings, k);
    final birthday = isBirthday(ref.watch(profileProvider).value?['dob'] as String?);
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final greet = now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';
    final unreadNotices = notices.value?.where((n) => !n.read).length ?? 0;

    // Laptop / large tablet: the side menu (parent_layout.dart) does the navigating; Home shows four cards at once.
    if (MediaQuery.sizeOf(context).width >= 960) {
      final diary = ref.watch(latestDiaryProvider);
      Widget card(String title, String link, VoidCallback go, Widget child) => _CardShell(lift: false, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))), TextButton(onPressed: go, child: Text(link))]),
        const SizedBox(height: 4), child]));
      return Scaffold(body: FestiveSky(child: RefreshIndicator(
        onRefresh: () async { ref.invalidate(calendarProvider); ref.invalidate(feesProvider); ref.invalidate(noticesProvider); ref.invalidate(latestDiaryProvider); },
        child: ListView(padding: const EdgeInsets.fromLTRB(34, 28, 34, 40), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('EEEE, d MMMM').format(now), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              Row(children: [Text(greet, style: t.headlineMedium), const SizedBox(width: 10), const TimeOfDayIcon(size: 34)]),
            ])),
            Text('${st.fullName} · $cls', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 18),
          if (birthday) BirthdayCard(st.fullName),
          const FestiveBanner(),
          const FadeRise(delayMs: 150, child: DeskHomeCard()),
          ...?notices.value?.where((n) => n.urgent && !n.read).map((n) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Material(color: Brand.crimson, borderRadius: BorderRadius.circular(16),
              child: ListTile(onTap: () => context.push('/notice/${n.id}'), leading: const Icon(Icons.warning_amber_rounded, color: Colors.white), title: Text(n.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)), trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white))))),
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 5, child: _MorningCard(fees: fees.value, transport: transport, cls: cls, calendar: calendar, grade: gradeCode)),
            const SizedBox(width: 18),
            Expanded(flex: 4, child: fees.when(loading: () => const _CardShell(child: const GoldLoading()), error: (e, _) => _CardShell(child: Text('Could not load fees.', style: TextStyle(color: cs.onSurfaceVariant))), data: (f) => _FeeCard(f))),
          ])),
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: card('Latest announcements', 'See all', () => context.go('/announcements'), Column(children: [
              for (final n in (notices.value ?? []).take(4)) Padding(padding: const EdgeInsets.only(bottom: 8), child: _NoticeRow(n, () => context.push('/notice/${n.id}'))),
              if (notices.value?.isEmpty ?? false) Text('No announcements yet.', style: TextStyle(color: cs.onSurfaceVariant)),
            ]))),
            const SizedBox(width: 18),
            Expanded(child: diary.when(loading: () => const _CardShell(child: SizedBox(height: 120, child: const GoldLoading())), error: (e, _) => _CardShell(child: Text('$e')), data: (d) => card(
              d.$1 == null ? 'Class diary' : 'Class diary · ${d.$1 == DateFormat('yyyy-MM-dd').format(now) ? 'today' : DateFormat('EEE d MMM').format(DateTime.parse(d.$1!))}', 'Open diary', () => context.go('/diary'),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (d.$2.isEmpty) Text('Nothing posted recently.', style: TextStyle(color: cs.onSurfaceVariant)),
                for (final e in d.$2) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Pill(e.kind.replaceAll('_', ' '), fg: Brand.blue, bg: Brand.blueTint), const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text([if (e.subject != null) e.subject!, if (e.dueOn != null) 'by ${DateFormat('EEE d MMM').format(DateTime.parse(e.dueOn!))}'].join(' · '), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ])),
                ])),
              ])))),
          ]),
        ]))));
    }

    return Scaffold(
      body: FestiveSky(child: RefreshIndicator(
        onRefresh: () async { ref.invalidate(calendarProvider); ref.invalidate(feesProvider); ref.invalidate(noticesProvider); ref.invalidate(unreadMessagesProvider); },
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: BrandHeader(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), hairline: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              InkWell(onTap: () => context.push(s.students.length > 1 ? '/students' : '/profile'), borderRadius: BorderRadius.circular(999),
                  child: Container(padding: const EdgeInsets.fromLTRB(6, 6, 12, 6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Avatar(st.initials, bg: Colors.white, fg: Brand.crimsonDeep, size: 34), const SizedBox(width: 10),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(st.fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                          Text('${st.grade ?? ''} · ${st.sectionText}', style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 11)),
                        ]),
                        if (s.students.length > 1) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.expand_more_rounded, color: Colors.white, size: 18)),
                      ]))),
              const Spacer(),
              if (on('messages')) ...[_HeaderIcon(Icons.chat_bubble_outline_rounded, unread, () => context.push('/messages')), const SizedBox(width: 8)],
              _HeaderIcon(Icons.notifications_none_rounded, unreadNotices, () => context.go('/announcements')),
              const SizedBox(width: 8),
              _HeaderIcon(Icons.settings_outlined, 0, () => context.push('/settings')),
            ]),
            const SizedBox(height: 18),
            Text(DateFormat('EEEE, d MMMM').format(now), style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 13)),
            Row(children: [Text(greet, style: t.headlineMedium?.copyWith(color: Colors.white)), const SizedBox(width: 10), const TimeOfDayIcon(size: 30)]),
            const SizedBox(height: 16),
            // morning card — sits inside the header
            _MorningCard(fees: fees.value, transport: transport, cls: cls, calendar: calendar, grade: gradeCode),
          ]))),
          SliverPadding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), sliver: SliverList(delegate: SliverChildListDelegate([
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (birthday) BirthdayCard(st.fullName),
              const FestiveBanner(),
              const FadeRise(delayMs: 150, child: DeskHomeCard()),
              // urgent banner(s)
              ...?notices.value?.where((n) => n.urgent && !n.read).map((n) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Material(color: Brand.crimson, borderRadius: BorderRadius.circular(16),
                  child: InkWell(onTap: () => context.push('/notice/${n.id}'), borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                    const Avatar('!', bg: Colors.white, fg: Brand.crimson, size: 40), const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Eyebrow('Urgent', color: Brand.gold2), Text(n.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))])),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white),
                  ])))))),
              // fee card
              FadeRise(delayMs: 260, child: fees.when(
                loading: () => const _CardShell(child: SizedBox(height: 90, child: const GoldLoading())),
                error: (e, _) => _CardShell(child: Text('Could not load fees. Pull to refresh.', style: TextStyle(color: cs.onSurfaceVariant))),
                data: (f) => _FeeCard(f),
              )),
              const SizedBox(height: 18),
              // tiles
              FadeRise(delayMs: 380, child: GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .98, children: [
                _Tile('Timetable', Icons.grid_view_rounded, Brand.blue, Brand.blueTint, () => context.push('/timetable')),
                if (on('star')) _Tile('Star of the month', Icons.star_border_rounded, Brand.violet, Brand.violetTint, () => context.push('/star')),
                if (on('gallery')) _Tile('Gallery', Icons.image_outlined, Brand.green, Brand.greenTint, () => context.push('/gallery')),
                if (on('leave')) _Tile('Leave', Icons.event_available_outlined, Brand.crimsonDeep, Brand.crimsonTint, () => context.push('/leave')),
                if (on('plan')) _Tile('Monthly plan', Icons.format_list_bulleted_rounded, Brand.amber, Brand.amberTint, () => context.push('/plan')),
                if (on('worksheets')) _Tile('Worksheets', Icons.task_outlined, Brand.blue, Brand.blueTint, () => context.push('/worksheets')),
                _Tile('Exams', Icons.fact_check_outlined, Brand.crimsonDeep, Brand.crimsonTint, () => context.push('/exams')),
                _Tile('Calendar', Icons.calendar_month_outlined, Brand.green, Brand.greenTint, () => context.push('/calendar')),
                // Toppers takes the old Messages place (Messages stays one tap away in the top bar)
                if (on('council')) _Tile('Student Council', Icons.how_to_vote_outlined, Brand.violet, Brand.violetTint, () => context.push('/council')),
                if (on('toppers') || on('fame')) _Tile(on('toppers') ? 'Toppers' : 'Hall of Fame', Icons.emoji_events_outlined, Brand.amber, Brand.amberTint, () => context.push(on('toppers') ? '/toppers' : '/fame'))
                else if (on('messages')) _Tile('Messages', Icons.chat_bubble_outline_rounded, Brand.amber, Brand.amberTint, () => context.push('/messages'), badge: unread),
              ])),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("What's new", style: t.titleLarge?.copyWith(fontSize: 16)), TextButton(onPressed: () => context.go('/announcements'), child: const Text('See all'))]),
              ...?notices.value?.where((n) => !n.urgent).take(2).map((n) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _NoticeRow(n, () => context.push('/notice/${n.id}')))),
              if (notices.value?.isEmpty ?? false) const NoteBox('No announcements yet. New ones from the school appear here and you get a notification.'),
            ]),
          ]))),
        ]),
      )),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon; final int badge; final VoidCallback onTap;
  const _HeaderIcon(this.icon, this.badge, this.onTap);
  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        Material(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(12),
            child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white, size: 22)))),
        if (badge > 0) Positioned(top: 6, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 5), height: 18, constraints: const BoxConstraints(minWidth: 18), alignment: Alignment.center,
            decoration: BoxDecoration(color: Brand.gold, borderRadius: BorderRadius.circular(9)), child: Text('$badge', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Brand.ink)))),
      ]);
}

class _CardShell extends StatelessWidget {
  final Widget child; final bool lift;
  const _CardShell({required this.child, this.lift = true});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(22),
          boxShadow: lift ? [BoxShadow(color: Brand.crimsonDeep.withValues(alpha: .12), blurRadius: 30, offset: const Offset(0, 10))] : null),
      child: child);
}

String _hm(dynamic t) { final x = (t ?? '').toString(); return x.length >= 5 ? x.substring(0, 5) : x; }

class _MorningCard extends ConsumerWidget {
  final FeeSummary? fees; final Map<String, dynamic>? transport; final String cls;
  final List<Map<String, dynamic>> calendar; final String? grade;
  const _MorningCard({this.fees, this.transport, required this.cls, this.calendar = const [], this.grade});

  static String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  /// 'Onam Holiday' → 'Onam', 'Dussehra break (Holiday)' → 'Dussehra break'
  static String _clean(String t) => t.replaceAll(RegExp(r'\s*\(holiday\)|\s*[–-]\s*holiday\b|\s+holiday$', caseSensitive: false), '').trim();

  /// Calendar entries on [d] that are meant for this student's grade.
  List<Map<String, dynamic>> _on(DateTime d) {
    final x = _iso(d);
    return calendar.where((e) => (e['starts_on'] as String).compareTo(x) <= 0 && ((e['ends_on'] ?? e['starts_on']) as String).compareTo(x) >= 0 && eventIsFor(e, grade)).toList();
  }
  Map<String, dynamic>? _holiday(DateTime d) { for (final e in _on(d)) { if (e['kind'] == 'holiday') return e; } return null; }
  bool _schoolDay(DateTime d) => (d.weekday < 6 || isWorkingSaturday(d, grade)) && _holiday(d) == null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now(); final today = DateTime(now.year, now.month, now.day);
    final workingSat = isWorkingSaturday(today, grade);
    final weekend = now.weekday == 7 || (now.weekday == 6 && !workingSat); // no school by the week pattern
    final tomorrow = today.add(const Duration(days: 1));
    // the next day the student actually has school (skips Sundays, off Saturdays and holidays)
    var back = tomorrow;
    for (var i = 0; i < 30 && !_schoolDay(back); i++) { back = back.add(const Duration(days: 1)); }
    final gap = back.difference(today).inDays;
    final resume = gap == 1 ? 'tomorrow' : gap < 7 ? DateFormat('EEEE').format(back) : DateFormat('EEEE, d MMM').format(back);

    final hol = _holiday(today);
    final todays = _on(today).where((e) => e['kind'] != 'holiday').toList();
    final holTomorrow = hol == null && !weekend ? _holiday(tomorrow) : null;
    final keyTomorrow = hol == null ? _on(tomorrow).where((e) => e['kind'] == 'exam' || e['kind'] == 'ptm').toList() : const <Map<String, dynamic>>[];
    const holidayRed = Color(0xFFFF6B6B), examAmber = Color(0xFFF2B84B), ptmViolet = Color(0xFFB79CF0);
    String label(String k) => k == 'exam' ? 'Exam' : k == 'ptm' ? 'Parent–teacher meeting' : 'At school today';
    Color dot(String k) => k == 'exam' ? examAmber : k == 'ptm' ? ptmViolet : Brand.blue;

    final next = fees?.unpaid.isNotEmpty == true ? fees!.unpaid.first : null;
    // homework and projects due on the next school day
    final hw = ref.watch(homeworkDueProvider(_iso(back))).value ?? 0;
    final noSchool = hol != null || weekend;
    final items = <(String, String, Color)>[
      if (hol != null) ('Holiday · ${_clean(hol['title'])}', 'No school today · classes resume $resume', holidayRed)
      else if (weekend) ('No school today', 'Classes resume $resume', Brand.muted)
      else if (workingSat) ('Working Saturday', 'School is on today (${saturdayOrdinal(today)} Saturday)', Brand.blue)
      else ('School day', 'Check the timetable for what to carry', Brand.blue),
      for (final e in todays.take(3)) (e['title'] as String, label(e['kind']), dot(e['kind'])),
      if (hw > 0) ('$hw homework for ${gap == 1 ? 'tomorrow' : resume}', 'See what to do in the Diary', Brand.gold2),
      if (todays.length > 3) ('+${todays.length - 3} more today', 'See the calendar', Brand.muted),
      if (holTomorrow != null) ('Tomorrow: ${_clean(holTomorrow['title'])}', 'Holiday · no school tomorrow', holidayRed)
      else if (!noSchool && isWorkingSaturday(tomorrow, grade)) ('Tomorrow is a working Saturday', 'School is on (${saturdayOrdinal(tomorrow)} Saturday)', Brand.blue),
      for (final e in keyTomorrow.take(2)) ('Tomorrow: ${e['title']}', label(e['kind']), dot(e['kind'])),
      if (next != null) ('Fee: ${inr(next.amount)} ${next.overdue ? 'overdue' : 'due ${DateFormat('d MMM').format(DateTime.parse(next.dueOn))}'}', next.title, next.overdue ? holidayRed : Brand.green),
      if (transport != null && !noSchool) ('Bus · ${transport!['route']?['name'] ?? ''}', '${transport!['stop']?['name'] ?? ''} · drop ${_hm(transport!['route']?['afternoon_start'])}', Brand.blue),
    ];
    return Container(padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1D1A20), Color(0xFF2C2730)]),
            border: Border.all(color: Brand.gold.withValues(alpha: .55)), borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Eyebrow('Your day · ${DateFormat('EEEE').format(now)}', color: Brand.gold), Text(cls, style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 11))]),
          const SizedBox(height: 10),
          for (final (i, (a, b, c)) in items.indexed) FadeRise(delayMs: 350 + i * 140, dy: 14, child: Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: c, shape: BoxShape.circle)), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)), Text(b, style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 11))])),
          ]))),
        ]));
  }
}

class _FeeCard extends StatelessWidget {
  final FeeSummary f;
  const _FeeCard(this.f);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (f.unpaid.isEmpty) {
      return _CardShell(child: Row(children: [const Avatar('✓', bg: Brand.greenTint, fg: Brand.green), const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('All fees paid for this year', style: TextStyle(fontWeight: FontWeight.w800)), Text('${inr(f.total)} received · receipts under Fees', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))]))]));
    }
    final dark = Theme.of(context).brightness == Brightness.dark; // brighter red / amber so the label reads on the dark card
    final od = f.overdue; final odAmt = od.fold<num>(0, (a, r) => a + r.amount);
    final next = f.dueSoon.isNotEmpty ? f.dueSoon.first : (f.upcoming.isNotEmpty ? f.upcoming.first : null);
    final head = od.isNotEmpty ? od.firstWhere((r) => !r.isLate, orElse: () => od.first) : next!;
    return InkWell(onTap: () => context.go('/fees'), borderRadius: BorderRadius.circular(22), child: _CardShell(child: Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Eyebrow(od.isNotEmpty ? 'Overdue · since ${DateFormat('d MMM').format(DateTime.parse(head.dueOn))}' : 'Due ${DateFormat('d MMM').format(DateTime.parse(head.dueOn))} · ${head.daysUntil()} days left', color: od.isNotEmpty ? (dark ? const Color(0xFFFF6B6B) : Brand.crimsonDeep) : (dark ? const Color(0xFFF2B84B) : Brand.amber)),
          CountUpText(inr(od.isNotEmpty ? odAmt : head.amount), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.5)),
          Text(od.isNotEmpty && od.any((r) => r.isLate) ? '${head.title} incl. late fee' : head.title, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ])),
        Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 18), alignment: Alignment.center, decoration: BoxDecoration(gradient: Brand.buttonGradient, borderRadius: BorderRadius.circular(12)),
            child: const Text('Pay now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
      ]),
      const SizedBox(height: 14), Divider(height: 1, color: cs.outline), const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text(od.isNotEmpty && next != null ? 'Next: ${next.title.split(' — ').first} · ${inr(next.amount)} due ${DateFormat('d MMM').format(DateTime.parse(next.dueOn))}' : 'Balance for the year ${inr(f.balance)}', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
        Row(mainAxisSize: MainAxisSize.min, children: [Text('of year paid  ', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)), GoldRing(f.pct.toDouble(), size: 46)]),
      ]),
    ])));
  }
}

class _Tile extends StatelessWidget {
  final String label; final IconData icon; final Color fg, bg; final VoidCallback onTap; final int badge;
  const _Tile(this.label, this.icon, this.fg, this.bg, this.onTap, {this.badge = 0});
  @override
  Widget build(BuildContext context) => Material(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Stack(children: [
        Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: fg, size: 22)),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.15))),
        ])),
        if (badge > 0) Positioned(top: 10, right: 10, child: Container(height: 18, constraints: const BoxConstraints(minWidth: 18), alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(color: Brand.gold, borderRadius: BorderRadius.circular(9)), child: Text('$badge', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Brand.ink)))),
      ])));
}

class _NoticeRow extends StatelessWidget {
  final Notice n; final VoidCallback onTap;
  const _NoticeRow(this.n, this.onTap);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(color: cs.surface, borderRadius: BorderRadius.circular(16), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: n.read ? Colors.transparent : Brand.crimson, shape: BoxShape.circle)), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Eyebrow('${n.category.replaceAll('_', ' ')} · ${n.audience}', color: context.tone(Brand.crimsonDeep)),
        Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        Text('${n.by} · ${DateFormat('d MMM, h:mm a').format(DateTime.parse(n.when).toLocal())}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ])),
    ]))));
  }
}
