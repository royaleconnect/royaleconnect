import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../core/data.dart';
import '../core/data2.dart';
import '../core/school_docs.dart' show openReportCardPdf;
import '../core/theme.dart';
import '../widgets/common.dart';
import 'family_screens.dart' show StorageImage;
import '../widgets/royal_extras.dart' show GoldLoading;
import '../widgets/royal_extras.dart' show Spotlight, openWithEnvelope;

/// Shared page frame: red header with back + title, body below.
class AppPage extends StatelessWidget {
  final String title; final Widget body; final Widget? headerExtra; final List<Widget> actions;
  const AppPage({super.key, required this.title, required this.body, this.headerExtra, this.actions = const []});
  @override
  Widget build(BuildContext context) => Scaffold(body: Column(children: [
        BrandHeader(padding: const EdgeInsets.fromLTRB(8, 4, 12, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(onPressed: () => context.canPop() ? context.pop() : context.go('/'), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
            Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800))),
            ...actions,
          ]),
          if (headerExtra != null) Padding(padding: const EdgeInsets.fromLTRB(12, 6, 8, 0), child: headerExtra),
        ])),
        Expanded(child: body),
      ]));
}

Widget _loading() => const GoldLoading();
Widget _empty(BuildContext c, String t) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, height: 1.5))));
Widget _card(BuildContext c, Widget child, {EdgeInsets padding = const EdgeInsets.all(14)}) => Container(margin: const EdgeInsets.only(bottom: 10), padding: padding, decoration: BoxDecoration(color: Theme.of(c).colorScheme.surface, borderRadius: BorderRadius.circular(18)), child: child);

// ---------------------------------------------------------------- timetable
class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key});
  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}
class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  late int day = DateTime.now().weekday.clamp(1, 6);
  static const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  @override
  Widget build(BuildContext context) {
    final tt = ref.watch(timetableProvider);
    final cs = Theme.of(context).colorScheme;
    return AppPage(title: 'Timetable',
      headerExtra: Row(children: [for (var d = 1; d <= 6; d++) Expanded(child: GestureDetector(onTap: () => setState(() => day = d), child: Container(
        margin: const EdgeInsets.only(right: 6), height: 36, alignment: Alignment.center,
        decoration: BoxDecoration(color: day == d ? Colors.white : Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
        child: Text(names[d - 1], style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: day == d ? Brand.crimsonDeep : Colors.white)))))]),
      body: tt.when(loading: _loading, error: (e, _) => _empty(context, '$e'), data: (rows) {
        final today = rows.where((r) => r['weekday'] == day).toList();
        if (today.isEmpty) return _empty(context, 'No periods set for ${names[day - 1]} yet.');
        return ListView(padding: const EdgeInsets.all(20), children: [for (final r in today) _card(context, Row(children: [
          SizedBox(width: 56, child: Column(children: [Text('P${r['period']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)), Text(r['starts_at'].toString().substring(0, 5), style: const TextStyle(fontWeight: FontWeight.w800))])),
          Container(width: 3, height: 36, decoration: BoxDecoration(color: r['subject'] == null ? Brand.gold : Brand.crimson, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['subject']?['name'] ?? r['label'] ?? 'Break', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (r['staff'] != null) Text(r['staff']['display_name'], style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ])),
          if (r['needs_kit'] == true) const Pill('Kit', fg: Brand.amber, bg: Brand.amberTint),
        ]))]);
      }));
  }
}

// ---------------------------------------------------------------- exams
class ExamsScreen extends ConsumerWidget {
  const ExamsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ex = ref.watch(examsProvider);
    final cs = Theme.of(context).colorScheme;
    return AppPage(title: 'Exams & portions', body: ex.when(loading: _loading, error: (e, _) => _empty(context, '$e'), data: (list) => list.isEmpty ? _empty(context, 'Exam schedules appear here once the school publishes them.') :
      ListView(padding: const EdgeInsets.all(20), children: [for (final e in list) _card(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Pill(e['term'] ?? '', fg: Brand.crimsonDeep, bg: Brand.crimsonTint), const Spacer(), Text('Max ${e['max_marks']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))]),
        const SizedBox(height: 8),
        Text(e['name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        if (e['starts_on'] != null) Text('${DateFormat('d MMM').format(DateTime.parse(e['starts_on']))} – ${e['ends_on'] == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(e['ends_on']))}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
        if (e['note'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(e['note'], style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
        const Divider(height: 22),
        for (final p in (List<Map<String, dynamic>>.from(e['exam_paper'] ?? [])..sort((a, b) => (a['on_date'] ?? '').compareTo(b['on_date'] ?? '')))) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 60, child: Text(p['on_date'] == null ? 'TBA' : DateFormat('EEE d').format(DateTime.parse(p['on_date'])), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['subject']?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (p['portions'] != null) Text(p['portions'], style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.4)),
          ])),
        ])),
      ]))])));
  }
}

