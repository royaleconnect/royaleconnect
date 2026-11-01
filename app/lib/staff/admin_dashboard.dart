import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/school_docs.dart' show openMonthlyReport;
import '../core/theme.dart';
import '../widgets/common.dart';
import 'staff_data.dart';
import 'staff_shell.dart';
import '../widgets/royal_extras.dart' show CountUpText, GoldLoading, FestiveBanner, FestiveSky;
import 'health_dot.dart';
import 'year_end.dart';
import 'password_requests.dart' show PasswordRequestsCard;
import '../widgets/staff_birthday.dart';

/// First screen for the IT admin, Principal and Vice Principal: the whole school at a glance.
/// Kept calm on purpose: six numbers, then Enrollment, Data checker and Leaving check, then the day.
/// Data comes from admin_dashboard (fees, app use, buses, calendar) and admin_overview (students, attendance,
/// notices read, data checks) and refreshes every minute. The health dot sits in the header.
/// Private chats stay private: only counts are shown, never message text.

bool isSchoolAdmin(Session s) => s.hasRole('it_admin') || s.hasRole('principal') || s.hasRole('vice_principal');

final adminDashProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
    Map<String, dynamic>.from(await db.rpc('admin_dashboard') as Map));

/// Students, attendance, notices read and the data checks (null until the database step of this update is run).
final adminOverviewProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  try {
    return Map<String, dynamic>.from(await db.rpc('admin_overview') as Map);
  } catch (_) {
    return null;
  }
});

String _inrShort(num v) {
  if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)} L';
  return inr(v);
}
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String _ago(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.now().difference(DateTime.parse(iso).toLocal());
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return DateFormat('d MMM, h:mm a').format(DateTime.parse(iso).toLocal());
}

const _actionLabels = {
  'calendar.insert': 'added to the calendar', 'calendar.update': 'changed a calendar item', 'calendar.delete': 'removed a calendar item', 'calendar.notify': 'told families about a calendar item',
  'announcement.remind': 'sent a notice reminder', 'password.reset': 'printed a password slip', 'password.reset.staff': 'reset a staff password', 'password.change': 'changed their password',
  'password.change.staff': 'changed their password', 'crew.account': 'made a bus crew login', 'view_as.family': 'viewed a family’s app (read-only)', 'session.revoke_all': 'signed out all phones of a student',
  'login.staff': 'signed in', 'login.crew': 'signed in (bus)', 'login.student': 'signed in', 'payment.record': 'recorded a payment', 'mark.edit': 'changed marks after publishing',
};

