import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat, PdfColor;
import 'package:pdf/widgets.dart' as pw;
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/school_docs.dart' show PdfDocScreen;
import '../core/theme.dart';
import '../core/xlsx_writer.dart';
import '../widgets/common.dart';
import '../widgets/royal_motion.dart';
import 'certificates_page.dart' show tcDraftFor, buildManyCertificatesPdf, certificateIssuedTick;
import 'staff_shell.dart';
import 'students_page.dart' show openStudentRecord;

/// Office reports (Release I, the approved mock):
///   • Student strength — one page instead of MCB's Branches + Enrollment review: class by class, School and Senior Secondary
///   • Leaving check — only what needs attention, then who left this year; Grade X and XII TCs for the whole class, no asking
///   • Notices read — how many families opened each notice, and a month-by-month count by type
String _dmy(String? iso) => iso == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());
String _n(num v) => NumberFormat.decimalPattern('en_IN').format(v);

// ------------------------------------------------------------------ shared pieces
/// A number card: label on top, a big number counting up, a line underneath.
class StatCard extends StatelessWidget {
  final String label; final num value; final String? sub; final Color? tone; final String? money; final Widget? extra;
  const StatCard(this.label, this.value, {super.key, this.sub, this.tone, this.money, this.extra});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.15, color: tone == null ? null : context.tone(tone!));
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outline.withValues(alpha: .6)),
          gradient: LinearGradient(colors: [cs.surface, Brand.gold.withValues(alpha: .05)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        money != null ? Text(money!, style: style) : CountUp(value.toDouble(), decimals: 0, style: style),
        if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
        if (extra != null) Padding(padding: const EdgeInsets.only(top: 4), child: extra!),
      ]),
    );
  }
}

/// Cards in a responsive grid (1 – 5 across).
Widget statGrid(BuildContext context, List<Widget> cards) => LayoutBuilder(builder: (_, c) {
  final per = c.maxWidth > 1000 ? cards.length.clamp(1, 5) : c.maxWidth > 640 ? 3 : 2;
  final w = (c.maxWidth - (per - 1) * 12) / per;
  return Padding(padding: const EdgeInsets.only(bottom: 14), child: Wrap(spacing: 12, runSpacing: 12, children: [
    for (final (i, card) in cards.indexed) SizedBox(width: w, child: FadeRise(delayMs: 60 * i, dy: 12, child: card)),
  ]));
});

/// A simple table: header row and data rows. [num] columns are right aligned. A row can be a total (bold, tinted).
class ReportTable extends StatelessWidget {
  final List<(String, int, bool)> cols;            // title, flex, right aligned
  final List<List<Widget>> rows; final Set<int> totals; final List<VoidCallback?>? onTap;
  const ReportTable({super.key, required this.cols, required this.rows, this.totals = const {}, this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget line(List<Widget> cells, {bool head = false, bool total = false, VoidCallback? tap}) {
      final row = Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: head ? 12 : 16),
        decoration: BoxDecoration(
          color: head ? Brand.gold.withValues(alpha: .08) : total ? Brand.gold.withValues(alpha: .06) : null,
          border: head ? null : Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .6)))),
        child: Row(children: [
          for (final (i, c) in cells.indexed) Expanded(flex: cols[i].$2, child: Align(alignment: cols[i].$3 ? Alignment.centerRight : Alignment.centerLeft,
              child: DefaultTextStyle.merge(style: TextStyle(fontWeight: head || total ? FontWeight.w800 : null, fontSize: head ? 11 : 13.5,
                  letterSpacing: head ? .8 : null, color: head ? cs.onSurfaceVariant : null), child: c))),
        ]));
      return tap == null ? row : InkWell(onTap: tap, child: row);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(14), child: Container(
      decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant.withValues(alpha: .7)), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        line([for (final c in cols) Text(c.$1.toUpperCase())], head: true),
        for (final (i, r) in rows.indexed) line(r, total: totals.contains(i), tap: onTap == null || i >= onTap!.length ? null : onTap![i]),
      ])));
  }
}

/// Horizontal scroll for wide tables on phones.
Widget wideTable(BuildContext context, Widget table, {double min = 760}) => LayoutBuilder(builder: (_, c) =>
    c.maxWidth >= min ? table : SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: min, child: table)));

Widget _loading() => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
Widget _err(Object e) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e), style: const TextStyle(color: Brand.crimsonDeep)));

// ================================================================== Student strength
final _strengthProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.cacheFor();
  return Map<String, dynamic>.from(await db.rpc('office_strength') as Map);
});

class StrengthPage extends ConsumerWidget {
  const StrengthPage({super.key});

