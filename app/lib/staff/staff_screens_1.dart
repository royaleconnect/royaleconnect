import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/data2.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'staff_data.dart';
import 'staff_shell.dart';

String _d(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String _dm(String? iso) => iso == null ? '' : DateFormat('d MMM').format(DateTime.parse(iso).toLocal());
String _dmy(String? iso) => iso == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());
String _dmt(String? iso) => iso == null ? '' : DateFormat('d MMM, h:mm a').format(DateTime.parse(iso).toLocal());
Widget _loading() => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
Widget _err(Object e) => Padding(padding: const EdgeInsets.all(24), child: Text('$e', style: const TextStyle(color: Brand.crimsonDeep)));
String _cls(Map<String, dynamic>? student) { final en = (student?['enrolment'] as List?) ?? []; if (en.isEmpty) return ''; final s = en.first['section']; return '${s?['grade']?['code'] ?? ''}-${s?['name'] ?? ''}'; }

// ---------------------------------------------------------------- staff login
class StaffLoginScreen extends ConsumerStatefulWidget {
  const StaffLoginScreen({super.key});
  @override
  ConsumerState<StaffLoginScreen> createState() => _StaffLoginScreenState();
}
class _StaffLoginScreenState extends ConsumerState<StaffLoginScreen> {
  final email = TextEditingController(), pw = TextEditingController(); bool busy = false, show = false; String? error;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(body: Center(child: SingleChildScrollView(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(decoration: const BoxDecoration(gradient: Brand.headerGradient, borderRadius: BorderRadius.vertical(top: Radius.circular(24))), padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)), child: Image.asset('assets/images/monogram.png', width: 26)), const Spacer(), TextButton(onPressed: () => context.go('/login'), child: const Text('Parent / student sign in', style: TextStyle(color: Colors.white)))]),
        const SizedBox(height: 16),
        Text('Staff sign in', style: t.headlineMedium?.copyWith(color: Colors.white)),
        Text('Use your school email. Teachers, office, accounts and transport.', style: TextStyle(color: Colors.white.withValues(alpha: .9))),
      ])),
      Container(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24))), padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.username], decoration: const InputDecoration(labelText: 'School email', hintText: 'name@rcis.in')),
        const SizedBox(height: 14),
        TextField(controller: pw, obscureText: !show, autofillHints: const [AutofillHints.password], onSubmitted: (_) => _go(), decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(icon: Icon(show ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => show = !show)))),
        const SizedBox(height: 18),
        if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!, style: const TextStyle(color: Brand.crimsonDeep, fontWeight: FontWeight.w700))),
        PrimaryButton('Sign in', busy: busy, onPressed: _go),
        const SizedBox(height: 10),
        Text('Forgotten your password? The IT admin can issue a one-time password.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
    ]))))));
  }
  Future<void> _go() async {
    setState(() { busy = true; error = null; });
    try { await ref.read(sessionProvider.notifier).loginStaff(email.text, pw.text); if (mounted) context.go('/staff'); }
    on AuthError catch (e) { setState(() => error = e.message); } catch (e) { setState(() => error = 'Could not complete sign-in: $e'); }
    if (mounted) setState(() => busy = false);
  }
}

class StaffSetPasswordScreen extends ConsumerStatefulWidget {
  const StaffSetPasswordScreen({super.key});
  @override
  ConsumerState<StaffSetPasswordScreen> createState() => _StaffSetPasswordScreenState();
}
class _StaffSetPasswordScreenState extends ConsumerState<StaffSetPasswordScreen> {
  final a = TextEditingController(), b = TextEditingController(); bool busy = false; String? error;
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Padding(padding: const EdgeInsets.all(24), child: Panel(title: 'Set your own password', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Text('The password you were given was for first use only.'), const SizedBox(height: 14),
    TextField(controller: a, obscureText: true, decoration: const InputDecoration(labelText: 'New password (8+ characters)')), const SizedBox(height: 12),
    TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'Repeat new password')), const SizedBox(height: 16),
    if (error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(error!, style: const TextStyle(color: Brand.crimsonDeep, fontWeight: FontWeight.w700))),
    PrimaryButton('Save and continue', busy: busy, onPressed: () async {
      if (a.text.length < 8) { setState(() => error = 'Use at least 8 characters.'); return; }
      if (a.text != b.text) { setState(() => error = "The two passwords don't match."); return; }
      setState(() { busy = true; error = null; });
      try { await ref.read(sessionProvider.notifier).changeStaffPassword(a.text); if (mounted) context.go('/staff'); } on AuthError catch (e) { setState(() => error = e.message); } catch (e) { setState(() => error = '$e'); }
      if (mounted) setState(() => busy = false);
    }),
  ]))))));
}

