import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../auth/session.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../screens/council_screen.dart' show CouncilView, councilTermsProvider;
import '../screens/toppers_screen.dart' show Face;
import '../widgets/common.dart';
import 'staff_data.dart' show gradesProvider;
import 'staff_screens_2.dart' show pickAndUpload;
import 'staff_shell.dart';

/// Student Council for staff: everyone sees the council; IT and the Principal manage the members and run the elections.
String _msg(Object e) => e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');
bool _canManage(Session s) => s.hasRole('it_admin') || s.hasRole('principal');
const _photoExt = ['jpg', 'jpeg', 'png', 'webp'];

class StaffCouncilScreen extends ConsumerWidget {
  const StaffCouncilScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value!;
    return StaffPage(title: 'Student Council', scroll: false, subtitle: 'The same page students and families see.',
      actions: [if (_canManage(s)) FilledButton.icon(onPressed: () => context.go('/staff/council/manage'), icon: const Icon(Icons.how_to_vote_rounded, size: 18), label: const Text('Members & elections'))],
      body: const CouncilView(staff: true));
  }
}

class CouncilAdminScreen extends ConsumerStatefulWidget {
  const CouncilAdminScreen({super.key});
  @override
  ConsumerState<CouncilAdminScreen> createState() => _CouncilAdminScreenState();
}

class _CouncilAdminScreenState extends ConsumerState<CouncilAdminScreen> {
  int tab = 0; String? termId;

  Future<void> _newTerm() async {
    final c = TextEditingController(text: '${DateTime.now().year + 1}-${(DateTime.now().year + 2) % 100}');
    final label = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('New council year'),
      content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'School year', hintText: 'e.g. 2027-28')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Add'))],
    ));
    if (label == null || label.isEmpty) return;
    try {
      final t = await db.from('council_term').insert({'label': label, 'published': false}).select('id').single();
      // copy last year's posts so only the names change
      final last = (ref.read(councilTermsProvider).value ?? const []).firstOrNull;
      final posts = List<Map<String, dynamic>>.from(last?['council_post'] ?? const []);
      if (posts.isNotEmpty) await db.from('council_post').insert([for (final p in posts) {'term_id': t['id'], 'title': p['title'], 'row_no': p['row_no'], 'sort': p['sort']}]);
      ref.invalidate(councilTermsProvider);
      setState(() => termId = t['id']);
    } catch (e) { if (mounted) toast(context, _msg(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    if (!_canManage(s)) return const StaffPage(title: 'Student Council', body: NoteBox('Only IT and the Principal manage the council and elections.'));
    return ref.watch(councilTermsProvider).when(
      loading: () => const StaffPage(title: 'Student Council', body: Center(child: CircularProgressIndicator())),
      error: (e, _) => StaffPage(title: 'Student Council', body: Text(_msg(e))),
      data: (terms) {
        final t = terms.where((x) => x['id'] == termId).firstOrNull ?? terms.firstOrNull;
        return StaffPage(
          title: 'Student Council · members & elections',
          subtitle: 'Add this year’s council by hand, or run next year’s elections: posts → candidates → open voting → results → publish.',
          actions: [OutlinedButton.icon(onPressed: () => context.go('/staff/council'), icon: const Icon(Icons.visibility_rounded, size: 18), label: const Text('See it as students do'))],
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final x in terms) ChoiceChip(label: Text('${x['label']}${x['published'] == true ? '' : ' (not shown yet)'}'), selected: x['id'] == t?['id'], showCheckmark: false,
                  selectedColor: Brand.crimson, labelStyle: TextStyle(fontWeight: FontWeight.w800, color: x['id'] == t?['id'] ? Colors.white : null), onSelected: (_) => setState(() => termId = x['id'])),
              ActionChip(avatar: const Icon(Icons.add_rounded, size: 18), label: const Text('New year'), onPressed: _newTerm),
            ]),
            const SizedBox(height: 12),
            if (t != null) ...[
              SegmentedButton<int>(segments: const [ButtonSegment(value: 0, label: Text('Council members'), icon: Icon(Icons.groups_rounded)), ButtonSegment(value: 1, label: Text('Elections'), icon: Icon(Icons.how_to_vote_rounded))],
                  selected: {tab}, showSelectedIcon: false, onSelectionChanged: (v) => setState(() => tab = v.first)),
              const SizedBox(height: 14),
              if (tab == 0) _MembersTab(term: t) else _ElectionTab(key: ValueKey(t['id']), term: t),
            ],
          ]),
        );
      },
    );
  }
}

