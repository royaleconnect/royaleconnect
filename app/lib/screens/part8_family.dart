import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth/session.dart';
import '../core/config.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_motion.dart' show FadeRise, ConfettiBurst;

/// Part 8, the family side:
///   • the app locked by the school — for pending fees (Fees, Transport, urgent notices and the office stay open)
///     or for another reason till a date (the whole app)
///   • voting in the Student Council elections through one link, without signing in

// ================================================================== the lock
/// The locks on this sign-in's children: student id → {kind: 'fees' | 'other', till, due}. Empty = nothing is locked.
final lockProvider = FutureProvider<Map<String, Map<String, dynamic>>>((ref) async {
  final s = ref.watch(sessionProvider).value;
  if (s == null || s.kind != 'student' || s.viewOnly) return const {};
  try {
    final rows = (await db.rpc('my_lock')) as List? ?? const [];
    return {for (final x in rows) '${(x as Map)['student_id']}': Map<String, dynamic>.from(x)};
  } catch (_) {
    return const {};   // never lock a family out because of a network problem
  }
});

/// Where a locked family may still go. null = the page is open; otherwise the address to show instead.
String? lockRedirect(Map<String, dynamic>? lock, String loc) {
  if (lock == null) return loc == '/locked' ? '/' : null;
  const always = ['/locked', '/students', '/settings', '/privacy', '/change-password', '/login/add', '/help'];
  if (always.any((p) => loc == p || loc.startsWith('$p/'))) return null;
  if (lock['kind'] == 'fees') {
    const open = ['/fees', '/pay', '/receipts', '/receipt', '/bus', '/announcements', '/notice'];
    if (open.any((p) => loc == p || loc.startsWith('$p/'))) return null;
  }
  return '/locked';
}

class LockedScreen extends ConsumerWidget {
  const LockedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    final lock = ref.watch(lockProvider).value?[s?.activeStudentId];
    final cs = Theme.of(context).colorScheme;
    final fees = lock?['kind'] == 'fees';
    final due = (lock?['due'] ?? 0) as num;
    final till = lock?['till'] == null ? null : DateTime.tryParse('${lock!['till']}');
    Widget tile(IconData icon, String t, String sub, VoidCallback? onTap, {bool locked = false}) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Material(
      color: cs.surface, borderRadius: BorderRadius.circular(16), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: locked ? cs.outlineVariant : Brand.gold.withValues(alpha: .6))),
        child: Opacity(opacity: locked ? .5 : 1, child: Row(children: [
          Icon(icon, color: locked ? cs.onSurfaceVariant : context.tone(Brand.crimsonDeep)), const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
            if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ])),
          Icon(locked ? Icons.lock_rounded : Icons.chevron_right_rounded, size: 20, color: cs.onSurfaceVariant),
        ]))))));
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(20, 14, 20, 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Royale Connect', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        if (s?.active != null) Text(s!.active!.fullName, style: TextStyle(color: Colors.white.withValues(alpha: .85), fontWeight: FontWeight.w600)),
      ])),
      Expanded(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: ListView(padding: const EdgeInsets.all(20), children: [
        FadeRise(child: Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Brand.amberTint, borderRadius: BorderRadius.circular(20), border: Border.all(color: Brand.gold.withValues(alpha: .7))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.lock_rounded, color: context.tone(Brand.amber)), const SizedBox(width: 10),
              Expanded(child: Text(fees ? 'Fees are pending' : 'The app is locked', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF5A3D05))))]),
            const SizedBox(height: 8),
            Text(lock == null ? 'One moment…'
                : fees ? 'Fees of ${inr(due)} are pending. Parts of the app are locked until they are paid. It opens again by itself as soon as the payment is in.'
                : 'The school has locked the app${till == null ? '' : ' till ${DateFormat('EEEE, d MMMM').format(till)}'}. Please contact the school office.',
                style: const TextStyle(color: Color(0xFF5A3D05), height: 1.4, fontWeight: FontWeight.w600)),
            if (fees) Padding(padding: const EdgeInsets.only(top: 14), child: PrimaryButton('Pay now', onPressed: () => context.go('/fees'))),
          ]))),
        const SizedBox(height: 18),
        if (fees) ...[
          tile(Icons.account_balance_wallet_rounded, 'Fees', 'Pay and see receipts', () => context.go('/fees')),
          tile(Icons.directions_bus_rounded, 'Transport', 'The school bus, live', () => context.go('/bus')),
          tile(Icons.campaign_rounded, 'Urgent notices', 'Only urgent notices are shown', () => context.go('/announcements')),
        ],
        tile(Icons.call_rounded, 'Contact the office', AppConfig.officePhonesShort, () => launchUrl(Uri.parse('tel:${AppConfig.officePhone}'))),
        if ((s?.students.length ?? 0) > 1) tile(Icons.switch_account_rounded, 'Another child', 'Choose a different child on this sign-in', () => context.go('/students')),
        const SizedBox(height: 8),
        for (final t in fees ? const ['Diary', 'Timetable and calendar', 'Messages to teachers', 'Marks and report cards', 'Gallery and class photos', 'Certificates and ID card'] : const <String>[])
          tile(Icons.block_rounded, t, '', null, locked: true),
        Center(child: TextButton.icon(onPressed: () => ref.invalidate(lockProvider), icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('I have paid — check again'))),
      ])))),
    ]));
  }
}

