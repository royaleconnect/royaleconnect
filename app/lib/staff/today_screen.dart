import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/data2.dart' show calendarProvider;
import '../core/data3.dart' show appSettingsProvider;
import '../core/theme.dart';
import '../widgets/common.dart';
import '../screens/family_screens.dart' show callNumber;
import 'admin_dashboard.dart';
import 'approvals_page.dart' show approvalsCountProvider, MyReceiptCancels;
import 'password_requests.dart' show PasswordRequestsCard, approvalsInboxProvider, inboxList;
import 'staff_data.dart';
import 'staff_shell.dart';
import '../screens/desk_screen.dart' show DeskHomeCard;
import '../widgets/royal_motion.dart' show FadeRise;
import '../widgets/royal_extras.dart' show FestiveBanner, FestiveSky;
import '../core/cache.dart';
import 'morning_brief.dart' show MorningBrief, TodayPeriods;
import 'thanks_wall.dart' show ThanksWallCard;

/// "Today" — the first page every teacher sees. One NEEDS YOU card (attendance, leave, messages, diary, birthdays),
/// then "Your periods today" (only when the timetable has periods for her), then what is coming up.
/// IT, the Principal and the Vice Principal keep the whole-school dashboard.
String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Everything the NEEDS YOU card shows, in one database call (staff_today()).
final staffTodayProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.cacheFor();
  final r = await db.rpc('staff_today');
  return Map<String, dynamic>.from((r as Map?) ?? const {});
});

/// Families in my class who have not started using the app (a gentle nudge for the class teacher).
final _notUsingProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, sectionId) async {
  ref.cacheFor();
  try {
    return [for (final x in (await db.rpc('not_using_app', params: {'p_section': sectionId})) as List) Map<String, dynamic>.from(x)];
  } catch (_) { return const []; }
});

/// "2 hours ago", "35 minutes ago", "3 days ago".
String _ago(String? iso) {
  if (iso == null) return '';
  final d = DateTime.now().difference(DateTime.parse(iso).toLocal());
  if (d.inMinutes < 2) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} minutes ago';
  if (d.inHours < 24) return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
  return d.inDays == 1 ? 'yesterday' : '${d.inDays} days ago';
}

