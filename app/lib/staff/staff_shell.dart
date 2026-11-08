import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../screens/desk_screen.dart' show DeskGate;
import '../auth/session.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../screens/help_screen.dart' show HelpFab;
import 'staff_data.dart';
import '../core/data3.dart' show appSettingsProvider, staffAccessOf, yearLabelProvider;
import '../widgets/hub_tabs.dart';
import 'staff_search.dart' show StaffSearchBar, StaffSearchShortcuts, showStaffSearch;
import 'approvals_page.dart' show approvalsCountProvider;
import '../widgets/guided_tour.dart' show maybeShowTour, tourRoleFor, TourTarget, tourRequestProvider;
import '../widgets/staff_birthday.dart';
import 'id_cards_page.dart' show idCardsAllReadyProvider;

/// One menu entry: route, label, icon, group, and which roles IT may open it to (empty = everyone).
/// Who sees it by default comes from [staffLayouts] (the menu of each role); IT can narrow it in School settings → "Who can use what".
class StaffItem {
  final String path, label, group; final IconData icon; final List<String> roles;
  /// locked = always shown to the roles above; IT cannot switch it off (Today, Help, My settings, School settings)
  final bool locked;
  const StaffItem(this.path, this.label, this.icon, this.group, {this.roles = const [], this.locked = false});
}

const officeRoles = ['office', 'it_admin', 'principal', 'vice_principal'];
const allStaffRoles = ['teacher', 'class_teacher', 'coordinator', 'accounts', 'office', 'transport_incharge', 'vice_principal', 'principal', 'it_admin'];

/// Highest role first: the menu groups and the phone's bottom bar follow a person's highest role.
const staffRoleOrder = ['it_admin', 'principal', 'vice_principal', 'office', 'accounts', 'transport_incharge', 'coordinator', 'class_teacher', 'teacher'];

// Every page that can be in the menu. Page titles are the same as these labels.
const staffMenu = [
  StaffItem('/staff', 'Today', Icons.today_rounded, 'TODAY', locked: true),
  StaffItem('/staff/approvals', 'Approvals', Icons.inbox_rounded, 'TODAY', roles: ['it_admin', 'principal', 'vice_principal', 'office']),
  StaffItem('/staff/messages', 'Messages', Icons.chat_bubble_rounded, 'TODAY'),
  StaffItem('/staff/announcements', 'Notices', Icons.campaign_rounded, 'TODAY', roles: ['class_teacher', 'coordinator', 'transport_incharge', ...officeRoles]),
  StaffItem('/staff/desk', "Principal's Desk", Icons.auto_awesome_rounded, 'TODAY', roles: ['it_admin', 'principal']),
  StaffItem('/staff/attendance', 'Attendance', Icons.fact_check_rounded, 'MY CLASS', roles: ['class_teacher', 'coordinator', ...officeRoles]),
  StaffItem('/staff/diary', 'Diary', Icons.menu_book_rounded, 'MY CLASS'),
  StaffItem('/staff/leave', 'Leave requests', Icons.event_busy_rounded, 'MY CLASS', roles: ['class_teacher', ...officeRoles]),
  StaffItem('/staff/exams', 'Exams & marks', Icons.grading_rounded, 'MY CLASS'),
  StaffItem('/staff/star', 'Star of the month', Icons.star_rounded, 'MY CLASS'),
  StaffItem('/staff/moments', 'Class photos', Icons.photo_library_rounded, 'MY CLASS'),
  StaffItem('/staff/students', 'Students', Icons.people_alt_rounded, 'STUDENTS'),
  StaffItem('/staff/class-logins', 'Class logins', Icons.key_rounded, 'MY CLASS', roles: ['class_teacher', 'office', 'it_admin']),
  StaffItem('/staff/fees', 'Fees & receipts', Icons.account_balance_wallet_rounded, 'STUDENTS', roles: ['accounts', ...officeRoles]),
  StaffItem('/staff/certificates', 'Certificates', Icons.workspace_premium_rounded, 'STUDENTS', roles: ['accounts', ...officeRoles]),
  StaffItem('/staff/id-cards', 'ID cards', Icons.badge_rounded, 'STUDENTS', roles: officeRoles),
  StaffItem('/staff/transport', 'Transport', Icons.directions_bus_rounded, 'STUDENTS', roles: ['transport_incharge', ...officeRoles]),
  StaffItem('/staff/bus-pins', 'Check pins', Icons.pin_drop_rounded, 'BUSES', roles: ['transport_incharge', ...officeRoles]),
  StaffItem('/staff/toppers', 'Honours', Icons.emoji_events_rounded, 'SCHOOL'),
  StaffItem('/staff/calendar', 'School calendar', Icons.calendar_month_rounded, 'SCHOOL', roles: officeRoles),
  StaffItem('/staff/feedback', 'Parent feedback', Icons.rate_review_rounded, 'SCHOOL', roles: officeRoles),
  StaffItem('/staff/setup', 'School setup', Icons.tune_rounded, 'SCHOOL', roles: ['accounts', ...officeRoles]),
  StaffItem('/staff/week', 'Your week', Icons.insights_rounded, 'SCHOOL', roles: ['principal', 'it_admin', 'vice_principal']),
  StaffItem('/staff/me', 'My settings', Icons.settings_rounded, 'ME', locked: true),
  StaffItem('/staff/help', 'Help', Icons.help_outline_rounded, 'ME', locked: true),
];

