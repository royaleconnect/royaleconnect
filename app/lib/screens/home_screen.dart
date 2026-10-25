import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value!;
    final st = s.active!;
    final fees = ref.watch(feesProvider);
    final notices = ref.watch(noticesProvider);
    final unread = ref.watch(unreadMessagesProvider).value ?? 0;
    final transport = ref.watch(transportProvider).value;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    final greet = now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening';
    final unreadNotices = notices.value?.where((n) => !n.read).length ?? 0;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async { ref.invalidate(feesProvider); ref.invalidate(noticesProvider); ref.invalidate(unreadMessagesProvider); },
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: BrandHeader(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), hairline: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              InkWell(onTap: () => context.push(s.students.length > 1 ? '/students' : '/profile'), borderRadius: BorderRadius.circular(999),
                  child: Container(padding: const EdgeInsets.fromLTRB(6, 6, 12, 6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Avatar(st.initials, bg: Colors.white, fg: Brand.crimsonDeep, size: 34), const SizedBox(width: 10),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(st.fullName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                          Text('${st.grade ?? ''} · ${st.section ?? ''}', style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 11)),
                        ]),
                        if (s.students.length > 1) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.expand_more_rounded, color: Colors.white, size: 18)),
                      ]))),
              const Spacer(),
              _HeaderIcon(Icons.chat_bubble_outline_rounded, unread, () => context.push('/messages')),
              const SizedBox(width: 8),
              _HeaderIcon(Icons.notifications_none_rounded, unreadNotices, () => context.go('/announcements')),
              const SizedBox(width: 8),
              _HeaderIcon(Icons.settings_outlined, 0, () => context.push('/settings')),
            ]),
            const SizedBox(height: 18),
            Text(DateFormat('EEEE, d MMMM').format(now), style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 13)),
            Text(greet, style: t.headlineMedium?.copyWith(color: Colors.white)),
            const SizedBox(height: 16),
            // morning card — sits inside the header
            _MorningCard(fees: fees.value, transport: transport, cls: st.cls),
          ]))),
          SliverPadding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), sliver: SliverList(delegate: SliverChildListDelegate([
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // urgent banner(s)
              ...?notices.value?.where((n) => n.urgent && !n.read).map((n) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Material(color: Brand.crimson, borderRadius: BorderRadius.circular(16),
                  child: InkWell(onTap: () => context.go('/announcements'), borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                    const Avatar('!', bg: Colors.white, fg: Brand.crimson, size: 40), const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Eyebrow('Urgent', color: Brand.gold2), Text(n.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))])),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white),
                  ])))))),
              // fee card
              fees.when(
                loading: () => const _CardShell(child: SizedBox(height: 90, child: Center(child: CircularProgressIndicator()))),
                error: (e, _) => _CardShell(child: Text('Could not load fees. Pull to refresh.', style: TextStyle(color: cs.onSurfaceVariant))),
                data: (f) => _FeeCard(f),
              ),
              const SizedBox(height: 18),
              // tiles
              GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .98, children: [
                _Tile('Timetable', Icons.grid_view_rounded, Brand.blue, Brand.blueTint, () => context.push('/timetable')),
                _Tile('Star of the month', Icons.star_border_rounded, Brand.violet, Brand.violetTint, () => context.push('/star')),
                _Tile('Gallery', Icons.image_outlined, Brand.green, Brand.greenTint, () => context.push('/gallery')),
                _Tile('Leave', Icons.event_available_outlined, Brand.crimsonDeep, Brand.crimsonTint, () => context.push('/leave')),
                _Tile('Monthly plan', Icons.format_list_bulleted_rounded, Brand.amber, Brand.amberTint, () => context.push('/plan')),
                _Tile('Worksheets', Icons.task_outlined, Brand.blue, Brand.blueTint, () => context.push('/worksheets')),
                _Tile('Exams', Icons.fact_check_outlined, Brand.crimsonDeep, Brand.crimsonTint, () => context.push('/exams')),
                _Tile('Calendar', Icons.calendar_month_outlined, Brand.green, Brand.greenTint, () => context.push('/calendar')),
                _Tile('Messages', Icons.chat_bubble_outline_rounded, Brand.amber, Brand.amberTint, () => context.push('/messages'), badge: unread),
              ]),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("What's new", style: t.titleLarge?.copyWith(fontSize: 16)), TextButton(onPressed: () => context.go('/announcements'), child: const Text('See all'))]),
              ...?notices.value?.where((n) => !n.urgent).take(2).map((n) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _NoticeRow(n, () => context.go('/announcements')))),
              if (notices.value?.isEmpty ?? false) const NoteBox('No announcements yet. New ones from the school appear here and you get a notification.'),
            ]),
          ]))),
        ]),
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon; final int badge; final VoidCallback onTap;
  const _HeaderIcon(this.icon, this.badge, this.onTap);
  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        Material(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(12),
            child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white, size: 22)))),
        if (badge > 0) Positioned(top: 6, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 5), height: 18, constraints: const BoxConstraints(minWidth: 18), alignment: Alignment.center,
            decoration: BoxDecoration(color: Brand.gold, borderRadius: BorderRadius.circular(9)), child: Text('$badge', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Brand.ink)))),
      ]);
}