  Future<void> _excel(BuildContext context, Map<String, dynamic> d) async {
    final rows = [for (final x in (d['rows'] as List)) Map<String, dynamic>.from(x as Map)];
    try {
      await saveBytes(buildXlsx('Student strength', ['Class', 'Boys', 'Girls', 'On rolls', 'Joined this year', 'Re-joined', 'Left this year'], [
        ['Royale Concorde International School, Kalyan Nagar · ${d['year']}', null, null, null, null, null, null],
        for (final r in rows) [r['name'], r['boys'], r['girls'], r['on_rolls'], r['joined'], r['rejoined'], r['left']],
        ['Total', d['total']?['boys'], d['total']?['girls'], d['total']?['on_rolls'], d['total']?['joined'], d['total']?['rejoined'], d['total']?['left']],
      ], widths: [26, 10, 10, 12, 16, 12, 14]), 'RCIS-student-strength-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx');
    } catch (e) { if (context.mounted) toast(context, 'Could not save the file: ${friendlyError(e)}'); }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_strengthProvider);
    return StaffPage(title: 'Student strength', subtitle: 'One page for the numbers MCB shows in Branches and Enrollment review — School and Senior Secondary together.',
      actions: [if (data.hasValue) OutlinedButton.icon(onPressed: () => _excel(context, data.value!), icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Excel'))],
      body: data.when(loading: _loading, error: (e, _) => _err(e), data: (d) {
        final rows = [for (final x in (d['rows'] as List)) Map<String, dynamic>.from(x as Map)];
        final t = Map<String, dynamic>.from(d['total'] ?? const {});
        num sum(Iterable<Map<String, dynamic>> l, String k) => l.fold<num>(0, (a, r) => a + ((r[k] ?? 0) as num));
        final school = rows.where((r) => r['senior'] != true).toList(), senior = rows.where((r) => r['senior'] == true).toList();
        List<Widget> cells(String name, Map<String, dynamic> r) => [
          Text(name), Text('${r['boys']}', style: TextStyle(color: context.tone(Brand.blue), fontWeight: FontWeight.w800)),
          Text('${r['girls']}', style: TextStyle(color: context.tone(const Color(0xFFD6407F)), fontWeight: FontWeight.w800)),
          Text('${r['on_rolls']}', style: const TextStyle(fontWeight: FontWeight.w900)), Text('${r['joined']}'), Text('${r['rejoined']}'),
          Text('${r['left']}', style: TextStyle(color: (r['left'] ?? 0) > 0 ? context.tone(Brand.crimsonDeep) : null, fontWeight: FontWeight.w700)),
        ];
        Map<String, dynamic> tot(List<Map<String, dynamic>> l) => {for (final k in ['boys', 'girls', 'on_rolls', 'joined', 'rejoined', 'left']) k: sum(l, k)};
        final table = <List<Widget>>[]; final totals = <int>{};
        for (final r in school) { table.add(cells(r['name'], r)); }
        if (school.isNotEmpty && senior.isNotEmpty) { totals.add(table.length); table.add(cells('School total (up to X)', tot(school))); }
        for (final r in senior) { table.add(cells(r['name'], r)); }
        if (senior.isNotEmpty && school.isNotEmpty) { totals.add(table.length); table.add(cells('Senior Secondary total (XI – XII)', tot(senior))); }
        totals.add(table.length); table.add(cells('RCIS Kalyan Nagar total', t));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          statGrid(context, [
            StatCard('On rolls', (t['on_rolls'] ?? 0) as num, extra: Text.rich(TextSpan(children: [
              TextSpan(text: '${_n((t['boys'] ?? 0) as num)} boys', style: TextStyle(color: context.tone(Brand.blue), fontWeight: FontWeight.w800)),
              const TextSpan(text: '  ·  '),
              TextSpan(text: '${_n((t['girls'] ?? 0) as num)} girls', style: TextStyle(color: context.tone(const Color(0xFFD6407F)), fontWeight: FontWeight.w800)),
            ]), style: const TextStyle(fontSize: 12.5))),
            StatCard('Joined this year', (t['joined'] ?? 0) as num, sub: 'new admissions · ${d['year']}'),
            StatCard('Left this year', (t['left'] ?? 0) as num, tone: Brand.crimsonDeep, sub: 'see Leaving check'),
            StatCard('Re-joined', (t['rejoined'] ?? 0) as num, sub: 'came back (new admission no.)'),
            StatCard('Suspended today', (d['suspended'] ?? 0) as num, tone: Brand.amber, sub: '${_n((d['never_logged_in'] ?? 0) as num)} never signed in'),
          ]),
          Panel(title: 'Class by class', child: wideTable(context, ReportTable(
            cols: const [('Class', 5, false), ('Boys', 2, true), ('Girls', 2, true), ('On rolls', 2, true), ('Joined', 2, true), ('Re-joined', 2, true), ('Left', 2, true)],
            rows: table, totals: totals), min: 640)),
          const NoteBox('Joined this year = first year in the school. Re-joined = a student who came back with a new admission number (for example Grade XI). Left = moved to Past students this year.'),
        ]);
      }),
    );
  }
}

// ================================================================== Leaving check
final _leavingProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.cacheFor();
  ref.watch(certificateIssuedTick);
  return Map<String, dynamic>.from(await db.rpc('office_leaving_check') as Map);
});
final _boardProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  ref.watch(certificateIssuedTick);
  return [for (final x in (await db.rpc('tc_board_classes')) as List? ?? const []) Map<String, dynamic>.from(x as Map)];
});

class LeavingCheckPage extends ConsumerStatefulWidget {
  const LeavingCheckPage({super.key});
  @override
  ConsumerState<LeavingCheckPage> createState() => _LeavingCheckPageState();
}

