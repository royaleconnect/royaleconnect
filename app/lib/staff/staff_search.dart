import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'students_page.dart' show openStudentRecord;
import 'package:go_router/go_router.dart';
import '../core/data3.dart' show appSettingsProvider;
import 'staff_shell.dart' show staffTheme, StaffItem, staffMenu, staffSubPages, staffHubOf, staffCanOpen;

/// Instant search for staff: one box at the top of every staff page (or Ctrl + K / ⌘ + K).
/// Type 2–3 letters of a student's name, admission number, a parent's phone or a receipt number; results appear while
/// typing. The database decides what each person may find: the office side finds every student, teachers only the
/// students of their own sections.
const _recordRoles = ['office', 'it_admin', 'principal', 'vice_principal', 'accounts'];   // same as the Students page

bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
String get staffSearchKeyHint => _isMac ? '⌘ K' : 'Ctrl K';

/// The search box shown at the top of staff pages. Clicking it opens the search.
class StaffSearchBar extends StatelessWidget {
  final EdgeInsets margin;
  const StaffSearchBar({super.key, this.margin = const EdgeInsets.fromLTRB(24, 16, 24, 0)});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(padding: margin, child: Align(alignment: Alignment.topLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: Material(
      color: cs.surface, borderRadius: BorderRadius.circular(14),
      child: InkWell(borderRadius: BorderRadius.circular(14), onTap: () => showStaffSearch(context),
        child: Container(height: 46, padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Brand.gold.withValues(alpha: dark ? .55 : .7), width: 1.5)),
          child: Row(children: [
            const Icon(Icons.search_rounded, color: Brand.gold, size: 22), const SizedBox(width: 10),
            Expanded(child: Text('Search a student — name, admission no., phone or receipt', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(border: Border.all(color: cs.outline), borderRadius: BorderRadius.circular(6)),
                child: Text(staffSearchKeyHint, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
          ])))))));
  }
}

/// Wrap the staff panel in this so Ctrl + K (⌘ + K on a Mac) opens the search from anywhere.
class StaffSearchShortcuts extends StatefulWidget {
  final Widget child;
  const StaffSearchShortcuts({super.key, required this.child});
  @override
  State<StaffSearchShortcuts> createState() => _StaffSearchShortcutsState();
}

class _StaffSearchShortcutsState extends State<StaffSearchShortcuts> {
  @override
  void initState() { super.initState(); HardwareKeyboard.instance.addHandler(_onKey); }
  @override
  void dispose() { HardwareKeyboard.instance.removeHandler(_onKey); super.dispose(); }
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.keyK) return false;
    final k = HardwareKeyboard.instance;
    if (!(k.isControlPressed || k.isMetaPressed) || k.isAltPressed || k.isShiftPressed) return false;
    if (!mounted || _searchOpen) return _searchOpen;
    showStaffSearch(context);
    return true;
  }
  @override
  Widget build(BuildContext context) => widget.child;
}

bool _searchOpen = false;

/// Opens the search over the current page.
Future<void> showStaffSearch(BuildContext context) async {
  if (_searchOpen) return;
  _searchOpen = true;
  try {
    final picked = await showGeneralDialog<Map<String, dynamic>>(
      context: context, barrierDismissible: true, barrierLabel: 'Close search', barrierColor: Colors.black.withValues(alpha: .35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (c, _, __) => staffTheme(c, const _SearchPanel()),
      transitionBuilder: (_, a, __, child) {
        final v = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: v, child: SlideTransition(position: Tween(begin: const Offset(0, -.03), end: Offset.zero).animate(v), child: child));
      });
    if (picked == null || !context.mounted) return;
    if (picked['page'] != null) { GoRouter.of(context).go(picked['page'] as String); return; }   // a page of the app
    final s = ProviderScope.containerOf(context, listen: false).read(sessionProvider).value;
    if (s != null && _recordRoles.any(s.hasRole)) {
      await openStudentRecord(context, picked['id'] as String);   // the full record, as on the Students page
    } else {
      await _showProfile(context, picked);                       // teachers: the short profile of a student in their class
    }
  } finally {
    _searchOpen = false;
  }
}