const _me = ('ME', ['/staff/me', '/staff/help']);
const _honours = ('SCHOOL', ['/staff/toppers']);

/// The menu of each role (groups in order). Honours is in every menu. A person with several roles gets all their pages.
const staffLayouts = <String, List<(String, List<String>)>>{
  'teacher': [('TODAY', ['/staff', '/staff/messages']), ('MY CLASSES', ['/staff/diary', '/staff/exams', '/staff/moments']), _honours, _me],
  'class_teacher': [('TODAY', ['/staff', '/staff/messages', '/staff/announcements']),
    ('MY CLASS', ['/staff/attendance', '/staff/diary', '/staff/leave', '/staff/exams', '/staff/star', '/staff/moments', '/staff/students', '/staff/class-logins']), _honours, _me],
  'coordinator': [('TODAY', ['/staff', '/staff/messages', '/staff/announcements']), ('MY GRADES', ['/staff/attendance', '/staff/diary', '/staff/exams', '/staff/students']), _honours, _me],
  'accounts': [('TODAY', ['/staff']), ('FEES', ['/staff/fees', '/staff/students', '/staff/certificates']), _honours, _me],
  'office': [('TODAY', ['/staff', '/staff/approvals', '/staff/messages', '/staff/announcements']),
    ('STUDENTS', ['/staff/students', '/staff/fees', '/staff/certificates', '/staff/id-cards', '/staff/transport']), ('SCHOOL', ['/staff/calendar', '/staff/feedback', '/staff/toppers']), _me],
  'transport_incharge': [('TODAY', ['/staff', '/staff/announcements']), ('BUSES', ['/staff/transport', '/staff/bus-pins', '/staff/students']), _honours, _me],
  'principal': [('TODAY', ['/staff', '/staff/approvals', '/staff/announcements', '/staff/desk']),
    ('SCHOOL', ['/staff/students', '/staff/attendance', '/staff/exams', '/staff/toppers', '/staff/feedback', '/staff/week']), _me],
  'vice_principal': [('TODAY', ['/staff', '/staff/approvals', '/staff/announcements']),
    ('SCHOOL', ['/staff/students', '/staff/attendance', '/staff/exams', '/staff/toppers', '/staff/feedback', '/staff/week']), _me],
  // IT: everything
  'it_admin': [('TODAY', ['/staff', '/staff/approvals', '/staff/messages', '/staff/announcements']),
    ('STUDENTS', ['/staff/students', '/staff/fees', '/staff/certificates', '/staff/id-cards', '/staff/transport', '/staff/toppers']),
    ('SCHOOL', ['/staff/desk', '/staff/calendar', '/staff/feedback', '/staff/setup', '/staff/week']),
    ('CLASSES', ['/staff/attendance', '/staff/diary', '/staff/leave', '/staff/exams', '/staff/star', '/staff/moments', '/staff/class-logins', '/staff/bus-pins']), _me],
};