class _LeavingCheckPageState extends ConsumerState<LeavingCheckPage> {
  String filter = '';   // '' all · 'tc' TC not taken · 'dues' fees pending

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final data = ref.watch(_leavingProvider);
    return StaffPage(title: 'Leaving check', subtitle: 'Students who left this year. Only problems are shown, so nothing is missed.',
      body: data.when(loading: _loading, error: (e, _) => _err(e), data: (d) {
        final who = [for (final x in (d['who'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
        final shown = who.where((w) => filter == '' || (filter == 'tc' && w['tc'] == 'not_taken') || (filter == 'dues' && ((w['due'] ?? 0) as num) > 0)).toList();
        Widget need(IconData icon, Color c, String text, String button, String f) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: CardRow(children: [
          Icon(icon, color: c), const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700))),
          OutlinedButton(onPressed: () => setState(() => filter = filter == f ? '' : f), child: Text(filter == f ? 'Show all' : button)),
        ]));
        final okLines = [
          if ((d['attendance_after_leaving'] ?? 0) == 0) 'No attendance marked after anyone left',
          'Every leaving has a reason', 'Fees after leaving were cancelled by themselves',
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          statGrid(context, [
            StatCard('Left this year', (d['left'] ?? 0) as num, sub: '${d['year']}'),
            StatCard('TC not taken yet', (d['tc_not_taken'] ?? 0) as num, tone: Brand.crimsonDeep, sub: 'left, but no TC given'),
            StatCard('Fees pending at leaving', (d['dues'] ?? 0) as num, tone: Brand.crimsonDeep, money: inr((d['dues'] ?? 0) as num), sub: '${d['dues_students'] ?? 0} students'),
          ]),
          const _BoardTcPanel(),
          Panel(title: 'Needs attention', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if ((d['tc_not_taken'] ?? 0) > 0) need(Icons.warning_amber_rounded, Brand.amber, '${d['tc_not_taken']} student${d['tc_not_taken'] == 1 ? '' : 's'} left but haven’t taken their TC', 'See list', 'tc'),
            if ((d['dues_students'] ?? 0) > 0) need(Icons.warning_amber_rounded, Brand.amber, '${d['dues_students']} left with fees pending · ${inr((d['dues'] ?? 0) as num)}', 'See list', 'dues'),
            if ((d['waiting_long'] ?? 0) > 0) need(Icons.hourglass_top_rounded, Brand.violet, '${d['waiting_long']} waiting for the Principal for over 7 days', 'See list', ''),
            if ((d['attendance_after_leaving'] ?? 0) > 0) need(Icons.fact_check_rounded, Brand.crimson, '${d['attendance_after_leaving']} marked present after their last day', 'See list', ''),
            Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 14, runSpacing: 4, children: [
              for (final l in okLines) Text('✓ $l', style: TextStyle(color: context.tone(Brand.green), fontWeight: FontWeight.w700, fontSize: 13)),
            ])),
            if ((d['waiting'] ?? 0) > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${d['waiting']} leaving${d['waiting'] == 1 ? ' is' : 's are'} with the Principal now (Approvals).', style: TextStyle(color: cs.onSurfaceVariant))),
          ])),
          Panel(title: filter == '' ? 'Who left · ${who.length}' : 'Who left · ${shown.length} of ${who.length}',
            trailing: TextButton.icon(onPressed: who.isEmpty ? null : () => _excel(who, '${d['year']}'), icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Excel')),
            child: shown.isEmpty ? Text('Nobody has left this year.', style: TextStyle(color: cs.onSurfaceVariant)) : wideTable(context, ReportTable(
              cols: const [('Student', 5, false), ('Class', 3, false), ('Last day', 3, false), ('Reason', 4, false), ('TC', 3, false), ('Fees pending', 3, true)],
              rows: [for (final w in shown) [
                Text('${w['full_name']}', style: const TextStyle(fontWeight: FontWeight.w800)), Text('${w['class'] ?? '—'}'), Text(_dmy(w['left_on'])),
                Text('${w['reason'] ?? '—'}'),
                switch (w['tc']) { 'taken' => const Pill('Taken', fg: Brand.green, bg: Brand.greenTint), 'not_needed' => const Pill('Not needed', fg: Brand.muted, bg: Brand.surface2),
                  _ => const Pill('Not taken', fg: Brand.crimsonDeep, bg: Brand.crimsonTint) },
                ((w['due'] ?? 0) as num) > 0 ? Text(inr(w['due'] as num), style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(Brand.crimsonDeep))) : const Text('—'),
              ]],
              onTap: [for (final w in shown) () => openStudentRecord(context, w['id']).then((_) => ref.invalidate(_leavingProvider))],
            ))),
        ]);
      }),
    );
  }

  Future<void> _excel(List<Map<String, dynamic>> who, String year) async {
    try {
      await saveBytes(buildXlsx('Who left', ['Student', 'Admission no', 'Class', 'Last day', 'Reason', 'TC', 'Fees pending (₹)'], [
        ['Royale Concorde International School, Kalyan Nagar · left in $year', null, null, null, null, null, null],
        for (final w in who) [w['full_name'], w['admission_no'], w['class'], w['left_on'], w['reason'],
          const {'taken': 'Taken', 'not_needed': 'Not needed'}[w['tc']] ?? 'Not taken', w['due']],
      ], widths: [26, 14, 14, 12, 22, 12, 14]), 'RCIS-who-left-$year.xlsx');
    } catch (e) { if (mounted) toast(context, 'Could not save the file: ${friendlyError(e)}'); }
  }
}