class _SearchPanel extends StatefulWidget {
  const _SearchPanel();
  @override
  State<_SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<_SearchPanel> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = const [];
  bool _busy = false; String? _error; int _hi = 0; int _ask = 0; String _asked = '';
  List<(StaffItem, String)> _pages = const [];   // pages of the app that match (page, name shown)
  int get _count => _pages.length + _rows.length;

  /// Pages this person can open whose name or everyday words match what was typed.
  List<(StaffItem, String)> _findPages(String q) {
    final c = ProviderScope.containerOf(context, listen: false);
    final s = c.read(sessionProvider).value; if (s == null) return const [];
    final set = c.read(appSettingsProvider).value;
    final words = q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final out = <(StaffItem, String)>[];
    for (final m in [...staffMenu, ...staffSubPages]) {
      if (m.path == '/staff/marks-status' || !staffCanOpen(s, set, m.path)) continue;
      final hub = staffHubOf[m.path];
      if (hub != null && hub != '/staff' && !staffCanOpen(s, set, hub)) continue;
      final parent = hub == null || hub == '/staff' ? null : staffMenu.where((x) => x.path == hub).firstOrNull?.label;
      final name = parent == null ? m.label : '$parent · ${m.label}';
      final hay = '$name ${_pageWords[m.path] ?? ''}'.toLowerCase();
      if (words.every(hay.contains)) out.add((m, name));
    }
    out.sort((a, b) => (a.$2.toLowerCase().startsWith(words.first) ? 0 : 1).compareTo(b.$2.toLowerCase().startsWith(words.first) ? 0 : 1));
    return out.take(4).toList();
  }

  @override
  void dispose() { _debounce?.cancel(); _text.dispose(); _focus.dispose(); _scroll.dispose(); super.dispose(); }