class _CardShell extends StatelessWidget {
  final Widget child; final bool lift;
  const _CardShell({required this.child, this.lift = true});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(22),
          boxShadow: lift ? [BoxShadow(color: Brand.crimsonDeep.withValues(alpha: .12), blurRadius: 30, offset: const Offset(0, 10))] : null),
      child: child);
}

String _hm(dynamic t) { final x = (t ?? '').toString(); return x.length >= 5 ? x.substring(0, 5) : x; }

class _MorningCard extends StatelessWidget {
  final FeeSummary? fees; final Map<String, dynamic>? transport; final String cls;
  const _MorningCard({this.fees, this.transport, required this.cls});
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now(); final weekend = now.weekday >= 6;
    final next = fees?.unpaid.isNotEmpty == true ? fees!.unpaid.first : null;
    final items = <(String, String, Color)>[
      weekend ? ('No school today', 'Classes resume ${now.weekday == 6 ? 'Monday' : 'tomorrow'}', Brand.muted) : ('Regular day', 'Check the timetable for what to carry', Brand.blue),
      if (next != null) ('Fee: ${inr(next.amount)} ${next.overdue ? 'overdue' : 'due ${DateFormat('d MMM').format(DateTime.parse(next.dueOn))}'}', next.title, next.overdue ? Brand.crimsonDeep : Brand.green),
      if (transport != null) ('Bus · ${transport!['route']?['name'] ?? ''}', '${transport!['stop']?['name'] ?? ''} · drop ${_hm(transport!['route']?['afternoon_start'])}', Brand.blue),
    ];
    return Container(padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1D1A20), Color(0xFF2C2730)]),
            border: Border.all(color: Brand.gold.withValues(alpha: .55)), borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Eyebrow('Your day · ${DateFormat('EEEE').format(now)}', color: Brand.gold), Text(cls, style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 11))]),
          const SizedBox(height: 10),
          for (final (a, b, c) in items) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: c, shape: BoxShape.circle)), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)), Text(b, style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 11))])),
          ])),
        ]));
  }
}

class _FeeCard extends StatelessWidget {
  final FeeSummary f;
  const _FeeCard(this.f);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (f.unpaid.isEmpty) {
      return _CardShell(child: Row(children: [const Avatar('✓', bg: Brand.greenTint, fg: Brand.green), const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('All fees paid for this year', style: TextStyle(fontWeight: FontWeight.w800)), Text('${inr(f.total)} received · receipts under Fees', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))]))]));
    }
    final od = f.overdue; final odAmt = od.fold<num>(0, (a, r) => a + r.amount);
    final next = f.dueSoon.isNotEmpty ? f.dueSoon.first : (f.upcoming.isNotEmpty ? f.upcoming.first : null);
    final head = od.isNotEmpty ? od.firstWhere((r) => !r.isLate, orElse: () => od.first) : next!;
    return InkWell(onTap: () => context.go('/fees'), borderRadius: BorderRadius.circular(22), child: _CardShell(child: Column(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Eyebrow(od.isNotEmpty ? 'Overdue · since ${DateFormat('d MMM').format(DateTime.parse(head.dueOn))}' : 'Due ${DateFormat('d MMM').format(DateTime.parse(head.dueOn))} · ${head.daysUntil()} days left', color: od.isNotEmpty ? Brand.crimsonDeep : Brand.amber),
          Text(inr(od.isNotEmpty ? odAmt : head.amount), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.5)),
          Text(od.isNotEmpty && od.any((r) => r.isLate) ? '${head.title} incl. late fee' : head.title, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ])),
        Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 18), alignment: Alignment.center, decoration: BoxDecoration(gradient: Brand.buttonGradient, borderRadius: BorderRadius.circular(12)),
            child: const Text('Pay now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
      ]),
      const SizedBox(height: 14), Divider(height: 1, color: cs.outline), const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text(od.isNotEmpty && next != null ? 'Next: ${next.title.split(' — ').first} · ${inr(next.amount)} due ${DateFormat('d MMM').format(DateTime.parse(next.dueOn))}' : 'Balance for the year ${inr(f.balance)}', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))),
        Text('${f.pct}% of year paid', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Brand.green)),
      ]),
    ])));
  }
}

class _Tile extends StatelessWidget {
  final String label; final IconData icon; final Color fg, bg; final VoidCallback onTap; final int badge;
  const _Tile(this.label, this.icon, this.fg, this.bg, this.onTap, {this.badge = 0});
  @override
  Widget build(BuildContext context) => Material(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(18),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Stack(children: [
        Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: fg, size: 22)),
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        ])),
        if (badge > 0) Positioned(top: 10, right: 10, child: Container(height: 18, constraints: const BoxConstraints(minWidth: 18), alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(color: Brand.gold, borderRadius: BorderRadius.circular(9)), child: Text('$badge', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Brand.ink)))),
      ])));
}

class _NoticeRow extends StatelessWidget {
  final Notice n; final VoidCallback onTap;
  const _NoticeRow(this.n, this.onTap);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(color: cs.surface, borderRadius: BorderRadius.circular(16), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6), decoration: BoxDecoration(color: n.read ? Colors.transparent : Brand.crimson, shape: BoxShape.circle)), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Eyebrow('${n.category.replaceAll('_', ' ')} · ${n.audience}', color: Brand.crimsonDeep),
        Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        Text('${n.by} · ${DateFormat('d MMM, h:mm a').format(DateTime.parse(n.when).toLocal())}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ])),
    ]))));
  }
}
