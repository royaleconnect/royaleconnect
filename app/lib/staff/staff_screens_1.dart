import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/data2.dart';
import '../core/theme.dart';
import '../widgets/auth_layout.dart';
import '../widgets/common.dart';
import '../widgets/empty_state.dart';
import 'staff_data.dart';
import 'staff_shell.dart';
import 'staff_screens_2.dart' show pickAndUploadMany;
import 'today_screen.dart' show staffTodayProvider;
import '../widgets/chat_bubble.dart';
import '../widgets/paper_plane.dart';

String _d(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String _dm(String? iso) => iso == null ? '' : DateFormat('d MMM').format(DateTime.parse(iso).toLocal());
String _dmy(String? iso) => iso == null ? '' : DateFormat('d MMM yyyy').format(DateTime.parse(iso).toLocal());
String _dmt(String? iso) => iso == null ? '' : DateFormat('d MMM, h:mm a').format(DateTime.parse(iso).toLocal());
Widget _loading() => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
Widget _err(Object e) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e), style: const TextStyle(color: Brand.crimsonDeep)));
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
    final cs = Theme.of(context).colorScheme;
    return AuthLayout(
      title: 'Staff sign in',
      subtitle: 'Use your school email, or the login ID given by the school.',
      topAction: TextButton(onPressed: () => context.go('/login'), child: const Text('Parent / student sign in', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
      formTitle: 'School staff',
      formSubtitle: 'Teachers, office, management and bus crew.',
      children: [
        TextField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.username], decoration: const InputDecoration(labelText: 'School email or login ID', hintText: 'name@rcis.in')),
        const SizedBox(height: 14),
        TextField(controller: pw, obscureText: !show, autofillHints: const [AutofillHints.password], onSubmitted: (_) => _go(), decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(icon: Icon(show ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => show = !show)))),
        const SizedBox(height: 18),
        if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error!, style: TextStyle(color: context.tone(Brand.crimsonDeep), fontWeight: FontWeight.w700))),
        PrimaryButton('Sign in', busy: busy, onPressed: _go),
        const SizedBox(height: 12),
        Text('Forgotten your password? The IT admin (staff) or the transport office (bus crew) can issue a new one.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ],
    );
  }
  Future<void> _go() async {
    setState(() { busy = true; error = null; });
    try { await ref.read(sessionProvider.notifier).loginStaff(email.text, pw.text); if (mounted) context.go(ref.read(sessionProvider).value?.kind == 'crew' ? '/driver' : '/staff'); }
    on AuthError catch (e) { setState(() => error = e.message); } catch (e) { setState(() => error = friendlyError(e)); }
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
  Widget build(BuildContext context) => AuthLayout(
    eyebrow: 'First sign-in',
    title: 'Set your own password',
    subtitle: 'The password you were given was for first use only. Choose one only you know.',
    formTitle: 'New password',
    children: [
      TextField(controller: a, obscureText: true, decoration: const InputDecoration(labelText: 'New password (8+ characters)')), const SizedBox(height: 12),
      TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'Repeat new password')), const SizedBox(height: 16),
      if (error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(error!, style: TextStyle(color: context.tone(Brand.crimsonDeep), fontWeight: FontWeight.w700))),
      PrimaryButton('Save and continue', busy: busy, onPressed: () async {
        if (a.text.length < 8) { setState(() => error = 'Use at least 8 characters.'); return; }
        if (a.text != b.text) { setState(() => error = "The two passwords don't match."); return; }
        setState(() { busy = true; error = null; });
        try { await ref.read(sessionProvider.notifier).changeStaffPassword(a.text); if (mounted) context.go('/staff'); } on AuthError catch (e) { setState(() => error = e.message); } catch (e) { setState(() => error = friendlyError(e)); }
        if (mounted) setState(() => busy = false);
      }),
    ],
  );
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
          if (shown.isEmpty) filter == 'open' ? const EmptyState(kind: EmptyKind.messages, title: 'No new messages', line: 'You’re all caught up.', compact: true) : Padding(padding: const EdgeInsets.all(24), child: Text('Nothing here.', style: TextStyle(color: cs.onSurfaceVariant))),
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
      return StaffPage(title: 'Messages', subtitle: 'Private chats with parents and students. Families are notified straight away, except between 12 am and 5 am.', scroll: false, actions: [newBtn], body: Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
      Expanded(child: msgs.when(loading: _loading, error: (e, _) => _err(e), data: (list) => ListView(padding: const EdgeInsets.all(16), children: [for (final m in list)
        ChatBubble(m: m, mine: m['sender_kind'] == 'staff', maxWidth: 420, time: _dmt, onChanged: () { ref.invalidate(messagesProvider(widget.conversationId)); ref.invalidate(inboxProvider); })]))),
      const Divider(height: 1),
      Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final s in _StaffMessagesScreenState.saved) Padding(padding: const EdgeInsets.only(right: 6), child: ActionChip(label: Text(s, style: const TextStyle(fontSize: 12)), onPressed: () => text.text = s))]))),
      Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 12), child: Row(children: [
        Expanded(child: TextField(controller: text, minLines: 1, maxLines: 4, decoration: const InputDecoration(hintText: 'Reply…', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)))),
        const SizedBox(width: 8),
        IconButton.filled(style: IconButton.styleFrom(backgroundColor: Brand.crimson), onPressed: busy ? null : () async {
          final b = text.text.trim(); if (b.isEmpty) return; setState(() => busy = true);
          try { await staffSend(widget.conversationId, b); text.clear(); ref.invalidate(messagesProvider(widget.conversationId)); ref.invalidate(inboxProvider); } catch (e) { if (mounted) toast(context, 'Could not send: ${friendlyError(e)}'); }
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
    final who = _NoticeRule.of(s);
    return StaffPage(title: 'Notices', subtitle: who.subtitle,
      actions: [FilledButton.icon(onPressed: () => _compose(context, ref, s), icon: const Icon(Icons.add_rounded), label: const Text('New notice'))],
      body: list.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => rows.isEmpty ? const Panel(child: EmptyState(kind: EmptyKind.notices, title: 'No notices sent yet', line: 'Notices you send appear here with who has read them.', compact: true)) : Column(children: [for (final a in rows) Panel(padding: const EdgeInsets.all(14), child: CardRow(children: [
        Pill(cats[a['category']] ?? a['category'], fg: a['category'] == 'urgent' ? Colors.white : Brand.crimsonDeep, bg: a['category'] == 'urgent' ? Brand.crimson : Brand.crimsonTint), const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(a['title'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          Text(a['body'], maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('${a['author']?['display_name'] ?? ''} · ${(a['audience_route_ids'] as List?)?.isNotEmpty == true ? '🚌 ${(a['audience_route_ids'] as List).length} bus route${(a['audience_route_ids'] as List).length == 1 ? '' : 's'}' : a['audience_bus_only'] == true ? '🚌 Bus families${a['audience_all'] == true ? '' : ' in ${(a['audience_grade_ids'] as List).length + (a['audience_section_ids'] as List).length} group(s)'}' : a['audience_all'] == true ? 'Whole school' : '${(a['audience_grade_ids'] as List).length + (a['audience_section_ids'] as List).length} group(s)'} · ${a['sent_at'] != null ? 'Sent ${_dmt(a['sent_at'])}' : 'Scheduled ${_dmt(a['scheduled_for'])}'}${(a['attachments'] as List?)?.isNotEmpty == true ? ' · 📎 ${(a['attachments'] as List).length}' : ''}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          if (a['sent_at'] != null && a['audience'] != null) _SeenBar(a: a, canRemind: s.isOffice || a['author_id'] == s.staff?['id']),
        ])),
        if (s.isOffice || a['author_id'] == s.staff?['id']) _NoticeMenu(a: a, office: s.isOffice),
      ]))])));
  }

  void _compose(BuildContext context, WidgetRef ref, Session s) {
    final who = _NoticeRule.of(s);
    String cat = 'general', title = '', body = ''; bool all = who.whole || who.busOnly; final grades = <String>{}, sections = <String>{}; DateTime? when; bool busy = false, uploading = false; final files = <Map<String, dynamic>>[];
    DateTime? pinUntil; String bus = who.busOnly ? 'bus' : '';   // bus: '' = everyone chosen · 'bus' = only bus students · otherwise one route id
    final me = s.staff?['id'];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(insetPadding: EdgeInsets.symmetric(horizontal: isNarrow(context) ? 12 : 40, vertical: 24), title: const Text('New notice'), content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 8, children: [for (final e in cats.entries) if (e.key != 'urgent' || who.urgent) ChoiceChip(label: Text(e.value), selected: cat == e.key, onSelected: (_) => set(() => cat = e.key))]),
      if (cat == 'urgent') const Padding(padding: EdgeInsets.only(top: 8), child: NoteBox('Urgent rings every phone immediately, even at night. For closures, safety and emergencies only.', icon: Icons.warning_amber_rounded, iconColor: Brand.crimson)),
      const SizedBox(height: 12),
      TextField(onChanged: (v) => title = v, decoration: const InputDecoration(labelText: 'Title')), const SizedBox(height: 10),
      TextField(onChanged: (v) => body = v, minLines: 4, maxLines: 10, decoration: const InputDecoration(labelText: 'Message')), const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final f in files) InputChip(avatar: Icon(f['mime'] == 'application/pdf' ? Icons.picture_as_pdf_rounded : Icons.image_rounded, size: 18, color: Brand.crimson), label: Text(f['name'], overflow: TextOverflow.ellipsis), onDeleted: () => set(() => files.remove(f))),
        OutlinedButton.icon(onPressed: uploading || files.length >= 10 ? null : () async { set(() => uploading = true); try { final up = await pickAndUploadMany(ctx, 'announcements'); set(() => files.addAll(up)); } catch (e) { if (ctx.mounted) toast(ctx, 'Upload failed: ${friendlyError(e)}'); } set(() => uploading = false); },
          icon: uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.attach_file_rounded, size: 18), label: Text(uploading ? 'Uploading…' : 'Attach PDFs / photos')),
      ]),
      const SizedBox(height: 12),
      const Text('Who gets it', style: TextStyle(fontWeight: FontWeight.w800)),
      if (who.whole) CheckboxListTile(value: all, onChanged: (v) => set(() => all = v ?? false), title: const Text('Whole school'), contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading),
      if (who.busOnly) const Padding(padding: EdgeInsets.only(top: 4), child: Text('Families whose children use the school bus.', style: TextStyle(fontSize: 13))),
      if (!all) ...[
        // grades: the whole school's (office) or only the coordinator's own grades
        if (who.grades) Consumer(builder: (_, r, __) {
          final mine = {for (final sec in r.watch(mySectionsProvider).value ?? const <Map<String, dynamic>>[]) sec['grade']?['id']};
          return r.watch(gradesProvider).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (gs) => Wrap(spacing: 6, children: [
            for (final g in gs) if (who.whole || mine.contains(g['id'])) FilterChip(label: Text(g['code']), selected: grades.contains(g['id']), onSelected: (v) => set(() => v ? grades.add(g['id']) : grades.remove(g['id'])))]));
        }),
        const SizedBox(height: 6),
        // sections: a class teacher sees only her own class
        Consumer(builder: (_, r, __) => r.watch(mySectionsProvider).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (ss) => Wrap(spacing: 6, children: [
          for (final sec in ss) if (who.whole || who.grades || sec['class_teacher_id'] == me) FilterChip(label: Text(sectionLabel(sec)), selected: sections.contains(sec['id']), onSelected: (v) => set(() => v ? sections.add(sec['id']) : sections.remove(sec['id'])))]))),
      ],
      // office / transport: send only to bus families (all routes, or one route)
      if (who.bus) Consumer(builder: (_, r, __) {
        final routes = [for (final x in r.watch(routesProvider).value ?? const <Map<String, dynamic>>[]) if (x['active'] != false) x];
        if (routes.isEmpty) return const SizedBox.shrink();
        return Padding(padding: const EdgeInsets.only(top: 10), child: DropdownButtonFormField<String>(
          value: bus, isExpanded: true, decoration: const InputDecoration(labelText: 'Bus', isDense: true),
          items: [
            if (!who.busOnly) const DropdownMenuItem(value: '', child: Text('Everyone chosen above')),
            DropdownMenuItem(value: 'bus', child: Text(who.busOnly ? 'All bus families' : 'Only students who use the school bus')),
            for (final ro in routes) DropdownMenuItem(value: ro['id'] as String, child: Text('Only bus route: ${ro['name']}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => set(() => bus = v ?? '')));
      }),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: Text(pinUntil == null ? 'Not kept on top' : 'Kept on top until ${DateFormat('d MMM').format(pinUntil!)}', style: const TextStyle(fontWeight: FontWeight.w700))),
        if (pinUntil != null) IconButton(tooltip: 'Do not keep on top', onPressed: () => set(() => pinUntil = null), icon: const Icon(Icons.close_rounded, size: 18)),
        TextButton.icon(onPressed: () async {
          final now = DateTime.now();
          final d = await showDatePicker(context: ctx, helpText: 'Keep on top until', initialDate: pinUntil ?? now.add(const Duration(days: 7)), firstDate: now, lastDate: now.add(const Duration(days: 120)));
          if (d != null) set(() => pinUntil = d); }, icon: const Icon(Icons.push_pin_outlined, size: 18), label: const Text('Keep on top'))]),
      Row(children: [Expanded(child: Text(when == null ? 'Send now' : 'Scheduled: ${DateFormat('d MMM, h:mm a').format(when!)}', style: const TextStyle(fontWeight: FontWeight.w700))), TextButton.icon(onPressed: () async {
        final d = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 180))); if (d == null) return;
        if (!ctx.mounted) return; final t = await showTimePicker(context: ctx, initialTime: const TimeOfDay(hour: 8, minute: 0)); if (t == null) return;
        set(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute)); }, icon: const Icon(Icons.schedule_rounded, size: 18), label: const Text('Schedule'))]),
    ]))), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : () async {
        if (title.trim().isEmpty || body.trim().isEmpty) { toast(ctx, 'Title and message are needed.'); return; }
        if (!all && grades.isEmpty && sections.isEmpty) { toast(ctx, 'Choose who should receive it.'); return; }
        if (cat == 'urgent' && !who.urgent) cat = 'general';
        set(() => busy = true);
        try { await postAnnouncement(ref, category: cat, title: title.trim(), body: body.trim(), all: all, gradeIds: grades.toList(), sectionIds: sections.toList(), scheduledFor: when, attachments: List.of(files), pinnedUntil: pinUntil, busOnly: bus == 'bus', routeIds: bus.isEmpty || bus == 'bus' ? const [] : [bus]); ref.invalidate(staffAnnouncementsProvider); if (ctx.mounted) { Navigator.pop(ctx); toast(context, when == null ? 'Sent ✓' : 'Scheduled ✓'); if (when == null && context.mounted) showPaperPlane(context); } }
        catch (e) { set(() => busy = false); if (ctx.mounted) toast(ctx, friendlyError(e)); }
      }, child: Text(when == null ? 'Send' : 'Schedule')),
    ])));
  }
}