/// The 4 pages at the bottom of the phone screen: the daily jobs of the person's highest role.
const staffBottomBar = <String, List<(String, String)>>{
  'teacher': [('/staff', 'Today'), ('/staff/diary', 'Diary'), ('/staff/marks', 'Marks'), ('/staff/messages', 'Messages')],
  'class_teacher': [('/staff', 'Today'), ('/staff/attendance', 'Attendance'), ('/staff/diary', 'Diary'), ('/staff/messages', 'Messages')],
  'coordinator': [('/staff', 'Today'), ('/staff/attendance', 'Attendance'), ('/staff/diary', 'Diary'), ('/staff/marks', 'Marks')],
  'accounts': [('/staff', 'Today'), ('/staff/fees', 'Fees'), ('/staff/students', 'Students'), ('/staff/certificates', 'Certificates')],
  'office': [('/staff', 'Today'), ('/staff/approvals', 'Approvals'), ('/staff/students', 'Students'), ('/staff/announcements', 'Notices')],
  'transport_incharge': [('/staff', 'Today'), ('/staff/transport', 'Transport'), ('/staff/announcements', 'Notices'), ('/staff/students', 'Students')],
  'principal': [('/staff', 'Today'), ('/staff/approvals', 'Approvals'), ('/staff/announcements', 'Notices'), ('/staff/week', 'Your week')],
  'vice_principal': [('/staff', 'Today'), ('/staff/approvals', 'Approvals'), ('/staff/announcements', 'Notices'), ('/staff/week', 'Your week')],
  'it_admin': [('/staff', 'Today'), ('/staff/approvals', 'Approvals'), ('/staff/students', 'Students'), ('/staff/setup', 'Setup')],
};

/// Pages reached through a tab of another menu item (they keep their own "who can use it" setting in School settings).
const staffSubPages = [
  StaffItem('/staff/marks', 'Marks entry', Icons.grading_rounded, 'MY CLASS'),
  StaffItem('/staff/reports', 'Report cards', Icons.assignment_turned_in_rounded, 'MY CLASS', roles: ['class_teacher', ...officeRoles]),
  StaffItem('/staff/council', 'Student Council', Icons.how_to_vote_rounded, 'STUDENTS'),
  StaffItem('/staff/users', 'Staff', Icons.badge_rounded, 'SCHOOL', roles: ['it_admin', 'principal']),
  StaffItem('/staff/sections', 'New sections', Icons.view_module_rounded, 'SCHOOL', roles: ['it_admin', 'principal']),
  StaffItem('/staff/bin', 'Bin', Icons.delete_outline_rounded, 'SCHOOL', roles: ['it_admin', 'principal']),
  StaffItem('/staff/settings', 'School settings', Icons.admin_panel_settings_rounded, 'SCHOOL', roles: ['it_admin'], locked: true),
  StaffItem('/staff/houses', 'Houses', Icons.flag_rounded, 'STUDENTS'),
  StaffItem('/staff/year-end', 'Year-end checklist', Icons.event_available_rounded, 'SCHOOL', roles: ['it_admin', 'principal'], locked: true),
];

