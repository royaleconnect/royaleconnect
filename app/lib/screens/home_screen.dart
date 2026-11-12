import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/data2.dart';
import '../core/data3.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_motion.dart';
import 'desk_screen.dart' show DeskHomeCard, deskMessagesProvider;
import '../widgets/royal_extras.dart';
import '../widgets/hub_tabs.dart';
import 'attendance_screen.dart' show StreakCard, attendanceSummaryProvider;
import 'family_today.dart';
import 'my_list.dart' show myListProvider, diaryTabProvider;
import 'notice_extras.dart' show noticeExtrasProvider;
import 'thanks_screen.dart' show ThanksHomeBanner;
import 'year_review_screen.dart' show YearReviewHomeCard;
import '../widgets/r_refresh.dart';
import '../widgets/guided_tour.dart' show TourTarget;

/// The family Home (approved mock, Nov 2026), the same on every screen size:
///   festival wish → one "Your day" card (school day / holiday, Needs you, My list) → two equal cards side by side:
///   Latest notices (with the Principal's Desk strip at the bottom) and Latest diary.
/// Phones and tablets also get the tiles (Calendar, Attendance… are not in the bottom tabs). Laptops (960 px+) use the side menu.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    for (final p in <ProviderOrFamily>[calendarProvider, feesProvider, noticesProvider, noticeExtrasProvider, unreadMessagesProvider, myListProvider, latestDiaryProvider, homeworkForProvider, transportProvider, enrolmentProvider, deskMessagesProvider]) {
      ref.invalidate(p);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value!;
    final st = s.active!;
    final settings = ref.watch(appSettingsProvider).value;
    final cls = classNow(ref, st);
    final width = MediaQuery.sizeOf(context).width;
    final now = DateTime.now();
    final greet = now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final laptop = width >= 960;

    final body = <Widget>[
      const BirthdayHomeCard(),
      const FestiveBanner(),
      const FadeRise(delayMs: 120, child: TourTarget('f-needs', child: YourDayCard())),
      const FadeRise(delayMs: 200, child: _NoticesAndDiary()),
      if (!laptop) FadeRise(delayMs: 260, child: Padding(padding: const EdgeInsets.only(bottom: 14), child: _Tiles(settings: settings))),
      const TourTarget('f-streak', child: HomeStreak()),
      const ThanksHomeBanner(),
      const YearReviewHomeCard(),
    ];

    // ---------------------------------------------------------------- laptop / large tablet
    if (laptop) {
      return Scaffold(body: FestiveSky(child: RRefresh(
        onRefresh: () => _refresh(ref),
        child: ListView(padding: const EdgeInsets.fromLTRB(34, 28, 34, 40), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('EEEE, d MMMM').format(now), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              Row(children: [Flexible(child: Text(greet, style: t.headlineMedium)), const SizedBox(width: 10), const TimeOfDayIcon(size: 34)]),
            ])),
            Flexible(child: Text('${st.fullName} · $cls', textAlign: TextAlign.right, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 18),
          ...body,
        ]))));
    }

    // ---------------------------------------------------------------- phone & tablet
    final tablet = width >= 600;
    final header = SliverToBoxAdapter(child: BrandHeader(padding: EdgeInsets.fromLTRB(tablet ? 28 : 20, 12, tablet ? 28 : 20, 20), hairline: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _TopRow(st: st, cls: cls, many: s.students.length > 1),
      const SizedBox(height: 18),
      Text(DateFormat('EEEE, d MMMM').format(now), style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 13)),
      Row(children: [Flexible(child: Text(greet, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.headlineMedium?.copyWith(color: Colors.white))), const SizedBox(width: 10), const TimeOfDayIcon(size: 30)]),
    ])));
    return Scaffold(
      body: FestiveSky(child: RRefresh(
        onRefresh: () => _refresh(ref),
        child: CustomScrollView(slivers: [
          header,
          SliverPadding(padding: EdgeInsets.fromLTRB(tablet ? 28 : 16, 16, tablet ? 28 : 16, 90), sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body))),
        ]),
      )),
    );
  }
}

/// Two equal cards under "Your day": Latest notices (the Principal's Desk strip at the bottom) and Latest diary.
/// Side by side when there is room (together the width of the festival wish), one under the other on phones.
class _NoticesAndDiary extends ConsumerWidget {
  const _NoticesAndDiary();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final notices = familyVisibleNotices(ref);
    final loaded = ref.watch(noticesProvider).value != null;
    final noticesCard = _Panel(title: 'Latest notices', onSeeAll: () => context.go('/announcements'), children: [
      for (final n in notices.take(3)) Padding(padding: const EdgeInsets.only(bottom: 8), child: _NoticeRow(n, () => context.push('/notice/${n.id}'))),
      if (loaded && notices.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('No notices yet.', style: TextStyle(color: cs.onSurfaceVariant))),
      const DeskHomeCard(compact: true),
    ]);
    final diaryCard = _Panel(title: 'Latest diary', onSeeAll: () { ref.read(diaryTabProvider.notifier).state = 0; context.go('/diary'); }, children: const [_DiaryList()]);
    return LayoutBuilder(builder: (_, c) => c.maxWidth >= 700
        ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: noticesCard), const SizedBox(width: 16), Expanded(child: diaryCard)]))
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [noticesCard, diaryCard]));
  }
}

