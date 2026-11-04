import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth/session.dart';
import 'core/config.dart';
import 'core/data.dart';
import 'core/data3.dart';
import 'core/theme.dart';
import 'router.dart';
import 'widgets/common.dart';
import 'widgets/guided_tour.dart' show TourTarget;
import 'widgets/hub_tabs.dart';

/// Parents and students on a laptop or large tablet: the school menu sits on the left (like the staff panel)
/// and the page fills the rest of the screen. Phones keep the tiles and bottom tabs.
class ParentFrame extends ConsumerWidget {
  final Widget child;
  const ParentFrame({super.key, required this.child});

  // 12 items (11 without the bus). Pages that belong together open with tabs at the top:
  // Calendar · Timetable · Exams — Attendance · Leave — Star · Toppers · Hall of Fame · Council · Houses.
  static const _groups = <(String, List<(String, String, IconData)>)>[
    ('DAILY', [('/', 'Home', Icons.home_rounded), ('/diary', 'Diary', Icons.menu_book_rounded), ('/announcements', 'Notices', Icons.campaign_rounded), ('/messages', 'Messages', Icons.chat_bubble_rounded)]),
    ('SCHOOL', [('/calendar', 'Calendar', Icons.calendar_month_rounded), ('/attendance', 'Attendance & leave', Icons.event_available_rounded), ('/reports', 'Reports', Icons.school_rounded),
                ('/fees', 'Fees & receipts', Icons.account_balance_wallet_rounded), ('/bus', 'Bus', Icons.directions_bus_rounded), ('/gallery', 'Gallery', Icons.photo_library_rounded), ('honours', 'Honours', Icons.emoji_events_rounded)]),
    ('ME', [('/profile', 'Profile', Icons.person_rounded)]),
  ];
  static const _hubOf = {'/timetable': '/calendar', '/exams': '/calendar', '/leave': '/attendance', '/star': 'honours', '/toppers': 'honours', '/fame': 'honours', '/council': 'honours', '/houses': 'honours',
    '/help': '/profile', '/feedback': '/profile', '/students': '/profile', '/idcard': '/profile', '/desk': '/'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final s = ref.watch(sessionProvider).value;
    final st = s?.active;
    final onBus = ref.watch(transportProvider).value != null;
    final unreadMsgs = ref.watch(unreadMessagesProvider).value ?? 0;
    final unreadNotices = ref.watch(noticesProvider).value?.where((n) => !n.read).length ?? 0;
    final settings = ref.watch(appSettingsProvider).value;
    // pages IT has switched off are not shown
    const switches = {'/messages': 'messages', '/bus': 'bus', '/gallery': 'gallery'};
    bool allowed(String p) => p == 'honours' ? const ['star', 'toppers', 'fame', 'council', 'houses'].any((k) => featureOn(settings, k)) : (switches[p] == null || featureOn(settings, switches[p]!));
    return AnimatedBuilder(animation: router.routerDelegate, builder: (context, _) {
      final loc = router.routerDelegate.currentConfiguration.uri.path;
      final top = '/${loc.split('/').where((x) => x.isNotEmpty).firstOrNull ?? ''}';
      final hub = _hubOf[top];
      bool on(String p) => hub != null ? hub == p : p == '/' ? loc == '/' : (loc == p || loc.startsWith('$p/') || (p == '/announcements' && loc.startsWith('/notice')) || (p == '/messages' && loc.startsWith('/chat')) || (p == '/fees' && (loc.startsWith('/pay') || loc.startsWith('/receipt'))));
      int badge(String p) => p == '/messages' ? unreadMsgs : p == '/announcements' ? unreadNotices : 0;
      return Row(children: [
        Material(child: Container(width: 256, decoration: const BoxDecoration(gradient: Brand.headerGradient), child: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 10), child: Row(children: [
            Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: Image.asset('assets/images/monogram.png', width: 26)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Royale Connect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              Text('Parent portal · ${ref.watch(yearLabelProvider).value ?? AppConfig.academicYearLabel}', style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 11)),
            ])),
          ])),
          Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 18), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Brand.gold, Colors.transparent]))),
          if (st != null) Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: TourTarget('f-child', child: Material(color: Colors.white.withValues(alpha: .13), borderRadius: BorderRadius.circular(14), child: InkWell(
            borderRadius: BorderRadius.circular(14), onTap: () => router.go((s?.students.length ?? 0) > 1 ? '/students' : '/profile'),
            child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
              Avatar(st.initials, bg: Colors.white, fg: Brand.crimsonDeep, size: 36), const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5)),
                Text((s?.students.length ?? 0) > 1 ? '${st.cls} · switch child' : '${st.cls} · profile', style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 11.5)),
              ])),
              if ((s?.students.length ?? 0) > 1) const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 18),
            ])))))),
          Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(10, 4, 10, 8), children: [
            for (final (g, items) in _groups) ...[
              Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 4), child: Text(g, style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 10.5, letterSpacing: 1.6, fontWeight: FontWeight.w800))),
              for (final (p, l, i) in items) if ((p != '/bus' || onBus) && allowed(p)) TourTarget('nav:$p', child: _Nav(l, i, selected: on(p), badge: badge(p), onTap: () => router.go(p == 'honours' ? hubStart(Hub.honours, settings) : p))),
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
