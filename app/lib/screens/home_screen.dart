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
import 'desk_screen.dart' show DeskHomeCard;
import '../widgets/royal_extras.dart';
import '../widgets/hub_tabs.dart';
import 'attendance_screen.dart' show StreakCard, attendanceSummaryProvider;
import 'family_today.dart';
import 'my_list.dart' show MyListHomeSummary, myListProvider, diaryTabProvider;
import 'notice_extras.dart' show noticeExtrasProvider;
import 'thanks_screen.dart' show ThanksHomeBanner;
import 'year_review_screen.dart' show YearReviewHomeCard;
import '../widgets/r_refresh.dart';
import '../widgets/guided_tour.dart' show TourTarget;
import 'now_next.dart';

/// The family Home. One "Today · needs you" card holds everything that needs the family (fee to pay, homework for the
/// next school day, new notices); the rest is calm: festival banner, Principal's Desk, My list, the bus line, the tiles.
/// Phones: one column · tablets (600–959 px): two columns · laptops (960 px+): the side menu does the navigating.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    for (final p in <ProviderOrFamily>[calendarProvider, feesProvider, noticesProvider, noticeExtrasProvider, unreadMessagesProvider, myListProvider, latestDiaryProvider, homeworkForProvider, transportProvider, enrolmentProvider]) {
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

    // ---------------------------------------------------------------- laptop / large tablet
    if (width >= 960) {
      final notices = familyVisibleNotices(ref);
      final diary = ref.watch(latestDiaryProvider);
      Widget card(String title, String link, VoidCallback go, Widget child) => _CardShell(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))), TextButton(onPressed: go, child: Text(link))]),
        const SizedBox(height: 4), child]));
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
          const BirthdayHomeCard(),
          const FestiveBanner(),
          FadeRise(delayMs: 120, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TourTarget('f-needs', child: TodayNeedsCard()),
              NowNextLine(), ExamCountdownChip(),
              MyListHomeSummary(),
            ])),
            const SizedBox(width: 18),
            const Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              HomeBusLine(),
              TourTarget('f-streak', child: HomeStreak()),
              DeskHomeCard(),
            ])),
          ])),
          const ThanksHomeBanner(),
          const YearReviewHomeCard(),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: card('Latest notices', 'See all', () => context.go('/announcements'), Column(children: [
              for (final n in notices.take(4)) Padding(padding: const EdgeInsets.only(bottom: 8), child: _NoticeRow(n, () => context.push('/notice/${n.id}'))),
              if (ref.watch(noticesProvider).value != null && notices.isEmpty) Text('No notices yet.', style: TextStyle(color: cs.onSurfaceVariant)),
            ]))),
            const SizedBox(width: 18),
            Expanded(child: diary.when(loading: () => const _CardShell(child: SizedBox(height: 120, child: GoldLoading())), error: (e, _) => const SizedBox.shrink(), data: (d) => card(
              d.$1 == null ? 'Class diary' : 'Class diary · ${d.$1 == DateFormat('yyyy-MM-dd').format(now) ? 'today' : DateFormat('EEE d MMM').format(DateTime.parse(d.$1!))}', 'Open diary',
              () { ref.read(diaryTabProvider.notifier).state = 0; context.go('/diary'); },
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

    // ---------------------------------------------------------------- phone & tablet
    final tablet = width >= 600;
    final header = SliverToBoxAdapter(child: BrandHeader(padding: EdgeInsets.fromLTRB(tablet ? 28 : 20, 12, tablet ? 28 : 20, 20), hairline: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _TopRow(st: st, cls: cls, many: s.students.length > 1),
      const SizedBox(height: 18),
      Text(DateFormat('EEEE, d MMMM').format(now), style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 13)),
      Row(children: [Flexible(child: Text(greet, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.headlineMedium?.copyWith(color: Colors.white))), const SizedBox(width: 10), const TimeOfDayIcon(size: 30)]),
    ])));

    const top = [BirthdayHomeCard(), FestiveBanner()];
    final today = [
      const FadeRise(delayMs: 120, child: TourTarget('f-needs', child: TodayNeedsCard())),
      const NowNextLine(), const ExamCountdownChip(),
    ];
    const calm = [
      FadeRise(delayMs: 200, child: DeskHomeCard()),
      ThanksHomeBanner(),
      YearReviewHomeCard(),
    ];
    final tiles = FadeRise(delayMs: 260, child: _Tiles(settings: settings));
    final List<Widget> body;
    if (tablet) {
      body = [
        ...top,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ...today,
            const FadeRise(delayMs: 200, child: MyListHomeSummary()),
            const TourTarget('f-streak', child: HomeStreak()),
          ])),
          const SizedBox(width: 18),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const HomeBusLine(),
            tiles,
            const SizedBox(height: 14),
            ...calm,
          ])),
        ]),
      ];
    } else {
      body = [
        ...top,
        ...today,
        ...calm,
        const FadeRise(delayMs: 230, child: MyListHomeSummary()),
        const HomeBusLine(),
        const FadeRise(delayMs: 240, child: TourTarget('f-streak', child: HomeStreak())),
        tiles,
      ];
    }
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
      if (onBus) _Tile('Bus', Icons.directions_bus_outlined, Brand.blue, Brand.blueTint, () => context.go('/bus')),
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

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(18), margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(22)),
      child: child);
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
