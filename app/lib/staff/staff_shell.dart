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

/// One menu entry: route, label, icon, group, and which roles see it (empty = everyone).
class StaffItem {
  final String path, label, group; final IconData icon; final List<String> roles;
  /// locked = always shown to the roles above; IT cannot switch it off (Today, Help, My settings, School settings)
  final bool locked;
  const StaffItem(this.path, this.label, this.icon, this.group, {this.roles = const [], this.locked = false});
}

const officeRoles = ['office', 'it_admin', 'principal', 'vice_principal'];
const allStaffRoles = ['teacher', 'class_teacher', 'coordinator', 'accounts', 'office', 'transport_incharge', 'vice_principal', 'principal', 'it_admin'];

const staffMenu = [
  StaffItem('/staff', 'Today', Icons.today_rounded, 'TODAY', locked: true),
  StaffItem('/staff/messages', 'Messages', Icons.chat_bubble_rounded, 'TODAY'),
  StaffItem('/staff/announcements', 'Notices', Icons.campaign_rounded, 'TODAY'),
  StaffItem('/staff/feedback', 'Parent feedback', Icons.rate_review_rounded, 'TODAY', roles: officeRoles),
  StaffItem('/staff/calendar', 'School calendar', Icons.calendar_month_rounded, 'TODAY', roles: officeRoles),
  StaffItem('/staff/diary', 'Class diary', Icons.menu_book_rounded, 'MY CLASS'),
  StaffItem('/staff/leave', 'Leave requests', Icons.event_busy_rounded, 'MY CLASS'),
  StaffItem('/staff/moments', 'Class photos', Icons.photo_library_rounded, 'MY CLASS'),
  StaffItem('/staff/star', 'Star of the month', Icons.star_rounded, 'MY CLASS'),
  StaffItem('/staff/worksheets', 'Worksheets', Icons.description_rounded, 'MY CLASS'),
  StaffItem('/staff/plan', 'Monthly plan', Icons.view_agenda_rounded, 'MY CLASS', roles: ['coordinator', ...officeRoles]),
  StaffItem('/staff/marks', 'Marks entry', Icons.grading_rounded, 'EXAMS & REPORTS'),
  StaffItem('/staff/reports', 'Report cards', Icons.assignment_turned_in_rounded, 'EXAMS & REPORTS', roles: ['class_teacher', ...officeRoles]),
  StaffItem('/staff/exams', 'Exams & portions', Icons.quiz_rounded, 'EXAMS & REPORTS'),
  StaffItem('/staff/students', 'Students', Icons.people_alt_rounded, 'STUDENTS'),
  StaffItem('/staff/sections', 'New sections', Icons.view_module_rounded, 'STUDENTS', roles: ['it_admin', 'principal']),
  StaffItem('/staff/fees', 'Fees desk', Icons.account_balance_wallet_rounded, 'STUDENTS', roles: ['accounts', ...officeRoles]),
  StaffItem('/staff/transport', 'Transport', Icons.directions_bus_rounded, 'STUDENTS', roles: ['transport_incharge', ...officeRoles]),
  StaffItem('/staff/toppers', 'Board Toppers & Hall of Fame', Icons.emoji_events_rounded, 'STUDENTS'),
  StaffItem('/staff/council', 'Student Council', Icons.how_to_vote_rounded, 'STUDENTS'),
  StaffItem('/staff/desk', "Principal's Desk", Icons.auto_awesome_rounded, 'STUDENTS'),
  StaffItem('/staff/users', 'Staff', Icons.badge_rounded, 'SCHOOL', roles: ['it_admin', 'principal']),
  StaffItem('/staff/setup', 'Classes & fees', Icons.tune_rounded, 'SCHOOL', roles: ['accounts', ...officeRoles]),
  StaffItem('/staff/settings', 'School settings', Icons.admin_panel_settings_rounded, 'SCHOOL', roles: ['it_admin'], locked: true),
  StaffItem('/staff/me', 'My settings', Icons.settings_rounded, 'ME', locked: true),
  StaffItem('/staff/help', 'Help', Icons.help_outline_rounded, 'ME', locked: true),
];

/// The most a page can be opened to (the database rules decide what each role can actually read).
List<String> maxRolesOf(StaffItem m) => m.roles.isEmpty ? allStaffRoles : m.roles;