class _Panel extends StatelessWidget {
  final String title; final VoidCallback onSeeAll; final List<Widget> children;
  const _Panel({required this.title, required this.onSeeAll, required this.children});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(padding: const EdgeInsets.fromLTRB(16, 8, 12, 14), margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: dark ? const Color(0xFF3A3028) : const Color(0xFFEEE6D8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          TextButton(onPressed: onSeeAll, child: const Text('See all')),
        ]),
        const SizedBox(height: 2),
        ...children,
      ]));
  }
}

/// Today's diary for the class. Nothing today: "Nothing in the diary today." and, below it, the last day that had entries.
class _DiaryList extends ConsumerWidget {
  const _DiaryList();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final d = ref.watch(latestDiaryProvider).value;
    final todayIso = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isToday = d?.$1 == todayIso;
    final list = d?.$2 ?? const <DiaryEntry>[];
    Widget entry(DiaryEntry e) {
      final note = e.kind != 'homework' && e.kind != 'project';
      final chip = e.subject ?? (note ? 'Note' : e.kind.replaceAll('_', ' '));
      final when = e.dueOn == null ? null : 'for ${dayWord(DateTime.parse(e.dueOn!))}';
      return Padding(padding: const EdgeInsets.only(bottom: 8), child: Material(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(14),
        child: InkWell(borderRadius: BorderRadius.circular(14), onTap: () { ref.read(diaryTabProvider.notifier).state = 0; context.go('/diary'); },
          child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Pill(chip, fg: note ? Brand.green : Brand.blue, bg: note ? Brand.greenTint : Brand.blueTint), const SizedBox(width: 8),
              Expanded(child: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
            ]),
            const SizedBox(height: 3),
            Text([if (e.by.isNotEmpty) e.by, if (when != null) when].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ])))));
    }
    if (isToday) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final e in list.take(3)) entry(e)]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Column(children: [
        Icon(Icons.menu_book_outlined, size: 30, color: Brand.gold.withValues(alpha: .9)),
        const SizedBox(height: 6),
        const Text('Nothing in the diary today.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
        Text('New homework and notes from teachers will show here.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ])),
      if (d?.$1 != null && list.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('LAST DIARY · ${DateFormat('EEE d MMM').format(DateTime.parse(d!.$1!)).toUpperCase()}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: cs.onSurfaceVariant))),
        for (final e in list.take(2)) entry(e),
      ],
    ]);
  }
}

/// The child chip (tap: profile, or switch child) and the three round buttons: messages (with the unread count),
/// notices (with the unread count, same list as the Notices page) and settings.
class _TopRow extends ConsumerWidget {
  final StudentRef st; final String cls; final bool many;
  const _TopRow({required this.st, required this.cls, required this.many});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final msgsOn = featureOn(ref.watch(appSettingsProvider).value, 'messages');
    final unreadMsgs = msgsOn ? (ref.watch(unreadMessagesProvider).value ?? 0) : 0;
    final unreadNotices = unreadFamilyNotices(ref);
    return Row(children: [
      Flexible(child: TourTarget('f-child', child: InkWell(onTap: () => context.push(many ? '/students' : '/profile'), borderRadius: BorderRadius.circular(999),
          child: Container(padding: const EdgeInsets.fromLTRB(6, 6, 12, 6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Avatar(st.initials, bg: Colors.white, fg: Brand.crimsonDeep, size: 34), const SizedBox(width: 10),
                Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(st.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                  Text(cls, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 11.5, fontWeight: FontWeight.w600)),
                ])),
                if (many) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.expand_more_rounded, color: Colors.white, size: 18)),
              ]))))),
      const SizedBox(width: 8),
      if (msgsOn) ...[_HeaderIcon(Icons.chat_bubble_outline_rounded, unreadMsgs, () => context.push('/messages'), tip: 'Messages'), const SizedBox(width: 6)],
      _HeaderIcon(Icons.notifications_none_rounded, unreadNotices, () => context.go('/announcements'), tip: 'Notices'),
      const SizedBox(width: 6),
      _HeaderIcon(Icons.settings_outlined, 0, () => context.push('/settings'), tip: 'Settings'),
    ]);
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon; final int badge; final VoidCallback onTap; final String tip;
  const _HeaderIcon(this.icon, this.badge, this.onTap, {required this.tip});
  @override
  Widget build(BuildContext context) => Tooltip(message: tip, child: Stack(clipBehavior: Clip.none, children: [
        Material(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(12),
            child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: SizedBox(width: 42, height: 42, child: Icon(icon, color: Colors.white, size: 22)))),
        if (badge > 0) Positioned(top: -3, right: -3, child: Container(padding: const EdgeInsets.symmetric(horizontal: 5), height: 18, constraints: const BoxConstraints(minWidth: 18), alignment: Alignment.center,
            decoration: BoxDecoration(color: Brand.gold, borderRadius: BorderRadius.circular(9)),
            child: MediaQuery.withNoTextScaling(child: Text(badge > 99 ? '99+' : '$badge', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Brand.ink))))),
      ]));
}

