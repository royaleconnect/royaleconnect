import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../core/config.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../core/xlsx_writer.dart';
import '../widgets/common.dart';
import 'office_reports.dart' show StatCard, statGrid, ReportTable, wideTable;
import 'staff_data.dart' show remindAnnouncement;
import 'staff_shell.dart';

/// Part 8 pieces that sit inside pages that were already there:
///   • School strength — "Look at students by" gender / house / transport / category, and month by month
///   • Notices — who read a notice (with Excel and a reminder to those who have not)
///   • Students — the count cards, and Lock app with its two reasons (fees pending · other reason)
///   • Today — a few numbers for the Principal, IT, the office and accounts
///   • Student Council — voting by one link, without signing in

// ================================================================== SCHOOL STRENGTH VIEWS
final _viewsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => Map<String, dynamic>.from(await db.rpc('strength_views') as Map));

class StrengthViews extends ConsumerStatefulWidget {
  const StrengthViews({super.key});
  @override
  ConsumerState<StrengthViews> createState() => _StrengthViewsState();
}

class _StrengthViewsState extends ConsumerState<StrengthViews> {
  String by = 'gender';
  static const _tabs = [('gender', 'Gender'), ('house', 'House'), ('transport', 'Transport'), ('category', 'Category'), ('months', 'Month by month')];
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Panel(title: 'Look at students by', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final (k, t) in _tabs) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(t), selected: by == k, showCheckmark: false, selectedColor: Brand.crimson,
            labelStyle: TextStyle(fontWeight: FontWeight.w800, color: by == k ? Colors.white : null), onSelected: (_) => setState(() => by = k))),
      ])),
      const SizedBox(height: 12),
      ref.watch(_viewsProvider).when(
        loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator(minHeight: 2)),
        error: (e, _) => Text(friendlyError(e)),
        data: (d) {
          if (by == 'months') {
            final ms = [for (final x in (d['months'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
            return wideTable(context, ReportTable(
              cols: const [('Month', 3, false), ('New admissions', 2, true), ('Left', 2, true), ('Came back', 2, true), ('On rolls at month end', 3, true)],
              rows: [for (final m in ms) [
                Text(DateFormat('MMMM yyyy').format(DateTime.parse('${m['month']}-01')), style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${m['joined']}', style: TextStyle(color: (m['joined'] ?? 0) > 0 ? context.tone(Brand.green) : null, fontWeight: FontWeight.w700)),
                Text('${m['left']}', style: TextStyle(color: (m['left'] ?? 0) > 0 ? context.tone(Brand.crimsonDeep) : null, fontWeight: FontWeight.w700)),
                Text('${m['back']}'), Text('${m['closing']}', style: const TextStyle(fontWeight: FontWeight.w900)),
              ]]), min: 600);
          }
          final rows = [for (final x in (d['by'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
          final tot = <String, int>{};
          for (final r in rows) { Map<String, dynamic>.from(r[by] ?? const {}).forEach((k, v) => tot[k] = (tot[k] ?? 0) + (v as num).toInt()); }
          // biggest first; "Not filled" / "No house" always last
          bool last(String k) => k == 'Not filled' || k == 'No house';
          final keys = tot.keys.toList()..sort((a, b) => last(a) != last(b) ? (last(a) ? 1 : -1) : tot[b]!.compareTo(tot[a]!));
          if (keys.isEmpty) return Text('No students yet.', style: TextStyle(color: cs.onSurfaceVariant));
          final all = rows.fold<int>(0, (a, r) => a + ((r['on_rolls'] ?? 0) as num).toInt());
          return wideTable(context, ReportTable(
            cols: [('Class', 4, false), for (final k in keys) (k, 2, true), ('On rolls', 2, true)],
            rows: [
              for (final r in rows) [Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                for (final k in keys) Text('${Map<String, dynamic>.from(r[by] ?? const {})[k] ?? 0}', style: TextStyle(color: last(k) ? cs.onSurfaceVariant : null)),
                Text('${r['on_rolls']}', style: const TextStyle(fontWeight: FontWeight.w900))],
              [const Text('Total'), for (final k in keys) Text('${tot[k]}'), Text('$all')],
            ], totals: {rows.length}), min: 360.0 + keys.length * 110);
        }),
      const SizedBox(height: 8),
      Text(by == 'category' ? 'Only categories that have students are shown. IT can add a category in School rules → Other lists.'
          : by == 'months' ? 'New admissions and students who left, month by month, for this school year.'
          : 'One number for the whole school, the same on every page: active students, School and Senior Secondary together.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
    ]));
  }
}

// ================================================================== WHO READ A NOTICE
Future<void> showNoticeReaders(BuildContext context, String id) => showDialog<void>(context: context, builder: (_) => _ReadersDialog(id: id));

class _ReadersDialog extends StatefulWidget {
  final String id;
  const _ReadersDialog({required this.id});
  @override
  State<_ReadersDialog> createState() => _ReadersDialogState();
}

class _ReadersDialogState extends State<_ReadersDialog> {
  late final Future<Map<String, dynamic>> data = () async { return Map<String, dynamic>.from(await db.rpc('notice_readers', params: {'p_id': widget.id}) as Map); }();
  String q = ''; bool unreadOnly = false, busy = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, dynamic>>(future: data, builder: (context, snap) {
      final d = snap.data;
      final all = [for (final x in (d?['rows'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
      final read = all.where((r) => r['read_at'] != null).length;
      final t = q.trim().toLowerCase();
      final rows = [for (final r in all) if ((!unreadOnly || r['read_at'] == null) && (t.isEmpty || '${r['name']} ${r['class']} ${r['adm']}'.toLowerCase().contains(t))) r];
      String when(Map<String, dynamic> r) => r['read_at'] == null ? '' : DateFormat('d MMM, h:mm a').format(DateTime.parse('${r['read_at']}').toLocal());
      return AlertDialog(
        title: Text(d == null ? 'Who read it' : '${d['title']}', maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SizedBox(width: 640, height: 480, child: snap.hasError ? Text(friendlyError(snap.error))
          : d == null ? const Center(child: CircularProgressIndicator())
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('$read of ${all.length} families have opened it${all.isEmpty ? '' : ' · ${(read * 100 / all.length).round()}%'}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(decoration: const InputDecoration(isDense: true, hintText: 'Search name, class or admission number', prefixIcon: Icon(Icons.search_rounded, size: 20)), onChanged: (v) => setState(() => q = v))),
                const SizedBox(width: 8),
                FilterChip(label: const Text('Not read'), selected: unreadOnly, onSelected: (v) => setState(() => unreadOnly = v)),
              ]),
              const SizedBox(height: 8),
              Expanded(child: rows.isEmpty ? Center(child: Text('Nobody to show.', style: TextStyle(color: cs.onSurfaceVariant))) : ListView.builder(itemCount: rows.length, itemBuilder: (_, i) {
                final r = rows[i];
                return Container(padding: const EdgeInsets.symmetric(vertical: 9), decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: .4)))), child: Row(children: [
                  Expanded(flex: 5, child: Text('${r['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Expanded(flex: 2, child: Text('${r['class'] ?? ''}', style: TextStyle(color: cs.onSurfaceVariant))),
                  Expanded(flex: 4, child: Align(alignment: Alignment.centerRight, child: r['read_at'] == null
                      ? Pill('Not read yet', fg: Brand.amber, bg: Brand.amberTint) : Text(when(r), style: TextStyle(fontSize: 12.5, color: context.tone(Brand.green), fontWeight: FontWeight.w700)))),
                ]));
              })),
            ])),
        actions: [
          if (d != null) TextButton.icon(onPressed: () async {
            try { await saveBytes(buildXlsx('Who read it', ['Student', 'Admission no', 'Class', 'Opened'], [for (final r in all) [r['name'], r['adm'], r['class'], when(r).isEmpty ? 'Not read' : when(r)]], widths: [28, 16, 10, 22]), 'RCIS-notice-read.xlsx'); }
            catch (e) { if (context.mounted) toast(context, 'Could not save the file: ${friendlyError(e)}'); }
          }, icon: const Icon(Icons.download_rounded, size: 18), label: const Text('Excel')),
          if (d != null && read < all.length) TextButton.icon(onPressed: busy ? null : () async {
            setState(() => busy = true);
            try { final n = await remindAnnouncement(widget.id); if (context.mounted) toast(context, 'Reminder sent to $n ${n == 1 ? 'family' : 'families'} ✓'); }
            catch (e) { if (context.mounted) toast(context, friendlyError(e)); }
            if (mounted) setState(() => busy = false);
          }, icon: const Icon(Icons.notifications_active_rounded, size: 18), label: Text(busy ? 'Sending…' : 'Remind those who have not read')),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      );
    });
  }
}

// ================================================================== STUDENTS: count cards and Lock app
final studentCountsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, filter) async {
  try { await db.rpc('locks_tidy'); } catch (_) {}   // a fee lock whose fees are now paid ends here
  return Map<String, dynamic>.from(await db.rpc('students_counts', params: {
    'p_grade': filter.startsWith('g:') ? filter.substring(2) : null, 'p_section': filter.startsWith('s:') ? filter.substring(2) : null}) as Map);
});

class StudentCountCards extends ConsumerWidget {
  final String filter;   // '' = whole school · 'g:<grade id>' · 's:<section id>'
  const StudentCountCards({super.key, required this.filter});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(studentCountsProvider(filter)).value;
    if (d == null) return const SizedBox(height: 4);
    num n(String k) => (d[k] ?? 0) as num;
    return statGrid(context, [
      StatCard('Active', n('active'), sub: filter.isEmpty ? 'whole school' : 'this class'),
      StatCard('New this year', n('new')),
      StatCard('Locked · fees', n('locked_fees'), tone: n('locked_fees') > 0 ? Brand.amber : null, sub: 'opens when paid'),
      StatCard('Locked · other', n('locked_other'), tone: n('locked_other') > 0 ? Brand.crimsonDeep : null),
      StatCard('Left this year', n('left'), sub: 'see Past students'),
    ]);
  }
}

/// Lock the app for one student: fees pending (part of the app stays open and it lifts by itself) or another reason till a date.
class LockDialog extends StatefulWidget {
  final Map<String, dynamic> student; final num? due;
  const LockDialog({super.key, required this.student, this.due});
  @override
  State<LockDialog> createState() => _LockDialogState();
}

class _LockDialogState extends State<LockDialog> {
  late String kind = (widget.due ?? 0) > 0 ? 'fees' : 'other';
  final note = TextEditingController(); DateTime till = DateTime.now().add(const Duration(days: 3)); bool busy = false;
  @override
  void dispose() { note.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (kind == 'other' && note.text.trim().length < 2) { toast(context, 'Please type the reason.'); return; }
    setState(() => busy = true);
    try {
      await db.rpc('student_lock', params: {'p_student': widget.student['id'], 'p_kind': kind, 'p_till': kind == 'other' ? DateFormat('yyyy-MM-dd').format(till) : null, 'p_note': note.text.trim()});
      if (!mounted) return;
      Navigator.pop(context, true);
      toast(context, kind == 'fees' ? 'Locked for fees. It opens by itself when the fees are paid.' : 'App locked till ${DateFormat('d MMM').format(till)}. It unlocks by itself.');
    } catch (e) { if (mounted) { toast(context, friendlyError(e)); setState(() => busy = false); } }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final due = widget.due ?? 0;
    Widget opt(String k, String t, String sub, {bool enabled = true}) => InkWell(onTap: enabled ? () => setState(() => kind = k) : null, borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(duration: const Duration(milliseconds: 180), margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: kind == k ? Brand.gold.withValues(alpha: .1) : null, borderRadius: BorderRadius.circular(14), border: Border.all(color: kind == k ? Brand.gold : cs.outlineVariant, width: kind == k ? 2 : 1)),
        child: Opacity(opacity: enabled ? 1 : .5, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(kind == k ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: kind == k ? Brand.gold : cs.onSurfaceVariant, size: 20), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3),
            Text(sub, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ])),
        ]))));
    return AlertDialog(
      title: Text('Lock the app for ${widget.student['full_name']}'),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        opt('fees', due > 0 ? 'Fees pending · ${inr(due)} due' : 'Fees pending', due > 0
            ? 'Only Fees, Transport, urgent notices and “Contact the office” stay open. Everything else is locked. It lifts by itself when the dues are paid.'
            : 'Nothing is due for this student today, so there is nothing to lock for.', enabled: due > 0),
        opt('other', 'Other reason', 'The whole app is locked until the date you choose (discipline, for example). It unlocks by itself after that date, or earlier with one tap.'),
        if (kind == 'other') Padding(padding: const EdgeInsets.only(bottom: 10), child: OutlinedButton.icon(onPressed: () async {
          final x = await showDatePicker(context: context, initialDate: till, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
          if (x != null) setState(() => till = x);
        }, icon: const Icon(Icons.event_rounded, size: 18), label: Text('Locked till ${DateFormat('EEE, d MMM yyyy').format(till)}'))),
        TextField(controller: note, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: kind == 'fees' ? 'Note for the record (optional)' : 'Reason', hintText: kind == 'fees' ? 'e.g. Term 2 and 3 not paid' : 'e.g. Discipline')),
        const SizedBox(height: 8),
        Text('Nothing is deleted. Teachers and the office see “App locked” on the student.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ]))),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Brand.amber), onPressed: busy ? null : _save, child: Text(busy ? 'Please wait…' : 'Lock app')),
      ],
    );
  }
}

