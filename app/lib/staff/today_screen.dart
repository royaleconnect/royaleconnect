import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/data2.dart' show calendarProvider;
import '../core/data3.dart' show isBirthday;
import '../core/theme.dart';
import '../widgets/common.dart';
import '../screens/family_screens.dart' show callNumber;
import 'admin_dashboard.dart';
import 'staff_data.dart';
import 'staff_shell.dart';
import '../screens/desk_screen.dart' show DeskHomeCard;
import '../widgets/royal_motion.dart' show FadeRise;

/// "Today" — the first page every teacher sees: what is waiting for them, with the button to do it right there.
/// IT, the Principal and the Vice Principal keep the whole-school dashboard.
String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// My class (as class teacher), its size, and the sections where I have not posted in the diary today.
final _todayProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final s = ref.watch(sessionProvider).value!;
  final me = s.staff!['id'];
  final secs = await ref.watch(mySectionsProvider.future);
  final assignments = await ref.watch(myAssignmentsProvider.future);
  final mine = secs.where((x) => x['class_teacher_id'] == me).toList();
  int students = 0;
  final birthdays = <String>[];
  var notUsing = <Map<String, dynamic>>[];
  if (mine.isNotEmpty) {
    final r = await db.from('enrolment').select('student_id,student:student_id(full_name,dob,active)').eq('section_id', mine.first['id']);
    students = r.length;
    for (final e in r) {
      final st = e['student'];
      if (st != null && st['active'] == true && isBirthday(st['dob'] as String?)) birthdays.add('${st['full_name']}');
    }
    try { notUsing = [for (final x in (await db.rpc('not_using_app', params: {'p_section': mine.first['id']})) as List) Map<String, dynamic>.from(x)]; } catch (_) {}
  }
  // sections I teach a subject in (or am class teacher of) with no diary post from me today
  final teach = {for (final a in assignments) a['section_id'] as String, for (final m in mine) m['id'] as String};
  final posted = await db.from('diary_entry').select('section_id').eq('author_id', me).eq('for_date', _iso(DateTime.now()));
  final done = {for (final p in posted) p['section_id'] as String};
  final notPosted = [for (final x in secs) if (teach.contains(x['id']) && !done.contains(x['id'])) x];
  return {'class': mine.isEmpty ? null : mine.first, 'students': students, 'not_posted': notPosted, 'birthdays': birthdays, 'not_using': notUsing};
});

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value!;
    if (isSchoolAdmin(s)) return const AdminDashboard();
    final cs = Theme.of(context).colorScheme;
    final ov = ref.watch(staffOverviewProvider).value ?? const {};
    final today = ref.watch(_todayProvider).value;
    final leaves = (ref.watch(staffLeavesProvider).value ?? const []).where((l) => l['status'] == 'pending').toList();
    final inbox = (ref.watch(inboxProvider).value ?? const []).where((c) => ((c['staff_unread'] ?? 0) as int) > 0).toList();
    final now = DateTime.now();
    final upcoming = (ref.watch(calendarProvider).value ?? const []).where((e) => ((e['ends_on'] ?? e['starts_on']) as String).compareTo(_iso(now)) >= 0).take(5).toList();
    final hour = now.hour;
    final myClass = today?['class'] as Map<String, dynamic>?;
    final notPosted = (today?['not_posted'] as List?) ?? const [];
    final narrow = isNarrow(context);

    Widget tile(String n, String label, String action, Color c, String path) => Expanded(child: Material(color: cs.surface, borderRadius: BorderRadius.circular(18), child: InkWell(
      onTap: () => context.go(path), borderRadius: BorderRadius.circular(18),
      child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outline.withValues(alpha: .6))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: context.tone(c))),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 8),
          Text('$action →', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: context.tone(c))),
        ])))));
    final tiles = [
      tile('${ov['unread'] ?? 0}', 'Parent messages waiting', (ov['unread'] ?? 0) > 0 ? 'Reply' : 'Open messages', Brand.crimson, '/staff/messages'),
      tile('${ov['leaves'] ?? 0}', 'Leave requests to approve', 'Review', Brand.amber, '/staff/leave'),
      tile('${notPosted.length}', notPosted.length == 1 ? 'Class without homework today' : 'Classes without homework today', notPosted.isEmpty ? 'All posted ✓' : 'Post now', notPosted.isEmpty ? Brand.green : Brand.blue, '/staff/diary'),
      if (s.isOffice) tile('${ov['feedback'] ?? 0}', 'New parent feedback', 'Read', Brand.violet, '/staff/feedback'),
    ];
    Widget line(List<Widget> ts) => IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final (i, t) in ts.indexed) ...[if (i > 0) const SizedBox(width: 12), t]]));

    final needs = <Widget>[
      for (final l in leaves.take(3)) _NeedRow(
        text: TextSpan(children: [
          const TextSpan(text: 'Leave · ', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: '${l['student']?['full_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: ' — ${_days(l)}, ${l['reason'] ?? ''}'),
        ]),
        actions: [
          OutlinedButton(onPressed: () async { await decideLeave(ref, l['id'], false); ref.invalidate(staffLeavesProvider); ref.invalidate(staffOverviewProvider); }, child: const Text('Decline')),
          FilledButton(onPressed: () async { await decideLeave(ref, l['id'], true); ref.invalidate(staffLeavesProvider); ref.invalidate(staffOverviewProvider); }, child: const Text('Approve')),
        ]),
      for (final c in inbox.take(3)) _NeedRow(
        text: TextSpan(children: [
          const TextSpan(text: 'Message · ', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: 'Parent of ${c['student']?['full_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: ' — ${c['staff_unread']} new'),
        ]),
        actions: [OutlinedButton(onPressed: () => context.go('/staff/messages'), child: const Text('Reply'))]),
      for (final x in notPosted.take(3)) _NeedRow(
        text: TextSpan(children: [
          const TextSpan(text: 'Diary · ', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: sectionLabel(Map<String, dynamic>.from(x as Map)), style: const TextStyle(fontWeight: FontWeight.w800)),
          const TextSpan(text: ' — nothing posted by you today'),
        ]),
        actions: [OutlinedButton(onPressed: () => context.go('/staff/diary'), child: const Text('Post'))]),
    ];

    final needsPanel = Panel(title: 'Needs you', child: needs.isEmpty
        ? Row(children: [Icon(Icons.check_circle_rounded, color: context.tone(Brand.green)), const SizedBox(width: 10), const Expanded(child: Text('Nothing waiting. Well done!', style: TextStyle(fontWeight: FontWeight.w700)))])
        : Column(children: [for (final (i, w) in needs.indexed) ...[if (i > 0) Divider(height: 18, color: cs.outline.withValues(alpha: .6)), w]]));
    final comingPanel = Panel(title: 'Coming up', child: upcoming.isEmpty
        ? Text('Nothing on the school calendar in the next few weeks.', style: TextStyle(color: cs.onSurfaceVariant))
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final (i, e) in upcoming.indexed) ...[
            if (i > 0) Divider(height: 16, color: cs.outline.withValues(alpha: .6)),
            Text.rich(TextSpan(children: [
              TextSpan(text: DateFormat('EEE d MMM').format(DateTime.parse(e['starts_on'])), style: const TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: ' · ${e['title']}'),
            ])),
          ]]));

    return StaffPage(
      title: '${hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening'}, ${s.staff?['name'] ?? ''}',
      subtitle: [DateFormat('EEEE, d MMMM').format(now), if (myClass != null) sectionLabel(myClass), if (myClass != null) '${today?['students'] ?? 0} students'].join(' · '),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const FadeRise(delayMs: 120, child: DeskHomeCard(staff: true)),
        if (((today?['birthdays'] as List?) ?? const []).isNotEmpty) Container(
          margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFF6E0), Color(0xFFFFE3E3)]), border: Border.all(color: Brand.gold, width: 1.5), borderRadius: BorderRadius.circular(16)),
          child: Text('🎂  Birthday today: ${(today!['birthdays'] as List).join(', ')} — the family has been sent the school’s wishes.', style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.crimsonDeep))),
        if (narrow) ...[line(tiles.sublist(0, 2)), const SizedBox(height: 12), line(tiles.sublist(2))] else line(tiles),
        const SizedBox(height: 16),
        if (myClass != null && ((today?['not_using'] as List?) ?? const []).isNotEmpty) Panel(padding: const EdgeInsets.all(14), child: CardRow(children: [
          const Icon(Icons.phonelink_off_rounded, color: Brand.amber), const SizedBox(width: 12),
          Expanded(child: Text('${(today!['not_using'] as List).length} families in ${sectionLabel(myClass)} have not started using Royale Connect yet. A quick call helps.', style: const TextStyle(fontWeight: FontWeight.w700))),
          OutlinedButton(onPressed: () => showDialog(context: context, builder: (_) => _NotUsingDialog(cls: sectionLabel(myClass), rows: List<Map<String, dynamic>>.from(today['not_using'] as List))), child: const Text('See the list')),
        ])),
        if (narrow) ...[needsPanel, comingPanel]
        else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: needsPanel), const SizedBox(width: 14), Expanded(flex: 2, child: comingPanel)]),
      ]),
    );
  }

  static String _days(Map<String, dynamic> l) {
    final a = DateTime.parse(l['from_date']), b = DateTime.parse(l['to_date'] ?? l['from_date']);
    final n = b.difference(a).inDays + 1;
    return n == 1 ? DateFormat('d MMM').format(a) : '$n days from ${DateFormat('d MMM').format(a)}';
  }
}

class _NeedRow extends StatelessWidget {
  final InlineSpan text; final List<Widget> actions;
  const _NeedRow({required this.text, required this.actions});
  @override
  Widget build(BuildContext context) => CardRow(children: [
    Expanded(child: Padding(padding: const EdgeInsets.only(top: 6), child: Text.rich(text, style: const TextStyle(fontSize: 14)))),
    for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: a),
  ]);
}


class _NotUsingDialog extends StatelessWidget {
  final String cls; final List<Map<String, dynamic>> rows;
  const _NotUsingDialog({required this.cls, required this.rows});
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Not using the app yet · $cls'),
    content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const NoteBox('Ask the parents to install Royale Connect and sign in with the admission number and the password slip. The office can print a new slip if it is lost.'),
      const SizedBox(height: 8),
      for (final r in rows) ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('${r['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${r['admission_no']}${r['phones'] != null ? ' · ${r['phones']}' : ''}'),
        trailing: r['phones'] == null ? null : IconButton(icon: const Icon(Icons.call_rounded, color: Brand.green), tooltip: 'Call',
            onPressed: () => callNumber('${r['phones']}'.split(' ').first.replaceAll(',', ''))),
      ),
    ]))),
    actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
  );
}