/// The tiles: the main places, one tap each (4 across like the approved mock; 3 across when that fills the rows better).
/// Each tile's height grows with the phone's text size, so large text never spills out.
class _Tiles extends ConsumerWidget {
  final Map<String, String>? settings;
  const _Tiles({required this.settings});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool on(String k) => featureOn(settings, k);
    final onBus = ref.watch(transportProvider).value != null && on('bus');
    final unreadNotices = unreadFamilyNotices(ref);
    final list = <Widget>[
      TourTarget('f-diary', child: _Tile('Diary', Icons.menu_book_outlined, Brand.blue, Brand.blueTint, () { ref.read(diaryTabProvider.notifier).state = 0; context.go('/diary'); })),
      TourTarget('f-notices', child: _Tile('Notices', Icons.campaign_outlined, Brand.crimsonDeep, Brand.crimsonTint, () => context.go('/announcements'), badge: unreadNotices)),
      TourTarget('f-fees', child: _Tile('Fees', Icons.account_balance_wallet_outlined, Brand.green, Brand.greenTint, () => context.go('/fees'))),
      if (onBus) _Tile('Transport', Icons.directions_bus_outlined, Brand.blue, Brand.blueTint, () => context.go('/bus')),
      _Tile('Calendar', Icons.calendar_month_outlined, Brand.green, Brand.greenTint, () => context.push('/calendar')),
      _Tile('Attendance', Icons.event_available_outlined, Brand.violet, Brand.violetTint, () => context.push('/attendance')),
      _Tile('Reports', Icons.school_outlined, Brand.crimsonDeep, Brand.crimsonTint, () => context.go('/reports')),
      if (const ['star', 'toppers', 'fame', 'council', 'houses'].any(on)) _Tile('Honours', Icons.emoji_events_outlined, Brand.amber, Brand.amberTint, () => context.push(hubStart(Hub.honours, settings))),
      if (on('gallery')) _Tile('Gallery', Icons.image_outlined, Brand.blue, Brand.blueTint, () => context.push('/gallery')),
    ];
    final cols = list.length % 4 == 0 ? 4 : list.length % 3 == 0 ? 3 : 4;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return GridView(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: 70 + 18 * scale.clamp(1.0, 2.2)),
      children: list,
    );
  }
}

class _Tile extends StatelessWidget {
  final String label; final IconData icon; final Color fg, bg; final VoidCallback onTap; final int badge;
  const _Tile(this.label, this.icon, this.fg, this.bg, this.onTap, {this.badge = 0});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Stack(children: [
        Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: dark ? fg.withValues(alpha: .22) : bg, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: context.tone(fg), size: 21)),
          const SizedBox(height: 7),
          FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.15))),
        ]))),
        if (badge > 0) Positioned(top: 6, right: 6, child: Container(height: 18, constraints: const BoxConstraints(minWidth: 18), alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(color: Brand.gold, borderRadius: BorderRadius.circular(9)),
            child: MediaQuery.withNoTextScaling(child: Text(badge > 99 ? '99+' : '$badge', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Brand.ink))))),
      ])));
  }
}

class _NoticeRow extends StatelessWidget {
  final Notice n; final VoidCallback onTap;
  const _NoticeRow(this.n, this.onTap);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(14), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: Padding(padding: const EdgeInsets.all(12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: n.read ? Colors.transparent : Brand.crimson, shape: BoxShape.circle)), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        Text('${n.by} · ${DateFormat('d MMM, h:mm a').format(DateTime.parse(n.when).toLocal())}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ])),
    ]))));
  }
}

/// The attendance streak on Home (only once the class teacher marks attendance in the app).
/// Reaching 30 or 60 days shows a short gold celebration once.
class HomeStreak extends ConsumerWidget {
  const HomeStreak({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(attendanceSummaryProvider(DateFormat('yyyy-MM-01').format(DateTime.now()))).value;
    if (d == null || (d['year_days'] ?? 0) == 0) return const SizedBox.shrink();
    final streak = (d['streak'] ?? 0) as int;
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: InkWell(borderRadius: BorderRadius.circular(20), onTap: () => context.push('/attendance'),
      child: Stack(clipBehavior: Clip.none, children: [
        StreakCard(streak: streak, best: (d['best'] ?? 0) as int, compact: true),
        if (streak == 30 || streak == 60) const Positioned.fill(child: IgnorePointer(child: ConfettiBurst(count: 70, origin: Alignment(-.6, -.2)))),
      ])));
  }
}