// ---------------------------------------------------------------- monthly plan
class MonthlyPlanScreen extends ConsumerStatefulWidget {
  const MonthlyPlanScreen({super.key});
  @override
  ConsumerState<MonthlyPlanScreen> createState() => _MonthlyPlanScreenState();
}
class _MonthlyPlanScreenState extends ConsumerState<MonthlyPlanScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String get iso => DateFormat('yyyy-MM-01').format(month);
  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(monthlyPlanProvider(iso));
    final cs = Theme.of(context).colorScheme;
    return AppPage(title: 'Monthly plan',
      headerExtra: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left_rounded, color: Colors.white)),
        Text(DateFormat('MMMM yyyy').format(month), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
        IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right_rounded, color: Colors.white)),
      ]),
      body: plan.when(loading: _loading, error: (e, _) => _empty(context, '$e'), data: (rows) => rows.isEmpty ? _empty(context, 'The plan for ${DateFormat('MMMM').format(month)} is not published yet.') :
        ListView(padding: const EdgeInsets.all(20), children: [for (final r in rows) _card(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r['subject']?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 6),
          Text(r['topics'], style: const TextStyle(height: 1.5)),
          if (r['assessment'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [Icon(Icons.fact_check_outlined, size: 16, color: context.tone(Brand.amber)), const SizedBox(width: 6), Expanded(child: Text(r['assessment'], style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)))])),
        ]))])));
  }
}

// ---------------------------------------------------------------- worksheets
class WorksheetsScreen extends ConsumerWidget {
  const WorksheetsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(worksheetsProvider);
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return AppPage(title: 'Worksheets', body: ws.when(loading: _loading, error: (e, _) => _empty(context, '$e'), data: (list) => list.isEmpty ? _empty(context, 'Worksheets shared by teachers appear here.') :
      ListView(padding: const EdgeInsets.all(20), children: [for (final w in list) _card(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Pill(w['kind'] ?? 'Worksheet', fg: Brand.blue, bg: Brand.blueTint), const SizedBox(width: 8), Text(w['subject']?['name'] ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)), const Spacer(),
          Text(DateFormat('d MMM').format(DateTime.parse(w['created_at']).toLocal()), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))]),
        const SizedBox(height: 8),
        Text(w['title'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        Text(w['author']?['display_name'] ?? '', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)), onPressed: () => openStorageFile(w['file_path']), icon: const Icon(Icons.picture_as_pdf_rounded, size: 18), label: const Text('Open PDF'))),
          if (w['answer_key_path'] != null) ...[const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
            onPressed: (w['answer_key_release_on'] == null || w['answer_key_release_on'].compareTo(today) <= 0) ? () => openStorageFile(w['answer_key_path']) : null,
            icon: const Icon(Icons.key_rounded, size: 18), label: Text(w['answer_key_release_on'] != null && w['answer_key_release_on'].compareTo(today) > 0 ? 'Key on ${DateFormat('d MMM').format(DateTime.parse(w['answer_key_release_on']))}' : 'Answer key')))],
        ]),
      ]))])));
  }
}