/// Grade X and XII: every student gets a TC — no ticking, no asking the Principal one by one.
class _BoardTcPanel extends ConsumerStatefulWidget {
  const _BoardTcPanel();
  @override
  ConsumerState<_BoardTcPanel> createState() => _BoardTcPanelState();
}

class _BoardTcPanelState extends ConsumerState<_BoardTcPanel> {
  String? busyFor; int done = 0, total = 0;

  bool _ready(Map<String, dynamic> g) {
    final r = g['ready_on'] as String?;
    if (r == null) return false;
    final d = DateTime.parse(r);
    final now = DateTime.now();
    return !DateTime(now.year, now.month, now.day).isBefore(d);
  }

  Future<void> _setDay(Map<String, dynamic> g) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, helpText: 'The day the last ${g['name']} board exam ends',
        initialDate: g['ready_on'] == null ? DateTime(now.month > 5 ? now.year + 1 : now.year, 3, 20) : DateTime.parse(g['ready_on']),
        firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 2));
    if (d == null) return;
    try { await db.rpc('tc_board_set_ready', params: {'p_code': g['code'], 'p_day': DateFormat('yyyy-MM-dd').format(d)}); ref.invalidate(_boardProvider); }
    catch (e) { if (mounted) toast(context, friendlyError(e)); }
  }

  /// [issue] = give every TC its number now (from the ready day); otherwise a draft to check.
  Future<void> _all(Map<String, dynamic> g, {required bool issue}) async {
    setState(() { busyFor = g['code']; done = 0; total = 0; });
    try {
      final list = [for (final x in (await db.rpc('tc_board_students', params: {'p_grade': g['grade_id']})) as List? ?? const []) Map<String, dynamic>.from(x as Map)];
      setState(() => total = list.length);
      final items = <(String, String, Map<String, dynamic>)>[];
      for (final s in list) {
        final data = await tcDraftFor(s['id']);
        data['reason'] = 'Passed Grade ${g['code']} (board examination)';
        String number = 'DRAFT';
        if (issue) {
          if (s['tc'] != null) {
            number = '${s['tc']['number']}';
          } else {
            number = '${await db.rpc('tc_board_issue', params: {'p_student': s['id'], 'p_data': data})}';
          }
        }
        items.add(('tc', number, data));
        if (mounted) setState(() => done++);
      }
      if (issue) ref.read(certificateIssuedTick.notifier).state++;
      if (!mounted) return;
      setState(() => busyFor = null);
      if (items.isEmpty) { toast(context, 'No ${g['name']} students found.'); return; }
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PdfDocScreen(
        title: '${g['name']} TCs${issue ? '' : ' (draft)'}', fileName: 'RCIS-${g['code']}-TCs${issue ? '' : '-draft'}.pdf',
        make: () => buildManyCertificatesPdf('${g['name']} TCs', items))));
    } catch (e) {
      if (mounted) { setState(() => busyFor = null); toast(context, friendlyError(e)); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(sessionProvider).value;
    final canSet = s != null && (s.hasRole('it_admin') || s.hasRole('principal') || s.hasRole('office'));
    final rows = ref.watch(_boardProvider).value ?? const <Map<String, dynamic>>[];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Panel(title: 'Grade X & XII TCs · made by themselves', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Every Grade X and XII student gets a TC. Nobody has to tick anything, and these don’t wait for the Principal one by one. '
          'Conduct is filled as “Good” — the class teacher changes only the few that need it.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
      const SizedBox(height: 8),
      for (final g in rows) Container(
        margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outlineVariant)),
        child: CardRow(children: [
          Container(width: 46, height: 46, alignment: Alignment.center, decoration: BoxDecoration(color: Brand.gold.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)),
              child: Text('${g['code']}', style: TextStyle(fontWeight: FontWeight.w900, color: context.tone(Brand.gold)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${g['name']}${g['sections'] != null ? ' (${g['sections']})' : ''} · ${g['students']} students', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if ((g['issued'] ?? 0) >= (g['students'] ?? 0) && (g['students'] ?? 0) > 0) const Pill('All TCs ready to give ✓', fg: Brand.green, bg: Brand.greenTint)
              else if (_ready(g)) Pill('Ready · ${g['issued']} of ${g['students']} numbered', fg: Brand.green, bg: Brand.greenTint)
              else Pill(g['ready_on'] == null ? 'Set the day the last board exam ends' : 'Ready on ${_dmy(g['ready_on'])}', fg: Brand.amber, bg: Brand.amberTint),
              if (busyFor == g['code']) Text('Preparing $done of $total…', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ]),
          ])),
          if (canSet) TextButton(onPressed: busyFor != null ? null : () => _setDay(g), child: Text(g['ready_on'] == null ? 'Set the day' : 'Change day')),
          OutlinedButton(onPressed: busyFor != null ? null : () => _all(g, issue: false), child: const Text('Preview')),
          if (_ready(g)) FilledButton(onPressed: busyFor != null ? null : () => _all(g, issue: true), child: const Text('Print all')),
        ])),
    ]));
  }
}

// ================================================================== Notices: who read them
final _noticeProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.cacheFor();
  return Map<String, dynamic>.from(await db.rpc('office_notice_report') as Map);
});

const noticeCategoryLabels = {'general': 'General', 'holiday': 'Holiday', 'field_trip': 'Field trip', 'exams': 'Exams', 'fees': 'Fees', 'urgent': 'Urgent'};

