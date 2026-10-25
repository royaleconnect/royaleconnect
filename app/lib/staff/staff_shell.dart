import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/session.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'staff_data.dart';

/// One menu entry: route, label, icon, and which roles see it (empty = everyone).
class StaffItem {
  final String path, label; final IconData icon; final List<String> roles; final bool officeOnly;
  const StaffItem(this.path, this.label, this.icon, {this.roles = const [], this.officeOnly = false});
}

const staffMenu = [
  StaffItem('/staff', 'Overview', Icons.dashboard_rounded),
  StaffItem('/staff/messages', 'Messages', Icons.chat_bubble_rounded),
  StaffItem('/staff/announcements', 'Announcements', Icons.campaign_rounded),
  StaffItem('/staff/diary', 'Class diary', Icons.menu_book_rounded),
  StaffItem('/staff/leave', 'Leave requests', Icons.event_busy_rounded),
  StaffItem('/staff/exams', 'Exams & portions', Icons.quiz_rounded),
  StaffItem('/staff/marks', 'Marks entry', Icons.grading_rounded),
  StaffItem('/staff/plan', 'Monthly plan', Icons.view_agenda_rounded, roles: ['coordinator', 'office', 'it_admin', 'principal', 'vice_principal']),
  StaffItem('/staff/worksheets', 'Worksheets', Icons.description_rounded),
  StaffItem('/staff/star', 'Star of the month', Icons.star_rounded),
  StaffItem('/staff/moments', 'Class moments', Icons.photo_library_rounded),
  StaffItem('/staff/feedback', 'Parent feedback', Icons.rate_review_rounded, officeOnly: true),
  StaffItem('/staff/fees', 'Fees desk', Icons.account_balance_wallet_rounded, roles: ['accounts', 'office', 'it_admin', 'principal', 'vice_principal']),
  StaffItem('/staff/transport', 'Transport', Icons.directions_bus_rounded, roles: ['transport_incharge', 'office', 'it_admin', 'principal', 'vice_principal']),
  StaffItem('/staff/students', 'Students', Icons.people_alt_rounded),
  StaffItem('/staff/users', 'Staff & settings', Icons.admin_panel_settings_rounded, roles: ['it_admin', 'principal']),
];

List<StaffItem> visibleMenu(Session s) => staffMenu.where((m) => (m.roles.isEmpty || m.roles.any(s.hasRole)) && (!m.officeOnly || s.isOffice)).toList();

/// Desktop: left sidebar + content. Phone: top bar + "More" drawer with the full menu, bottom bar with the 4 most used.
class StaffShell extends ConsumerWidget {
  final Widget child;
  const StaffShell({super.key, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    if (s == null || !s.isStaff) return const SizedBox.shrink();
    final menu = visibleMenu(s);
    final loc = GoRouterState.of(context).matchedLocation;
    final ov = ref.watch(staffOverviewProvider).value ?? const {};
    int badge(String p) => p == '/staff/messages' ? (ov['unread'] ?? 0) : p == '/staff/leave' ? (ov['leaves'] ?? 0) : p == '/staff/feedback' ? (ov['feedback'] ?? 0) : 0;
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(builder: (_, c) {
      final wide = c.maxWidth >= 960;
      if (wide) {
        return Scaffold(body: Row(children: [
          Container(width: 252, decoration: const BoxDecoration(gradient: Brand.headerGradient), child: SafeArea(child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 10), child: Row(children: [
              Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: Image.asset('assets/images/monogram.png', width: 26)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Royale Connect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)), Text('Staff panel · ${AppConfig.academicYearLabel}', style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 11))])),
            ])),
            Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 18), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Brand.gold, Colors.transparent]))),
            const SizedBox(height: 8),
            Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: [for (final m in menu) _NavTile(m, selected: loc == m.path || (m.path != '/staff' && loc.startsWith(m.path)), badge: badge(m.path), onTap: () => context.go(m.path))])),
            _MeTile(s, onSignOut: () async { await ref.read(sessionProvider.notifier).signOut(); if (context.mounted) context.go('/login'); }),
          ]))),
          Expanded(child: ColoredBox(color: cs.surfaceContainerHighest.withValues(alpha: .35), child: child)),
        ]));
      }
      // phone / tablet
      final quick = menu.take(4).toList();
      return Scaffold(
        appBar: AppBar(backgroundColor: Brand.crimsonDeep, foregroundColor: Colors.white, elevation: 0,
          title: Text(menu.firstWhere((m) => loc == m.path || (m.path != '/staff' && loc.startsWith(m.path)), orElse: () => menu.first).label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          actions: [IconButton(onPressed: () => _more(context, menu, loc, badge), icon: const Icon(Icons.menu_rounded))]),
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: quick.indexWhere((m) => loc == m.path || (m.path != '/staff' && loc.startsWith(m.path))).clamp(0, quick.length - 1),
          onDestinationSelected: (i) => context.go(quick[i].path),
          destinations: [for (final m in quick) NavigationDestination(icon: badge(m.path) > 0 ? Badge(label: Text('${badge(m.path)}'), child: Icon(m.icon)) : Icon(m.icon), label: m.label.split(' ').first)],
        ),
      );
    });
  }

  void _more(BuildContext context, List<StaffItem> menu, String loc, int Function(String) badge) => showModalBottomSheet(context: context, showDragHandle: true, builder: (_) => ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), shrinkWrap: true, children: [
    for (final m in menu) ListTile(leading: Icon(m.icon, color: Brand.crimsonDeep), title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: badge(m.path) > 0 ? CircleAvatar(radius: 11, backgroundColor: Brand.crimson, child: Text('${badge(m.path)}', style: const TextStyle(color: Colors.white, fontSize: 11))) : null,
      selected: loc == m.path, onTap: () { Navigator.pop(context); context.go(m.path); }),
  ]));
}