/// Which menu item a tab-page belongs to (so the right item stays highlighted).
const staffHubOf = {'/staff/marks': '/staff/exams', '/staff/reports': '/staff/exams', '/staff/council': '/staff/toppers', '/staff/houses': '/staff/toppers',
  '/staff/users': '/staff/setup', '/staff/sections': '/staff/setup', '/staff/bin': '/staff/setup', '/staff/settings': '/staff/setup', '/staff/fees/reports': '/staff/fees', '/staff/year-end': '/staff', '/staff/thanks': '/staff'};

/// Roles that have this page in their own menu (the normal setting when IT has not changed it).
List<String> defaultRolesOf(StaffItem m) {
  if (staffSubPages.contains(m)) return maxRolesOf(m);
  final r = [for (final e in staffLayouts.entries) if (e.value.any((g) => g.$2.contains(m.path))) e.key];
  return r.isEmpty ? maxRolesOf(m) : r;
}

/// May this person open this page (menu item or tab page)?
bool staffCanOpen(Session s, Map<String, String>? settings, String path) {
  final all = [...staffMenu, ...staffSubPages];
  final m = all.where((x) => x.path == path).firstOrNull;
  return m == null || chosenRolesOf(m, staffAccessOf(settings)).any(s.hasRole);
}

/// The same rule for any address inside the panel (used by the router): '/staff/toppers/edit' follows '/staff/toppers'.
bool staffCanOpenRoute(Session s, Map<String, String>? settings, String loc) {
  if (loc == '/staff' || loc == '/staff/me' || loc == '/staff/help' || loc == '/staff/set-password') return true;
  final all = [...staffMenu, ...staffSubPages].where((m) => m.path != '/staff' && (loc == m.path || loc.startsWith('${m.path}/'))).toList()
    ..sort((a, b) => b.path.length.compareTo(a.path.length));
  return all.isEmpty || staffCanOpen(s, settings, all.first.path);
}

/// Bumped when the router turns someone away from a page; the panel then shows "You don't have access to that page".
final staffAccessDenied = ValueNotifier<int>(0);

/// For the router: null = go ahead; '/staff' = not allowed (and the panel shows a short message).
String? staffRouteRedirect(Session s, Map<String, String>? settings, String loc) {
  if (staffCanOpenRoute(s, settings, loc)) return null;
  staffAccessDenied.value++;
  return '/staff';
}

/// The most a page can be opened to (the database rules decide what each role can actually read).
List<String> maxRolesOf(StaffItem m) => m.roles.isEmpty ? allStaffRoles : {...m.roles, ...[for (final e in staffLayouts.entries) if (e.value.any((g) => g.$2.contains(m.path))) e.key]}.toList();

/// What IT has chosen in School settings → "Who can use what" (missing = the normal roles of each menu).
List<String> chosenRolesOf(StaffItem m, Map<String, List<String>> access) =>
    m.locked ? maxRolesOf(m) : !access.containsKey(m.path) ? defaultRolesOf(m) : access[m.path]!.where(maxRolesOf(m).contains).toList();

/// This person's highest role (decides the order of the menu groups and the bottom bar).
String staffTopRole(Session s) => staffRoleOrder.firstWhere(s.hasRole, orElse: () => 'teacher');

List<StaffItem> visibleMenu(Session s, [Map<String, String>? settings]) {
  final access = staffAccessOf(settings);
  final allowed = {for (final m in staffMenu) if (chosenRolesOf(m, access).any(s.hasRole)) m.path: m};
  // groups and order: the highest role's menu first, then pages from the person's other roles, then pages IT has opened to them
  final groups = <String, List<StaffItem>>{};
  final placed = <String>{};
  void put(String g, String p) { final m = allowed[p]; if (m == null || placed.contains(p)) return; placed.add(p); (groups[g] ??= []).add(m); }
  for (final r in staffRoleOrder.where(s.hasRole)) {
    for (final (g, paths) in staffLayouts[r]!) { if (g != 'ME') for (final p in paths) { put(g, p); } }
  }
  for (final m in staffMenu) { if (m.group != 'ME') put(m.group, m.path); }
  for (final p in _me.$2) { put('ME', p); }
  // a person who is both class teacher and coordinator: Students once
  return [for (final e in groups.entries) ...e.value];
}

