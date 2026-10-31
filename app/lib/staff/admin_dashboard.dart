import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/school_docs.dart' show openMonthlyReport;
import '../core/theme.dart';
import '../widgets/common.dart';
import 'staff_data.dart';
import 'staff_shell.dart';
import '../widgets/royal_extras.dart' show CountUpText, GoldLoading;

/// First screen for the IT admin, Principal and Vice Principal: the whole school at a glance.
/// Everything comes from one database call (admin_dashboard) and refreshes every minute.
/// Private chats stay private: only counts are shown, never message text.

bool isSchoolAdmin(Session s) => s.hasRole('it_admin') || s.hasRole('principal') || s.hasRole('vice_principal');

final adminDashProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
    Map<String, dynamic>.from(await db.rpc('admin_dashboard') as Map));

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
  void initState() { super.initState(); tick = Timer.periodic(const Duration(seconds: 60), (_) => ref.invalidate(adminDashProvider)); }
  @override
  void dispose() { tick?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    final dash = ref.watch(adminDashProvider);
    final cs = Theme.of(context).colorScheme;
    final h = DateTime.now().hour;
    final greet = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
    return StaffPage(
      title: '$greet${s.staff?['name'] != null ? ', ${s.staff!['name']}' : ''}',
      subtitle: '${DateFormat('EEEE d MMMM yyyy').format(DateTime.now())} · the whole school at a glance${dash.value?['generated_at'] != null ? ' · updated ${DateFormat('h:mm a').format(DateTime.parse(dash.value!['generated_at']).toLocal())}' : ''}',
      actions: [
        FilledButton.icon(onPressed: () => _monthly(context), icon: const Icon(Icons.picture_as_pdf_rounded, size: 18), label: const Text('Monthly report')),
        OutlinedButton.icon(onPressed: () { ref.invalidate(adminDashProvider); ref.invalidate(_adoptionProvider); }, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
      ],
      body: dash.when(
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator())),
        error: (e, _) => Panel(child: Text('Could not load the dashboard: $e\nIf this says “function admin_dashboard does not exist”, the database step of the update has not been run yet.', style: const TextStyle(color: Brand.crimsonDeep))),
        data: (d) => _body(context, d, cs),
      ),
    );
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

  Widget _body(BuildContext context, Map<String, dynamic> d, ColorScheme cs) {
    final fam = Map<String, dynamic>.from(d['families'] ?? {});
    final fees = Map<String, dynamic>.from(d['fees'] ?? {});
    final bus = Map<String, dynamic>.from(d['buses'] ?? {});
    final att = Map<String, dynamic>.from(d['attention'] ?? {});
    final tch = Map<String, dynamic>.from(d['teaching'] ?? {});
    final hl = Map<String, dynamic>.from(d['health'] ?? {});
    final students = _i(fam['students']), signed = _i(fam['signed_in']);
    final running = List<Map<String, dynamic>>.from(bus['running'] ?? const []);
    final idle = List<String>.from(bus['idle'] ?? const []);
    final attention = _i(att['leave_pending']) + _i(att['feedback_new']) + _i(att['messages_late']);

    final tiles = <Widget>[
      _Tile('Families on the app', '$signed', sub: students == 0 ? 'no students yet' : '${(signed * 100 / students).round()}% of $students students · ${_i(fam['new_week'])} new this week',
          icon: Icons.family_restroom_rounded, color: Brand.blue, onTap: () => context.go('/staff/students')),
      _Tile('Opened the app today', '${_i(fam['opened_today'])}', sub: 'students’ families · ${_i(fam['staff_today'])} of ${_i(fam['staff_total'])} staff',
          icon: Icons.phone_android_rounded, color: Brand.violet),
      _Tile('Fees collected today', _inrShort(fees['today_amount'] ?? 0), sub: '${_i(fees['today_count'])} payments · ${_i(fees['today_online'])} online · month ${_inrShort(fees['month_amount'] ?? 0)}',
          icon: Icons.account_balance_wallet_rounded, color: Brand.green, onTap: () => context.go('/staff/fees')),
      _Tile('Overdue fees', _inrShort(fees['overdue_amount'] ?? 0), sub: '${_i(fees['overdue_students'])} students · reminders go automatically',
          icon: Icons.warning_amber_rounded, color: Brand.crimson, onTap: () => context.go('/staff/fees')),
      _Tile('Buses live now', '${running.length} / ${_i(bus['routes'])}', sub: running.isEmpty ? 'no trip running · ${_i(bus['trips_today'])} trips today' : running.map((r) => r['route']).join(', '),
          icon: Icons.directions_bus_rounded, color: Brand.amber, onTap: () => context.go('/staff/transport')),
      _Tile('Needs attention', '$attention', sub: '${_i(att['leave_pending'])} leave · ${_i(att['feedback_new'])} feedback · ${_i(att['messages_late'])} chats waiting > 24 h',
          icon: Icons.notifications_active_rounded, color: attention > 0 ? Brand.crimson : Brand.green, onTap: () => context.go(_i(att['leave_pending']) > 0 ? '/staff/leave' : _i(att['feedback_new']) > 0 ? '/staff/feedback' : '/staff/messages')),
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
          panel(const _AdoptionPanel()),
          panel(_notices(context, d, cs)),
          panel(_teaching(context, tch, cs)),
          panel(_today(context, d, running, idle, cs)),
          panel(_health(context, hl, fam, cs)),
          panel(const _ViewAsFamily()),
          panel(_activity(context, d, cs)),
        ]),
        Text('Private chats stay private: the dashboard shows counts only, never message text.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]);
    });
  }

  Widget _notices(BuildContext context, Map<String, dynamic> d, ColorScheme cs) {
    final list = List<Map<String, dynamic>>.from(d['notices'] ?? const []);
    return Panel(title: 'Notices read — last 7 days', trailing: TextButton(onPressed: () => context.go('/staff/announcements'), child: const Text('All notices')), child: list.isEmpty
        ? Text('No notices sent in the last 7 days.', style: TextStyle(color: cs.onSurfaceVariant))
        : Column(children: [for (final n in list) Builder(builder: (_) {
            final aud = _i(n['audience']), seen = _i(n['seen']);
            final p = aud == 0 ? 0.0 : (seen / aud).clamp(0.0, 1.0);
            return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${n['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                Text('${(p * 100).round()}%', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(p >= .8 ? Brand.green : p >= .5 ? Brand.amber : Brand.crimson))),
              ]),
              const SizedBox(height: 4),
              ClipRRect(borderRadius: BorderRadius.circular(9), child: LinearProgressIndicator(value: p, minHeight: 8, backgroundColor: cs.surfaceContainerHighest, color: context.tone(p >= .8 ? Brand.green : p >= .5 ? Brand.amber : Brand.crimson))),
              Text('$seen of $aud families opened it · ${_ago(n['sent_at'])}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ]));
          })]));
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

  Widget _health(BuildContext context, Map<String, dynamic> h, Map<String, dynamic> fam, ColorScheme cs) {
    final queue = _i(h['queue']), oldest = _i(h['queue_oldest_min']);
    final jobs = List<Map<String, dynamic>>.from(h['jobs'] ?? const []);
    final jobsOk = jobs.every((j) => j['status'] == null || j['status'] == 'succeeded');
    final files = h['files_mb'] == null ? null : _i(h['files_mb']);
    final dbMb = _i(h['db_mb']);
    Widget ok(bool good, String text) => Pill(text, fg: good ? Brand.green : Brand.crimsonDeep, bg: good ? Brand.greenTint : Brand.crimsonTint);
    return Panel(title: 'System health', child: Column(children: [
      Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Expanded(child: Text('Server & database', style: TextStyle(color: cs.onSurfaceVariant))), ok(true, 'Working')])),
      Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Expanded(child: Text('Phone notifications', style: TextStyle(color: cs.onSurfaceVariant))),
        ok(queue == 0 || oldest < 5, queue > 0 && oldest >= 5 ? '$queue waiting ($oldest min)' : '${_i(h['sent_hour'])} in the last hour · ${_i(h['sent_today'])} today')])),
      Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [Expanded(child: Text('Night jobs (fees, clean-up, notices)', style: TextStyle(color: cs.onSurfaceVariant))), ok(jobsOk, jobsOk ? 'All OK' : 'Check')])),
      _row('Phones getting notifications', '${_i(fam['push_phones'])}', cs),
      _row('Database used', '$dbMb MB of 500 MB${dbMb > 400 ? ' — time for Pro' : ''}', cs, color: dbMb > 400 ? context.tone(Brand.crimson) : null),
      if (files != null) _row('Files & photos stored', '$files MB of 1,024 MB${files > 800 ? ' — time for Pro' : ''}', cs, color: files > 800 ? context.tone(Brand.crimson) : null),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('https://console.firebase.google.com/project/royale-connect/crashlytics'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.bug_report_outlined, size: 18), label: const Text('App crash reports')),
        OutlinedButton.icon(onPressed: () => launchUrl(Uri.parse('https://github.com/royaleconnect/royaleconnect/actions'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.cloud_done_outlined, size: 18), label: const Text('Backups & builds')),
      ]),
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