// ---------------------------------------------------------------- overview
class StaffOverviewScreen extends ConsumerWidget {
  const StaffOverviewScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value!;
    final ov = ref.watch(staffOverviewProvider);
    final secs = ref.watch(mySectionsProvider);
    final cs = Theme.of(context).colorScheme;
    final hour = DateTime.now().hour;
    Widget stat(String n, String l, IconData i, Color c, String path) => Expanded(child: Material(color: cs.surface, borderRadius: BorderRadius.circular(18), child: InkWell(onTap: () => context.go(path), borderRadius: BorderRadius.circular(18), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: cs.outline.withValues(alpha: .6))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(i, color: c), const SizedBox(height: 10), Text(n, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)), Text(l, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700))])))));
    return StaffPage(title: '${hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening'}, ${s.staff?['name'] ?? ''}', subtitle: DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()), body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ov.when(loading: _loading, error: (e, _) => _err(e), data: (m) {
        final tiles = [
          stat('${m['unread']}', 'Unread messages', Icons.chat_bubble_rounded, Brand.blue, '/staff/messages'),
          stat('${m['leaves']}', 'Leave requests waiting', Icons.event_busy_rounded, Brand.amber, '/staff/leave'),
          stat('${m['diary_today']}', 'Diary entries today', Icons.menu_book_rounded, Brand.green, '/staff/diary'),
          if (s.isOffice) stat('${m['feedback']}', 'New feedback', Icons.rate_review_rounded, Brand.violet, '/staff/feedback'),
        ];
        Widget line(List<Widget> ts) => IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final (i, t) in ts.indexed) ...[if (i > 0) const SizedBox(width: 12), t]]));
        if (isNarrow(context) && tiles.length == 4) return Column(children: [line(tiles.sublist(0, 2)), const SizedBox(height: 12), line(tiles.sublist(2))]);
        return line(tiles);
      }),
      const SizedBox(height: 18),
      Panel(title: 'Your sections', child: secs.when(loading: _loading, error: (e, _) => _err(e), data: (list) => list.isEmpty ? Text('No sections assigned yet. The office sets class teachers and subject teachers under Students.', style: TextStyle(color: cs.onSurfaceVariant)) :
        Wrap(spacing: 8, runSpacing: 8, children: [for (final sec in list) Chip(avatar: Icon(sec['class_teacher_id'] == s.staff?['id'] ? Icons.star_rounded : Icons.class_rounded, size: 16, color: Brand.crimsonDeep), label: Text(sectionLabel(sec) + (sec['class_teacher_id'] == s.staff?['id'] ? ' · class teacher' : ''), style: const TextStyle(color: Brand.crimsonDeep, fontWeight: FontWeight.w800)), backgroundColor: Brand.crimsonTint, side: BorderSide.none)]))),
      Panel(title: 'Quick actions', child: Wrap(spacing: 10, runSpacing: 10, children: [
        for (final (l, i, p) in [('Post diary', Icons.menu_book_rounded, '/staff/diary'), ('Send announcement', Icons.campaign_rounded, '/staff/announcements'), ('Approve leave', Icons.event_busy_rounded, '/staff/leave'), ('Share class moment', Icons.photo_camera_rounded, '/staff/moments'), ('Enter marks', Icons.grading_rounded, '/staff/marks')])
          OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => context.go(p), icon: Icon(i, size: 18), label: Text(l)),
      ])),
    ]));
  }
}