class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});
  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends ConsumerState<AdminDashboard> {
  Timer? tick;
  @override
  void initState() { super.initState(); tick = Timer.periodic(const Duration(seconds: 60), (_) { ref.invalidate(adminDashProvider); ref.invalidate(adminOverviewProvider); }); }
  @override
  void dispose() { tick?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    final dash = ref.watch(adminDashProvider);
    final cs = Theme.of(context).colorScheme;
    final h = DateTime.now().hour;
    final greet = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
    return FestiveSky(child: StaffPage(
      title: '$greet${s.staff?['name'] != null ? ', ${s.staff!['name']}' : ''}',
      subtitle: '${DateFormat('EEEE d MMMM yyyy').format(DateTime.now())} · the whole school at a glance${dash.value?['generated_at'] != null ? ' · updated ${DateFormat('h:mm a').format(DateTime.parse(dash.value!['generated_at']).toLocal())}' : ''}',
      actions: [
        const HealthDot(),
        FilledButton.icon(onPressed: () => _monthly(context), icon: const Icon(Icons.picture_as_pdf_rounded, size: 18), label: const Text('Monthly report')),
        OutlinedButton.icon(onPressed: () { ref.invalidate(adminDashProvider); ref.invalidate(adminOverviewProvider); ref.invalidate(_adoptionProvider); ref.invalidate(yearEndProvider); }, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
      ],
      body: dash.when(
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator())),
        error: (e, _) => Panel(child: Text('Could not load the dashboard: $e\nIf this says “function admin_dashboard does not exist”, the database step of the update has not been run yet.', style: const TextStyle(color: Brand.crimsonDeep))),
        data: (d) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const FestiveBanner(), const StaffBirthdayLine(), const PasswordRequestsCard(), const YearEndCard(), _body(context, d, ref.watch(adminOverviewProvider).value, cs), const StaffBirthdaysPanel()]),
      ),
    ));
  }

  Future<void> _monthly(BuildContext context) async {
    final now = DateTime.now();
    var month = DateTime(now.year, now.month, 1);
    final hl = TextEditingController();
    final go = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: const Text('Monthly report'),
      content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var k = 0; k < 4; k++) Builder(builder: (_) {
            final m = DateTime(now.year, now.month - k, 1);
            return ChoiceChip(label: Text(DateFormat('MMMM yyyy').format(m)), selected: m == month, onSelected: (_) => set(() => month = m));
          }),
        ]),
        const SizedBox(height: 14),
        TextField(controller: hl, minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Highlights of the month (optional)', hintText: 'e.g. Science expo · Inter-school football winners')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Make the PDF'))],
    )));
    if (go == true && context.mounted) openMonthlyReport(context, month, hl.text);
  }

  Widget _body(BuildContext context, Map<String, dynamic> d, Map<String, dynamic>? o, ColorScheme cs) {
    final fam = Map<String, dynamic>.from(d['families'] ?? {});
    final fees = Map<String, dynamic>.from(d['fees'] ?? {});
    final bus = Map<String, dynamic>.from(d['buses'] ?? {});
    final tch = Map<String, dynamic>.from(d['teaching'] ?? {});
    final running = List<Map<String, dynamic>>.from(bus['running'] ?? const []);
    final idle = List<String>.from(bus['idle'] ?? const []);
    final att = Map<String, dynamic>.from(o?['attendance'] ?? {});
    final nts = Map<String, dynamic>.from(o?['notices'] ?? {});
    final grades = List<Map<String, dynamic>>.from(o?['grades'] ?? const []);
    final students = o == null ? _i(fam['students']) : _i(o['students']);
    final seats = grades.fold<int>(0, (a, g) => a + _i(g['seats']));
    final marked = _i(att['marked']), present = _i(att['present']);
    final aud = _i(nts['audience']), seen = _i(nts['seen']);

    final tiles = <Widget>[
      _Tile('Students', '$students', sub: o == null ? 'in the current classes' : '${seats > 0 ? 'of $seats seats · ' : ''}${_i(o['new_this_year'])} new this year · ${_i(o['left_this_year'])} left',
          icon: Icons.school_rounded, color: Brand.blue, onTap: () => context.go('/staff/students')),
      _Tile('Present today', marked == 0 ? '—' : '${(present * 100 / marked).round()}%',
          sub: marked == 0 ? 'attendance not taken yet today' : '${_i(att['absent'])} absent · ${_i(att['sections_marked'])} of ${_i(att['sections'])} classes marked',
          icon: Icons.fact_check_rounded, color: Brand.green, onTap: () => context.go('/staff/attendance')),
      _Tile('Fees collected today', _inrShort(fees['today_amount'] ?? 0), sub: '${_i(fees['today_count'])} payments · this month ${_inrShort(fees['month_amount'] ?? 0)}',
          icon: Icons.account_balance_wallet_rounded, color: Brand.green, onTap: () => context.go('/staff/fees')),
      _Tile('Dues', _inrShort(fees['overdue_amount'] ?? 0), sub: '${_i(fees['overdue_students'])} students · reminders go by themselves',
          icon: Icons.warning_amber_rounded, color: Brand.crimson, onTap: () => context.go('/staff/fees')),
      _Tile('Opened the app today', '${_i(fam['opened_today'])}', sub: 'families · ${_i(fam['staff_today'])} of ${_i(fam['staff_total'])} staff',
          icon: Icons.phone_android_rounded, color: Brand.violet),
      _Tile('Notices read', aud == 0 ? '—' : '${(seen * 100 / aud).clamp(0, 100).round()}%',
          sub: _i(nts['sent']) == 0 ? 'no notices in the last 7 days' : '${_i(nts['sent'])} notice${_i(nts['sent']) == 1 ? '' : 's'} in the last 7 days',
          icon: Icons.campaign_rounded, color: Brand.amber, onTap: () => context.go('/staff/announcements')),
    ];

    return LayoutBuilder(builder: (_, c) {
      final w = c.maxWidth;
      final cols = w >= 1000 ? 3 : w >= 640 ? 2 : 1;
      final tileW = (w - 12 * (cols - 1)) / cols;
      final panelCols = w >= 900 ? 2 : 1;
      final panelW = (w - 14 * (panelCols - 1)) / panelCols;
      Widget panel(Widget p) => SizedBox(width: panelW, child: p);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 12, runSpacing: 12, children: [for (final t in tiles) SizedBox(width: tileW, child: t)]),
        const SizedBox(height: 14),
        Wrap(spacing: 14, children: [
          if (o != null) panel(_enrollment(context, o, cs)),
          if (o != null) panel(Column(children: [_dataChecker(context, o, cs), _leaving(context, o, cs)])),
          panel(_today(context, d, running, idle, cs)),
          panel(_teaching(context, tch, cs)),
          panel(const _AdoptionPanel()),
          panel(const _ViewAsFamily()),
          panel(_activity(context, d, cs)),
        ]),
        Text('Private chats stay private: the dashboard shows counts only, never message text.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]);
    });
  }

  // ---------------------------------------------------------------- Enrollment
  Widget _enrollment(BuildContext context, Map<String, dynamic> o, ColorScheme cs) {
    final grades = List<Map<String, dynamic>>.from(o['grades'] ?? const []);
    final secs = List<Map<String, dynamic>>.from(o['sections'] ?? const []);
    return Panel(title: 'Enrollment', trailing: TextButton(onPressed: () => context.go('/staff/students'), child: const Text('Students')), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (grades.isEmpty) Text('No students in the current classes yet.', style: TextStyle(color: cs.onSurfaceVariant)),
      for (final g in grades) Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 52, child: Text('${g['code']}', style: const TextStyle(fontWeight: FontWeight.w800))),
        Expanded(child: Text([for (final s in secs) if (s['grade'] == g['code']) '${s['section']} ${s['n']}'].join(' · '), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
        Text(g['seats'] != null && _i(g['seats']) > 0 ? '${g['n']} / ${g['seats']}' : '${g['n']}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ])),
      const Divider(height: 20),
      _row('New admissions this year', '${_i(o['new_this_year'])}', cs),
      _row('Left this year', '${_i(o['left_this_year'])}', cs),
    ]));
  }

  // ---------------------------------------------------------------- Data checker
  static const _checks = [
    ('dob', 'Students without a date of birth', false), ('blood_group', 'Students without a blood group', false), ('photo', 'Students without a photo', false),
    ('phone', 'Students without a parent phone', false), ('house', 'Students without a house', false),
    ('staff_phone', 'Staff without a phone number', true), ('no_class_teacher', 'Classes without a class teacher', true),
  ];

  Widget _dataChecker(BuildContext context, Map<String, dynamic> o, ColorScheme cs) {
    final c = Map<String, dynamic>.from(o['checks'] ?? {});
    final open = _checks.where((k) => _i(c[k.$1]) > 0).length;
    return Panel(title: 'Data checker', trailing: Pill(open == 0 ? 'All complete' : '$open to fill in', fg: open == 0 ? Brand.green : Brand.amber, bg: open == 0 ? Brand.greenTint : Brand.amberTint),
      child: Column(children: [for (final k in _checks) _checkRow(context, k.$1, k.$2, _i(c[k.$1]), cs)]));
  }

  Widget _checkRow(BuildContext context, String kind, String label, int n, ColorScheme cs) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
    Icon(n == 0 ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 18, color: context.tone(n == 0 ? Brand.green : Brand.amber)),
    const SizedBox(width: 8),
    Expanded(child: Text(label, style: TextStyle(color: n == 0 ? cs.onSurfaceVariant : cs.onSurface))),
    Text('$n', style: TextStyle(fontWeight: FontWeight.w800, color: n == 0 ? cs.onSurfaceVariant : context.tone(Brand.amber))),
    SizedBox(width: 64, child: n == 0 ? null : TextButton(onPressed: () => _showList(context, kind, label), child: const Text('Show'))),
  ]));

  // ---------------------------------------------------------------- Leaving check
  Widget _leaving(BuildContext context, Map<String, dynamic> o, ColorScheme cs) {
    final n = _i(o['certificates_pending']);
    return Panel(title: 'Leaving check', child: Row(children: [
      Icon(n == 0 ? Icons.verified_rounded : Icons.assignment_late_rounded, color: context.tone(n == 0 ? Brand.green : Brand.crimson)),
      const SizedBox(width: 10),
      Expanded(child: Text(n == 0 ? 'Everyone who left has a TC and a conduct certificate uploaded.' : '$n student${n == 1 ? '' : 's'} left without a TC or conduct certificate uploaded.',
          style: TextStyle(color: n == 0 ? cs.onSurfaceVariant : cs.onSurface))),
      if (n > 0) TextButton(onPressed: () => _showList(context, 'certificates', 'Left without a TC or conduct certificate'), child: const Text('Show')),
    ]));
  }

  void _showList(BuildContext context, String kind, String title) {
    final staffList = kind == 'staff_phone' || kind == 'no_class_teacher';
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 480, height: 420, child: FutureBuilder(
        future: db.rpc('data_check_list', params: {'p_kind': kind}),
        builder: (_, snap) {
          if (snap.hasError) return Text('Could not load: ${snap.error}');
          if (!snap.hasData) return const GoldLoading();
          final rows = [for (final r in snap.data as List) Map<String, dynamic>.from(r as Map)];
          if (rows.isEmpty) return const Center(child: Text('Nothing missing now ✓'));
          return ListView.separated(itemCount: rows.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (_, i) => ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            title: Text('${rows[i]['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${rows[i]['info'] ?? ''}'),
          ));
        },
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')),
        FilledButton(onPressed: () { Navigator.pop(c); context.go(kind == 'staff_phone' ? '/staff/users' : staffList ? '/staff/setup' : '/staff/students'); },
            child: Text(kind == 'staff_phone' ? 'Open Staff' : staffList ? 'Open Classes' : 'Open Students')),
      ],
    ));
  }

  Widget _row(String k, String v, ColorScheme cs, {Color? color}) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
    Expanded(child: Text(k, style: TextStyle(color: cs.onSurfaceVariant))),
    Text(v, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
  ]));

  Widget _teaching(BuildContext context, Map<String, dynamic> t, ColorScheme cs) {
    final secs = _i(t['sections']), diary = _i(t['diary_sections_today']);
    final chats = _i(t['chats_week']), ans = _i(t['chats_answered']);
    final rc = List<Map<String, dynamic>>.from(t['report_cards'] ?? const []);
    return Panel(title: 'Teaching today', child: Column(children: [
      _row('Class diary posted', '$diary of $secs sections · ${_i(t['diary_posts_today'])} notes', cs, color: secs > 0 && diary >= secs * .8 ? context.tone(Brand.green) : null),
      _row('Parent chats answered (7 days)', chats == 0 ? '—' : '${(ans * 100 / chats).round()}% of $chats', cs, color: chats > 0 && ans / chats >= .9 ? context.tone(Brand.green) : null),
      for (final r in rc) _row('Report cards · ${r['term']}', '${_i(r['published'])} of ${_i(r['total'])} published', cs),
      if (rc.isEmpty) _row('Report cards', 'none started yet', cs),
    ]));
  }

  Widget _today(BuildContext context, Map<String, dynamic> d, List<Map<String, dynamic>> running, List<String> idle, ColorScheme cs) {
    final cal = List<Map<String, dynamic>>.from(d['calendar'] ?? const []);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return Panel(title: 'Today & tomorrow', trailing: TextButton(onPressed: () => context.go('/staff/calendar'), child: const Text('Calendar')), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (cal.isEmpty) Text('Nothing on the calendar today or tomorrow.', style: TextStyle(color: cs.onSurfaceVariant)),
      for (final e in cal) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
        Pill((e['starts_on'] as String).compareTo(today) <= 0 ? 'Today' : 'Tomorrow', fg: Brand.crimsonDeep, bg: Brand.crimsonTint),
        const SizedBox(width: 8),
        Expanded(child: Text('${e['title']}${(e['grades'] as List?)?.isNotEmpty == true ? ' · ${(e['grades'] as List).join(', ')}' : ''}', style: TextStyle(fontWeight: e['kind'] == 'holiday' ? FontWeight.w800 : FontWeight.w600))),
      ])),
      const Divider(height: 20),
      Text('Buses', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant, fontSize: 12)),
      if (running.isEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('No trip running right now.', style: TextStyle(color: cs.onSurfaceVariant))),
      for (final r in running) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
        Icon(Icons.circle, size: 10, color: r['last_fix_at'] != null && DateTime.now().difference(DateTime.parse(r['last_fix_at']).toLocal()).inSeconds < 60 ? Brand.green : Brand.amber),
        const SizedBox(width: 8),
        Expanded(child: Text('${r['route']} · ${'${r['kind']}'.startsWith('morning') ? 'morning' : 'afternoon'}${r['next_stop'] != null ? ' · next: ${r['next_stop']}' : ''}')),
        Text(_ago(r['last_fix_at']), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ])),
      if (running.isNotEmpty && idle.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Not started: ${idle.join(', ')}', style: TextStyle(fontSize: 12, color: context.tone(Brand.amber)))),
    ]));
  }

  Widget _activity(BuildContext context, Map<String, dynamic> d, ColorScheme cs) {
    final list = List<Map<String, dynamic>>.from(d['activity'] ?? const []).where((a) => !'${a['action']}'.startsWith('login.')).take(8).toList();
    return Panel(title: 'Recent activity', child: list.isEmpty
        ? Text('Nothing yet.', style: TextStyle(color: cs.onSurfaceVariant))
        : Column(children: [for (final a in list) Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 74, child: Text(_ago(a['at']), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant))),
            Expanded(child: Text('${a['who']} ${_actionLabels[a['action']] ?? a['action']}${a['detail'] is Map && (a['detail'] as Map)['title'] != null ? ' · “${(a['detail'] as Map)['title']}”' : ''}', style: const TextStyle(fontSize: 13))),
          ]))]));
  }
}

