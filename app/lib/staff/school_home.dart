import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_motion.dart' show CountUp, FadeRise;
import '../widgets/royal_extras.dart' show GoldLoading;
import 'office_reports.dart' show ReportTable;
import 'staff_shell.dart';
import 'students_page.dart' show openStudentRecord;

/// The school at a glance — the first page for IT, the Principal, the Vice Principal and the office.
/// Four big numbers, then rows of cards that are always the same height (no empty gaps):
///   Student strength (class by class, with app use) · Latest notice
///   Today & tomorrow · Who is using the app
///   Needs attention · Recent activity
/// Numbers come from office_glance + school_home (and admin_dashboard for the day's teaching and activity).

final glanceProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  ref.cacheFor();
  try { return Map<String, dynamic>.from(await db.rpc('office_glance') as Map); } catch (_) { return null; }
});
final schoolHomeProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  ref.cacheFor();
  try { return Map<String, dynamic>.from(await db.rpc('school_home') as Map); } catch (_) { return null; }
});

num _n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
final _nf = NumberFormat.decimalPattern('en_IN');
String _num(Object? v) => _nf.format(_n(v));
String _inrShort(num v) {
  if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)} L';
  return inr(v);
}

/// What a line in the activity list says, in plain words.
const activityWords = {
  'calendar.insert': 'added to the calendar', 'calendar.update': 'changed a calendar item', 'calendar.delete': 'removed a calendar item', 'calendar.notify': 'told families about a calendar item',
  'announcement.remind': 'sent a notice reminder', 'announcement.urgent': 'sent an urgent notice', 'password.reset': 'printed a password slip', 'password.reset.staff': 'reset a staff password',
  'password.change': 'changed their password', 'password.change.staff': 'changed their password', 'password.first_use_all_staff': 'gave all staff their first password',
  'password.bulk': 'printed password slips for a class', 'crew.account': 'made a transport crew login', 'view_as.family': 'viewed a family’s app (read-only)',
  'session.revoke_all': 'signed out all phones of a student', 'session.revoke_all.self': 'signed out of all their phones', 'payment.record': 'recorded a payment', 'payment.success': 'received a fee payment',
  'mark.edit': 'changed marks', 'attendance.save': 'took attendance', 'bin.restore': 'brought something back from the Bin', 'certificate.issue': 'issued a certificate',
  'certificate.reprint': 'reprinted a certificate', 'council.publish': 'published the Student Council', 'fees.apply': 'set up fees', 'fees.plan': 'changed a fee plan',
  'fees.remind_overdue': 'reminded families about overdue fees', 'fees.remind_one': 'sent a family a fee reminder', 'fees.waived_rte': 'waived RTE fees', 'house.points': 'gave house points',
  'import.students': 'imported students', 'import.staff': 'imported staff', 'import.routes': 'imported transport routes', 'import.paid': 'imported paid fees', 'pin.set': 'set a pickup pin',
  'receipt.cancel_asked': 'asked to cancel a receipt', 'receipt.cancelled': 'cancelled a receipt', 'receipt.cancel_rejected': 'declined a receipt cancellation', 'route.save': 'changed a route',
  'route.stops': 'changed route stops', 'section.plan': 'planned sections', 'section.publish': 'published new sections', 'section.save': 'changed a section', 'staff.active': 'switched a staff member on',
  'staff.add': 'added a staff member', 'staff.dob': 'added a staff birthday', 'staff.edit': 'edited a staff member', 'staff.inactive': 'switched a staff member off', 'student.add': 'added a student',
  'student.back': 'brought a student back', 'student.corrected': 'corrected student details', 'student.correction_asked': 'asked to correct student details', 'student.edit': 'edited student details',
  'student.fee_category': 'changed a fee category', 'student.inactive': 'marked a student inactive', 'student.leaving_asked': 'asked for a student to leave', 'student.left': 'marked a student as left',
  'student.link': 'linked an old admission', 'student.suspended': 'suspended a student', 'student.suspension_ended': 'ended a suspension', 'tc.approved': 'approved a TC', 'tc.asked': 'asked for a TC',
  'tc.declined': 'declined a TC', 'trip.end_by_office': 'ended a bus trip', 'trip.take_over': 'took over a bus trip', 'year.move': 'moved classes to the new year',
  'login.staff': 'signed in', 'login.student': 'signed in', 'login.crew': 'signed in (transport)',
};
String activityLine(String action) => activityWords[action] ?? action.replaceAll('_', ' ').replaceAll('.', ' · ');

