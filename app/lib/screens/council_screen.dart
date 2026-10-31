import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../auth/session.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'academics_screens.dart' show AppPage;
import 'toppers_screen.dart' show Face;
import '../widgets/royal_extras.dart' show GoldLoading;

/// Student Council — this year's council (photos, line by line), earlier councils as year tabs,
/// and voting when the school opens the elections. One vote per post; nobody can see who voted for whom.
String _msg(Object e) => e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');

/// Councils with their posts and members, newest first (families see published ones; staff see all).
final councilTermsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await db.from('council_term').select('id,label,published,council_post(id,title,row_no,sort,council_member(id,full_name,class_label,photo_path,sort))').order('label', ascending: false);
  return List<Map<String, dynamic>>.from(rows);
});

/// The election this child can vote in right now (null when none is open).
final openElectionProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final s = ref.watch(sessionProvider).value;
  final st = s?.active;
  if (s == null || s.kind != 'student' || st == null) return null;
  final r = await db.rpc('council_open_election', params: {'p_student': st.id});
  return r == null ? null : Map<String, dynamic>.from(r as Map);
});

class CouncilScreen extends StatelessWidget {
  const CouncilScreen({super.key});
  @override
  Widget build(BuildContext context) => const AppPage(title: 'Student Council', body: CouncilView());
}

class CouncilView extends ConsumerStatefulWidget {
  final bool staff;
  const CouncilView({super.key, this.staff = false});
  @override
  ConsumerState<CouncilView> createState() => _CouncilViewState();
}

class _CouncilViewState extends ConsumerState<CouncilView> {
  String? termId;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final election = widget.staff ? null : ref.watch(openElectionProvider).value;
    return ref.watch(councilTermsProvider).when(
      loading: () => const GoldLoading(),
      error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_msg(e)))),
      data: (all) {
        final terms = all.where((t) => t['published'] == true).toList();
        final t = terms.where((x) => x['id'] == termId).firstOrNull ?? terms.firstOrNull;
        final posts = List<Map<String, dynamic>>.from(t?['council_post'] ?? const [])
          ..sort((a, b) { final r = ((a['row_no'] ?? 9) as int).compareTo((b['row_no'] ?? 9) as int); return r != 0 ? r : ((a['sort'] ?? 100) as int).compareTo((b['sort'] ?? 100) as int); });
        final rows = <int, List<Map<String, dynamic>>>{};
        for (final p in posts) {
          for (final m in List<Map<String, dynamic>>.from(p['council_member'] ?? const [])) {
            rows.putIfAbsent((p['row_no'] ?? 9) as int, () => []).add({...m, 'post': p['title']});
          }
        }
        return Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: RefreshIndicator(
          onRefresh: () async { ref.invalidate(councilTermsProvider); ref.invalidate(openElectionProvider); },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
            if (terms.length > 1) SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final x in terms) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
                label: Text('${x['label']}'), selected: x['id'] == t?['id'], showCheckmark: false, selectedColor: Brand.crimson,
                labelStyle: TextStyle(fontWeight: FontWeight.w800, color: x['id'] == t?['id'] ? Colors.white : null), onSelected: (_) => setState(() => termId = x['id']))),
            ])),
            if (election != null && election['eligible'] == true) _VoteBanner(election),
            if (t == null) const NoteBox('The Student Council will appear here once the school adds it.', icon: Icons.groups_rounded),
            if (t != null) Padding(padding: const EdgeInsets.only(top: 6, bottom: 10), child: Text('Student Council ${t['label']}', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: context.tone(Brand.crimsonDeep)))),
            for (final e in (rows.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) Padding(padding: const EdgeInsets.only(bottom: 0), child: LayoutBuilder(builder: (_, c) {
              // every card the same: two per line, same photo size; the two of a line share one height (no empty space)
              final pairs = [for (var i = 0; i < e.value.length; i += 2) e.value.sublist(i, math.min(i + 2, e.value.length))];
              return Column(children: [for (final pr in pairs) Padding(padding: const EdgeInsets.only(bottom: 10), child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, m) in pr.indexed) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: _MemberCard(m))],
                if (pr.length == 1) const Expanded(child: SizedBox()),
              ])))]);
            })),
            if (t != null && rows.isEmpty) Text('Members will appear here soon.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            if (election == null || election['eligible'] != true) Container(padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Brand.amberTint, border: Border.all(color: Brand.gold), borderRadius: BorderRadius.circular(12)),
              child: const Text('🗳  Next year’s Student Council elections will open here.', textAlign: TextAlign.center, style: TextStyle(color: Brand.ink, fontWeight: FontWeight.w700))),
          ]),
        )));
      },
    );
  }
}

class _MemberCard extends StatelessWidget {
  final Map<String, dynamic> m;
  const _MemberCard(this.m);
  static const size = 88.0;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18)),
    child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
      Face(m['full_name'] ?? '', m['photo_path'], size: size),
      const SizedBox(height: 8),
      Text('${m['post']}'.toUpperCase(), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: .4, color: context.tone(Brand.crimson))),
      const SizedBox(height: 2),
      Text('${m['full_name']}', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      if ((m['class_label'] ?? '').toString().isNotEmpty) Text('${m['class_label']}', maxLines: 1, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]),
  );
}