class NoticeReportPage extends ConsumerStatefulWidget {
  const NoticeReportPage({super.key});
  @override
  ConsumerState<NoticeReportPage> createState() => _NoticeReportPageState();
}

class _NoticeReportPageState extends ConsumerState<NoticeReportPage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final data = ref.watch(_noticeProvider);
    return StaffPage(title: 'Notices · who read them', subtitle: 'How many families opened each notice, and how many notices of each kind went out every month.',
      body: data.when(loading: _loading, error: (e, _) => _err(e), data: (d) {
        final ns = [for (final x in (d['notices'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
        final ms = [for (final x in (d['months'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
        final sentTo = ns.fold<num>(0, (a, n) => a + ((n['sent_to'] ?? 0) as num));
        final readBy = ns.fold<num>(0, (a, n) => a + ((n['read_by'] ?? 0) as num));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          statGrid(context, [
            StatCard('Notices (last 4 months)', ns.length),
            StatCard('Read on average', sentTo == 0 ? 0 : (readBy * 100 / sentTo).round(), money: sentTo == 0 ? '—' : '${(readBy * 100 / sentTo).round()}%', tone: Brand.green),
            StatCard('Families reached', readBy, sub: 'opened a notice'),
          ]),
          SegmentedButton<int>(showSelectedIcon: false, segments: const [ButtonSegment(value: 0, label: Text('Sent notices')), ButtonSegment(value: 1, label: Text('Month by month'))],
              selected: {tab}, onSelectionChanged: (v) => setState(() => tab = v.first)),
          const SizedBox(height: 14),
          if (tab == 0) Panel(child: ns.isEmpty ? Text('No notices sent in the last four months.', style: TextStyle(color: cs.onSurfaceVariant)) : wideTable(context, ReportTable(
            cols: const [('Notice', 6, false), ('Type', 2, false), ('Sent to', 3, false), ('Sent', 2, false), ('Read by families', 5, false)],
            rows: [for (final n in ns) () {
              final to = ((n['sent_to'] ?? 0) as num), rd = ((n['read_by'] ?? 0) as num);
              final pc = to == 0 ? 0.0 : (rd / to).clamp(0, 1).toDouble();
              return <Widget>[
                Text('${n['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                Pill(noticeCategoryLabels[n['category']] ?? '${n['category']}', fg: Brand.muted, bg: Brand.surface2),
                Text('${n['audience']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(DateFormat('d MMM').format(DateTime.parse(n['sent_at']).toLocal())),
                Row(children: [
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: pc, minHeight: 7,
                      backgroundColor: cs.outlineVariant.withValues(alpha: .4), color: pc >= .7 ? Brand.green : pc >= .4 ? Brand.amber : Brand.crimson))),
                  const SizedBox(width: 8),
                  Text('${(pc * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(width: 6),
                  Text('${_n(rd)} of ${_n(to)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ]),
              ];
            }()]), min: 820))
          else Panel(child: Builder(builder: (_) {
            final months = ms.map((m) => m['month'] as String).toSet().toList()..sort((a, b) => b.compareTo(a));
            final cats = noticeCategoryLabels.keys.where((k) => ms.any((m) => m['category'] == k)).toList();
            if (months.isEmpty) return Text('No notices yet.', style: TextStyle(color: cs.onSurfaceVariant));
            int nOf(String m, String c) => ms.where((x) => x['month'] == m && x['category'] == c).fold<int>(0, (a, x) => a + ((x['n'] ?? 0) as int));
            return wideTable(context, ReportTable(
              cols: [('Type', 3, false), for (final m in months) (DateFormat('MMM').format(DateTime.parse('$m-01')), 1, true)],
              rows: [
                for (final c in cats) [Text(noticeCategoryLabels[c]!), for (final m in months) Text('${nOf(m, c)}')],
                [const Text('Total'), for (final m in months) Text('${cats.fold<int>(0, (a, c) => a + nOf(m, c))}')],
              ], totals: {cats.length}), min: 560);
          })),
        ]);
      }),
    );
  }
}

// ================================================================== Print any report table (A4, school name on top)
Future<void> printReport(BuildContext context, String title, List<String> head, List<List<String>> rows, {List<(String, String)> totals = const []}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PdfDocScreen(
      title: title, fileName: 'RCIS-${title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}.pdf',
      make: () async {
        final doc = pw.Document(title: title, author: 'Royale Concorde International School');
        final base = pw.Font.helvetica(), bold = pw.Font.helveticaBold();
        String clean(String s) => s.replaceAll('₹', 'Rs ').replaceAll('–', '-').replaceAll('·', '-').replaceAll('’', "'");
        doc.addPage(pw.MultiPage(
          pageFormat: head.length > 6 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          theme: pw.ThemeData.withFont(base: base, bold: bold),
          header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Royale Concorde International School, Kalyan Nagar', style: pw.TextStyle(font: bold, fontSize: 13)),
            pw.Text('${clean(title)} - printed ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),
          ]),
          build: (_) => [
            pw.TableHelper.fromTextArray(
              headers: [for (final h in head) clean(h)], data: [for (final r in rows) [for (final c in r) clean(c)]],
              headerStyle: pw.TextStyle(font: bold, fontSize: 8.5), cellStyle: const pw.TextStyle(fontSize: 8.5),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF4EEDF)),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColor.fromInt(0xFFDDD5C5), width: .5))),
            if (totals.isNotEmpty) pw.SizedBox(height: 10),
            for (final (k, v) in totals) pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Text('${clean(k)}   ', style: const pw.TextStyle(fontSize: 10)), pw.Text(clean(v), style: pw.TextStyle(font: bold, fontSize: 10))]),
          ],
        ));
        return doc.save();
      })));