/// The phone's bottom bar: the 4 daily jobs of the highest role (only pages this person may open).
List<StaffItem> staffQuickBar(Session s, Map<String, String>? settings, List<StaffItem> menu) {
  final all = [...staffMenu, ...staffSubPages];
  final out = <StaffItem>[];
  for (final (p, label) in staffBottomBar[staffTopRole(s)]!) {
    final m = all.where((x) => x.path == p).firstOrNull;
    if (m != null && staffCanOpen(s, settings, p)) out.add(StaffItem(p, label, m.icon, m.group));
  }
  for (final m in menu) {
    if (out.length >= 4) break;
    if (m.group != 'ME' && !out.any((x) => x.path == m.path)) out.add(m);
  }
  return out.take(4).toList();
}

/// Inside the staff panel, buttons size to their text (the app-wide theme makes them full width for phone forms).
/// Full-screen pages opened on top of the panel (student record, grade planner) use this too.
Widget staffTheme(BuildContext context, Widget child) {
  final base = Theme.of(context);
  final cs = base.colorScheme;
  return Theme(data: base.copyWith(
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), side: BorderSide(color: cs.outline, width: 1.5), foregroundColor: cs.onSurface, textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
  ), child: child);
}

/// Desktop: left sidebar + content. Phone: top bar + "More" drawer with the full menu, bottom bar with the 4 most used.
class StaffShell extends ConsumerWidget {
  final Widget child;
  const StaffShell({super.key, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    if (s == null || !s.isStaff) return const SizedBox.shrink();
    ref.watch(tourRequestProvider);   // "Take the tour again" from Help
    WidgetsBinding.instance.addPostFrameCallback((_) { if (context.mounted) maybeShowTour(context, tourRoleFor(s)); });
    final settings = ref.watch(appSettingsProvider).value;
    final menu = visibleMenu(s, settings);
    final loc0 = GoRouterState.of(context).matchedLocation;
    final loc = staffHubOf.entries.where((e) => loc0 == e.key || loc0.startsWith('${e.key}/')).firstOrNull?.value ?? loc0;
    final ov = ref.watch(staffOverviewProvider).value ?? const {};
    final approvals = ref.watch(approvalsCountProvider);
    final idReady = officeRoles.any(s.hasRole) && ref.watch(idCardsAllReadyProvider).value == true;
    int badge(String p) => p == '/staff/messages' ? (ov['unread'] ?? 0) : p == '/staff/leave' ? (ov['leaves'] ?? 0) : p == '/staff/feedback' ? (ov['feedback'] ?? 0) : p == '/staff/approvals' ? approvals : 0;
    final cs = Theme.of(context).colorScheme;
    // The app-wide button theme is "full width" (right for phone screens). Inside the panel, buttons size to their content.
    final content = staffTheme(context, child);

    // Help: bottom right of the Overview page
    final help = loc0 == '/staff' ? HelpFab(onTap: () => context.go('/staff/help')) : null;
    return _AccessDeniedToast(child: StaffSearchShortcuts(child: DeskGate(child: StaffBirthdayGate(child: LayoutBuilder(builder: (_, c) {
      final wide = c.maxWidth >= 960;
      if (wide) {
        return Scaffold(body: Row(children: [
          Container(width: 252, decoration: const BoxDecoration(gradient: Brand.headerGradient), child: SafeArea(child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 10), child: Row(children: [
              Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: Image.asset('assets/images/monogram.png', width: 26)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Royale Connect', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)), Text('Staff panel · ${ref.watch(yearLabelProvider).value ?? AppConfig.academicYearLabel}', style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 11))])),
            ])),
            Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 18), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Brand.gold, Colors.transparent]))),
            const SizedBox(height: 8),
            Expanded(child: ListView(padding: const EdgeInsets.symmetric(horizontal: 10), children: [
              for (final (i, m) in menu.indexed) ...[
                if (i == 0 || menu[i - 1].group != m.group) Padding(padding: const EdgeInsets.fromLTRB(12, 14, 12, 4), child: Text(m.group, style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 10.5, letterSpacing: 1.6, fontWeight: FontWeight.w800))),
                TourTarget('nav:${m.path}', child: _NavTile(m, selected: loc == m.path || (m.path != '/staff' && loc.startsWith('${m.path}/')), badge: badge(m.path), glow: m.path == '/staff/id-cards' && idReady, onTap: () => m.path == '/staff/me' ? context.push(m.path) : context.go(m.path))),
              ],
            ])),
            _MeTile(s, onSignOut: () async { await ref.read(sessionProvider.notifier).signOut(); if (context.mounted) context.go('/login'); }),
          ]))),
          Expanded(child: ColoredBox(color: cs.surfaceContainerHighest.withValues(alpha: .35), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const TourTarget('staff-search', child: StaffSearchBar()), Expanded(child: content)]))),
        ]), floatingActionButton: help);
      }
      // phone / tablet
      final quick = staffQuickBar(s, settings, menu);
      bool on(StaffItem m) => loc0 == m.path || loc == m.path || (m.path != '/staff' && (loc.startsWith('${m.path}/') || loc0.startsWith('${m.path}/')));
      return Scaffold(
        appBar: AppBar(backgroundColor: Brand.crimsonDeep, foregroundColor: Colors.white, elevation: 0,
          title: Text(menu.firstWhere((m) => loc == m.path || (m.path != '/staff' && loc.startsWith('${m.path}/')), orElse: () => menu.first).label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          actions: [TourTarget('staff-search', child: IconButton(onPressed: () => showStaffSearch(context), icon: const Icon(Icons.search_rounded), tooltip: 'Search a student')), TourTarget('staff-menu', child: IconButton(onPressed: () => _more(context, ref, s, menu, loc, badge), icon: const Icon(Icons.menu_rounded), tooltip: 'Menu'))]),
        body: content,
        floatingActionButton: help,
        bottomNavigationBar: NavigationBar(
          selectedIndex: quick.indexWhere(on).clamp(0, quick.length - 1),
          onDestinationSelected: (i) => context.go(quick[i].path),
          destinations: [for (final m in quick) TourTarget('nav:${m.path}', child: NavigationDestination(icon: badge(m.path) > 0 ? Badge(label: Text('${badge(m.path)}'), child: Icon(m.icon)) : Icon(m.icon), label: const {'Parent feedback': 'Feedback', 'School calendar': 'Calendar', 'Leave requests': 'Leave', 'Exams & marks': 'Exams', 'Fees & receipts': 'Fees'}[m.label] ?? m.label))],
        ),
      );
    })))));
  }

  void _more(BuildContext context, WidgetRef ref, Session s, List<StaffItem> menu, String loc, int Function(String) badge) => showModalBottomSheet(context: context, showDragHandle: true, isScrollControlled: true, builder: (sheet) => ConstrainedBox(
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
    child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), shrinkWrap: true, children: [
      for (final (i, m) in menu.where((m) => m.path != '/staff/me').indexed) ...[
        if (i == 0 || menu.where((m) => m.path != '/staff/me').elementAt(i - 1).group != m.group) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 2), child: Text(m.group, style: const TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: Brand.muted))),
        ListTile(leading: Icon(m.icon, color: Brand.crimson), title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: badge(m.path) > 0 ? CircleAvatar(radius: 11, backgroundColor: Brand.crimson, child: Text('${badge(m.path)}', style: const TextStyle(color: Colors.white, fontSize: 11))) : null,
        selected: loc == m.path, onTap: () { Navigator.pop(sheet); context.go(m.path); }),
      ],
      const Divider(height: 24),
      ListTile(leading: Avatar((s.staff?['name'] ?? '').toString().trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase(), size: 36),
        title: Text('${s.staff?['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(s.roles.map(roleLabel).join(' · '))),
      ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('My settings & password', style: TextStyle(fontWeight: FontWeight.w700)), onTap: () { Navigator.pop(sheet); context.push('/staff/me'); }),
      ListTile(leading: const Icon(Icons.logout_rounded, color: Brand.crimson), title: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.w800, color: Brand.crimson)),
        onTap: () async { Navigator.pop(sheet); await ref.read(sessionProvider.notifier).signOut(); if (context.mounted) context.go('/login'); }),
    ])));
}