// ---------------------------------------------------------------- messages (inbox + thread)
class StaffMessagesScreen extends ConsumerStatefulWidget {
  const StaffMessagesScreen({super.key});
  @override
  ConsumerState<StaffMessagesScreen> createState() => _StaffMessagesScreenState();
}
class _StaffMessagesScreenState extends ConsumerState<StaffMessagesScreen> {
  String? open; String filter = 'open'; final reply = TextEditingController(); bool sending = false;
  static const saved = ['Noted, thank you.', 'Will check and get back to you by tomorrow.', 'Please send the file as a PDF.', 'Kindly meet me after school on Friday.'];

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider);
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (_, c) {
      final wide = c.maxWidth >= 860;
      final list = inbox.when(loading: _loading, error: (e, _) => _err(e), data: (rows) {
        final shown = rows.where((r) => filter == 'all' || (filter == 'open' ? r['staff_done'] != true : r['staff_done'] == true)).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: SegmentedButton<String>(segments: const [ButtonSegment(value: 'open', label: Text('Open')), ButtonSegment(value: 'done', label: Text('Done')), ButtonSegment(value: 'all', label: Text('All'))], selected: {filter}, onSelectionChanged: (v) => setState(() => filter = v.first))),
          if (shown.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text('Nothing here.', style: TextStyle(color: cs.onSurfaceVariant))),
          for (final r in shown) ListTile(
            selected: open == r['id'], selectedTileColor: Brand.crimson.withValues(alpha: .14), selectedColor: cs.onSurface,
            leading: Avatar((r['student']?['full_name'] ?? '?').toString().split(' ').take(2).map((w) => w[0]).join(), size: 40),
            title: Text(r['student']?['full_name'] ?? '', style: TextStyle(fontWeight: (r['staff_unread'] ?? 0) > 0 ? FontWeight.w800 : FontWeight.w600)),
            subtitle: Text('${_cls(r['student'])} · ${r['last_message_at'] == null ? 'no messages' : _dmt(r['last_message_at'])}'),
            trailing: (r['staff_unread'] ?? 0) > 0 ? CircleAvatar(radius: 11, backgroundColor: Brand.crimson, child: Text('${r['staff_unread']}', style: const TextStyle(color: Colors.white, fontSize: 11))) : (r['staff_done'] == true ? const Icon(Icons.check_circle_rounded, color: Brand.green, size: 18) : null),
            onTap: () { setState(() => open = r['id']); markConversationReadStaff(r['id']); if (!wide) _openSheet(context, r); },
          ),
        ]);
      });
      final newBtn = FilledButton.icon(onPressed: () => _newMessage(context, wide), icon: const Icon(Icons.add_comment_rounded), label: const Text('New message'));
      if (!wide) return StaffPage(title: 'Messages', subtitle: 'Private chats with parents and students', scroll: true, actions: [newBtn], body: Panel(padding: EdgeInsets.zero, child: list));
      return StaffPage(title: 'Messages', subtitle: 'Private chats with parents and students. Delivered to the family between 6 am and 9 pm.', scroll: false, actions: [newBtn], body: Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 360, child: Panel(padding: EdgeInsets.zero, fill: true, child: SingleChildScrollView(child: list))),
        const SizedBox(width: 14),
        Expanded(child: Panel(padding: EdgeInsets.zero, fill: true, child: open == null ? Center(child: Text('Pick a conversation', style: TextStyle(color: cs.onSurfaceVariant))) : _Thread(conversationId: open!, meta: (inbox.value ?? []).firstWhere((r) => r['id'] == open, orElse: () => {})))),
      ])));
    });
  }

  /// Pick a student from the sections this teacher works with and open (or resume) the chat with that family.
  void _newMessage(BuildContext context, bool wide) {
    String q = '';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(title: const Text('Message a family'), content: SizedBox(width: 480, height: MediaQuery.sizeOf(context).height < 760 ? MediaQuery.sizeOf(context).height * .6 : 520, child: Column(children: [
      TextField(autofocus: true, onChanged: (v) => set(() => q = v.toLowerCase()), decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search by name or admission number')),
      const SizedBox(height: 8),
      Expanded(child: Consumer(builder: (_, r, __) => r.watch(myStudentsProvider).when(loading: _loading, error: (e, _) => _err(e), data: (rows) {
        final shown = rows.where((x) => q.isEmpty || (x['student']['full_name'] as String).toLowerCase().contains(q) || (x['student']['admission_no'] as String).toLowerCase().contains(q)).toList();
        if (shown.isEmpty) return const Center(child: Text('No students found.'));
        return ListView(children: [for (final x in shown) ListTile(
          leading: Avatar((x['student']['full_name'] as String).split(' ').take(2).map((w) => w[0]).join(), size: 36),
          title: Text(x['student']['full_name'], style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${sectionLabelOf(x['section'])} · Roll ${x['roll_no'] ?? '—'} · ${x['student']['admission_no']}'),
          onTap: () async {
            final id = await staffOpenConversation(ref, x['student']['id']);
            ref.invalidate(inboxProvider);
            if (!ctx.mounted) return; Navigator.pop(ctx);
            setState(() { filter = 'all'; open = id; });
            if (!wide && context.mounted) _openSheet(context, {'id': id, 'student': x['student'], 'staff_done': false});
          })]);
      }))),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))])));
  }

  void _openSheet(BuildContext context, Map<String, dynamic> r) => showModalBottomSheet(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => SizedBox(height: MediaQuery.of(context).size.height * .9, child: _Thread(conversationId: r['id'], meta: r)));
}