/// One row where every card is as tall as the tallest (wide screens); stacked on phones.
Widget evenRow(BuildContext context, List<(int, Widget)> cards) {
  if (isNarrow(context) || MediaQuery.sizeOf(context).width < 1000) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final c in cards) c.$2]);
  return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    for (final (i, c) in cards.indexed) ...[if (i > 0) const SizedBox(width: 16), Expanded(flex: c.$1, child: c.$2)],
  ]));
}

class SchoolHome extends ConsumerWidget {
  /// teaching today, buses and activity (IT / Principal / VP only)
  final Map<String, dynamic>? admin;
  const SchoolHome({super.key, this.admin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(glanceProvider).value;
    final h = ref.watch(schoolHomeProvider).value;
    if (g == null && h == null) {
      return ref.watch(glanceProvider).isLoading ? const SizedBox(height: 160, child: GoldLoading()) : const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    final st = Map<String, dynamic>.from(g?['students'] ?? const {});
    final sf = Map<String, dynamic>.from(g?['staff'] ?? const {});
    final fees = g?['fees'] == null ? null : Map<String, dynamic>.from(g!['fees']);
    final att = Map<String, dynamic>.from(h?['attendance'] ?? const {});
    final marked = _n(att['marked']), present = _n(att['present']);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final kpis = <Widget>[
      _Kpi(icon: Icons.school_rounded, label: 'Students', value: _n(st['total']), extra: Text.rich(TextSpan(children: [
        TextSpan(text: '${_num(st['boys'])} boys', style: TextStyle(color: context.tone(Brand.blue), fontWeight: FontWeight.w800)), const TextSpan(text: '  ·  '),
        TextSpan(text: '${_num(st['girls'])} girls', style: TextStyle(color: context.tone(const Color(0xFFD6407F)), fontWeight: FontWeight.w800)),
        if (_n(st['total']) - _n(st['boys']) - _n(st['girls']) > 0) TextSpan(text: '  ·  ${_num(_n(st['total']) - _n(st['boys']) - _n(st['girls']))} not filled'),
      ]), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
      _Kpi(icon: Icons.fact_check_rounded, label: 'Present today', text: marked == 0 ? '—' : '${(present * 100 / marked).round()}%',
          sub: marked == 0 ? 'attendance not taken yet today' : '${_num(att['sections_marked'])} of ${_num(att['sections'])} classes marked · ${_num(att['absent'])} absent'),
      if (fees != null) _Kpi(icon: Icons.currency_rupee_rounded, label: 'Fees collected', text: _inrShort(_n(fees['collected'])),
          sub: _n(fees['expected']) == 0 ? 'this school year' : 'of ${_inrShort(_n(fees['expected']))} this year · ${(_n(fees['collected']) * 100 / _n(fees['expected'])).round()}%'),
      _Kpi(icon: Icons.groups_rounded, label: 'Staff', value: _n(sf['total']), sub: '${_num(sf['teaching'])} teaching · ${_num(sf['other'])} others'),
    ];
    final per = wide ? kpis.length : 2;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (_, c) {
        final w = (c.maxWidth - (per - 1) * 14) / per;
        return Padding(padding: const EdgeInsets.only(bottom: 16), child: Wrap(spacing: 14, runSpacing: 14, children: [
          for (final (i, k) in kpis.indexed) SizedBox(width: w, child: FadeRise(delayMs: 60 * i, dy: 12, child: k)),
        ]));
      }),
      evenRow(context, [(5, _strength(context, h, st, cs)), (3, _notice(context, g, cs))]),
      evenRow(context, [(5, _today(context, h, cs)), (3, _usage(context, g, cs))]),
      evenRow(context, [(1, _attention(context, h, cs)), if (admin != null) (1, _activity(context, cs))]),
      Text('Private chats stay private — only counts are shown here, never the messages.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
    ]);
  }

  // ---------------------------------------------------------------- Student strength
  Widget _strength(BuildContext context, Map<String, dynamic>? h, Map<String, dynamic> st, ColorScheme cs) {
    final rows = List<Map<String, dynamic>>.from(h?['classes'] ?? const []);
    num tb = 0, tg = 0, tt = 0, tu = 0;
    for (final r in rows) { tb += _n(r['boys']); tg += _n(r['girls']); tt += _n(r['total']); tu += _n(r['using']); }
    Widget bar(num u, num t) => Row(children: [
      SizedBox(width: 70, child: ClipRRect(borderRadius: BorderRadius.circular(9), child: LinearProgressIndicator(value: t == 0 ? 0 : (u / t).toDouble(), minHeight: 6,
          backgroundColor: Brand.gold.withValues(alpha: .15), color: const Color(0xFFA8822F)))),
      const SizedBox(width: 8),
      Flexible(child: Text('${_num(u)} of ${_num(t)}', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
    ]);
    return Panel(title: 'Student strength', trailing: TextButton(onPressed: () => context.go('/staff/strength'), child: const Text('Open →')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (rows.isEmpty) Text('No students in the current classes yet.', style: TextStyle(color: cs.onSurfaceVariant))
        else ReportTable(
          cols: const [('Class', 3, false), ('Sections', 3, false), ('Boys', 2, true), ('Girls', 2, true), ('Students', 2, true), ('Using the app', 4, false)],
          rows: [
            for (final r in rows) [Text('${r['code']}', style: const TextStyle(fontWeight: FontWeight.w900)), Text('${r['sections'] ?? '—'}', style: TextStyle(color: cs.onSurfaceVariant)),
              Text(_num(r['boys'])), Text(_num(r['girls'])), Text(_num(r['total']), style: const TextStyle(fontWeight: FontWeight.w900)), bar(_n(r['using']), _n(r['total']))],
            [const Text('Total'), Text('${rows.length} classes'), Text(_num(tb)), Text(_num(tg)), Text(_num(tt)), Text('${_num(tu)} of ${_num(tt)} · ${tt == 0 ? 0 : (tu * 100 / tt).round()}%')],
          ], totals: {rows.length}, onTap: [for (final _ in rows) () => context.go('/staff/students')]),
        const SizedBox(height: 10),
        Text('${_num(st['joined'])} joined this year · ${_num(st['left'])} left · ${_num(st['rejoined'])} re-joined', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ]));
  }

  // ---------------------------------------------------------------- Latest notice
  Widget _notice(BuildContext context, Map<String, dynamic>? g, ColorScheme cs) {
    final n = g?['notice'] == null ? null : Map<String, dynamic>.from(g!['notice']);
    return Panel(title: 'Latest notice', trailing: TextButton(onPressed: () => context.go('/staff/announcements/report'), child: const Text('All →')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (n == null) Text('No notice sent yet.', style: TextStyle(color: cs.onSurfaceVariant))
        else ...[
          Text('${n['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 3),
          Text('${n['audience']} · sent ${DateFormat('d MMM').format(DateTime.parse(n['sent_at']).toLocal())}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          Builder(builder: (_) {
            final to = _n(n['sent_to']), rd = _n(n['read_by']);
            final pc = to == 0 ? 0.0 : (rd / to).clamp(0, 1).toDouble();
            return Row(children: [
              SizedBox(width: 84, height: 84, child: Stack(fit: StackFit.expand, children: [
                TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: pc), duration: const Duration(milliseconds: 1200), curve: Curves.easeOutCubic,
                    builder: (_, v, __) => CircularProgressIndicator(value: v, strokeWidth: 9, backgroundColor: Brand.gold.withValues(alpha: .16), color: Brand.green, strokeCap: StrokeCap.round)),
                Center(child: Text('${(pc * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
              ])),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_num(rd)} of ${_num(to)} families', style: const TextStyle(fontWeight: FontWeight.w900)),
                Text('have read it', style: TextStyle(color: cs.onSurfaceVariant)),
              ])),
            ]);
          }),
        ],
        const SizedBox(height: 16),
        Text('${_num(g?['notifications_month'])} phone notifications sent this month — free, no SMS credits.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ]));
  }

  // ---------------------------------------------------------------- Today & tomorrow
  Widget _today(BuildContext context, Map<String, dynamic>? h, ColorScheme cs) {
    final cal = List<Map<String, dynamic>>.from(h?['calendar'] ?? const []);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final bus = Map<String, dynamic>.from(admin?['buses'] ?? const {});
    final running = List<Map<String, dynamic>>.from(bus['running'] ?? const []);
    final tch = Map<String, dynamic>.from(admin?['teaching'] ?? const {});
    final rc = List<Map<String, dynamic>>.from(tch['report_cards'] ?? const []);
    Widget line(Widget left, Widget right) => Container(padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .45)))),
        child: Row(children: [Expanded(child: left), const SizedBox(width: 10), right]));
    final small = TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant);
    return Panel(title: 'Today & tomorrow', trailing: TextButton(onPressed: () => context.go('/staff/calendar'), child: const Text('Calendar →')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (cal.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Nothing on the calendar today or tomorrow.', style: TextStyle(color: cs.onSurfaceVariant))),
        for (final e in cal) line(Row(children: [
          Pill('${e['starts_on']}'.compareTo(today) <= 0 ? 'TODAY' : 'TOMORROW', fg: Brand.crimsonDeep, bg: Brand.crimsonTint),
          const SizedBox(width: 10),
          Expanded(child: Text('${e['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: e['kind'] == 'holiday' ? FontWeight.w900 : FontWeight.w600))),
        ]), Text((e['grades'] as List?)?.isNotEmpty == true ? (e['grades'] as List).join(', ') : 'Whole school', style: small)),
        if (admin != null) ...[
          line(const Row(children: [Icon(Icons.directions_bus_rounded, size: 18), SizedBox(width: 8), Text('Transport')]),
              Text(running.isEmpty ? 'No trip running right now' : '${running.length} ${running.length == 1 ? 'bus' : 'buses'} on the road', style: small)),
          line(const Row(children: [Icon(Icons.menu_book_rounded, size: 18), SizedBox(width: 8), Text('Diary posted')]),
              Text('${_num(tch['diary_sections_today'])} of ${_num(tch['sections'])} sections', style: small)),
          for (final r in rc) line(Row(children: [const Icon(Icons.workspace_premium_rounded, size: 18), const SizedBox(width: 8), Flexible(child: Text('Report cards · ${r['term']}'))]),
              Text('${_num(r['published'])} of ${_num(r['total'])} published', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800,
                  color: _n(r['published']) >= _n(r['total']) && _n(r['total']) > 0 ? context.tone(Brand.green) : cs.onSurfaceVariant))),
        ],
      ]));
  }

  // ---------------------------------------------------------------- Who is using the app
  Widget _usage(BuildContext context, Map<String, dynamic>? g, ColorScheme cs) {
    final u = Map<String, dynamic>.from(g?['usage'] ?? const {});
    final fam = Map<String, dynamic>.from(u['families'] ?? const {}), stf = Map<String, dynamic>.from(u['staff'] ?? const {});
    return Panel(title: 'Who is using the app', trailing: TextButton(onPressed: () => showNeverSignedIn(context), child: Text('Never signed in (${_num(fam['never'])}) →')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ReportTable(cols: const [('', 3, false), ('Web', 2, true), ('Android', 2, true), ('iPhone', 2, true), ('Never', 2, true)], rows: [
          for (final (who, m) in [('Families', fam), ('Staff', stf)]) [Text(who, style: const TextStyle(fontWeight: FontWeight.w700)), Text(_num(m['web'])), Text(_num(m['android'])), Text(_num(m['ios'])),
            Text(_num(m['never']), style: TextStyle(fontWeight: FontWeight.w900, color: _n(m['never']) > 0 ? context.tone(Brand.crimsonDeep) : null))],
        ]),
        const SizedBox(height: 10),
        Text('Class teachers see their own families who haven’t signed in, on their Today page.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ]));
  }

  // ---------------------------------------------------------------- Needs attention
  static const _checks = [
    ('photo', 'Students without a photo', '/staff/students'), ('dob', 'Students without a date of birth', '/staff/students'),
    ('blood_group', 'Students without a blood group', '/staff/students'), ('phone', 'Students without a parent phone', '/staff/students'),
    ('house', 'Students without a house', '/staff/students'), ('no_class_teacher', 'Classes without a class teacher', '/staff/setup'),
    ('staff_phone', 'Staff without a phone number', '/staff/users'), ('staff_dob', 'Staff without a date of birth', '/staff/users'),
    ('certificates', 'Left without a TC or conduct certificate', '/staff/leaving'),
  ];

  Widget _attention(BuildContext context, Map<String, dynamic>? h, ColorScheme cs) {
    final c = Map<String, dynamic>.from(h?['checks'] ?? const {});
    final open = _checks.where((k) => _n(c[k.$1]) > 0).toList();
    final ok = _checks.where((k) => _n(c[k.$1]) == 0).map((k) => k.$2.replaceFirst('Students without ', '').replaceFirst('Staff without ', 'staff ').replaceFirst('Classes without ', '')).toList();
    return Panel(title: 'Needs attention', trailing: Pill(open.isEmpty ? 'ALL COMPLETE' : '${open.length} TO FILL IN', fg: open.isEmpty ? Brand.green : Brand.amber, bg: open.isEmpty ? Brand.greenTint : Brand.amberTint),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final k in open) Container(padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .45)))),
          child: Row(children: [
            Icon(Icons.error_outline_rounded, size: 19, color: context.tone(Brand.amber)), const SizedBox(width: 10),
            Expanded(child: Text(k.$2)),
            Text(_num(c[k.$1]), style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(width: 6),
            TextButton(onPressed: () => _showList(context, k.$1, k.$2, k.$3), child: const Text('Show')),
          ])),
        if (open.isEmpty) Text('Everything is filled in ✓', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(Brand.green))),
        if (ok.isNotEmpty && open.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('✓ All filled: ${ok.join(', ')}.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
      ]));
  }

  void _showList(BuildContext context, String kind, String title, String page) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 480, height: 420, child: FutureBuilder(
        future: db.rpc('data_check_list', params: {'p_kind': kind}),
        builder: (_, snap) {
          if (snap.hasError) return Text('Could not load: ${friendlyError(snap.error)}');
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
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close')), FilledButton(onPressed: () { Navigator.pop(c); context.go(page); }, child: const Text('Open'))],
    ));
  }

  // ---------------------------------------------------------------- Recent activity
  Widget _activity(BuildContext context, ColorScheme cs) {
    final list = List<Map<String, dynamic>>.from(admin?['activity'] ?? const []).where((a) => !'${a['action']}'.startsWith('login.')).take(7).toList();
    return Panel(title: 'Recent activity', child: list.isEmpty
        ? Text('Nothing yet.', style: TextStyle(color: cs.onSurfaceVariant))
        : Column(children: [for (final a in list) Container(padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .45)))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 128, child: Text(a['at'] == null ? '' : DateFormat('d MMM · h:mm a').format(DateTime.parse(a['at']).toLocal()),
                  maxLines: 1, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
              Expanded(child: Text('${a['who']} ${activityLine('${a['action']}')}${a['detail'] is Map && (a['detail'] as Map)['title'] != null ? ' · “${(a['detail'] as Map)['title']}”' : ''}',
                  style: const TextStyle(fontSize: 13.5))),
            ]))]));
  }
}