/// Shows "You don't have access to that page" when the router sends someone back to Today.
class _AccessDeniedToast extends StatefulWidget {
  final Widget child;
  const _AccessDeniedToast({required this.child});
  @override
  State<_AccessDeniedToast> createState() => _AccessDeniedToastState();
}

class _AccessDeniedToastState extends State<_AccessDeniedToast> {
  void _show() => WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) toast(context, 'You don’t have access to that page'); });
  @override
  void initState() { super.initState(); staffAccessDenied.addListener(_show); }
  @override
  void dispose() { staffAccessDenied.removeListener(_show); super.dispose(); }
  @override
  Widget build(BuildContext context) => widget.child;
}

class _NavTile extends StatelessWidget {
  final StaffItem m; final bool selected; final int badge; final VoidCallback onTap; final bool glow;
  const _NavTile(this.m, {required this.selected, required this.badge, required this.onTap, this.glow = false});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 2), child: AnimatedContainer(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: selected ? Colors.white.withValues(alpha: .16) : Colors.transparent,
          border: Border(left: BorderSide(color: selected ? Brand.gold2 : Colors.transparent, width: 3))),
      child: Material(color: Colors.transparent, borderRadius: BorderRadius.circular(12),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
        Icon(m.icon, size: 20, color: selected ? Brand.gold2 : Colors.white.withValues(alpha: .85)), const SizedBox(width: 12),
        Expanded(child: Text(m.label, style: TextStyle(color: Colors.white, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, fontSize: 13.5))),
        if (glow) Tooltip(message: 'All ID cards ready', child: Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.gold2, boxShadow: [BoxShadow(color: Brand.gold2.withValues(alpha: .8), blurRadius: 8)]))),
        if (badge > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Brand.gold, borderRadius: BorderRadius.circular(999)), child: Text('$badge', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Brand.ink))),
      ]))))));
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

