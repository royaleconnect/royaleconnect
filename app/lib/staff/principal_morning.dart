import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart' show inr;
import 'approvals_page.dart' show leavingsInboxProvider;
import 'password_requests.dart' show approvalsInboxProvider;
import 'staff_data.dart' show remindAnnouncement;
import 'staff_shell.dart' show toast;

/// The Principal's morning: 5 cards at the top of her Home, everything that needs her today on one page.
/// Tap a card to see what is behind it; the link at the bottom opens the full page.
///   Students present · Waiting for you · Fees collected today · Latest notice · Today in school
final principalMorningProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.cacheFor(const Duration(minutes: 2));
  final r = await db.rpc('principal_morning');
  return Map<String, dynamic>.from((r as Map?) ?? const {});
});

class PrincipalMorning extends ConsumerStatefulWidget {
  const PrincipalMorning({super.key});
  @override
  ConsumerState<PrincipalMorning> createState() => _PrincipalMorningState();
}

class _Card {
  final String key, label, value, line, pill, heading, go, route; final IconData icon; final Color fg, bg, pillFg, pillBg; final List<(String, String)> rows;
  const _Card(this.key, this.icon, this.fg, this.bg, this.label, this.value, this.line, this.pill, this.pillFg, this.pillBg, this.heading, this.go, this.route, this.rows);
}

class _PrincipalMorningState extends ConsumerState<PrincipalMorning> {
  String? open; bool reminding = false;
  String _n(num v) => NumberFormat.decimalPattern('en_IN').format(v);
  String _lakh(num v) => v >= 100000 ? '₹${(v / 100000).toStringAsFixed(1)} L' : inr(v);