class _Kpi extends StatelessWidget {
  final IconData icon; final String label; final num? value; final String? text; final String? sub; final Widget? extra;
  const _Kpi({required this.icon, required this.label, this.value, this.text, this.sub, this.extra});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final big = (Theme.of(context).textTheme.headlineSmall ?? const TextStyle()).copyWith(fontSize: 34, height: 1.15, color: cs.onSurface);
    return Container(
      constraints: const BoxConstraints(minHeight: 128),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outline.withValues(alpha: .5)),
        gradient: LinearGradient(colors: [cs.surface, Color.alphaBlend(Brand.gold.withValues(alpha: .07), cs.surface)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: Brand.gold.withValues(alpha: .10), blurRadius: 18, offset: const Offset(0, 6))]),
      foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border(top: BorderSide(color: Brand.gold.withValues(alpha: .8), width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: cs.onSurfaceVariant))),
          Container(width: 34, height: 34, decoration: BoxDecoration(color: Brand.gold.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: context.tone(const Color(0xFFA8822F)))),
        ]),
        const SizedBox(height: 6),
        text != null ? Text(text!, style: big) : CountUp((value ?? 0).toDouble(), decimals: 0, style: big),
        if (sub != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(sub!, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
        if (extra != null) Padding(padding: const EdgeInsets.only(top: 3), child: extra!),
      ]),
    );
  }
}