Future<void> markConversationReadStaff(String id) => db.from('conversation').update({'staff_unread': 0}).eq('id', id);

class _Thread extends ConsumerStatefulWidget {
  final String conversationId; final Map<String, dynamic> meta;
  const _Thread({required this.conversationId, required this.meta});
  @override
  ConsumerState<_Thread> createState() => _ThreadState();
}
class _ThreadState extends ConsumerState<_Thread> {
  final text = TextEditingController(); bool busy = false;
  @override
  Widget build(BuildContext context) {
    final msgs = ref.watch(messagesProvider(widget.conversationId));
    final cs = Theme.of(context).colorScheme;
    final done = widget.meta['staff_done'] == true;
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 8), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.meta['student']?['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), Text('${_cls(widget.meta['student'])} · ${widget.meta['student']?['admission_no'] ?? ''}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))])),
        TextButton.icon(onPressed: () async { await markDone(widget.conversationId, !done); ref.invalidate(inboxProvider); ref.invalidate(staffOverviewProvider); }, icon: Icon(done ? Icons.undo_rounded : Icons.check_rounded, size: 18), label: Text(done ? 'Reopen' : 'Mark done')),
      ])),
      const Divider(height: 1),
      Expanded(child: msgs.when(loading: _loading, error: (e, _) => _err(e), data: (list) => ListView(padding: const EdgeInsets.all(16), children: [for (final m in list) Align(alignment: m['sender_kind'] == 'staff' ? Alignment.centerRight : Alignment.centerLeft, child: Container(
        constraints: const BoxConstraints(maxWidth: 420), margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(color: m['sender_kind'] == 'staff' ? Brand.crimson : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (m['attachment_path'] != null) InkWell(onTap: () => openStorageFile(m['attachment_path']), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.attach_file_rounded, size: 16, color: m['sender_kind'] == 'staff' ? Colors.white : cs.onSurface), Flexible(child: Text(m['attachment_name'] ?? 'file', style: TextStyle(decoration: TextDecoration.underline, color: m['sender_kind'] == 'staff' ? Colors.white : cs.onSurface)))])),
          if (m['body'] != null) Align(alignment: Alignment.centerLeft, child: SelectableText(m['body'], style: TextStyle(color: m['sender_kind'] == 'staff' ? Colors.white : cs.onSurface, height: 1.4))),
          Text(_dmt(m['created_at']), style: TextStyle(fontSize: 10, color: m['sender_kind'] == 'staff' ? Colors.white70 : cs.onSurfaceVariant)),
        ])))]))),
      const Divider(height: 1),
      Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final s in _StaffMessagesScreenState.saved) Padding(padding: const EdgeInsets.only(right: 6), child: ActionChip(label: Text(s, style: const TextStyle(fontSize: 12)), onPressed: () => text.text = s))]))),
      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 12), child: Row(children: [
        Expanded(child: TextField(controller: text, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Reply…', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)))),
        const SizedBox(width: 8),
        IconButton.filled(style: IconButton.styleFrom(backgroundColor: Brand.crimson), onPressed: busy ? null : () async {
          final b = text.text.trim(); if (b.isEmpty) return; setState(() => busy = true);
          try { await staffSend(widget.conversationId, b); text.clear(); ref.invalidate(messagesProvider(widget.conversationId)); ref.invalidate(inboxProvider); } catch (e) { if (mounted) toast(context, 'Could not send: $e'); }
          if (mounted) setState(() => busy = false);
        }, icon: const Icon(Icons.send_rounded)),
      ])),
    ]);
  }
}