  @override
  Widget build(BuildContext context) {
    final m = ref.watch(principalMorningProvider);
    final inbox = ref.watch(approvalsInboxProvider).value;
    final leavings = ref.watch(leavingsInboxProvider).value ?? const [];
    return m.when(loading: () => const SizedBox.shrink(), error: (e, _) => const SizedBox.shrink(), data: (d) {
      final cards = _cards(d, inbox, leavings);
      final cur = cards.where((c) => c.key == open).firstOrNull;
      return Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (_, box) {
          final per = box.maxWidth >= 1150 ? 5 : box.maxWidth >= 860 ? 3 : box.maxWidth >= 520 ? 2 : 1;
          final w = (box.maxWidth - 12 * (per - 1)) / per;
          return Wrap(spacing: 12, runSpacing: 12, children: [for (final c in cards) SizedBox(width: w, child: _tile(c))]);
        }),
        AnimatedSize(duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic, child: cur == null ? const SizedBox(width: double.infinity) : _detail(cur, d)),
      ]));
    });
  }

  List<_Card> _cards(Map<String, dynamic> d, Map<String, dynamic>? inbox, List leavings) {
    final at = Map<String, dynamic>.from(d['attendance'] ?? const {});
    final marked = (at['marked'] ?? 0) as num, present = (at['present'] ?? 0) as num, absent = (at['absent'] ?? 0) as num, onLeave = (at['on_leave'] ?? 0) as num;
    final notMarked = [for (final x in (at['not_marked'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    final closed = at['closed'] == true;
    final fees = Map<String, dynamic>.from(d['fees'] ?? const {});
    final notice = d['notice'] == null ? null : Map<String, dynamic>.from(d['notice']);
    final today = Map<String, dynamic>.from(d['today'] ?? const {});
    final events = [for (final x in (today['events'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    final staffBd = [for (final x in (today['staff_birthdays'] as List? ?? const [])) '$x'];
    final stuBd = (today['student_birthdays'] ?? 0) as num;

    // waiting for her decision: TC requests, receipt cancellations, students leaving, data corrections
    List<Map<String, dynamic>> lst(String k) => [for (final x in ((inbox?[k] as List?) ?? const [])) Map<String, dynamic>.from(x as Map)];
    final decide = inbox?['can_decide'] == true;
    final tcs = decide ? lst('tcs') : const <Map<String, dynamic>>[], cancels = decide ? lst('cancels') : const <Map<String, dynamic>>[], fixes = decide ? lst('corrections') : const <Map<String, dynamic>>[];
    final leaving = decide ? leavings : const [];
    final waiting = tcs.length + cancels.length + fixes.length + leaving.length;
    String who(Map<String, dynamic> r) => '${r['student'] ?? r['student_name'] ?? ''}${(r['class'] ?? '').toString().isNotEmpty ? ' · ${r['class']}' : ''}';

    final readPct = notice == null || (notice['total'] ?? 0) == 0 ? 0 : ((notice['read'] as num) * 100 / (notice['total'] as num)).round();
    final unread = notice == null ? 0 : (notice['total'] as num) - (notice['read'] as num);

    return [
      _Card('att', Icons.fact_check_rounded, Brand.green, Brand.greenTint, 'STUDENTS PRESENT',
        closed ? 'Closed' : marked == 0 ? '—' : '${(present * 100 / marked).round()}%',
        closed ? 'No school today' : '${_n(present)} of ${_n(marked)} marked present',
        closed ? 'Holiday' : notMarked.isEmpty ? 'All classes marked' : '${notMarked.length} ${notMarked.length == 1 ? 'class' : 'classes'} not marked yet',
        notMarked.isEmpty ? Brand.green : Brand.amber, notMarked.isEmpty ? Brand.greenTint : Brand.amberTint,
        'Attendance today', 'Open attendance', '/staff/attendance', [
          for (final x in notMarked.take(8)) ('${x['label']}', 'Not marked yet · ${x['teacher']}'),
          if (notMarked.length > 8) ('…', '${notMarked.length - 8} more classes not marked'),
          ('Absent today', '${_n(absent)} students${onLeave > 0 ? ' · ${_n(onLeave)} on approved leave' : ''}'),
        ]),
      _Card('wait', Icons.inbox_rounded, Brand.amber, Brand.amberTint, 'WAITING FOR YOU', '$waiting', waiting == 0 ? 'nothing needs you now' : 'need your yes or no',
        waiting == 0 ? 'All clear' : [if (tcs.isNotEmpty) '${tcs.length} TC', if (cancels.isNotEmpty) '${cancels.length} receipt', if (leaving.isNotEmpty) '${leaving.length} leaving', if (fixes.isNotEmpty) '${fixes.length} correction'].join(' · '),
        waiting == 0 ? Brand.green : Brand.amber, waiting == 0 ? Brand.greenTint : Brand.amberTint,
        'Waiting for your decision', 'Open approvals', '/staff/approvals', [
          for (final r in tcs) ('TC request', who(r)),
          for (final r in cancels) ('Receipt cancellation', '${r['receipt_no'] ?? ''}${r['amount'] != null ? ' · ${inr(r['amount'] as num)}' : ''}'),
          for (final r in leaving) ('Student leaving', who(Map<String, dynamic>.from(r as Map))),
          for (final r in fixes) ('Data correction', who(r)),
          if (waiting == 0) ('All clear', 'Nothing is waiting for you right now'),
        ]),
      _Card('fees', Icons.currency_rupee_rounded, Brand.green, Brand.greenTint, 'FEES COLLECTED TODAY', inr((fees['total'] ?? 0) as num),
        '${fees['count'] ?? 0} receipt${fees['count'] == 1 ? '' : 's'}', 'This month ${_lakh((fees['month'] ?? 0) as num)}', Brand.green, Brand.greenTint,
        'Fees today', 'Open fee reports', '/staff/fees/reports', [
          ('Online', '${inr((fees['online'] ?? 0) as num)} · ${fees['online_n'] ?? 0} receipts'),
          ('Cash at the office', '${inr((fees['cash'] ?? 0) as num)} · ${fees['cash_n'] ?? 0} receipts'),
          ('Cheque / bank', '${inr((fees['bank'] ?? 0) as num)} · ${fees['bank_n'] ?? 0} receipts'),
          ('Overdue (whole school)', '${_lakh((fees['overdue'] ?? 0) as num)} · ${_n((fees['overdue_students'] ?? 0) as num)} students'),
        ]),
      _Card('notice', Icons.campaign_rounded, Brand.blue, Brand.blueTint, 'LATEST NOTICE', notice == null ? '—' : '$readPct%',
        notice == null ? 'no notice sent yet' : 'families have read “${notice['title']}”', notice == null ? 'Nothing sent' : unread == 0 ? 'Everyone has read it' : '${_n(unread)} not read yet',
        Brand.blue, Brand.blueTint, notice == null ? 'Latest notice' : 'Latest notice · ${notice['title']}', 'Open notices', '/staff/announcements', notice == null ? const [] : [
          ('Sent', DateFormat('EEE d MMM, h:mm a').format(DateTime.parse(notice['sent_at']).toLocal())),
          ('Read', '${_n(notice['read'] as num)} families ($readPct%)'),
          ('Not read yet', '${_n(unread)} families'),
        ]),
      _Card('day', Icons.auto_awesome_rounded, const Color(0xFF6B4A08), const Color(0xFFF7E9C6), 'TODAY IN SCHOOL', '${events.length}',
        events.isEmpty ? 'no events on the calendar' : events.length == 1 ? '${events.first['title']}' : 'events and dates today',
        '${_n(stuBd)} student birthday${stuBd == 1 ? '' : 's'}${staffBd.isNotEmpty ? ' · ${staffBd.length} staff' : ''}', const Color(0xFF6B4A08), const Color(0xFFF7E9C6),
        'Today in school', 'Open calendar', '/staff/calendar', [
          for (final e in events) ('${e['kind'] ?? 'Event'}'.replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase()), '${e['title']}'),
          ('Birthdays', '${_n(stuBd)} student${stuBd == 1 ? '' : 's'}${staffBd.isNotEmpty ? ' · staff: ${staffBd.join(', ')}' : ''} — the app wishes them itself'),
        ]),
    ];
  }

  Widget _tile(_Card c) {
    final cs = Theme.of(context).colorScheme;
    final on = open == c.key;
    return Material(color: cs.surface, borderRadius: BorderRadius.circular(18), child: InkWell(borderRadius: BorderRadius.circular(18), onTap: () => setState(() => open = on ? null : c.key),
      child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: on ? Brand.gold : cs.outlineVariant, width: on ? 2 : 1)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 28, height: 28, decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(9)), child: Icon(c.icon, size: 16, color: c.fg)),
            const SizedBox(width: 8),
            Expanded(child: Text(c.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 8),
          Text(c.value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(c.line, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: c.pillBg, borderRadius: BorderRadius.circular(99)),
              child: Text(c.pill, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.pillFg), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]))));
  }

  Widget _detail(_Card c, Map<String, dynamic> d) {
    final cs = Theme.of(context).colorScheme;
    final notice = d['notice'] == null ? null : Map<String, dynamic>.from(d['notice']);
    final unread = notice == null ? 0 : (notice['total'] as num) - (notice['read'] as num);
    return Container(width: double.infinity, margin: const EdgeInsets.only(top: 14), padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(c.heading, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          if (c.key == 'notice' && notice != null && unread > 0) Padding(padding: const EdgeInsets.only(right: 8), child: OutlinedButton.icon(onPressed: reminding ? null : () async {
            setState(() => reminding = true);
            try { final n = await remindAnnouncement(notice['id']); if (mounted) toast(context, 'Reminder sent to $n ${n == 1 ? 'family' : 'families'} ✓'); }
            catch (e) { if (mounted) toast(context, friendlyError(e)); }
            if (mounted) setState(() => reminding = false);
          }, icon: const Icon(Icons.notifications_active_rounded, size: 16), label: Text(reminding ? 'Sending…' : 'Remind the $unread'))),
          TextButton(onPressed: () => context.go(c.route), child: Text('${c.go} →', style: const TextStyle(color: Brand.crimson, fontWeight: FontWeight.w800))),
        ]),
        for (final r in c.rows) Container(padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 190, child: Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w800))),
            Expanded(child: Text(r.$2, style: TextStyle(color: cs.onSurfaceVariant))),
          ])),
      ]));
  }
}