/// Families who have never signed in, class by class, with a phone to call.
Future<void> showNeverSignedIn(BuildContext context) async {
  List<Map<String, dynamic>> rows = const [];
  try { rows = [for (final x in (await db.rpc('office_never_logged_in')) as List? ?? const []) Map<String, dynamic>.from(x as Map)]; } catch (_) {}
  if (!context.mounted) return;
  await showDialog(context: context, builder: (c) {
    final byClass = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) { byClass.putIfAbsent('${r['class'] ?? 'No class yet'}', () => []).add(r); }
    return AlertDialog(
      title: Text('Never signed in · ${_num(rows.length)}'),
      content: SizedBox(width: 560, height: 480, child: rows.isEmpty ? const Text('Every family has signed in ✓') : ListView(children: [
        const NoteBox('Class teachers can call these families and help them sign in with the admission number and the password slip.'),
        for (final e in byClass.entries) ...[
          Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 4), child: Text('${e.key} · ${e.value.length}', style: TextStyle(fontWeight: FontWeight.w900, color: c.tone(Brand.gold)))),
          for (final r in e.value) ListTile(dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text('${r['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${r['admission_no']}'),
            trailing: Text('${r['phone'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
            onTap: () { Navigator.pop(c); openStudentRecord(context, r['id']); }),
        ],
      ])),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
    );
  });
}