// ================================================================== members (added by hand, or by publishing an election)
class _MembersTab extends ConsumerWidget {
  final Map<String, dynamic> term;
  const _MembersTab({required this.term});

  Future<void> _post(BuildContext context, WidgetRef ref, [Map<String, dynamic>? p]) async {
    final title = TextEditingController(text: p?['title'] ?? '');
    final row = TextEditingController(text: '${p?['row_no'] ?? 3}');
    final order = TextEditingController(text: '${p?['sort'] ?? 100}');
    final r = await showDialog<String>(context: context, builder: (c) => AlertDialog(
      title: Text(p == null ? 'Add a post' : 'Post'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, autofocus: p == null, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Post', hintText: 'e.g. House Captain – Red House')),
        const SizedBox(height: 10),
        TextField(controller: row, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Line on the page', helperText: '1 = top line (Head Boy / Girl), 2 = next line … two posts a line look best')),
        const SizedBox(height: 10),
        TextField(controller: order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Order in the line (left first)')),
      ])),
      actions: [
        if (p != null) TextButton(onPressed: () => Navigator.pop(c, 'delete'), child: const Text('Delete post', style: TextStyle(color: Brand.crimson))),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save')),
      ],
    ));
    try {
      if (r == 'delete') { await db.from('council_post').delete().eq('id', p!['id']); }
      else if (r == 'save' && title.text.trim().isNotEmpty) {
        final data = {'term_id': term['id'], 'title': title.text.trim(), 'row_no': int.tryParse(row.text.trim()) ?? 3, 'sort': int.tryParse(order.text.trim()) ?? 100};
        if (p == null) { await db.from('council_post').insert(data); } else { await db.from('council_post').update(data).eq('id', p['id']); }
      }
      ref.invalidate(councilTermsProvider);
    } catch (e) { if (context.mounted) toast(context, _msg(e)); }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final posts = List<Map<String, dynamic>>.from(term['council_post'] ?? const [])
      ..sort((a, b) { final r = ((a['row_no'] ?? 9) as int).compareTo((b['row_no'] ?? 9) as int); return r != 0 ? r : ((a['sort'] ?? 100) as int).compareTo((b['sort'] ?? 100) as int); });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(title: 'Council ${term['label']}', trailing: Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: () => _post(context, ref), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add a post')),
        FilledButton(onPressed: () async {
          try { await db.from('council_term').update({'published': term['published'] != true}).eq('id', term['id']); ref.invalidate(councilTermsProvider); } catch (e) { if (context.mounted) toast(context, _msg(e)); }
        }, child: Text(term['published'] == true ? 'Hide from families' : 'Show to families')),
      ]), child: posts.isEmpty ? Text('No posts yet. Add Head Boy, Head Girl, … or start the Elections tab.', style: TextStyle(color: cs.onSurfaceVariant)) : Column(children: [
        for (final p in posts) Builder(builder: (_) {
          final m = List<Map<String, dynamic>>.from(p['council_member'] ?? const []).firstOrNull;
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: m == null ? CircleAvatar(backgroundColor: Brand.surface2, child: Text('${p['row_no']}', style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.muted))) : Face(m['full_name'] ?? '', m['photo_path'], size: 46),
            title: Text('${p['title']} · ${m?['full_name'] ?? 'not added'}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Line ${p['row_no']}${m != null ? ' · ${m['photo_path'] == null ? 'no photo yet' : 'photo added'}${(m['class_label'] ?? '').toString().isNotEmpty ? ' · ${m['class_label']}' : ''}' : ''}'),
            trailing: Wrap(spacing: 4, children: [
              IconButton(tooltip: 'Post', icon: const Icon(Icons.tune_rounded), onPressed: () => _post(context, ref, p)),
              IconButton(tooltip: m == null ? 'Add the person' : 'Change', icon: Icon(m == null ? Icons.person_add_alt_1_rounded : Icons.edit_rounded), onPressed: () async {
                final ok = await showDialog<bool>(context: context, builder: (_) => _PersonDialog(table: 'council_member', parent: {'post_id': p['id']}, row: m, postTitle: p['title']));
                if (ok == true) ref.invalidate(councilTermsProvider);
              }),
            ]),
          );
        }),
      ])),
      const NoteBox('Lines: 1 = Head Boy & Head Girl (big photos), 2 = Deputies, 3 = Cultural, 4 = Sports … Each line shows its posts side by side.'),
    ]);
  }
}