// ---------------------------------------------------------------- announcements
class StaffAnnouncementsScreen extends ConsumerWidget {
  const StaffAnnouncementsScreen({super.key});
  static const cats = {'general': 'General', 'holiday': 'Holiday', 'field_trip': 'Field trip', 'exams': 'Exams', 'fees': 'Fees', 'urgent': 'Urgent'};
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value!;
    final list = ref.watch(staffAnnouncementsProvider);
    final cs = Theme.of(context).colorScheme;
    return StaffPage(title: 'Announcements', subtitle: s.isOffice ? 'Whole school, grades or sections. Urgent bypasses quiet hours — use only when necessary.' : 'To your own sections. School-wide notices go through the office.',
      actions: [FilledButton.icon(onPressed: () => _compose(context, ref, s), icon: const Icon(Icons.add_rounded), label: const Text('New announcement'))],
      body: list.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => rows.isEmpty ? Panel(child: Text('Nothing sent yet.', style: TextStyle(color: cs.onSurfaceVariant))) : Column(children: [for (final a in rows) Panel(padding: const EdgeInsets.all(14), child: CardRow(children: [
        Pill(cats[a['category']] ?? a['category'], fg: a['category'] == 'urgent' ? Colors.white : Brand.crimsonDeep, bg: a['category'] == 'urgent' ? Brand.crimson : Brand.crimsonTint), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a['title'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          Text(a['body'], maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('${a['author']?['display_name'] ?? ''} · ${a['audience_all'] == true ? 'Whole school' : '${(a['audience_grade_ids'] as List).length + (a['audience_section_ids'] as List).length} group(s)'} · ${a['sent_at'] != null ? 'Sent ${_dmt(a['sent_at'])}' : 'Scheduled ${_dmt(a['scheduled_for'])}'}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
        ])),
      ]))])));
  }

  void _compose(BuildContext context, WidgetRef ref, Session s) {
    String cat = 'general', title = '', body = ''; bool all = s.isOffice; final grades = <String>{}, sections = <String>{}; DateTime? when; bool busy = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(title: const Text('New announcement'), content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 8, children: [for (final e in cats.entries) if (e.key != 'urgent' || s.isOffice) ChoiceChip(label: Text(e.value), selected: cat == e.key, onSelected: (_) => set(() => cat = e.key))]),
      if (cat == 'urgent') const Padding(padding: EdgeInsets.only(top: 8), child: NoteBox('Urgent rings every phone immediately, even at night. For closures, safety and emergencies only.', icon: Icons.warning_amber_rounded, iconColor: Brand.crimson)),
      const SizedBox(height: 12),
      TextField(onChanged: (v) => title = v, decoration: const InputDecoration(labelText: 'Title')), const SizedBox(height: 10),
      TextField(onChanged: (v) => body = v, minLines: 4, maxLines: 10, decoration: const InputDecoration(labelText: 'Message')), const SizedBox(height: 12),
      const Text('Audience', style: TextStyle(fontWeight: FontWeight.w800)),
      if (s.isOffice) CheckboxListTile(value: all, onChanged: (v) => set(() => all = v ?? false), title: const Text('Whole school'), contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading),
      if (!all) ...[
        if (s.isOffice) Consumer(builder: (_, r, __) => r.watch(gradesProvider).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (gs) => Wrap(spacing: 6, children: [for (final g in gs) FilterChip(label: Text(g['code']), selected: grades.contains(g['id']), onSelected: (v) => set(() => v ? grades.add(g['id']) : grades.remove(g['id'])))]))),
        const SizedBox(height: 6),
        Consumer(builder: (_, r, __) => r.watch(mySectionsProvider).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (ss) => Wrap(spacing: 6, children: [for (final sec in ss) FilterChip(label: Text(sectionLabel(sec)), selected: sections.contains(sec['id']), onSelected: (v) => set(() => v ? sections.add(sec['id']) : sections.remove(sec['id'])))]))),
      ],
      const SizedBox(height: 12),
      Row(children: [Expanded(child: Text(when == null ? 'Send now' : 'Scheduled: ${DateFormat('d MMM, h:mm a').format(when!)}', style: const TextStyle(fontWeight: FontWeight.w700))), TextButton.icon(onPressed: () async {
        final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 180))); if (d == null) return;
        if (!ctx.mounted) return; final t = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 8, minute: 0)); if (t == null) return;
        set(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute)); }, icon: const Icon(Icons.schedule_rounded, size: 18), label: const Text('Schedule'))]),
    ]))), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : () async {
        if (title.trim().isEmpty || body.trim().isEmpty) { toast(ctx, 'Title and message are needed.'); return; }
        if (!all && grades.isEmpty && sections.isEmpty) { toast(ctx, 'Choose who should receive it.'); return; }
        set(() => busy = true);
        try { await postAnnouncement(ref, category: cat, title: title.trim(), body: body.trim(), all: all, gradeIds: grades.toList(), sectionIds: sections.toList(), scheduledFor: when); ref.invalidate(staffAnnouncementsProvider); if (ctx.mounted) { Navigator.pop(ctx); toast(context, when == null ? 'Sent.' : 'Scheduled.'); } }
        catch (e) { set(() => busy = false); if (ctx.mounted) toast(ctx, 'Not allowed or failed: $e'); }
      }, child: Text(when == null ? 'Send' : 'Schedule')),
    ])));
  }
}