/// Who a person may send notices to (the database checks it again):
/// office / IT / Principal / VP — whole school, grades, sections, bus families, urgent;
/// coordinator — her own grades (not urgent); class teacher — only her own class; transport in-charge — bus families.
class _NoticeRule {
  final bool whole, grades, bus, busOnly, urgent;
  const _NoticeRule({this.whole = false, this.grades = false, this.bus = false, this.busOnly = false, this.urgent = false});
  factory _NoticeRule.of(Session s) {
    if (s.isOffice) return const _NoticeRule(whole: true, grades: true, bus: true, urgent: true);
    final coord = s.hasRole('coordinator'), ct = s.hasRole('class_teacher'), tr = s.hasRole('transport_incharge');
    if (coord) return _NoticeRule(grades: true, bus: tr);
    if (ct) return _NoticeRule(bus: tr);
    if (tr) return const _NoticeRule(bus: true, busOnly: true);
    return const _NoticeRule();
  }
  String get subtitle => whole ? 'Whole school, grades or sections. Urgent rings every phone at once — use only when necessary.'
      : grades ? 'To the families of your grades. School-wide notices go through the office.'
      : busOnly ? 'To bus families — all routes or one route.'
      : 'To the families of your class. School-wide notices go through the office.';
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
    return secs.when(loading: () => const StaffPage(title: 'Diary', body: SizedBox()), error: (e, _) => StaffPage(title: 'Diary', body: _err(e)), data: (list) {
      sectionId ??= list.isEmpty ? null : list.first['id'];
      if (list.isEmpty) {
        return const StaffPage(title: 'Diary', subtitle: 'Homework, things to bring, tests. Parents see it the moment you post.',
          body: Panel(child: EmptyState(kind: EmptyKind.homework, title: 'No classes yet', line: 'When the office gives you a class or a subject, it appears here and you can post homework.', compact: true)));
      }
      final entries = sectionId == null ? null : ref.watch(staffDiaryProvider((sectionId!, _d(day))));
      return StaffPage(title: 'Diary', subtitle: 'Homework, things to bring, tests. Parents see it the moment you post.',
        actions: [if (sectionId != null) FilledButton.icon(onPressed: () => _compose(context, list), icon: const Icon(Icons.add_rounded), label: const Text('Post entry'))],
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Panel(padding: const EdgeInsets.all(12), child: PickRow(children: [
            Expanded(child: PickField<String>(label: 'Section', value: sectionId, items: [for (final s in list) DropdownMenuItem(value: s['id'] as String, child: Text(sectionLabel(s)))], onChanged: (v) => setState(() => sectionId = v))),
            const SizedBox(width: 12),
            OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 54)), onPressed: () async { final d = await showDatePicker(context: context, initialDate: day, firstDate: DateTime.now().subtract(const Duration(days: 120)), lastDate: DateTime.now()); if (d != null) setState(() => day = d); }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(DateFormat('EEE, d MMM').format(day))),
          ])),
          if (entries != null) entries.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => rows.isEmpty ? const Panel(child: EmptyState(kind: EmptyKind.homework, title: 'Nothing posted for this day', line: 'Homework and notes you post appear here.', compact: true)) : Column(children: [for (final e in rows) Panel(padding: const EdgeInsets.all(14), child: CardRow(children: [
            Pill(kinds[e['kind']] ?? e['kind'], fg: Brand.blue, bg: Brand.blueTint), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e['title'], style: const TextStyle(fontWeight: FontWeight.w800)),
              if (e['body'] != null) Text(e['body'], style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              Text('${e['subject']?['name'] ?? 'General'} · ${e['author']?['display_name'] ?? ''}${e['due_on'] != null ? ' · for ${_dm(e['due_on'])}' : ''}${e['needs_submission'] == true ? ' · submission on' : ''}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            ])),
            IconButton(onPressed: () async { final key = (sectionId!, _d(day)); await deleteDiary(e['id']); ref.invalidate(staffDiaryProvider(key)); if (context.mounted) showUndo(context, 'Diary note', () => ref.invalidate(staffDiaryProvider(key))); }, icon: const Icon(Icons.delete_outline_rounded), tooltip: 'Remove'),
          ]))])),
        ]));
    });
  }

  void _compose(BuildContext context, List<Map<String, dynamic>> sections) {
    final assigns = ref.read(myAssignmentsProvider).value ?? [];
    final mySubjects = assigns.where((a) => a['section_id'] == sectionId).map((a) => a['subject']).toList();
    String kind = 'homework', title = '', body = ''; String? subjectId = mySubjects.isNotEmpty ? mySubjects.first['id'] : null; DateTime? due; bool needs = false, busy = false;
    // "Also send to": only other sections of the SAME grade where I teach the SAME subject (never another grade), ticked already
    final here = sections.firstWhere((s) => s['id'] == sectionId);
    final unticked = <String>{};
    List<Map<String, dynamic>> twins() => subjectId == null ? const [] : [for (final a in assigns)
        if (a['section_id'] != sectionId && a['subject']?['id'] == subjectId && a['section']?['grade']?['code'] == here['grade']?['code']) a];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(insetPadding: EdgeInsets.symmetric(horizontal: isNarrow(context) ? 12 : 40, vertical: 24), title: Text('Post to ${sectionLabel(sections.firstWhere((s) => s['id'] == sectionId))} · today'), content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, children: [for (final e in kinds.entries) ChoiceChip(label: Text(e.value), selected: kind == e.key, onSelected: (_) => set(() => kind = e.key))]),
      const SizedBox(height: 12),
      Consumer(builder: (_, r, __) => r.watch(subjectsProvider).when(loading: () => const SizedBox(), error: (e, _) => _err(e), data: (subs) => PickField<String?>(label: 'Subject (optional)', value: subjectId, items: [const DropdownMenuItem(value: null, child: Text('General')), for (final s in subs) DropdownMenuItem(value: s['id'] as String, child: Text(s['name']))], onChanged: (v) => set(() => subjectId = v)))),
      const SizedBox(height: 10),
      TextField(onChanged: (v) => title = v, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Maths — Ex 4.2 Q1–10')), const SizedBox(height: 10),
      TextField(onChanged: (v) => body = v, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Details (optional)')), const SizedBox(height: 10),
      Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () async { final now = DateTime.now(); final d = await showDatePicker(context: ctx, initialDate: now.add(const Duration(days: 1)), firstDate: now, lastDate: now.add(const Duration(days: 60))); if (d != null) set(() => due = d); }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(due == null ? 'For / due date (optional) — e.g. test on Wednesday' : 'For ${DateFormat('EEE d MMM').format(due!)}')))]),
      Padding(padding: const EdgeInsets.only(top: 6), child: Text('Parents see this note under today\'s diary. The date above shows on it as a tag.', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant))),
      SwitchListTile(value: needs, onChanged: (v) => set(() => needs = v), title: const Text('Students submit a file in the app'), subtitle: const Text('Off by default. Turn on for projects to be returned.'), contentPadding: EdgeInsets.zero),
      if (twins().isNotEmpty) Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.fromLTRB(12, 10, 12, 6), decoration: BoxDecoration(color: Brand.amberTint, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Also send to', style: TextStyle(fontWeight: FontWeight.w800)),
          Text('Only your other ${here['grade']?['code'] ?? ''} sections for the same subject.', style: const TextStyle(fontSize: 12)),
          Wrap(spacing: 4, children: [for (final a in twins()) FilterChip(
            label: Text('${a['section']?['grade']?['code']}-${a['section']?['name']} · ${a['subject']?['name']}'),
            selected: !unticked.contains(a['section_id']),
            onSelected: (v) => set(() => v ? unticked.remove(a['section_id']) : unticked.add(a['section_id'] as String)))]),
        ])),
    ]))), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : () async {
        if (title.trim().isEmpty) { toast(ctx, 'Title is needed.'); return; }
        set(() => busy = true);
        try {
          final targets = [sectionId!, for (final a in twins()) if (!unticked.contains(a['section_id'])) a['section_id'] as String];
          for (final sec in targets) {
            await postDiary(ref, sectionId: sec, subjectId: subjectId, kind: kind, title: title.trim(), body: body.trim().isEmpty ? null : body.trim(), forDate: DateTime.now(), dueOn: due, needsSubmission: needs);
          }
          setState(() => day = DateTime.now()); ref.invalidate(staffDiaryProvider((sectionId!, _d(DateTime.now())))); ref.invalidate(staffOverviewProvider);
          if (ctx.mounted) Navigator.pop(ctx);
          if (targets.length > 1 && context.mounted) {
            final names = [sectionLabel(here), for (final a in twins()) if (!unticked.contains(a['section_id'])) '${a['section']?['grade']?['code']}-${a['section']?['name']}'];
            toast(context, 'Sent to ${names.join(', ')}');
          }
        }
        catch (e) { set(() => busy = false); if (ctx.mounted) toast(ctx, 'Could not post: ${friendlyError(e)}'); }
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
    return StaffPage(title: 'Leave requests', subtitle: 'Approve or decline — the family is told at once.', body: list.when(loading: _loading, error: (e, _) => _err(e), data: (rows) => rows.isEmpty ? const Panel(child: EmptyState(kind: EmptyKind.calendar, title: 'No leave requests', line: 'Nothing waiting for you.', compact: true)) : Column(children: [for (final l in rows) Panel(padding: const EdgeInsets.all(14), child: CardRow(children: [
      Pill(l['status'], fg: col[l['status']]!.$1, bg: col[l['status']]!.$2), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${l['student']?['full_name'] ?? ''} · ${_cls(l['student'])}', style: const TextStyle(fontWeight: FontWeight.w800)),
        Text('${l['from_date'] == l['to_date'] ? _dmy(l['from_date']) : '${_dm(l['from_date'])} – ${_dmy(l['to_date'])}'} · ${l['reason']}${l['note'] != null ? ' — ${l['note']}' : ''}', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        Text('Requested ${_dmt(l['created_at'])}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
      ])),
      if (l['status'] == 'pending') ...[
        TextButton(onPressed: () => decideLeaveWithToast(context, ref, l['id'], false), child: const Text('Decline', style: TextStyle(color: Brand.crimson, fontWeight: FontWeight.w800))),
        FilledButton(onPressed: () => decideLeaveWithToast(context, ref, l['id'], true), child: const Text('Approve')),
      ],
    ]))])));
  }
}