/// Add / change a council member or a candidate: name, class, photo (and a one-line message for candidates).
class _PersonDialog extends ConsumerStatefulWidget {
  final String table; final Map<String, dynamic> parent; final Map<String, dynamic>? row; final String postTitle; final bool slogan;
  const _PersonDialog({required this.table, required this.parent, this.row, required this.postTitle, this.slogan = false});
  @override
  ConsumerState<_PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends ConsumerState<_PersonDialog> {
  late final name = TextEditingController(text: widget.row?['full_name'] ?? '');
  late final cls = TextEditingController(text: widget.row?['class_label'] ?? '');
  late final slogan = TextEditingController(text: widget.row?['slogan'] ?? '');
  late String? photo = widget.row?['photo_path'];
  bool busy = false;

  Future<void> _save() async {
    if (name.text.trim().isEmpty) { toast(context, 'Please type the name.'); return; }
    setState(() => busy = true);
    try {
      final data = {...widget.parent, 'full_name': name.text.trim(), 'class_label': cls.text.trim().isEmpty ? null : cls.text.trim(), 'photo_path': photo,
        if (widget.slogan) 'slogan': slogan.text.trim().isEmpty ? null : slogan.text.trim()};
      if (widget.row == null) { await db.from(widget.table).insert(data); } else { await db.from(widget.table).update(data).eq('id', widget.row!['id']); }
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.postTitle),
    content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Face(name.text, photo, size: 90)),
      const SizedBox(height: 8),
      Center(child: Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: busy ? null : () async {
          try { final p = await pickAndUpload(context, 'photos/council', ext: _photoExt, maxMb: 5); if (p != null) setState(() => photo = p); } catch (e) { if (context.mounted) toast(context, _msg(e)); }
        }, icon: const Icon(Icons.photo_camera_rounded, size: 18), label: Text(photo == null ? 'Add photo' : 'Change photo')),
        if (photo != null) TextButton(onPressed: () => setState(() => photo = null), child: const Text('Remove photo')),
      ])),
      const SizedBox(height: 12),
      TextField(controller: name, textCapitalization: TextCapitalization.words, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Name *')),
      const SizedBox(height: 10),
      TextField(controller: cls, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Class (optional)', hintText: 'e.g. XII-A')),
      if (widget.slogan) ...[
        const SizedBox(height: 10),
        TextField(controller: slogan, maxLength: 60, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'One-line message (optional)', hintText: 'e.g. A school where every voice counts')),
      ],
    ]))),
    actions: [
      if (widget.row != null) TextButton(onPressed: busy ? null : () async {
        try { await db.from(widget.table).delete().eq('id', widget.row!['id']); if (context.mounted) Navigator.pop(context, true); } catch (e) { if (context.mounted) toast(context, _msg(e)); }
      }, child: const Text('Remove', style: TextStyle(color: Brand.crimson))),
      TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')),
    ],
  );
}

// ================================================================== elections
final _electionProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, termId) async {
  final e = await db.from('council_election').select('id,opens_at,closes_at,voter_grades,status,council_candidate(id,post_id,full_name,class_label,slogan,photo_path,sort)').eq('term_id', termId).maybeSingle();
  if (e == null) return null;
  final m = Map<String, dynamic>.from(e);
  if (m['status'] != 'draft') {
    try { m['results'] = Map<String, dynamic>.from(await db.rpc('council_results', params: {'p_election': m['id']}) as Map); } catch (_) {}
  }
  return m;
});

class _ElectionTab extends ConsumerStatefulWidget {
  final Map<String, dynamic> term;
  const _ElectionTab({super.key, required this.term});
  @override
  ConsumerState<_ElectionTab> createState() => _ElectionTabState();
}

class _ElectionTabState extends ConsumerState<_ElectionTab> {
  bool busy = false;
  String get termId => widget.term['id'];
  void _refresh() { ref.invalidate(_electionProvider(termId)); ref.invalidate(councilTermsProvider); }