// ---------------------------------------------------------------- star of the month
class StarScreen extends ConsumerWidget {
  const StarScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(starProvider);
    final cs = Theme.of(context).colorScheme;
    Widget photo(Map<String, dynamic> s, double size) { final p = s['photo_path'] ?? s['student']?['photo_path']; return p != null ? StorageImage(p, width: size, height: size, radius: BorderRadius.circular(size * .33)) : Avatar((s['student']?['full_name'] ?? '?').toString().split(' ').take(2).map((w) => w[0]).join(), size: size, bg: Brand.amberTint, fg: Brand.amber); }
    return AppPage(title: 'Star of the month', body: st.when(loading: _loading, error: (e, _) => _empty(context, '$e'), data: (list) {
      if (list.isEmpty) return _empty(context, 'The class teacher picks a star every month. The first one appears here.');
      final top = list.first; final rest = list.skip(1).toList();
      return ListView(padding: const EdgeInsets.all(20), children: [
        Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFF6DD), Color(0xFFFBE7B5)]), borderRadius: BorderRadius.circular(24), border: Border.all(color: Brand.gold.withValues(alpha: .6))), child: Column(children: [
          const Icon(Icons.star_rounded, color: Brand.gold, size: 30),
          Text(DateFormat('MMMM yyyy').format(DateTime.parse(top['month'])).toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: Brand.amber)),
          const SizedBox(height: 12),
          Spotlight(child: photo(top, 112)),
          const SizedBox(height: 12),
          Text(top['student']?['full_name'] ?? '', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Brand.ink)),
          const SizedBox(height: 6),
          Text(top['reason'], textAlign: TextAlign.center, style: const TextStyle(color: Brand.ink, height: 1.45)),
          const SizedBox(height: 6),
          Text('— ${top['posted_by_staff']?['display_name'] ?? 'Class teacher'}', style: const TextStyle(fontSize: 12, color: Brand.amber, fontWeight: FontWeight.w700)),
        ])),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 18),
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Eyebrow('Earlier this year', color: cs.onSurfaceVariant)),
          for (final s in rest) _card(context, Row(children: [
            photo(s, 48), const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(DateFormat('MMMM yyyy').format(DateTime.parse(s['month'])).toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: cs.onSurfaceVariant)),
              Text(s['student']?['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(s['reason'], style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.4)),
            ])),
          ])),
        ],
      ]);
    }));
  }
}