class _Tile extends StatelessWidget {
  final String label, value, sub; final IconData icon; final Color color; final VoidCallback? onTap;
  const _Tile(this.label, this.value, {required this.sub, required this.icon, required this.color, this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(color: cs.surface, borderRadius: BorderRadius.circular(18), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outline.withValues(alpha: .6))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: context.tone(color).withValues(alpha: .14), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: context.tone(color))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .4, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          CountUpText(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: context.tone(color))),
          Text(sub, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ])),
        if (onTap != null) Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      ]),
    )));
  }
}

/// Search any student and open exactly what their family sees — read-only; the database refuses every change.
class _ViewAsFamily extends ConsumerStatefulWidget {
  const _ViewAsFamily();
  @override
  ConsumerState<_ViewAsFamily> createState() => _ViewAsFamilyState();
}

class _ViewAsFamilyState extends ConsumerState<_ViewAsFamily> {
  String q = ''; bool busy = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final res = ref.watch(studentSearchProvider(q));
    return Panel(title: 'View as family', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Student name or admission number', isDense: true)),
      const SizedBox(height: 6),
      if (q.trim().length >= 2) res.when(
        loading: () => const Padding(padding: EdgeInsets.all(12), child: const GoldLoading()),
        error: (e, _) => Text('$e'),
        data: (rows) => rows.isEmpty ? Padding(padding: const EdgeInsets.all(8), child: Text('No student found.', style: TextStyle(color: cs.onSurfaceVariant))) : Column(children: [
          for (final st in rows.take(6)) ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            title: Text('${st['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${st['admission_no']}${(st['enrolment'] as List?)?.isNotEmpty == true ? ' · ${st['enrolment'][0]['section']?['grade']?['code']}-${st['enrolment'][0]['section']?['name']}' : ''}'),
            trailing: FilledButton(onPressed: busy ? null : () async {
              setState(() => busy = true);
              try {
                await ref.read(sessionProvider.notifier).viewAsFamily(st['id']);
                if (context.mounted) context.go('/');
              } catch (e) {
                if (context.mounted) toast(context, 'Could not open: $e');
              }
              if (mounted) setState(() => busy = false);
            }, child: const Text('View')),
          ),
        ]),
      ),
      Padding(padding: const EdgeInsets.only(top: 6), child: Text('Opens the parent app for that child, read-only, for 2 hours. Nothing can be sent, changed or paid, and it does not count as the family reading notices. Every use is recorded.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
    ]));
  }
}