  void _changed(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) { setState(() { _rows = const []; _pages = const []; _busy = false; _error = null; _asked = ''; }); return; }
    setState(() { _pages = _findPages(v.trim()); _hi = 0; });
    _debounce = Timer(const Duration(milliseconds: 250), () => _run(v.trim()));
  }

  Future<void> _run(String q) async {
    final my = ++_ask;
    setState(() => _busy = true);
    try {
      final r = await db.rpc('staff_quick_search', params: {'p_q': q});
      if (!mounted || my != _ask) return;
      setState(() { _rows = [for (final x in (r as List? ?? const [])) Map<String, dynamic>.from(x as Map)]; _hi = 0; _busy = false; _error = null; _asked = q; });
    } catch (e) {
      if (!mounted || my != _ask) return;
      setState(() { _busy = false; _error = 'Could not search just now. Please try again.'; });
    }
  }

  void _move(int d) {
    if (_count == 0) return;
    setState(() => _hi = (_hi + d) % _count);
    if (_scroll.hasClients) {
      const rowH = 64.0;
      final top = _hi * rowH, view = _scroll.position.viewportDimension;
      if (top < _scroll.offset) _scroll.jumpTo(top);
      if (top + rowH > _scroll.offset + view) _scroll.jumpTo(top + rowH - view);
    }
  }

  void _choose(int i) {
    if (i < 0 || i >= _count) return;
    if (i < _pages.length) { Navigator.of(context).pop(<String, dynamic>{'page': _pages[i].$1.path}); return; }
    Navigator.of(context).pop(_rows[i - _pages.length]);
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) { _move(1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowUp) { _move(-1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) { _choose(_hi); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.escape) { Navigator.of(context).pop(); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final w = size.width < 680 ? size.width - 24 : 620.0;
    final q = _text.text.trim();
    Widget body;
    if (_error != null) {
      body = _hint(cs, _error!);
    } else if (q.length < 2) {
      body = _hint(cs, 'Type at least 2 letters. Use ↑ ↓ and Enter to choose, Esc to close.');
    } else if (_count == 0 && !_busy && _asked == q) {
      body = _hint(cs, 'Nothing found for “$q”. Try a student’s name, or a page such as Fees or Attendance.');
    } else {
      body = ListView.builder(controller: _scroll, shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 4), itemCount: _count, itemExtent: 64, itemBuilder: (_, i) {
        if (i < _pages.length) {
          final (m, name) = _pages[i];
          return MouseRegion(onHover: (_) { if (_hi != i) setState(() => _hi = i); }, child: InkWell(onTap: () => _choose(i), child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color: i == _hi ? (dark ? Brand.gold.withValues(alpha: .16) : const Color(0xFFFFF8E6)) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: dark ? Brand.gold.withValues(alpha: .2) : Brand.amberTint, borderRadius: BorderRadius.circular(12)), child: Icon(m.icon, size: 20, color: context.tone(Brand.crimsonDeep))),
              const SizedBox(width: 12),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                Text('Open this page', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ])),
              Icon(i == _hi ? Icons.keyboard_return_rounded : Icons.arrow_forward_rounded, size: 18, color: cs.onSurfaceVariant),
            ]))));
        }
        final r = _rows[i - _pages.length];
        final sub = [
          if (r['class'] != null) r['class'],
          r['admission_no'] ?? '',
          if (r['active'] == false) 'left the school',
          if (r['matched'] != null) r['matched'],
        ].where((x) => '$x'.isNotEmpty).join(' · ');
        return MouseRegion(onHover: (_) { if (_hi != i) setState(() => _hi = i); }, child: InkWell(onTap: () => _choose(i), child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          color: i == _hi ? (dark ? Brand.gold.withValues(alpha: .16) : const Color(0xFFFFF8E6)) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Avatar(_initials('${r['full_name'] ?? ''}'), size: 40, bg: r['active'] == false ? Brand.surface2 : Brand.crimsonTint, fg: r['active'] == false ? Brand.muted : Brand.crimsonDeep),
            const SizedBox(width: 12),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['full_name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ])),
            if (i == _hi) Icon(Icons.keyboard_return_rounded, size: 18, color: cs.onSurfaceVariant),
          ]))));
      });
    }
    return SafeArea(child: Align(alignment: Alignment.topCenter, child: Padding(padding: EdgeInsets.only(top: size.height < 600 ? 12 : 64), child: Material(
      color: cs.surface, elevation: 0, borderRadius: BorderRadius.circular(18), clipBehavior: Clip.antiAlias,
      child: Container(width: w, constraints: BoxConstraints(maxHeight: size.height * .7),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: Brand.gold, width: 2),
            boxShadow: [BoxShadow(color: const Color(0xFFA8822F).withValues(alpha: .35), blurRadius: 30, offset: const Offset(0, 12))]),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Focus(onKeyEvent: _key, child: TextField(
            controller: _text, focusNode: _focus, autofocus: true, onChanged: _changed, onSubmitted: (_) => _choose(_hi), textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: 'A student, a phone or receipt no. — or a page, like Fees',
              prefixIcon: const Icon(Icons.search_rounded, color: Brand.gold),
              suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
              filled: false, border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16)),
          )),
          Divider(height: 1, color: cs.outline),
          Flexible(child: body),
        ]))))));
  }

  Widget _hint(ColorScheme cs, String t) => Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 18), child: Text(t, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)));
}