// ================================================================== the office Home at a glance (the approved mock)
final officeGlanceProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  ref.cacheFor();
  try { return Map<String, dynamic>.from(await db.rpc('office_glance') as Map); } catch (_) { return null; }
});

String _inrShort(num v) {
  if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(2)} Cr';
  if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)} L';
  return inr(v);
}

class OfficeGlance extends ConsumerWidget {
  const OfficeGlance({super.key});

  Future<void> _never(BuildContext context) async {
    List<Map<String, dynamic>> rows = const [];
    try { rows = [for (final x in (await db.rpc('office_never_logged_in')) as List? ?? const []) Map<String, dynamic>.from(x as Map)]; } catch (_) {}
    if (!context.mounted) return;
    await showDialog(context: context, builder: (c) {
      final byClass = <String, List<Map<String, dynamic>>>{};
      for (final r in rows) { byClass.putIfAbsent('${r['class'] ?? 'No class yet'}', () => []).add(r); }
      return AlertDialog(
        title: Text('Never signed in · ${rows.length}'),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(officeGlanceProvider).value;
    if (d == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final st = Map<String, dynamic>.from(d['students'] ?? const {});
    final sf = Map<String, dynamic>.from(d['staff'] ?? const {});
    final fees = d['fees'] == null ? null : Map<String, dynamic>.from(d['fees']);
    final notice = d['notice'] == null ? null : Map<String, dynamic>.from(d['notice']);
    final usage = Map<String, dynamic>.from(d['usage'] ?? const {});
    num n(Map m, String k) => (m[k] ?? 0) as num;
    final boys = n(st, 'boys'), girls = n(st, 'girls');
    final bg = boys + girls;
    const pink = Color(0xFFD6407F);
    final narrow = isNarrow(context);

    Widget dot(Color c, String big, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)), const SizedBox(width: 8),
      Text.rich(TextSpan(children: [TextSpan(text: big, style: const TextStyle(fontWeight: FontWeight.w900)), TextSpan(text: ' $text')]))]);

    final strength = Panel(title: 'Student strength', trailing: TextButton(onPressed: () => GoRouter.of(context).go('/staff/strength'), child: const Text('Open →')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 28, runSpacing: 10, children: [
          dot(Brand.green, _n(n(st, 'total')), 'on rolls'), dot(Brand.blue, _n(n(st, 'joined')), 'joined this year'),
          dot(Brand.crimson, _n(n(st, 'left')), 'left this year'), dot(Brand.amber, _n(n(st, 'rejoined')), 're-joined'),
        ]),
        const SizedBox(height: 16),
        ClipRRect(borderRadius: BorderRadius.circular(99), child: SizedBox(height: 9, child: Row(children: [
          Expanded(flex: bg == 0 ? 1 : boys.toInt().clamp(1, 1 << 30), child: Container(color: Brand.blue)),
          Expanded(flex: bg == 0 ? 1 : girls.toInt().clamp(1, 1 << 30), child: Container(color: pink)),
        ]))),
        const SizedBox(height: 8),
        Text(bg == 0 ? 'Fill in Boy / Girl in the student details to see the split.' : 'Boys ${(boys * 100 / bg).round()}% · Girls ${(girls * 100 / bg).round()}%',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ]));

    final latest = Panel(title: 'Latest notice', trailing: TextButton(onPressed: () => GoRouter.of(context).go('/staff/announcements/report'), child: const Text('All →')),
      child: notice == null ? Text('No notice sent yet.', style: TextStyle(color: cs.onSurfaceVariant)) : Builder(builder: (_) {
        final to = n(notice, 'sent_to'), rd = n(notice, 'read_by');
        final pc = to == 0 ? 0.0 : (rd / to).clamp(0, 1).toDouble();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${notice['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 4),
          Text('${notice['audience']} · ${DateFormat('d MMM').format(DateTime.parse(notice['sent_at']).toLocal())}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: pc, minHeight: 8, backgroundColor: Brand.gold.withValues(alpha: .15), color: Brand.green)),
          const SizedBox(height: 8),
          Text('${(pc * 100).round()}% of families have read it', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ]);
      }));

    final fam = Map<String, dynamic>.from(usage['families'] ?? const {}), stf = Map<String, dynamic>.from(usage['staff'] ?? const {});
    final apps = Panel(title: 'Who is using the app', trailing: OutlinedButton(onPressed: () => _never(context), child: Text('Never signed in (${_n(n(fam, 'never'))})')),
      child: wideTable(context, ReportTable(
        cols: const [('Who', 4, false), ('Web', 2, true), ('Android', 2, true), ('iPhone', 2, true), ('Never signed in', 3, true)],
        rows: [
          for (final (who, m) in [('Parents / students', fam), ('Staff', stf)]) [
            Text(who), Text(_n(n(m, 'web'))), Text(_n(n(m, 'android'))), Text(_n(n(m, 'ios'))),
            Text(_n(n(m, 'never')), style: TextStyle(fontWeight: FontWeight.w900, color: n(m, 'never') > 0 ? context.tone(Brand.crimsonDeep) : null)),
          ],
        ]), min: 560));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      statGrid(context, [
        StatCard('Students', n(st, 'total'), extra: Text.rich(TextSpan(children: [
          TextSpan(text: '${_n(boys)} boys', style: TextStyle(color: context.tone(Brand.blue), fontWeight: FontWeight.w800)), const TextSpan(text: '  ·  '),
          TextSpan(text: '${_n(girls)} girls', style: TextStyle(color: context.tone(pink), fontWeight: FontWeight.w800))]), style: const TextStyle(fontSize: 12.5))),
        StatCard('Staff', n(sf, 'total'), sub: '${_n(n(sf, 'teaching'))} teaching · ${_n(n(sf, 'other'))} others'),
        StatCard('Phone notifications sent', (d['notifications_month'] ?? 0) as num, sub: 'this month · free, no SMS credits'),
        if (fees != null) StatCard('Fees collected', n(fees, 'collected'), money: _inrShort(n(fees, 'collected')),
            sub: n(fees, 'expected') == 0 ? 'this school year' : 'of ${_inrShort(n(fees, 'expected'))} this year · ${(n(fees, 'collected') * 100 / n(fees, 'expected')).round()}%'),
      ]),
      if (narrow) ...[strength, latest] else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 5, child: strength), const SizedBox(width: 14), Expanded(flex: 3, child: latest)]),
      apps,
    ]);
  }
}

