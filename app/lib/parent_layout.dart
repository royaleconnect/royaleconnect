import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth/session.dart';
import 'core/config.dart';
import 'core/data.dart';
import 'core/theme.dart';
import 'router.dart';
import 'widgets/common.dart';

/// Parents and students on a laptop or large tablet: the school menu sits on the left (like the staff panel)
/// and the page fills the rest of the screen. Phones keep the tiles and bottom tabs.
class ParentFrame extends ConsumerWidget {
  final Widget child;
  const ParentFrame({super.key, required this.child});

  static const _groups = <(String, List<(String, String, IconData)>)>[
    ('DAILY', [('/', 'Home', Icons.home_rounded), ('/diary', 'Class diary', Icons.menu_book_rounded), ('/announcements', 'Announcements', Icons.campaign_rounded), ('/messages', 'Messages', Icons.chat_bubble_rounded)]),
    ('STUDIES', [('/calendar', 'Calendar', Icons.calendar_month_rounded), ('/timetable', 'Timetable', Icons.grid_view_rounded), ('/exams', 'Exams & portions', Icons.fact_check_rounded), ('/plan', 'Monthly plan', Icons.format_list_bulleted_rounded), ('/worksheets', 'Worksheets', Icons.task_rounded), ('/reports', 'Report cards', Icons.school_rounded)]),
    ('SCHOOL', [('/fees', 'Fees & receipts', Icons.account_balance_wallet_rounded), ('/bus', 'Bus', Icons.directions_bus_rounded), ('/gallery', 'Moments & albums', Icons.photo_library_rounded), ('/star', 'Star of the month', Icons.star_rounded), ('/leave', 'Leave', Icons.event_available_rounded), ('/feedback', 'Feedback', Icons.rate_review_rounded), ('/help', 'Help', Icons.help_outline_rounded)]),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final s = ref.watch(sessionProvider).value;
    final st = s?.active;
    final onBus = ref.watch(transportProvider).value != null;
    final unreadMsgs = ref.watch(unreadMessagesProvider).value ?? 0;
    final unreadNotices = ref.watch(noticesProvider).value?.where((n) => !n.read).length ?? 0;
    return AnimatedBuilder(animation: router.routerDelegate, builder: (context, _) {
      final loc = router.routerDelegate.currentConfiguration.uri.path;
      bool on(String p) => p == '/' ? loc == '/' : (loc == p || loc.startsWith('$p/') || (p == '/announcements' && loc.startsWith('/notice')) || (p == '/messages' && loc.startsWith('/chat')) || (p == '/fees' && (loc.startsWith('/pay') || loc.startsWith('/receipt'))));
      int badge(String p) => p == '/messages' ? unreadMsgs : p == '/announcements' ? unreadNotices : 0;
      return Row(children: [
        Material(child: Container(width: 256, decoration: const BoxDecoration(gradient: Brand.headerGradient), child: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 10), child: Row(children: [
            Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: Image.asset('assets/images/monogram.png', width: 26)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Royale Connect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              Text('Parent portal · ${AppConfig.academicYearLabel}', style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 11)),
            ])),
          ])),
          Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 18), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Brand.gold, Colors.transparent]))),
          if (st != null) Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: Material(color: Colors.white.withValues(alpha: .13), borderRadius: BorderRadius.circular(14), child: InkWell(
            borderRadius: BorderRadius.circular(14), onTap: () => router.go((s?.students.length ?? 0) > 1 ? '/students' : '/profile'),
            child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
              Avatar(st.initials, bg: Colors.white, fg: Brand.crimsonDeep, size: 36), const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
                Text((s?.students.length ?? 0) > 1 ? '${st.cls} · switch child' : '${st.cls} · profile', style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 11.5)),
              ])),
              if ((s?.students.length ?? 0) > 1) const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 18),
            ]))))),
          Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(10, 4, 10, 8), children: [
            for (final (g, items) in _groups) ...[
              Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 4), child: Text(g, style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 10.5, letterSpacing: 1.6, fontWeight: FontWeight.w800))),
              for (final (p, l, i) in items) if (p != '/bus' || onBus) _Nav(l, i, selected: on(p), badge: badge(p), onTap: () => router.go(p)),
            ],
          ])),
          Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 18), color: Colors.white.withValues(alpha: .15)),
          Padding(padding: const EdgeInsets.fromLTRB(10, 6, 10, 10), child: Column(children: [
            _Nav('Settings', Icons.settings_outlined, selected: loc == '/settings', onTap: () => router.go('/settings')),
            _Nav('Sign out', Icons.logout_rounded, onTap: () async { await ref.read(sessionProvider.notifier).signOut(); router.go('/login'); }),
          ])),
        ])))),
        Expanded(child: child),
      ]);
    });
  }
}

class _Nav extends StatelessWidget {
  final String label; final IconData icon; final bool selected; final int badge; final VoidCallback onTap;
  const _Nav(this.label, this.icon, {this.selected = false, this.badge = 0, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Material(color: selected ? Colors.white.withValues(alpha: .17) : Colors.transparent, borderRadius: BorderRadius.circular(11),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(11), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), child: Row(children: [
        Icon(icon, size: 19, color: selected ? Brand.gold2 : Colors.white.withValues(alpha: .85)), const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(color: Colors.white, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, fontSize: 13.5))),
        if (badge > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Brand.gold, borderRadius: BorderRadius.circular(999)), child: Text('$badge', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Brand.ink))),
      ])))));
}