/// Approve / decline one leave request: one checked database call; success and errors are shown in plain words.
Future<void> decideLeaveWithToast(BuildContext context, WidgetRef ref, String id, bool approve) async {
  try {
    final r = await db.rpc('leave_decide', params: {'p_id': id, 'p_approve': approve});
    final who = (r is Map ? r['student'] : null) ?? '';
    ref.invalidate(staffLeavesProvider); ref.invalidate(staffOverviewProvider); ref.invalidate(staffTodayProvider);
    if (context.mounted) toast(context, '${approve ? 'Approved' : 'Declined'} ✓ · $who — family told');
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
  }
}

/// "Seen for 412 of 520 students" with a progress bar and a reminder button.
class _SeenBar extends ConsumerStatefulWidget {
  final Map<String, dynamic> a; final bool canRemind;
  const _SeenBar({required this.a, required this.canRemind});
  @override
  ConsumerState<_SeenBar> createState() => _SeenBarState();
}
class _SeenBarState extends ConsumerState<_SeenBar> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = (widget.a['audience'] ?? 0) as int, seen = (widget.a['seen'] ?? 0) as int;
    final left = (total - seen).clamp(0, total);
    return Padding(padding: const EdgeInsets.only(top: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(children: [TextSpan(text: '$seen', style: const TextStyle(fontWeight: FontWeight.w800)), TextSpan(text: ' of $total students\' families have seen it')]), style: const TextStyle(fontSize: 12.5)),
      const SizedBox(height: 6),
      ClipRRect(borderRadius: BorderRadius.circular(9), child: LinearProgressIndicator(value: total == 0 ? 0 : seen / total, minHeight: 7, color: Brand.green, backgroundColor: cs.outline.withValues(alpha: .35))),
      if (widget.canRemind && left > 0) Padding(padding: const EdgeInsets.only(top: 8), child: FilledButton.tonalIcon(onPressed: busy ? null : () async {
        setState(() => busy = true);
        try { final n = await remindAnnouncement(widget.a['id']); if (context.mounted) toast(context, 'Reminder queued for $n families. It reaches phones once notifications are switched on.'); }
        catch (e) { if (context.mounted) toast(context, 'Could not send reminder: ${friendlyError(e)}'); }
        if (mounted) setState(() => busy = false);
      }, icon: const Icon(Icons.notifications_active_outlined, size: 18), label: Text('Remind the $left who haven\'t'))),
    ]));
  }
}