/// Everyday words that should also find a page.
const _pageWords = <String, String>{
  '/staff/fees': 'receipts payment paid money collection',
  '/staff/fees/record': 'pay cash cheque upi collect receipt new',
  '/staff/fees/dues': 'pending balance defaulters not paid unpaid',
  '/staff/fees/reports': 'day sheet cash book collection month cancelled',
  '/staff/fees/day': 'cash book collection today',
  '/staff/fees/concessions': 'scholarship discount waiver',
  '/staff/students': 'admission record profile new student',
  '/staff/strength': 'count how many boys girls category',
  '/staff/leaving': 'tc transfer leaving left',
  '/staff/certificates': 'tc bonafide transfer certificate letter',
  '/staff/id-cards': 'identity card photo',
  '/staff/staff-ids': 'identity card teacher',
  '/staff/attendance': 'absent present roll call',
  '/staff/attendance/register': 'month absent present sheet',
  '/staff/exams': 'test marks timetable exam',
  '/staff/marks': 'enter marks exam test',
  '/staff/reports': 'report card progress result',
  '/staff/exam-reports': 'marks entered status result toppers grades absent',
  '/staff/promotion': 'promote detained pass next class',
  '/staff/announcements': 'notice circular announcement',
  '/staff/approvals': 'approve pending waiting',
  '/staff/setup': 'classes sections fee heads subjects',
  '/staff/users': 'teacher staff login role add',
  '/staff/settings': 'access who can use switch feature school rules',
  '/staff/rules': 'grading internal parts electives categories report card settings',
  '/staff/sections': 'new sections next year shuffle',
  '/staff/year-end': 'move up new year promotion',
  '/staff/class-logins': 'password login parent student',
  '/staff/transport': 'bus route stop',
  '/staff/toppers': 'honours toppers council houses',
  '/staff/council': 'election vote',
  '/staff/calendar': 'holiday event date',
  '/staff/albums': 'photos gallery',
  '/staff/week': 'last week summary',
  '/staff/me': 'password theme my settings',
};

String _initials(String n) => n.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase();

/// Short profile that slides in from the right (teachers; the office opens the full record instead).
Future<void> _showProfile(BuildContext context, Map<String, dynamic> r) => showGeneralDialog(
  context: context, barrierDismissible: true, barrierLabel: 'Close', barrierColor: Colors.black.withValues(alpha: .25),
  transitionDuration: const Duration(milliseconds: 380),
  pageBuilder: (c, _, __) => staffTheme(c, _Profile(r)),
  transitionBuilder: (_, a, __, child) => SlideTransition(position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child));

class _Profile extends StatelessWidget {
  final Map<String, dynamic> r;
  const _Profile(this.r);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final w = MediaQuery.sizeOf(context).width;
    final phones = '${r['phones'] ?? ''}'.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    Widget card(String label, Widget value) => Container(width: double.infinity, margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outline)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)), const SizedBox(height: 2), value]));
    Text bold(String t) => Text(t, style: const TextStyle(fontWeight: FontWeight.w800));
    return Align(alignment: Alignment.centerRight, child: Material(color: cs.surface, elevation: 12, child: SizedBox(width: w < 420 ? w : 360, height: double.infinity, child: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Avatar(_initials('${r['full_name'] ?? ''}'), size: 54, bg: Brand.violet, fg: Colors.white),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r['full_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text([if (r['class'] != null) r['class'], if (r['roll_no'] != null) 'Roll ${r['roll_no']}', r['admission_no'] ?? ''].join(' · '), style: TextStyle(color: cs.onSurfaceVariant)),
        ])),
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded), tooltip: 'Close'),
      ]),
      const SizedBox(height: 6),
      if (r['father_name'] != null) card('Father', bold('${r['father_name']}')),
      if (r['mother_name'] != null) card('Mother', bold('${r['mother_name']}')),
      if (phones.isNotEmpty) card('Family phone', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final p in phones) InkWell(onTap: () => launchUrl(Uri.parse('tel:${p.replaceAll(RegExp(r'[^0-9+]'), '')}')), child: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
          Expanded(child: bold(p)), Icon(Icons.call_rounded, size: 18, color: context.tone(Brand.green)),
        ]))),
      ])),
      if (r['house'] != null || r['blood_group'] != null) card('House · Blood group', bold([r['house'] ?? '—', r['blood_group'] ?? '—'].join(' · '))),
      if (r['bus'] != null) card('Transport', bold('${r['bus']}')),
    ])))));
  }
}