// ================================================================== voting by one link
class VoteLinkScreen extends StatefulWidget {
  final String linkKey;
  const VoteLinkScreen({super.key, required this.linkKey});
  @override
  State<VoteLinkScreen> createState() => _VoteLinkScreenState();
}

class _VoteLinkScreenState extends State<VoteLinkScreen> {
  late Future<Map<String, dynamic>> info = _load();
  final picked = <String, String>{};   // post id → candidate id
  bool busy = false, done = false;

  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(await db.rpc('vote_link_open', params: {'p_key': widget.linkKey}) as Map);

  Future<void> _vote(List<Map<String, dynamic>> posts) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Cast your vote?'),
      content: Text(picked.length < posts.length ? 'You have chosen for ${picked.length} of ${posts.length} posts. A vote cannot be changed afterwards.' : 'A vote cannot be changed afterwards.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Go back')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Vote'))]));
    if (ok != true) return;
    setState(() => busy = true);
    try {
      await db.rpc('vote_link_cast', params: {'p_key': widget.linkKey, 'p_choices': [for (final e in picked.entries) {'post_id': e.key, 'candidate_id': e.value}]});
      if (mounted) setState(() { done = true; busy = false; picked.clear(); });
    } catch (e) {
      if (mounted) { setState(() => busy = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)))); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget message(IconData icon, String t, String sub, {Widget? action}) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 56, color: Brand.gold), const SizedBox(height: 14),
      Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 8),
      Text(sub, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
      if (action != null) Padding(padding: const EdgeInsets.only(top: 18), child: action),
    ])));
    return Scaffold(body: Column(children: [
      const BrandHeader(padding: EdgeInsets.fromLTRB(20, 14, 20, 16), child: Text('Student Council elections', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800))),
      Expanded(child: done
        ? Stack(children: [
            message(Icons.how_to_vote_rounded, 'Your vote is in. Thank you!', 'Nobody can see who you voted for.',
                action: OutlinedButton.icon(onPressed: () => setState(() { done = false; info = _load(); }), icon: const Icon(Icons.person_rounded, size: 18), label: const Text('Next student'))),
            const Positioned.fill(child: IgnorePointer(child: ConfettiBurst())),
          ])
        : FutureBuilder<Map<String, dynamic>>(future: info, builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snap.hasError) return message(Icons.wifi_off_rounded, 'Could not open the ballot', 'Please check the internet and try again.', action: FilledButton(onPressed: () => setState(() => info = _load()), child: const Text('Try again')));
            final d = snap.data!;
            if (d['state'] == 'closed') return message(Icons.lock_clock_rounded, 'Voting is not open', 'The school opens voting on election day. Please try again then.');
            if (d['state'] != 'open') return message(Icons.link_off_rounded, 'This link does not work', 'Please ask the school for the new voting link.');
            final posts = [for (final x in (d['posts'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
            return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 28), children: [
              Text('Council ${d['label'] ?? ''}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Choose one candidate for each post, then press Vote at the bottom. Your vote is secret.', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 14),
              for (final (i, p) in posts.indexed) FadeRise(delayMs: 50 * i, dy: 10, child: Container(margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: picked.containsKey(p['id']) ? Brand.gold : cs.outlineVariant, width: picked.containsKey(p['id']) ? 1.6 : 1)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${p['title']}'.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.4, color: context.tone(Brand.crimsonDeep))),
                  const SizedBox(height: 8),
                  for (final k in [for (final x in (p['candidates'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)]) Padding(padding: const EdgeInsets.only(bottom: 8), child: InkWell(
                    onTap: () => setState(() => picked[p['id'] as String] = k['id'] as String), borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: picked[p['id']] == k['id'] ? Brand.gold.withValues(alpha: .14) : null, borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: picked[p['id']] == k['id'] ? Brand.gold : cs.outlineVariant.withValues(alpha: .7), width: picked[p['id']] == k['id'] ? 2 : 1)),
                      child: Row(children: [
                        Icon(picked[p['id']] == k['id'] ? Icons.check_circle_rounded : Icons.radio_button_off_rounded, color: picked[p['id']] == k['id'] ? Brand.gold : cs.onSurfaceVariant), const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${k['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                          if ('${k['class'] ?? ''}${k['slogan'] ?? ''}'.isNotEmpty) Text([if ((k['class'] ?? '').toString().isNotEmpty) '${k['class']}', if ((k['slogan'] ?? '').toString().isNotEmpty) '“${k['slogan']}”'].join(' · '),
                              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                        ])),
                      ])))),
                ]))),
              PrimaryButton(busy ? 'Sending…' : picked.isEmpty ? 'Choose your candidates' : 'Vote (${picked.length} of ${posts.length})', onPressed: busy || picked.isEmpty ? null : () => _vote(posts)),
            ])));
          })),
    ]));
  }
}