// ================================================================== TODAY: a few numbers
final todayExtrasProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final r = await db.rpc('today_extras');
  return r == null ? null : Map<String, dynamic>.from(r as Map);
});

class TodayExtras extends ConsumerWidget {
  final bool fees, diary;   // which tiles this person may open
  const TodayExtras({super.key, required this.fees, required this.diary});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(todayExtrasProvider).value;
    if (d == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    num n(String k) => (d[k] ?? 0) as num;
    Widget tile(String label, String value, String sub, IconData icon, Color tone, String path) => InkWell(onTap: () => context.go(path), borderRadius: BorderRadius.circular(16),
      child: Container(width: 232, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: cs.outline.withValues(alpha: .6)),
          gradient: LinearGradient(colors: [cs.surface, tone.withValues(alpha: .06)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: tone.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: context.tone(tone), size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .9, color: cs.onSurfaceVariant)),
            Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, height: 1.25)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ])),
        ])));
    final tiles = [
      if (diary && n('diary_total') > 0) tile('Diary posted', '${n('diary_posted')} / ${n('diary_total')}', 'see Diary check', Icons.menu_book_rounded, n('diary_posted') >= n('diary_total') ? Brand.green : Brand.amber, '/staff/diary-check'),
      if (fees) tile('Fees today', inr(n('fees_today')), '${n('receipts_today')} ${n('receipts_today') == 1 ? 'receipt' : 'receipts'} · day sheet', Icons.receipt_long_rounded, Brand.green, '/staff/fees/day'),
      if (fees && n('concessions_waiting') > 0) tile(d['can_decide'] == true ? 'Waiting for you' : 'With the Principal', '${n('concessions_waiting')}', n('concessions_waiting') == 1 ? 'concession to decide' : 'concessions to decide', Icons.volunteer_activism_rounded, Brand.amber, '/staff/fees/concessions'),
      if (n('locked_fees') > 0) tile('App locked · fees', '${n('locked_fees')}', 'opens when paid', Icons.lock_rounded, Brand.amber, '/staff/students'),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Wrap(spacing: 12, runSpacing: 12, children: tiles));
  }
}

