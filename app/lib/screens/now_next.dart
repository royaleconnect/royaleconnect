import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../core/data2.dart';
import '../core/data3.dart' show appSettingsProvider, featureOn;
import '../core/theme.dart';

/// What is happening in class right now, from the class timetable — for the family Home.
/// "Now: Maths · Next: English at 10:40" during school hours on school days; nothing at other times.
/// Hidden on Sundays, off Saturdays, holidays on the school calendar, and when IT has switched the timetable off.
class NowNextLine extends ConsumerStatefulWidget {
  const NowNextLine({super.key});
  @override
  ConsumerState<NowNextLine> createState() => _NowNextLineState();
}

class _NowNextLineState extends ConsumerState<NowNextLine> {
  Timer? _t;
  @override
  void initState() { super.initState(); _t = Timer.periodic(const Duration(seconds: 30), (_) { if (mounted) setState(() {}); }); }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!featureOn(ref.watch(appSettingsProvider).value, 'timetable')) return const SizedBox.shrink();
    final slots = ref.watch(timetableProvider).value;
    if (slots == null || slots.isEmpty) return const SizedBox.shrink();
    final grade = ref.watch(enrolmentProvider).value?['section']?['grade']?['code'] as String?;
    final calendar = ref.watch(calendarProvider).value ?? const [];
    final text = nowNextText(slots, DateTime.now(), grade: grade, calendar: calendar);
    if (text == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Material(color: cs.surface, borderRadius: BorderRadius.circular(16), child: InkWell(
      borderRadius: BorderRadius.circular(16), onTap: () => context.push('/timetable'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border(left: BorderSide(color: Brand.gold.withValues(alpha: .9), width: 4))),
        child: Row(children: [
          Icon(Icons.schedule_rounded, size: 20, color: context.tone(Brand.crimson)),
          const SizedBox(width: 10),
          Expanded(child: Text.rich(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.35))),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ]),
      ),
    )));
  }
}

String _subject(Map<String, dynamic> s) => (s['subject']?['name'] ?? s['label'] ?? 'Free period').toString();
DateTime _at(DateTime day, dynamic hhmm) {
  final p = '$hhmm'.split(':');
  return DateTime(day.year, day.month, day.day, int.tryParse(p.first) ?? 0, p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
}

/// The line for [now], or null when there is nothing to say (no school today, before 1 hour of the first period, after the last).
TextSpan? nowNextText(List<Map<String, dynamic>> slots, DateTime now, {String? grade, List<Map<String, dynamic>> calendar = const []}) {
  if (now.weekday == DateTime.sunday) return null;
  if (now.weekday == DateTime.saturday && grade != null && !isWorkingSaturday(now, grade)) return null;
  final iso = DateFormat('yyyy-MM-dd').format(now);
  final holiday = calendar.any((e) => e['kind'] == 'holiday' && (e['starts_on'] as String).compareTo(iso) <= 0 &&
      ((e['ends_on'] ?? e['starts_on']) as String).compareTo(iso) >= 0 && eventIsFor(e, grade));
  if (holiday) return null;
  final today = slots.where((s) => s['weekday'] == now.weekday && s['starts_at'] != null).toList()
    ..sort((a, b) => (a['period'] as int).compareTo(b['period'] as int));
  if (today.isEmpty) return null;
  final starts = [for (final s in today) _at(now, s['starts_at'])];
  // a period lasts as long as the shortest gap between two periods (breaks make the other gaps longer); 40 min if unknown
  var len = 40;
  for (var i = 1; i < starts.length; i++) {
    final g = starts[i].difference(starts[i - 1]).inMinutes;
    if (g >= 25 && g < len) len = g;
  }
  final hm = DateFormat('h:mm');
  const b = TextStyle(fontWeight: FontWeight.w800);
  if (now.isBefore(starts.first)) {
    if (starts.first.difference(now).inMinutes > 60) return null;
    return TextSpan(children: [const TextSpan(text: 'First period: '), TextSpan(text: _subject(today.first), style: b), TextSpan(text: ' at ${hm.format(starts.first)}')]);
  }
  for (var i = 0; i < today.length; i++) {
    final end = starts[i].add(Duration(minutes: len));
    final nextStart = i + 1 < starts.length ? starts[i + 1] : null;
    final inPeriod = !now.isBefore(starts[i]) && now.isBefore(nextStart != null && nextStart.isBefore(end) ? nextStart : end);
    if (inPeriod) {
      return TextSpan(children: [
        const TextSpan(text: 'Now: '), TextSpan(text: _subject(today[i]), style: b),
        if (nextStart != null) ...[const TextSpan(text: '  ·  Next: '), TextSpan(text: _subject(today[i + 1]), style: b), TextSpan(text: ' at ${hm.format(nextStart)}')]
        else const TextSpan(text: '  ·  last period'),
      ]);
    }
    if (nextStart != null && !now.isBefore(end) && now.isBefore(nextStart)) {
      return TextSpan(children: [const TextSpan(text: 'Break  ·  Next: '), TextSpan(text: _subject(today[i + 1]), style: b), TextSpan(text: ' at ${hm.format(nextStart)}')]);
    }
  }
  return null;   // school is over for the day
}

/// "Periodic Test 2 in 5 days" — when an exam (published for the child's grade) starts within the next 14 days.
class ExamCountdownChip extends ConsumerWidget {
  const ExamCountdownChip({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exams = ref.watch(examsProvider).value ?? const [];
    final now = DateTime.now(), today = DateTime(now.year, now.month, now.day);
    Map<String, dynamic>? next; int days = 99;
    for (final e in exams) {
      final d = DateTime.tryParse('${e['starts_on']}');
      if (d == null) continue;
      final n = DateTime(d.year, d.month, d.day).difference(today).inDays;
      if (n >= 0 && n <= 14 && n < days) { days = n; next = e; }
    }
    if (next == null) return const SizedBox.shrink();
    final when = days == 0 ? 'starts today' : days == 1 ? 'starts tomorrow' : 'in $days days';
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Align(alignment: Alignment.centerLeft, child: Material(
      color: Brand.amberTint, shape: StadiumBorder(side: BorderSide(color: Brand.gold.withValues(alpha: .7))),
      child: InkWell(customBorder: const StadiumBorder(), onTap: () => context.push('/exams'), child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.edit_calendar_rounded, size: 16, color: Color(0xFF7A5A1C)),
          const SizedBox(width: 8),
          Flexible(child: Text('${next['name']} $when', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF5A4210)))),
        ]),
      )),
    )));
  }
}