// ---------------------------------------------------------------- class diary (teacher)
class StaffDiaryScreen extends ConsumerStatefulWidget {
  const StaffDiaryScreen({super.key});
  @override
  ConsumerState<StaffDiaryScreen> createState() => _StaffDiaryScreenState();
}
class _StaffDiaryScreenState extends ConsumerState<StaffDiaryScreen> {
  String? sectionId; DateTime day = DateTime.now();
  static const kinds = {'homework': 'Homework', 'to_bring': 'To bring', 'reminder': 'Reminder', 'test': 'Test', 'notice': 'Notice', 'project': 'Project'};
  @override
  Widget build(BuildContext context) {
    final secs = ref.watch(mySectionsProvider);
    final cs = Theme.of(context).colorScheme;
    return secs.when(loading: () => const StaffPage(title: 'Class diary', body: SizedBox()), error: (e, _) => StaffPage(title: 'Class diary', body: _err(e)), data: (list) {
      sectionId ??= list.isEmpty ? null : list.first['id'];
      final entries = sectionId == null ? null : ref.watch(staffDiaryProvider((sectionId!, _d(day))));
      return StaffPage(title: 'Class diary', subtitle: 'Homework, things to bring, tests. Parents see it the moment you post.',
        actions: [if (sectionId != null) FilledButton.icon(onPressed: () => _compose(context, list), icon: const Icon(Icons.add_rounded), label: const Text('Post entry'))],
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Panel(padding: const EdgeInsets.all(12), child: PickRow(children: [
            Expanded(child: PickField<String>(label: 'Section', value: sectionId, items: [for (final s in list) DropdownMenuItem(value: s['id'] as String, child: Text(sectionLabel(s)))], onChanged: (v) => setState(() => sectionId = v))),
            const SizedBox(width: 12),
            OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 54)), onPressed: () async { final d = await showDatePicker(context: context, initialDate: day, firstDate: DateTime.now().subtract(const Duration(days: 60)), lastDate: DateTime.now().add(const Duration(days: 60))); if (d != null) setState(() => day = d); }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(DateFormat('EEE, d MMM').format(day))),
          ])),
          if (entries != null) entries.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => rows.isEmpty ? Panel(child: Text('Nothing posted for this day yet.', style: TextStyle(color: cs.onSurfaceVariant))) : Column(children: [for (final e in rows) Panel(padding: const EdgeInsets.all(14), child: CardRow(children: [
            Pill(kinds[e['kind']] ?? e['kind'], fg: Brand.blue, bg: Brand.blueTint), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e['title'], style: const TextStyle(fontWeight: FontWeight.w800)),
              if (e['body'] != null) Text(e['body'], style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              Text('${e['subject']?['name'] ?? 'General'} · ${e['author']?['display_name'] ?? ''}${e['due_on'] != null ? ' · due ${_dm(e['due_on'])}' : ''}${e['needs_submission'] == true ? ' · submission on' : ''}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            ])),
            IconButton(onPressed: () async { await deleteDiary(e['id']); ref.invalidate(staffDiaryProvider((sectionId!, _d(day)))); }, icon: const Icon(Icons.delete_outline_rounded), tooltip: 'Remove'),
          ]))])),
        ]));
    });
  }

  void _compose(BuildContext context, List<Map<String, dynamic>> sections) {
    final assigns = ref.read(myAssignmentsProvider).value ?? [];
    final mySubjects = assigns.where((a) => a['section_id'] == sectionId).map((a) => a['subject']).toList();
    String kind = 'homework', title = '', body = ''; String? subjectId = mySubjects.isNotEmpty ? mySubjects.first['id'] : null; DateTime? due; bool needs = false, busy = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(title: Text('Post to ${sectionLabel(sections.firstWhere((s) => s['id'] == sectionId))} · ${DateFormat('d MMM').format(day)}'), content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, children: [for (final e in kinds.entries) ChoiceChip(label: Text(e.value), selected: kind == e.key, onSelected: (_) => set(() => kind = e.key))]),
      const SizedBox(height: 12),
      Consumer(builder: (_, r, __) => r.watch(subjectsProvider).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (subs) => PickField<String?>(label: 'Subject (optional)', value: subjectId, items: [const DropdownMenuItem(value: null, child: Text('General')), for (final s in subs) DropdownMenuItem(value: s['id'] as String, child: Text(s['name']))], onChanged: (v) => set(() => subjectId = v)))),
      const SizedBox(height: 10),
      TextField(onChanged: (v) => title = v, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Maths — Ex 4.2 Q1–10')), const SizedBox(height: 10),
      TextField(onChanged: (v) => body = v, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Details (optional)')), const SizedBox(height: 10),
      Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () async { final d = await showDatePicker(context: ctx, initialDate: day.add(const Duration(days: 1)), firstDate: day, lastDate: day.add(const Duration(days: 60))); if (d != null) set(() => due = d); }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(due == null ? 'Due date (optional)' : 'Due ${DateFormat('d MMM').format(due!)}')))]),
      SwitchListTile(value: needs, onChanged: (v) => set(() => needs = v), title: const Text('Students submit a file in the app'), subtitle: const Text('Off by default. Turn on for projects or worksheets to be returned.'), contentPadding: EdgeInsets.zero),
    ]))), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : () async {
        if (title.trim().isEmpty) { toast(ctx, 'Title is needed.'); return; }
        set(() => busy = true);
        try { await postDiary(ref, sectionId: sectionId!, subjectId: subjectId, kind: kind, title: title.trim(), body: body.trim().isEmpty ? null : body.trim(), forDate: day, dueOn: due, needsSubmission: needs); ref.invalidate(staffDiaryProvider((sectionId!, _d(day)))); ref.invalidate(staffOverviewProvider); if (ctx.mounted) Navigator.pop(ctx); }
        catch (e) { set(() => busy = false); if (ctx.mounted) toast(ctx, 'Could not post: $e'); }
      }, child: const Text('Post')),
    ])));
  }
}