// ================================================================== COUNCIL: voting by one link
class VoteLinkPanel extends StatefulWidget {
  final String electionId; final String? linkKey; final int byLink; final bool open; final VoidCallback onChanged;
  const VoteLinkPanel({super.key, required this.electionId, required this.linkKey, required this.byLink, required this.open, required this.onChanged});
  @override
  State<VoteLinkPanel> createState() => _VoteLinkPanelState();
}

class _VoteLinkPanelState extends State<VoteLinkPanel> {
  bool busy = false;
  Future<void> _set(bool on) async {
    setState(() => busy = true);
    try { await db.rpc('council_link_set', params: {'p_election': widget.electionId, 'p_on': on}); widget.onChanged(); if (mounted) toast(context, on ? 'The voting link is ready ✓' : 'The link is switched off. Nobody can vote with it now.'); }
    catch (e) { if (mounted) toast(context, friendlyError(e)); }
    if (mounted) setState(() => busy = false);
  }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final key = widget.linkKey;
    final url = key == null ? null : '${AppConfig.webUrl}/vote?k=$key';
    return Panel(title: 'Voting by one link (no sign-in)', trailing: key == null
        ? FilledButton.icon(onPressed: busy ? null : () => _set(true), icon: const Icon(Icons.link_rounded, size: 18), label: const Text('Make the voting link'))
        : OutlinedButton(onPressed: busy ? null : () => _set(false), child: const Text('Switch the link off')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (url == null) Text('For students who do not remember their sign-in. One link opens the ballot: the student picks one candidate for each post and presses Vote. Their names are not asked and nobody can see who voted for whom.', style: TextStyle(color: cs.onSurfaceVariant))
        else ...[
          Container(padding: const EdgeInsets.fromLTRB(14, 10, 6, 10), decoration: BoxDecoration(color: Brand.gold.withValues(alpha: .08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Brand.gold.withValues(alpha: .5))), child: Row(children: [
            Expanded(child: SelectableText(url, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            IconButton(tooltip: 'Copy the link', onPressed: () async { await Clipboard.setData(ClipboardData(text: url)); if (context.mounted) toast(context, 'Link copied ✓'); }, icon: const Icon(Icons.copy_rounded, size: 18)),
          ])),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Pill(widget.open ? 'Voting is open' : 'Voting is not open yet', fg: widget.open ? Brand.green : Brand.amber, bg: widget.open ? Brand.greenTint : Brand.amberTint),
            Text('${widget.byLink} ${widget.byLink == 1 ? 'vote' : 'votes'} came through the link', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Text('The link works only while voting is open. It does not know who is voting, so one person could vote more than once: open it on the school’s computers with a teacher in the room, and switch the link off when voting ends. Making a new link stops the old one.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ],
      ]));
  }
}

// ================================================================== NOTICES: only some students of the classes chosen
/// Opens a tick list of the students in the grades / sections chosen. Returns the ids ticked (empty = everyone), or null when cancelled.
/// The office also gets quick picks by language, group and elective ("only Science", "only AI").
Future<Set<String>?> pickNoticeStudents(BuildContext context, {required bool office, required List<String> gradeIds, required List<String> sectionIds, required Set<String> initial}) =>
    showDialog<Set<String>>(context: context, builder: (_) => _PickStudents(office: office, gradeIds: gradeIds, sectionIds: sectionIds, initial: initial));

class _PickStudents extends StatefulWidget {
  final bool office; final List<String> gradeIds, sectionIds; final Set<String> initial;
  const _PickStudents({required this.office, required this.gradeIds, required this.sectionIds, required this.initial});
  @override
  State<_PickStudents> createState() => _PickStudentsState();
}

class _PickStudentsState extends State<_PickStudents> {
  late final Future<List<Map<String, dynamic>>> rows = _load();
  late final picked = {...widget.initial}; String q = '';

  Future<List<Map<String, dynamic>>> _load() async {
    final out = <String, Map<String, dynamic>>{};
    if (widget.office) {
      Future<void> take(Map<String, dynamic> p) async {
        final r = Map<String, dynamic>.from(await db.rpc('office_students', params: {'p_q': '', 'p_past': false, 'p_offset': 0, 'p_limit': 300, ...p}) as Map);
        for (final x in (r['rows'] as List? ?? const [])) { final m = Map<String, dynamic>.from(x as Map); out['${m['id']}'] = m; }
      }
      for (final g in widget.gradeIds) { await take({'p_grade': g, 'p_section': null}); }
      for (final s in widget.sectionIds) { await take({'p_grade': null, 'p_section': s}); }
    } else {
      for (final s in widget.sectionIds) {
        final data = await db.from('enrolment').select('roll_no,student:student_id(id,full_name,active)').eq('section_id', s).order('roll_no', ascending: true);
        for (final x in data) { final st = x['student']; if (st != null && st['active'] != false) out['${st['id']}'] = {'id': st['id'], 'full_name': st['full_name'], 'class': ''}; }
      }
    }
    return out.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Only some students'),
      content: SizedBox(width: 560, height: 480, child: FutureBuilder<List<Map<String, dynamic>>>(future: rows, builder: (context, snap) {
        if (snap.hasError) return Text(friendlyError(snap.error));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!;
        // quick picks: every value that some (but not all) of these students have
        final quick = <(String, String, String)>[];   // key, value, label
        for (final (k, label) in const [('l2', '2nd'), ('grp', ''), ('el', '')]) {
          final vals = {for (final r in all) if ((r[k] ?? '').toString().isNotEmpty) '${r[k]}'};
          for (final v in vals) { if (all.where((r) => r[k] == v).length < all.length) quick.add((k, v, label.isEmpty ? v : '$label $v')); }
        }
        final t = q.trim().toLowerCase();
        final shown = [for (final r in all) if (t.isEmpty || '${r['full_name']} ${r['class']} ${r['admission_no'] ?? ''}'.toLowerCase().contains(t)) r];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${picked.length} of ${all.length} ticked. Leave everything unticked to send to everyone in the classes chosen.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          if (quick.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, v, label) in quick) ActionChip(label: Text('Only $label'), onPressed: () => setState(() { picked..clear()..addAll([for (final r in all) if (r[k] == v) '${r['id']}']); })),
            if (picked.isNotEmpty) ActionChip(label: const Text('Clear ticks'), onPressed: () => setState(picked.clear)),
          ])),
          TextField(decoration: const InputDecoration(isDense: true, hintText: 'Search a name', prefixIcon: Icon(Icons.search_rounded, size: 20)), onChanged: (v) => setState(() => q = v)),
          const SizedBox(height: 6),
          Expanded(child: ListView.builder(itemCount: shown.length, itemBuilder: (_, i) {
            final r = shown[i]; final id = '${r['id']}';
            return CheckboxListTile(dense: true, value: picked.contains(id), controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero,
                title: Text('${r['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: (r['class'] ?? '').toString().isEmpty ? null : Text([r['class'], if ((r['grp'] ?? '').toString().isNotEmpty) r['grp'], if ((r['el'] ?? '').toString().isNotEmpty) r['el'], if ((r['l2'] ?? '').toString().isNotEmpty) '2nd ${r['l2']}'].join(' · ')),
                onChanged: (v) => setState(() => v == true ? picked.add(id) : picked.remove(id)));
          })),
        ]);
      })),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, picked), child: Text(picked.isEmpty ? 'Everyone in the classes' : 'Use these ${picked.length}')),
      ],
    );
  }
}