String roleLabel(String r) => const {'teacher': 'Teacher', 'class_teacher': 'Class teacher', 'coordinator': 'Coordinator', 'vice_principal': 'Vice Principal', 'principal': 'Principal', 'accounts': 'Accounts', 'office': 'Office', 'it_admin': 'IT admin', 'transport_incharge': 'Transport', 'driver': 'Driver', 'conductor': 'Bus assistant'}[r] ?? r;

/// Page frame used by every staff screen: title row + optional action button, then content; max width on desktop.
class StaffPage extends StatelessWidget {
  final String title; final String? subtitle; final Widget body; final List<Widget> actions; final bool scroll;
  final Hub? hub;   // tabs to the pages that share one menu item
  const StaffPage({super.key, required this.title, this.subtitle, required this.body, this.actions = const [], this.scroll = true, this.hub});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (_, c) {
      final full = c.maxWidth.isFinite ? c.maxWidth : MediaQuery.sizeOf(context).width;
      final w = full < 1100 ? full : 1100.0;
      final narrow = full < 700;
      final pad = narrow ? 16.0 : 24.0;
      final titles = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: t.headlineSmall?.copyWith(fontSize: narrow ? 21 : 24)),
        if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: narrow ? 13 : 14))),
        if (hub != null) Padding(padding: const EdgeInsets.only(top: 12), child: HubTabs(hub!, onDark: false)),
      ]);
      final header = Padding(padding: EdgeInsets.fromLTRB(pad, narrow ? 16 : 22, pad, 12), child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [titles, for (final a in actions) Padding(padding: const EdgeInsets.only(top: 12), child: a)])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: titles), for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: a)]));
      final column = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [header, Padding(padding: EdgeInsets.fromLTRB(pad, 0, pad, 32), child: body)]);
      if (scroll) {
        return SingleChildScrollView(child: Align(alignment: Alignment.topLeft, child: SizedBox(width: w, child: column)));
      }
      return Align(alignment: Alignment.topLeft, child: SizedBox(width: w, height: c.maxHeight.isFinite ? c.maxHeight : MediaQuery.sizeOf(context).height,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, Expanded(child: body)])));
    });
  }
}