/// "Aarav’s birthday today" · "Aarav and Diya — birthdays today"
String _birthdayLine(List names) {
  final first = [for (final n in names) '$n'.trim().split(RegExp(r'\s+')).first];
  if (first.length == 1) return '${first.first}’s birthday today';
  final all = first.length == 2 ? first.join(' and ') : '${first.sublist(0, first.length - 1).join(', ')} and ${first.last}';
  return '$all — birthdays today';
}

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value!;
    if (isSchoolAdmin(s)) return const AdminDashboard();
    final cs = Theme.of(context).colorScheme;
    final settings = ref.watch(appSettingsProvider).value;
    bool can(String p) => staffCanOpen(s, settings, p);
    final t = ref.watch(staffTodayProvider);
    final m = t.value ?? const <String, dynamic>{};
    final ov = ref.watch(staffOverviewProvider).value ?? const {};
    final now = DateTime.now();
    final upcoming = (ref.watch(calendarProvider).value ?? const []).where((e) => ((e['ends_on'] ?? e['starts_on']) as String).compareTo(_iso(now)) >= 0).take(5).toList();
    final myClass = m['class'] as Map?;
    final cls = '${myClass?['label'] ?? ''}';
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    final approvals = s.isOffice && can('/staff/approvals') ? ref.watch(approvalsCountProvider) : 0;
    final myCancels = s.hasRole('accounts') ? inboxList(ref.watch(approvalsInboxProvider).value, 'my_cancels') : const <Map<String, dynamic>>[];
    final birthdays = (m['birthdays'] as List?) ?? const [];
    final diarySecs = [for (final x in (m['diary_sections'] as List?) ?? const []) '$x'];

    // ---- NEEDS YOU: one line per job, each with its button
    final rows = <Widget>[
      if (myClass != null && m['school_open'] == true && m['attendance_taken'] == false && can('/staff/attendance'))
        _NeedRow(icon: '✅', tint: Brand.crimsonTint, title: 'Attendance not taken', sub: '$cls · today', action: 'Take', onTap: () => context.go('/staff/attendance')),
      if (n('leaves') > 0 && can('/staff/leave'))
        _NeedRow(icon: '🙋', tint: Brand.blueTint, title: '${n('leaves')} leave request${n('leaves') == 1 ? '' : 's'}', sub: 'Tap to approve', action: 'Open', onTap: () => context.go('/staff/leave')),
      if (n('messages') > 0 && can('/staff/messages'))
        _NeedRow(icon: '💬', tint: Brand.amberTint, title: '${n('messages')} parent message${n('messages') == 1 ? '' : 's'}',
            sub: m['oldest_message_at'] != null ? 'Oldest ${_ago(m['oldest_message_at'] as String?)}' : 'Waiting for your reply', action: 'Reply', onTap: () => context.go('/staff/messages')),
      if (n('diary_pending') > 0 && can('/staff/diary'))
        _NeedRow(icon: '📖', tint: Brand.violetTint, title: '${n('diary_pending')} diary ${n('diary_pending') == 1 ? 'note' : 'notes'} to post',
            sub: diarySecs.isEmpty ? 'Nothing posted for today yet' : diarySecs.join(' · '), action: 'Post', onTap: () => context.go('/staff/diary')),
      if (approvals > 0)
        _NeedRow(icon: '📥', tint: Brand.crimsonTint, title: '$approvals waiting in Approvals', sub: 'Password help and certificates', action: 'Open', onTap: () => context.go('/staff/approvals')),
      if ((ov['feedback'] ?? 0) > 0 && can('/staff/feedback'))
        _NeedRow(icon: '🗣', tint: Brand.violetTint, title: '${ov['feedback']} new parent feedback', sub: 'From the families', action: 'Read', onTap: () => context.go('/staff/feedback')),
      if (birthdays.isNotEmpty)
        _NeedRow(icon: '🎂', tint: Brand.greenTint, title: _birthdayLine(birthdays), sub: cls),
    ];

    final needs = Panel(padding: const EdgeInsets.fromLTRB(16, 14, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('NEEDS YOU', style: TextStyle(fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
      const SizedBox(height: 6),
      if (t.isLoading && t.value == null) const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: LinearProgressIndicator(minHeight: 2))
      else if (rows.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [
        Icon(Icons.check_circle_rounded, color: context.tone(Brand.green)), const SizedBox(width: 10),
        const Expanded(child: Text('Nothing waiting. Well done!', style: TextStyle(fontWeight: FontWeight.w700))),
      ]))
      else for (final (i, w) in rows.indexed) ...[if (i > 0) Divider(height: 1, color: cs.outline.withValues(alpha: .5)), w],
    ]));

    final notUsing = myClass == null ? const <Map<String, dynamic>>[] : ref.watch(_notUsingProvider('${myClass['id']}')).value ?? const [];
    final coming = Panel(title: 'Coming up', child: upcoming.isEmpty
        ? Text('Nothing on the school calendar in the next few weeks.', style: TextStyle(color: cs.onSurfaceVariant))
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final (i, e) in upcoming.indexed) ...[
            if (i > 0) Divider(height: 16, color: cs.outline.withValues(alpha: .6)),
            Text.rich(TextSpan(children: [
              TextSpan(text: DateFormat('EEE d MMM').format(DateTime.parse(e['starts_on'])), style: const TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: ' · ${e['title']}'),
            ])),
          ]]));

    return FestiveSky(child: StaffPage(
      title: 'Today',
      subtitle: myClass == null ? null : '$cls · ${myClass['students'] ?? 0} students',   // the date is on the greeting card
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const FestiveBanner(),
        const MorningBrief(),
        if (t.hasError) Panel(child: Text(friendlyError(t.error!), style: const TextStyle(color: Brand.crimsonDeep))) else FadeRise(child: needs),
        const TodayPeriods(),
        // password help: the class teacher handles it here; the office sees it in Approvals (the line above)
        if (!s.isOffice || !can('/staff/approvals')) const PasswordRequestsCard(),
        if (myCancels.isNotEmpty) MyReceiptCancels(rows: myCancels),
        const FadeRise(delayMs: 120, child: DeskHomeCard(staff: true)),
        if (myClass != null && notUsing.isNotEmpty) Panel(padding: const EdgeInsets.all(14), child: CardRow(children: [
          const Icon(Icons.phonelink_off_rounded, color: Brand.amber), const SizedBox(width: 12),
          Expanded(child: Text('${notUsing.length} ${notUsing.length == 1 ? 'family' : 'families'} in $cls ${notUsing.length == 1 ? 'has' : 'have'} not started using Royale Connect yet. A quick call helps.', style: const TextStyle(fontWeight: FontWeight.w700))),
          OutlinedButton(onPressed: () => showDialog(context: context, builder: (_) => _NotUsingDialog(cls: cls, rows: notUsing)), child: const Text('See the list')),
        ])),
        coming,
        const ThanksWallCard(),
      ]),
    ));
  }
}

/// One line of the NEEDS YOU card: icon, what, a small line under it, and the button on the right.
class _NeedRow extends StatelessWidget {
  final String icon, title, sub; final Color tint; final String? action; final VoidCallback? onTap;
  const _NeedRow({required this.icon, required this.tint, required this.title, required this.sub, this.action, this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(children: [
      Container(width: 36, height: 36, alignment: Alignment.center, decoration: BoxDecoration(color: dark ? tint.withValues(alpha: .18) : tint, borderRadius: BorderRadius.circular(10)),
          child: Text(icon, style: const TextStyle(fontSize: 17))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
        if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ])),
      if (action != null) Text('$action ›', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: context.tone(Brand.crimson))),
    ])));
  }
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