// ---------------------------------------------------------------- leave requests
class StaffLeaveScreen extends ConsumerWidget {
  const StaffLeaveScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(staffLeavesProvider);
    final cs = Theme.of(context).colorScheme;
    const col = {'pending': (Brand.amber, Brand.amberTint), 'approved': (Brand.green, Brand.greenTint), 'declined': (Brand.crimsonDeep, Brand.crimsonTint)};
    return StaffPage(title: 'Leave requests', subtitle: 'Class teachers see their own section; the office sees all.', body: list.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => rows.isEmpty ? Panel(child: Text('No requests.', style: TextStyle(color: cs.onSurfaceVariant))) : Column(children: [for (final l in rows) Panel(padding: const EdgeInsets.all(14), child: CardRow(children: [
      Pill(l['status'], fg: col[l['status']]!.$1, bg: col[l['status']]!.$2), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${l['student']?['full_name'] ?? ''} · ${_cls(l['student'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
        Text('${l['from_date'] == l['to_date'] ? _dmy(l['from_date']) : '${_dm(l['from_date'])} – ${_dmy(l['to_date'])}'} · ${l['reason']}${l['note'] != null ? ' — ${l['note']}' : ''}', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        Text('Requested ${_dmt(l['created_at'])}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
      ])),
      if (l['status'] == 'pending') ...[
        TextButton(onPressed: () async { await decideLeave(ref, l['id'], false); ref.invalidate(staffLeavesProvider); ref.invalidate(staffOverviewProvider); }, child: const Text('Decline', style: TextStyle(color: Brand.crimson, fontWeight: FontWeight.w800))),
        FilledButton(onPressed: () async { await decideLeave(ref, l['id'], true); ref.invalidate(staffLeavesProvider); ref.invalidate(staffOverviewProvider); }, child: const Text('Approve')),
      ],
    ]))])));
  }
}