/// White card used everywhere in the panel.
class Panel extends StatelessWidget {
  final Widget child; final EdgeInsets padding; final String? title; final Widget? trailing; final bool fill;
  /// [fill] = true when the panel has a fixed height and the child should take all of it (chat thread, lists with their own scrolling).
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.title, this.trailing, this.fill = false});
  @override
  Widget build(BuildContext context) => Container(margin: const EdgeInsets.only(bottom: 14), padding: padding, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: .6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min, children: [
        if (title != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: isNarrow(context) && trailing != null
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)), const SizedBox(height: 6), trailing!])
            : Row(children: [Expanded(child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))), if (trailing != null) trailing!])),
        if (fill) Expanded(child: child) else child,
      ]));
}

/// Dropdown bound to a list of maps.
class PickField<T> extends StatelessWidget {
  final String label; final T? value; final List<DropdownMenuItem<T>> items; final ValueChanged<T?> onChanged;
  const PickField({super.key, required this.label, required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(value: value, items: items, onChanged: onChanged, decoration: InputDecoration(labelText: label), isExpanded: true);
}

/// Phones and small tablets: stack things vertically instead of squeezing them into one row.
bool isNarrow(BuildContext context) => MediaQuery.sizeOf(context).width < 700;

bool _isSpacer(Widget w) => w is SizedBox && w.child == null;

/// A card row: [lead] (pill/icon), the Expanded body, then actions.
/// Wide: one row. Narrow: lead on top, body full width, actions underneath on the right.
class CardRow extends StatelessWidget {
  final List<Widget> children;
  const CardRow({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    if (!isNarrow(context)) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
    final i = children.indexWhere((w) => w is Expanded);
    final lead = children.take(i < 0 ? 0 : i).where((w) => !_isSpacer(w)).toList();
    final body = i < 0 ? null : (children[i] as Expanded).child;
    final actions = children.skip(i + 1).where((w) => !_isSpacer(w)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (lead.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: lead)),
      if (lead.isNotEmpty && body != null) const SizedBox(height: 8),
      if (body != null) body,
      if (actions.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions)),
    ]);
  }
}

/// A filter bar (pickers, date buttons, month arrows). Wide: one row. Narrow: each field full width, small controls on one line.
class PickRow extends StatelessWidget {
  final List<Widget> children;
  const PickRow({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    if (!isNarrow(context)) return Row(children: children);
    final fields = [for (final w in children) if (w is Expanded) w.child];
    final small = [for (final w in children) if (w is! Expanded && !_isSpacer(w)) w];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (final (i, f) in fields.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 10), child: f),
      if (small.isNotEmpty) Padding(padding: EdgeInsets.only(top: fields.isEmpty ? 0 : 8), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: small)),
    ]);
  }
}

String sectionLabel(Map<String, dynamic> sec) => '${sec['grade']?['code'] ?? ''}-${sec['name'] ?? ''}';

void toast(BuildContext context, String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, width: isNarrow(context) ? null : 420));