class _VoteBanner extends ConsumerWidget {
  final Map<String, dynamic> e;
  const _VoteBanner(this.e);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voted = e['voted'] == true;
    final closes = e['closes_at'] == null ? null : DateTime.parse(e['closes_at']).toLocal();
    return Container(
      margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: Brand.headerGradient, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('🗳 Council Elections ${e['label']}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(voted ? 'Thank you for voting! The results will be announced by the school.' : 'Voting is open${closes != null ? ' till ${DateFormat('EEE d MMM, h:mm a').format(closes)}' : ''} · one vote per post · secret',
            style: TextStyle(color: Colors.white.withValues(alpha: .9))),
        if (!voted) ...[
          const SizedBox(height: 12),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Brand.crimsonDeep),
            onPressed: () async { await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VotingScreen(election: e))); ref.invalidate(openElectionProvider); },
            child: const Text('Vote now')),
        ],
      ]),
    );
  }
}

// ================================================================== voting
class VotingScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> election;
  const VotingScreen({super.key, required this.election});
  @override
  ConsumerState<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends ConsumerState<VotingScreen> {
  List<Map<String, dynamic>>? posts;   // [{id,title,candidates:[...]}]
  final choice = <String, String>{};   // post → candidate
  int step = 0; bool busy = false; String? error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final c = await db.from('council_candidate').select('id,post_id,full_name,class_label,slogan,photo_path,sort,post:post_id(id,title,row_no,sort)').eq('election_id', widget.election['id']);
      final by = <String, Map<String, dynamic>>{};
      for (final k in c) {
        final p = k['post'];
        by.putIfAbsent(p['id'], () => {...Map<String, dynamic>.from(p), 'candidates': <Map<String, dynamic>>[]})['candidates'].add(Map<String, dynamic>.from(k));
      }
      final list = by.values.toList()..sort((a, b) { final r = ((a['row_no'] ?? 9) as int).compareTo((b['row_no'] ?? 9) as int); return r != 0 ? r : ((a['sort'] ?? 100) as int).compareTo((b['sort'] ?? 100) as int); });
      setState(() => posts = list);
    } catch (e) { setState(() => error = _msg(e)); }
  }

  Future<void> _submit() async {
    setState(() => busy = true);
    try {
      final st = ref.read(sessionProvider).value!.active!;
      await db.rpc('council_vote_cast', params: {'p_election': widget.election['id'], 'p_student': st.id,
        'p_choices': [for (final e in choice.entries) {'post_id': e.key, 'candidate_id': e.value}]});
      if (!mounted) return;
      await showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Thank you for voting! 🎉'),
          content: const Text('Your vote is saved and is secret. The school will announce the new council.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))]));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_msg(e)))); setState(() => busy = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = posts;
    Widget body;
    if (error != null) { body = Center(child: Text(error!)); }
    else if (p == null) { body = const GoldLoading(); }
    else if (p.isEmpty) { body = const Center(child: Text('No candidates yet.')); }
    else if (step >= p.length) {
      // review
      body = ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Check your choices', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Once you submit, your vote cannot be changed. Nobody can see who you voted for.', style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        for (final (i, x) in p.indexed) ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${x['title']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(choice[x['id']] == null ? 'No vote' : (x['candidates'] as List).firstWhere((k) => k['id'] == choice[x['id']])['full_name']),
          trailing: TextButton(onPressed: () => setState(() => step = i), child: const Text('Change')),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: busy || choice.isEmpty ? null : _submit, child: Text(busy ? 'Saving…' : 'Submit my vote')),
      ]);
    } else {
      final post = p[step];
      body = ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [for (var i = 0; i < p.length; i++) Expanded(child: Container(height: 6, margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(color: i <= step ? Brand.crimson : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(4))))]),
        const SizedBox(height: 10),
        Text('Post ${step + 1} of ${p.length}', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
        Text('${post['title']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        for (final k in (post['candidates'] as List)) Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(
          color: choice[post['id']] == k['id'] ? Brand.greenTint : cs.surface, borderRadius: BorderRadius.circular(16),
          child: InkWell(borderRadius: BorderRadius.circular(16), onTap: () => setState(() => choice[post['id']] = k['id']), child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: choice[post['id']] == k['id'] ? Brand.green : Colors.transparent, width: 2)),
            child: Row(children: [
              Face(k['full_name'] ?? '', k['photo_path'], size: 58),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${k['full_name']}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: choice[post['id']] == k['id'] ? Brand.ink : null)),
                Text([if ((k['class_label'] ?? '').toString().isNotEmpty) k['class_label'], if ((k['slogan'] ?? '').toString().isNotEmpty) '“${k['slogan']}”'].join(' · '),
                    style: TextStyle(fontSize: 12.5, color: choice[post['id']] == k['id'] ? Brand.muted : cs.onSurfaceVariant)),
              ])),
              Icon(choice[post['id']] == k['id'] ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: choice[post['id']] == k['id'] ? Brand.green : cs.outline),
            ]))))),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => setState(() => step++), child: Text(step == p.length - 1 ? 'Review my choices' : 'Next post →')),
        if (step > 0) TextButton(onPressed: () => setState(() => step--), child: const Text('← Back')),
      ]);
    }
    return Scaffold(
      appBar: AppBar(backgroundColor: Brand.crimsonDeep, foregroundColor: Colors.white, title: Text('Council Elections ${widget.election['label']}', style: const TextStyle(fontWeight: FontWeight.w800))),
      body: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: body)),
    );
  }
}