class _NavTile extends StatelessWidget {
  final StaffItem m; final bool selected; final int badge; final VoidCallback onTap;
  const _NavTile(this.m, {required this.selected, required this.badge, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Material(color: selected ? Colors.white.withValues(alpha: .16) : Colors.transparent, borderRadius: BorderRadius.circular(12),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
        Icon(m.icon, size: 20, color: selected ? Brand.gold2 : Colors.white.withValues(alpha: .85)), const SizedBox(width: 12),
        Expanded(child: Text(m.label, style: TextStyle(color: Colors.white, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, fontSize: 13.5))),
        if (badge > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Brand.gold, borderRadius: BorderRadius.circular(999)), child: Text('$badge', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Brand.ink))),
      ])))));
}

class _MeTile extends StatelessWidget {
  final Session s; final VoidCallback onSignOut;
  const _MeTile(this.s, {required this.onSignOut});
  @override
  Widget build(BuildContext context) {
    final name = s.staff?['name'] ?? '';
    return Container(margin: const EdgeInsets.all(12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Row(children: [
      Avatar(name.toString().trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase(), bg: Colors.white, fg: Brand.crimsonDeep, size: 36),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)), Text(s.roles.map(roleLabel).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 11))])),
      IconButton(onPressed: () => context.push('/staff/me'), icon: const Icon(Icons.settings_outlined, color: Colors.white, size: 20), tooltip: 'My settings'),
      IconButton(onPressed: onSignOut, icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 20), tooltip: 'Sign out'),
    ]));
  }
}

String roleLabel(String r) => const {'teacher': 'Teacher', 'class_teacher': 'Class teacher', 'coordinator': 'Coordinator', 'vice_principal': 'Vice Principal', 'principal': 'Principal', 'accounts': 'Accounts', 'office': 'Office', 'it_admin': 'IT admin', 'transport_incharge': 'Transport', 'driver': 'Driver', 'conductor': 'Conductor'}[r] ?? r;

/// Page frame used by every staff screen: title row + optional action button, then content; max width on desktop.
class StaffPage extends StatelessWidget {
  final String title; final String? subtitle; final Widget body; final List<Widget> actions; final bool scroll;
  const StaffPage({super.key, required this.title, this.subtitle, required this.body, this.actions = const [], this.scroll = true});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final header = Padding(padding: const EdgeInsets.fromLTRB(24, 22, 24, 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: t.headlineSmall?.copyWith(fontSize: 24)), if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))])),
      ...actions,
    ]));
    final content = ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, scroll ? Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), child: body) : Expanded(child: body)]));
    return scroll ? SingleChildScrollView(child: Align(alignment: Alignment.topLeft, child: content)) : Align(alignment: Alignment.topLeft, child: content);
  }
}

/// White card used everywhere in the panel.
class Panel extends StatelessWidget {
  final Widget child; final EdgeInsets padding; final String? title; final Widget? trailing;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.title, this.trailing});
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 14), padding: padding, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: .6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [Expanded(child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))), if (trailing != null) trailing!])),
        child,
      ]));
}

/// Dropdown bound to a list of maps.
class PickField<T> extends StatelessWidget {
  final String label; final T? value; final List<DropdownMenuItem<T>> items; final ValueChanged<T?> onChanged;
  const PickField({super.key, required this.label, required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(value: value, items: items, onChanged: onChanged, decoration: InputDecoration(labelText: label), isExpanded: true);
}

String sectionLabel(Map<String, dynamic> sec) => '${sec['grade']?['code'] ?? ''}-${sec['name'] ?? ''}';

void toast(BuildContext context, String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, width: 420));