// ------------------------------------------------------------------ switching from MyClassBoard
final _adoptionProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
    Map<String, dynamic>.from((await db.rpc('app_adoption')) as Map? ?? const {}));

class _AdoptionPanel extends ConsumerWidget {
  const _AdoptionPanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Panel(title: 'Switching from MCB', child: ref.watch(_adoptionProvider).when(
      loading: () => const SizedBox(height: 80, child: const GoldLoading()),
      error: (e, _) => Text('$e', style: const TextStyle(color: Brand.crimsonDeep)),
      data: (a) {
        final total = _i(a['total']), using = _i(a['using']);
        final pct = total == 0 ? 0.0 : using / total;
        final grades = List<Map<String, dynamic>>.from(a['grades'] ?? const []);
        Widget bar(double v, {double h = 10}) => ClipRRect(borderRadius: BorderRadius.circular(9), child: LinearProgressIndicator(value: v, minHeight: h,
            backgroundColor: cs.surfaceContainerHighest, color: v < .6 ? Brand.amber : Brand.green));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Families using Royale Connect', style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8), bar(pct, h: 14), const SizedBox(height: 6),
          Text('$using of $total · ${(pct * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 10),
          for (final g in grades) Builder(builder: (_) {
            final t = _i(g['total']), u = _i(g['using']); final v = t == 0 ? 0.0 : u / t;
            return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
              SizedBox(width: 48, child: Text('${g['code']}', style: const TextStyle(fontWeight: FontWeight.w800))),
              Expanded(child: bar(v)),
              SizedBox(width: 120, child: Text('  ${(v * 100).round()}% · $u/$t${v < .6 ? ' · needs a push' : ''}', style: TextStyle(fontSize: 12, color: v < .6 ? context.tone(Brand.crimsonDeep) : cs.onSurfaceVariant, fontWeight: v < .6 ? FontWeight.w800 : FontWeight.w500))),
            ]));
          }),
          const SizedBox(height: 6),
          Text('Class teachers see the families not using the app yet on their Today page.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]);
      },
    ));
  }
}