/// ⋮ on a notice: Edit · Unsend (within 10 minutes, removed from every phone) · Delete (office, any time). Undo right after.
class _NoticeMenu extends ConsumerWidget {
  final Map<String, dynamic> a; final bool office;
  const _NoticeMenu({required this.a, required this.office});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sent = DateTime.tryParse(a['sent_at'] ?? a['created_at'] ?? '')?.toLocal();
    final fresh = sent == null || DateTime.now().difference(sent).inMinutes < 10;
    return PopupMenuButton<String>(tooltip: 'More', icon: const Icon(Icons.more_vert_rounded), onSelected: (v) async {
      if (v == 'edit') {
        final t = TextEditingController(text: a['title']), b = TextEditingController(text: a['body']);
        final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Edit notice'), content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: t, decoration: const InputDecoration(labelText: 'Title')), const SizedBox(height: 10),
          TextField(controller: b, minLines: 4, maxLines: 10, decoration: const InputDecoration(labelText: 'Message')),
          const SizedBox(height: 8),
          const Text('Families see the corrected notice with "Updated" on it. No new notification is sent.', style: TextStyle(fontSize: 12)),
        ])), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save'))]));
        if (ok != true || t.text.trim().isEmpty || b.text.trim().isEmpty) return;
        try { await db.from('announcement').update({'title': t.text.trim(), 'body': b.text.trim(), 'edited_at': DateTime.now().toUtc().toIso8601String()}).eq('id', a['id']); ref.invalidate(staffAnnouncementsProvider); if (context.mounted) toast(context, 'Notice updated ✓'); }
        catch (e) { if (context.mounted) toast(context, 'Could not save: ${friendlyError(e)}'); }
        return;
      }
      final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
        title: Text(v == 'unsend' ? 'Unsend this notice?' : 'Delete this notice?'),
        content: Text(v == 'unsend' ? 'It disappears from every phone, with its notification.' : 'It is removed for families and staff. IT can bring it back from the Bin for 30 days.'),
        actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Brand.crimson), onPressed: () => Navigator.pop(d, true), child: Text(v == 'unsend' ? 'Unsend' : 'Delete'))]));
      if (ok != true) return;
      try {
        await db.rpc('notice_unsend', params: {'p_id': a['id']});
        ref.invalidate(staffAnnouncementsProvider);
        if (context.mounted) showUndo(context, 'Notice', () => ref.invalidate(staffAnnouncementsProvider));
      } catch (e) { if (context.mounted) toast(context, friendlyError(e)); }
    }, itemBuilder: (_) => [
      const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Edit'), dense: true)),
      if (fresh) const PopupMenuItem(value: 'unsend', child: ListTile(leading: Icon(Icons.undo_rounded, color: Brand.crimson), title: Text('Unsend'), subtitle: Text('Within 10 minutes of sending'), dense: true))
      else if (office) const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded, color: Brand.crimson), title: Text('Delete'), dense: true)),
    ]);
  }
}