/// What IT has chosen in School settings → "Who can use what" (missing = the normal roles).
List<String> chosenRolesOf(StaffItem m, Map<String, List<String>> access) =>
    m.locked || !access.containsKey(m.path) ? maxRolesOf(m) : access[m.path]!.where(maxRolesOf(m).contains).toList();

List<StaffItem> visibleMenu(Session s, [Map<String, String>? settings]) {
  final access = staffAccessOf(settings);
  return staffMenu.where((m) => chosenRolesOf(m, access).any(s.hasRole)).toList();
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
    final menu = visibleMenu(s, ref.watch(appSettingsProvider).value);
    final loc = GoRouterState.of(context).matchedLocation;
    final ov = ref.watch(staffOverviewProvider).value ?? const {};
    int badge(String p) => p == '/staff/messages' ? (ov['unread'] ?? 0) : p == '/staff/leave' ? (ov['leaves'] ?? 0) : p == '/staff/feedback' ? (ov['feedback'] ?? 0) : 0;
    final cs = Theme.of(context).colorScheme;
    // The app-wide button theme is "full width" (right for phone screens). Inside the panel, buttons size to their content.
    final content = staffTheme(context, child);

    // Help: bottom right of the Overview page
    final help = loc == '/staff' ? HelpFab(onTap: () => context.go('/staff/help')) : null;
    return DeskGate(child: LayoutBuilder(builder: (_, c) {
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
                _NavTile(m, selected: loc == m.path || (m.path != '/staff' && loc.startsWith(m.path)), badge: badge(m.path), onTap: () => m.path == '/staff/me' ? context.push(m.path) : context.go(m.path)),
              ],
            ])),
            _MeTile(s, onSignOut: () async { await ref.read(sessionProvider.notifier).signOut(); if (context.mounted) context.go('/login'); }),
          ]))),
          Expanded(child: ColoredBox(color: cs.surfaceContainerHighest.withValues(alpha: .35), child: content)),
        ]), floatingActionButton: help);
      }
      // phone / tablet
      final quick = menu.take(4).toList();
      return Scaffold(
        appBar: AppBar(backgroundColor: Brand.crimsonDeep, foregroundColor: Colors.white, elevation: 0,
          title: Text(menu.firstWhere((m) => loc == m.path || (m.path != '/staff' && loc.startsWith(m.path)), orElse: () => menu.first).label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          actions: [IconButton(onPressed: () => _more(context, ref, s, menu, loc, badge), icon: const Icon(Icons.menu_rounded), tooltip: 'Menu')]),
        body: content,
        floatingActionButton: help,
        bottomNavigationBar: NavigationBar(
          selectedIndex: quick.indexWhere((m) => loc == m.path || (m.path != '/staff' && loc.startsWith(m.path))).clamp(0, quick.length - 1),
          onDestinationSelected: (i) => context.go(quick[i].path),
          destinations: [for (final m in quick) NavigationDestination(icon: badge(m.path) > 0 ? Badge(label: Text('${badge(m.path)}'), child: Icon(m.icon)) : Icon(m.icon), label: const {'Parent feedback': 'Feedback', 'School calendar': 'Calendar', 'Class diary': 'Diary', 'Leave requests': 'Leave', 'Exams & portions': 'Exams', 'Marks entry': 'Marks'}[m.label] ?? m.label.split(' ').first)],
        ),
      );
    }));
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

String roleLabel(String r) => const {'teacher': 'Teacher', 'class_teacher': 'Class teacher', 'coordinator': 'Coordinator', 'vice_principal': 'Vice Principal', 'principal': 'Principal', 'accounts': 'Accounts', 'office': 'Office', 'it_admin': 'IT admin', 'transport_incharge': 'Transport', 'driver': 'Driver', 'conductor': 'Bus assistant'}[r] ?? r;

/// Page frame used by every staff screen: title row + optional action button, then content; max width on desktop.
class StaffPage extends StatelessWidget {
  final String title; final String? subtitle; final Widget body; final List<Widget> actions; final bool scroll;
  const StaffPage({super.key, required this.title, this.subtitle, required this.body, this.actions = const [], this.scroll = true});
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