  Future<void> _do(Future<void> Function() f, [String? ok]) async {
    setState(() => busy = true);
    try { await f(); _refresh(); if (ok != null && mounted) toast(context, ok); } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _publish(Map<String, dynamic> e, List<Map<String, dynamic>> posts) async {
    final winners = <Map<String, String>>[];
    while (true) {
      try {
        await db.rpc('council_publish', params: {'p_election': e['id'], 'p_winners': winners});
        _refresh();
        if (mounted) toast(context, 'Published. ${widget.term['label']} is now the main council tab and families have been told.');
        return;
      } catch (err) {
        final m = _msg(err);
        final post = posts.where((p) => m.contains('tie for ${p['title']}')).firstOrNull;
        if (post == null || !mounted) { if (mounted) toast(context, m); return; }
        // a tie: the Principal / IT chooses
        final cands = List<Map<String, dynamic>>.from(e['council_candidate'] ?? const []).where((k) => k['post_id'] == post['id']).toList();
        final pick = await showDialog<String>(context: context, builder: (c) => SimpleDialog(title: Text('Tie for ${post['title']} — who is the winner?'), children: [
          for (final k in cands) SimpleDialogOption(onPressed: () => Navigator.pop(c, k['id'] as String), child: Text('${k['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
        ]));
        if (pick == null) return;
        winners.add({'post_id': post['id'], 'candidate_id': pick});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final posts = List<Map<String, dynamic>>.from(widget.term['council_post'] ?? const [])
      ..sort((a, b) { final r = ((a['row_no'] ?? 9) as int).compareTo((b['row_no'] ?? 9) as int); return r != 0 ? r : ((a['sort'] ?? 100) as int).compareTo((b['sort'] ?? 100) as int); });
    final grades = ref.watch(gradesProvider).value ?? const <Map<String, dynamic>>[];
    return ref.watch(_electionProvider(termId)).when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
      error: (e, _) => Text(_msg(e)),
      data: (e) {
        if (e == null) {
          return Panel(title: 'Elections for ${widget.term['label']}', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(posts.isEmpty ? 'First add the posts in “Council members” (Head Boy, Head Girl …), then start the election here.' : 'Posts: ${posts.map((p) => p['title']).join(', ')}.', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: busy || posts.isEmpty ? null : () => _do(() async => db.from('council_election').insert({'term_id': termId})),
                icon: const Icon(Icons.how_to_vote_rounded, size: 18), label: const Text('Start preparing the election'))),
          ]));
        }
        final status = e['status'] as String;
        final cands = List<Map<String, dynamic>>.from(e['council_candidate'] ?? const []);
        final res = e['results'] as Map<String, dynamic>?;
        final votes = {for (final c in List<Map<String, dynamic>>.from(res?['candidates'] ?? const [])) c['id']: (c['votes'] as num).toInt()};
        final voterGrades = List<String>.from(e['voter_grades'] ?? const []);
        final closes = e['closes_at'] == null ? null : DateTime.parse(e['closes_at']).toLocal();
        final label = const {'draft': 'Preparing', 'open': 'Voting open', 'closed': 'Voting closed', 'published': 'Published'}[status];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Panel(title: 'Elections ${widget.term['label']} · $label', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (res != null) Text('${res['voted']} of ${res['eligible']} students have voted${(res['eligible'] ?? 0) > 0 ? ' (${((res['voted'] as num) * 100 / (res['eligible'] as num)).round()}%)' : ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Who can vote', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final g in grades) FilterChip(label: Text('${g['code']}'), selected: voterGrades.contains(g['code']), visualDensity: VisualDensity.compact,
                onSelected: status == 'draft' ? (v) => _do(() async => db.from('council_election').update({'voter_grades': v ? [...voterGrades, g['code']] : voterGrades.where((x) => x != g['code']).toList()}).eq('id', e['id'])) : null)]),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: status == 'published' ? null : () async {
              final d = await showDatePicker(context: context, initialDate: closes ?? DateTime.now().add(const Duration(days: 2)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)));
              if (d == null || !context.mounted) return;
              final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 16, minute: 0));
              if (t == null) return;
              _do(() async => db.from('council_election').update({'closes_at': DateTime(d.year, d.month, d.day, t.hour, t.minute).toUtc().toIso8601String()}).eq('id', e['id']));
            }, icon: const Icon(Icons.timer_rounded, size: 18), label: Text(closes == null ? 'Voting closes at… (choose)' : 'Voting closes ${DateFormat('EEE d MMM, h:mm a').format(closes)}'))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (status == 'draft') FilledButton.icon(onPressed: busy || cands.isEmpty ? null : () async {
                final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Open voting now?'),
                    content: Text('Students of ${voterGrades.join(', ')} get a notification and can vote${closes != null ? ' until ${DateFormat('EEE d MMM, h:mm a').format(closes)}' : ''}. Candidates cannot be changed after this.'),
                    actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Open voting'))]));
                if (ok == true) _do(() async => db.rpc('council_open', params: {'p_election': e['id']}), 'Voting is open. Students have been told.');
              }, icon: const Icon(Icons.play_arrow_rounded, size: 18), label: const Text('Open voting')),
              if (status == 'open') OutlinedButton.icon(onPressed: busy ? null : () => _do(() async => db.from('council_election').update({'status': 'closed', 'closes_at': DateTime.now().toUtc().toIso8601String()}).eq('id', e['id']), 'Voting closed.'),
                  icon: const Icon(Icons.stop_rounded, size: 18), label: const Text('Close voting now')),
              if (status == 'open' || status == 'closed') FilledButton.icon(onPressed: busy ? null : () => _publish(e, posts), icon: const Icon(Icons.campaign_rounded, size: 18), label: Text('Publish the new council ${widget.term['label']}')),
              if (status != 'draft') OutlinedButton.icon(onPressed: busy ? null : _refresh, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh totals')),
            ]),
          ])),
          for (final p in posts) Builder(builder: (_) {
            final list = cands.where((k) => k['post_id'] == p['id']).toList()..sort((a, b) => (votes[b['id']] ?? 0).compareTo(votes[a['id']] ?? 0));
            final total = list.fold<int>(0, (a, k) => a + (votes[k['id']] ?? 0));
            final top = list.isEmpty ? 0 : (votes[list.first['id']] ?? 0);
            final tie = list.where((k) => (votes[k['id']] ?? 0) == top).length > 1 && top > 0;
            return Panel(title: '${p['title']} · ${list.length} candidate${list.length == 1 ? '' : 's'}', trailing: status == 'draft' ? OutlinedButton.icon(onPressed: () async {
              final ok = await showDialog<bool>(context: context, builder: (_) => _PersonDialog(table: 'council_candidate', parent: {'election_id': e['id'], 'post_id': p['id']}, postTitle: 'Candidate · ${p['title']}', slogan: true));
              if (ok == true) _refresh();
            }, icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text('Add candidate')) : null,
            child: list.isEmpty ? Text('No candidates yet (usually three).', style: TextStyle(color: cs.onSurfaceVariant)) : Column(children: [
              for (final k in list) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
                Face(k['full_name'] ?? '', k['photo_path'], size: 40),
                const SizedBox(width: 10),
                SizedBox(width: 180, child: Text('${k['full_name']}${(k['class_label'] ?? '').toString().isNotEmpty ? ' · ${k['class_label']}' : ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
                if (res != null) ...[
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(minHeight: 10, value: total == 0 ? 0 : (votes[k['id']] ?? 0) / total,
                      backgroundColor: cs.surfaceContainerHighest, color: (votes[k['id']] ?? 0) == top && top > 0 ? (tie ? Brand.amber : Brand.green) : Brand.gold))),
                  SizedBox(width: 90, child: Text('${votes[k['id']] ?? 0}${total > 0 ? ' · ${((votes[k['id']] ?? 0) * 100 / total).round()}%' : ''}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
                ] else Expanded(child: Text(k['slogan'] == null ? '' : '“${k['slogan']}”', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
                if (status == 'draft') IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () async {
                  final ok = await showDialog<bool>(context: context, builder: (_) => _PersonDialog(table: 'council_candidate', parent: {'election_id': e['id'], 'post_id': p['id']}, row: k, postTitle: 'Candidate · ${p['title']}', slogan: true));
                  if (ok == true) _refresh();
                }),
              ])),
              if (tie) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Tie — you will be asked to choose the winner when you publish.', style: TextStyle(color: context.tone(Brand.amber), fontWeight: FontWeight.w700))),
            ]));
          }),
          const NoteBox('Results are seen only by IT and the Principal until you publish. Totals only — nobody can see who voted for whom.', icon: Icons.lock_rounded),
        ]);
      },
    );
  }
}