// ---------------------------------------------------------------- calendar
/// The school year planner, one month at a time. Opens on the current month (so on 1 Nov it opens on November);
/// arrows move to the previous / next month.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}
class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String filter = 'all';
  static const colors = {'holiday': (Brand.crimsonDeep, Brand.crimsonTint), 'exam': (Brand.amber, Brand.amberTint), 'ptm': (Brand.violet, Brand.violetTint), 'event': (Brand.blue, Brand.blueTint)};
  static const labels = {'all': 'All', 'holiday': 'Holidays', 'exam': 'Exams', 'ptm': 'Parents', 'event': 'Events'};
  static String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  @override
  Widget build(BuildContext context) {
    final ev = ref.watch(calendarProvider);
    final grade = ref.watch(enrolmentProvider).value?['section']?['grade']?['code'] as String?;
    final cs = Theme.of(context).colorScheme;
    final today = _iso(DateTime.now());
    final first = _iso(month), last = _iso(DateTime(month.year, month.month + 1, 0));
    return AppPage(title: 'Calendar',
      headerExtra: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 30), tooltip: 'Previous month'),
          Expanded(child: GestureDetector(onTap: () => setState(() => month = DateTime(DateTime.now().year, DateTime.now().month)),
              child: Text(DateFormat('MMMM yyyy').format(month), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)))),
          IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 30), tooltip: 'Next month'),
        ]),
        const SizedBox(height: 6),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final e in labels.entries) HeaderChip(e.value, selected: filter == e.key, onTap: () => setState(() => filter = e.key))])),
      ]),
      body: ev.when(loading: _loading, error: (e, _) => _empty(context, '$e'), data: (all) {
        // everything that touches this month (a break from 23 Dec to 1 Jan shows in both months), oldest first
        // working Saturdays (1st, 3rd, 5th) for Grades VI–XII, unless the calendar has a holiday that day
        final sats = <Map<String, dynamic>>[];
        for (var d = month; d.month == month.month; d = DateTime(d.year, d.month, d.day + 1)) {
          if (!isWorkingSaturday(d, grade)) continue;
          final x = _iso(d);
          final off = all.any((e) => e['kind'] == 'holiday' && (e['starts_on'] as String).compareTo(x) <= 0 && ((e['ends_on'] ?? e['starts_on']) as String).compareTo(x) >= 0);
          if (!off) sats.add({'title': 'Working Saturday (${saturdayOrdinal(d)} Saturday) – school is on', 'starts_on': x, 'ends_on': null, 'kind': 'event'});
        }
        final list = [...all, ...sats].where((e) {
          final s = e['starts_on'] as String; final en = (e['ends_on'] ?? s) as String;
          return s.compareTo(last) <= 0 && en.compareTo(first) >= 0 && (filter == 'all' || e['kind'] == filter);
        }).toList()..sort((a, b) => (a['starts_on'] as String).compareTo(b['starts_on'] as String));
        final isThisMonth = month.year == DateTime.now().year && month.month == DateTime.now().month;
        return GestureDetector(
          // swipe left / right also changes the month
          onHorizontalDragEnd: (d) { final v = d.primaryVelocity ?? 0; if (v.abs() > 300) setState(() => month = DateTime(month.year, month.month + (v < 0 ? 1 : -1))); },
          child: ListView(padding: const EdgeInsets.all(20), children: [
            if (!isThisMonth) Padding(padding: const EdgeInsets.only(bottom: 10), child: Center(child: TextButton.icon(onPressed: () => setState(() => month = DateTime(DateTime.now().year, DateTime.now().month)), icon: const Icon(Icons.today_rounded, size: 18), label: const Text('Back to this month')))),
            if (list.isEmpty) _empty(context, filter == 'all' ? 'Nothing on the school calendar for ${DateFormat('MMMM').format(month)}.' : 'No ${labels[filter]!.toLowerCase()} in ${DateFormat('MMMM').format(month)}.'),
            for (final e in list) Builder(builder: (_) {
              final c = colors[e['kind']] ?? (Brand.muted, Brand.surface2);
              final s = e['starts_on'] as String; final en = (e['ends_on'] ?? s) as String; final d = DateTime.parse(s);
              final isToday = s.compareTo(today) <= 0 && en.compareTo(today) >= 0;
              final past = en.compareTo(today) < 0;
              return Opacity(opacity: past ? .5 : 1, child: _card(context, Row(children: [
                Container(width: 48, padding: const EdgeInsets.symmetric(vertical: 6), decoration: BoxDecoration(color: c.$2, borderRadius: BorderRadius.circular(12), border: isToday ? Border.all(color: Brand.crimson, width: 2) : null),
                    child: Column(children: [Text(DateFormat('d').format(d), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: c.$1)), Text(DateFormat('EEE').format(d), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.$1))])),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e['title'], style: TextStyle(fontWeight: e['kind'] == 'holiday' ? FontWeight.w800 : FontWeight.w700, color: e['kind'] == 'holiday' ? context.tone(Brand.crimsonDeep) : null)),
                  if (en != s) Text('${DateFormat('d MMM').format(d)} – ${DateFormat('d MMM yyyy').format(DateTime.parse(en))}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  if ((e['note'] ?? '').toString().trim().isNotEmpty) Text(e['note'].toString().trim(), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ])),
                if (isToday) const Pill('Today', fg: Brand.crimsonDeep, bg: Brand.crimsonTint),
              ]), padding: const EdgeInsets.fromLTRB(10, 10, 14, 10)));
            }),
            const SizedBox(height: 8),
            Text('As per the school diary. The school may revise dates; changes appear here automatically.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ]),
        );
      }));
  }
}

// ---------------------------------------------------------------- report cards
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rc = ref.watch(reportCardsProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(body: Column(children: [
      const BrandHeader(padding: EdgeInsets.fromLTRB(20, 14, 20, 16), child: Text('Report card', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
      Expanded(child: rc.when(loading: _loading, error: (e, _) => _empty(context, '$e'), data: (list) => list.isEmpty ? _empty(context, 'Report cards appear here the moment the school publishes them — no one sees a draft.') :
        ListView(padding: const EdgeInsets.all(20), children: [
          for (final r in list) _card(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Pill(r['academic_year']?['label'] ?? '', fg: Brand.crimsonDeep, bg: Brand.crimsonTint), const Spacer(), Text('Published ${DateFormat('d MMM yyyy').format(DateTime.parse(r['published_at']).toLocal())}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))]),
          const SizedBox(height: 8),
          Text(r['term'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          if (r['working_days'] != null) Text('Attendance ${r['days_present']}/${r['working_days']} days', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          if (r['remarks'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('"${r['remarks']}"', style: const TextStyle(fontStyle: FontStyle.italic, height: 1.45))),
          const SizedBox(height: 12),
          PrimaryButton('Open report card', icon: Icons.mark_email_unread_rounded, onPressed: () => openWithEnvelope(context, title: '${r['term']}', subtitle: '${r['academic_year']?['label'] ?? ''} · Royale Concorde International School', open: () => openReportCardPdf(context, r['id'], name: r['term']))),
        ]))]))),
    ]));
  }
}