// ================================================================== Fee dues (fee by fee, like MCB)
final _duesSummaryProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, grade) async {
  ref.cacheFor();
  return Map<String, dynamic>.from(await db.rpc('fee_dues_summary', params: {'p_grade': grade.isEmpty ? null : grade}) as Map);
});
final _duesStudentsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, grade) async {
  ref.cacheFor();
  return [for (final x in (await db.rpc('fee_report_dues', params: {'p_grade': grade.isEmpty ? null : grade})) as List? ?? const []) Map<String, dynamic>.from(x as Map)];
});

class FeeDuesPage extends ConsumerStatefulWidget {
  const FeeDuesPage({super.key});
  @override
  ConsumerState<FeeDuesPage> createState() => _FeeDuesPageState();
}

class _FeeDuesPageState extends ConsumerState<FeeDuesPage> {
  String grade = ''; bool students = false;

  List<Map<String, dynamic>> _l(Map<String, dynamic> d, String k) => [for (final x in (d[k] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
  num _sum(List<Map<String, dynamic>> l, String k) => l.fold<num>(0, (a, r) => a + ((r[k] ?? 0) as num));

  Future<void> _remind() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Remind everyone who hasn’t paid?'),
      content: const Text('Every family with an overdue fee gets one notification with the amount. This can be sent once a day.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send reminders'))],
    ));
    if (ok != true) return;
    try { final n = await db.rpc('fee_remind_overdue'); if (mounted) toast(context, 'Reminder sent to $n ${n == 1 ? 'family' : 'families'} ✓'); }
    catch (e) { if (mounted) toast(context, friendlyError(e)); }
  }

  Future<void> _excel(Map<String, dynamic> d) async {
    final rows = await ref.read(_duesStudentsProvider(grade).future);
    try {
      await saveBytes(buildXlsx('Fee dues', ['Student', 'Admission no', 'Class', 'Phones', 'This year (₹)', 'Late fee (₹)', 'Last year (₹)', 'Total due (₹)', 'Fees due'], [
        ['Royale Concorde International School, Kalyan Nagar · dues as on ${DateFormat('d MMM yyyy').format(DateTime.now())}', null, null, null, null, null, null, null, null],
        for (final r in rows) [r['student'], r['admission_no'], r['class'], r['phones'], (r['overdue'] as num) - ((r['last_year'] ?? 0) as num), r['late_fee'], r['last_year'], r['overdue'], r['items']],
        ['Grand total', null, null, null, null, _sum(rows, 'late_fee'), _sum(rows, 'last_year'), _sum(rows, 'overdue'), null],
      ], widths: [26, 14, 9, 34, 13, 12, 12, 13, 50]), 'RCIS-fee-dues-${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx');
    } catch (e) { if (mounted) toast(context, 'Could not save the file: ${friendlyError(e)}'); }
  }

  void _print(Map<String, dynamic> d) {
    final ty = _l(d, 'this_year'), fl = _l(d, 'failed'), ly = _l(d, 'last_year');
    final total = _sum(ty, 'amount') + _sum(fl, 'amount') + _sum(ly, 'amount');
    printReport(context, 'Fee dues', ['Part', 'Fee', 'Students', 'Amount', 'Late fee'], [
      for (final r in ty) ['This year ${d['year']}', '${r['fee']}', '${r['students']}', inr(r['amount'] as num), inr(r['late_fee'] as num)],
      for (final r in fl) ['Online payment failed', '${r['fee']}', '${r['students']}', inr(r['amount'] as num), ''],
      for (final r in ly) ['Last year ${d['last_label'] ?? ''}', '${r['fee']}', '${r['students']}', inr(r['amount'] as num), ''],
    ], totals: [('Late fee', inr(_sum(ty, 'late_fee'))), ('Grand total pending', inr(total))]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grades = ref.watch(_gradesProvider).value ?? const <Map<String, dynamic>>[];
    final data = ref.watch(_duesSummaryProvider(grade));
    final s = ref.watch(sessionProvider).value;
    return StaffPage(title: 'Fee dues', subtitle: 'What is still to be paid, fee by fee — this year, online payments that failed, and last year.',
      actions: [
        if (data.hasValue) OutlinedButton.icon(onPressed: () => _print(data.value!), icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Print')),
        if (data.hasValue) OutlinedButton.icon(onPressed: () => _excel(data.value!), icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Excel')),
        if (s != null && !s.viewOnly) FilledButton.icon(onPressed: _remind, icon: const Icon(Icons.send_rounded, size: 18), label: const Text('Remind all who haven’t paid')),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(padding: const EdgeInsets.all(12), child: PickRow(children: [
          Expanded(child: PickField<String>(label: 'Class', value: grade, items: [
            const DropdownMenuItem(value: '', child: Text('All classes · active students')),
            for (final g in grades) DropdownMenuItem(value: g['id'] as String, child: Text('${g['name']}')),
          ], onChanged: (v) => setState(() => grade = v ?? ''))),
          const SizedBox(width: 12),
          Expanded(child: Text('As on ${DateFormat('d MMM yyyy').format(DateTime.now())}', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant))),
        ])),
        data.when(loading: _loading, error: (e, _) => _err(e), data: (d) {
          final ty = _l(d, 'this_year'), fl = _l(d, 'failed'), ly = _l(d, 'last_year');
          final total = _sum(ty, 'amount') + _sum(fl, 'amount') + _sum(ly, 'amount');
          Widget money(num v, {bool b = false, Color? c}) => Text(inr(v), style: TextStyle(fontWeight: b ? FontWeight.w900 : FontWeight.w600, color: c == null ? null : context.tone(c)));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Panel(title: 'This year · ${d['year']}', child: ty.isEmpty ? Text('Nothing overdue this year ✓', style: TextStyle(color: cs.onSurfaceVariant)) : wideTable(context, ReportTable(
              cols: const [('Fee', 6, false), ('Students', 2, true), ('Amount', 3, true), ('Late fee', 3, true)],
              rows: [
                for (final r in ty) [Text('${r['fee']}'), Text('${r['students']}'), money(r['amount'] as num), money(r['late_fee'] as num)],
                [const Text('Total'), Text('${_sum(ty, 'students')}'), money(_sum(ty, 'amount'), b: true), money(_sum(ty, 'late_fee'), b: true)],
              ], totals: {ty.length}), min: 560)),
            if (fl.isNotEmpty) Panel(title: 'Online payment failed · last 30 days', child: wideTable(context, ReportTable(
              cols: const [('Fee', 8, false), ('Students', 2, true), ('Amount', 3, true)],
              rows: [for (final r in fl) [Text('${r['fee']}'), Text('${r['students']}'), money(r['amount'] as num)]]), min: 480)),
            if (ly.isNotEmpty) Panel(title: 'Pending from last year${d['last_label'] != null ? ' · ${d['last_label']}' : ''}', child: wideTable(context, ReportTable(
              cols: const [('Fee', 8, false), ('Students', 2, true), ('Amount', 3, true)],
              rows: [for (final r in ly) [Text('${r['fee']}'), Text('${r['students']}'), money(r['amount'] as num)]]), min: 480)),
            Align(alignment: Alignment.centerRight, child: Container(
              constraints: const BoxConstraints(minWidth: 320), margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Brand.crimson.withValues(alpha: .07), borderRadius: BorderRadius.circular(18), border: Border.all(color: Brand.crimson.withValues(alpha: .25))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('GRAND TOTAL PENDING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: cs.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(inr(total), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: context.tone(Brand.crimsonDeep))),
                Text('this year + failed payments + last year · late fees ${inr(_sum(ty, 'late_fee'))} extra', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ]))),
            Panel(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent), child: ExpansionTile(
              initiallyExpanded: students, onExpansionChanged: (v) => setState(() => students = v),
              leading: Icon(Icons.people_alt_rounded, color: context.tone(Brand.gold)),
              title: const Text('Student by student', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('Who owes what, with the parents’ phones', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              children: [if (students) ref.watch(_duesStudentsProvider(grade)).when(loading: _loading, error: (e, _) => _err(e), data: (rows) => rows.isEmpty
                  ? const Padding(padding: EdgeInsets.all(12), child: Text('No overdue fees ✓'))
                  : wideTable(context, ReportTable(
                      cols: const [('Student', 5, false), ('Class', 2, false), ('Phone', 4, false), ('Late fee', 2, true), ('Total due', 3, true)],
                      rows: [for (final r in rows) [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${r['student']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text('${r['items'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))]),
                        Text('${r['class'] ?? ''}'), Text('${r['phones'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        money((r['late_fee'] ?? 0) as num), money(r['overdue'] as num, b: true, c: Brand.crimsonDeep)]],
                      onTap: [for (final r in rows) () => openStudentRecord(context, r['student_id'])]), min: 760))],
            ))),
          ]);
        }),
      ]),
    );
  }
}

final _gradesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async =>
    List<Map<String, dynamic>>.from(await db.from('grade').select('id,code,name,sort_order').order('sort_order', ascending: true)));
