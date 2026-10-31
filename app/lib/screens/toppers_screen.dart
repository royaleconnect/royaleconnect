import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/data3.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'academics_screens.dart' show AppPage;
import 'family_screens.dart' show StorageImage;
import '../widgets/royal_extras.dart' show GoldLoading;
import '../widgets/royal_motion.dart' show CountUp, FadeRise, ShineSweep;

/// Board Toppers (Class X · Class XII) and the Hall of Fame — one page with three tabs.
/// Toppers: pick a year → the top 3 on a podium, then every subject centum (100 / 100).
/// Hall of Fame: a gold-frame wall with "In the spotlight" on top, filters by field and batch.
class ToppersScreen extends ConsumerStatefulWidget {
  final int tab;   // 0 = Class X, 1 = Class XII, 2 = Hall of Fame
  const ToppersScreen({super.key, this.tab = 0});
  @override
  ConsumerState<ToppersScreen> createState() => _ToppersScreenState();
}

class _ToppersScreenState extends ConsumerState<ToppersScreen> {
  late int tab = widget.tab;
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).value;
    final showToppers = featureOn(settings, 'toppers'), showFame = featureOn(settings, 'fame');
    final tabs = [if (showToppers) (0, 'Class X'), if (showToppers) (1, 'Class XII'), if (showFame) (2, 'Hall of Fame')];
    if (tabs.isNotEmpty && !tabs.any((t) => t.$1 == tab)) tab = tabs.first.$1;
    return AppPage(
      title: tab == 2 ? 'Hall of Fame' : 'Board Toppers',
      headerExtra: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final (i, l) in tabs) HeaderChip(l, selected: tab == i, onTap: () => setState(() => tab = i)),
      ])),
      body: tabs.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('This page is switched off by the school.')))
          : Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760),
              child: tab == 2 ? const FameWall() : ToppersView(boardClass: tab == 0 ? 'X' : 'XII'))),
    );
  }
}

// ================================================================== toppers
class ToppersView extends ConsumerStatefulWidget {
  final String boardClass;
  const ToppersView({super.key, required this.boardClass});
  @override
  ConsumerState<ToppersView> createState() => _ToppersViewState();
}

class _ToppersViewState extends ConsumerState<ToppersView> {
  int? year;
  @override
  void didUpdateWidget(covariant ToppersView old) { super.didUpdateWidget(old); if (old.boardClass != widget.boardClass) year = null; }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = ref.watch(toppersProvider(widget.boardClass));
    final results = ref.watch(boardResultsProvider(widget.boardClass)).value ?? const {};
    return all.when(
      loading: () => const GoldLoading(),
      error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load: $e'))),
      data: (rows) {
        final years = {for (final r in rows) (r['year'] as num).toInt(), ...results.keys}.toList()..sort((a, b) => b.compareTo(a));
        if (years.isEmpty) {
          return ListView(padding: const EdgeInsets.all(20), children: [NoteBox('Class ${widget.boardClass} toppers will appear here once the school adds them.', icon: Icons.emoji_events_outlined, iconColor: Brand.gold)]);
        }
        final y = years.contains(year) ? year! : years.first;
        final ofYear = rows.where((r) => (r['year'] as num).toInt() == y).toList();
        final podium = ofYear.where((r) => r['kind'] == 'rank').toList()..sort((a, b) => ((a['rank'] ?? 9) as int).compareTo((b['rank'] ?? 9) as int));
        final centums = ofYear.where((r) => r['kind'] == 'centum').toList();
        // centums by subject (in the order the school chose), and in each subject the school toppers first
        int rankOf(Map<String, dynamic> r) => (podium.where((p) => '${p['full_name']}'.toLowerCase() == '${r['full_name']}'.toLowerCase()).firstOrNull?['rank'] ?? 99) as int;
        int sortOf(Map<String, dynamic> r) => (r['sort'] ?? 100) as int;
        final bySubject = <String, List<Map<String, dynamic>>>{};
        for (final r in centums) { bySubject.putIfAbsent('${r['subject'] ?? ''}', () => []).add(r); }
        for (final l in bySubject.values) {
          l.sort((a, b) { final x = rankOf(a).compareTo(rankOf(b)); if (x != 0) return x; final y = sortOf(a).compareTo(sortOf(b)); return y != 0 ? y : '${a['full_name']}'.compareTo('${b['full_name']}'); });
        }
        int subjectOrder(String s) => bySubject[s]!.map(sortOf).reduce((a, b) => a < b ? a : b);
        final subjects = bySubject.keys.toList()..sort((a, b) { final x = subjectOrder(a).compareTo(subjectOrder(b)); return x != 0 ? x : a.compareTo(b); });
        final res = results[y];
        final top = podium.isEmpty ? null : podium.first['percent'];
        return RefreshIndicator(
          onRefresh: () async { ref.invalidate(toppersProvider(widget.boardClass)); ref.invalidate(boardResultsProvider(widget.boardClass)); },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
            // years
            SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final x in years) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
                label: Text('$x'), selected: x == y, showCheckmark: false, selectedColor: Brand.crimson,
                labelStyle: TextStyle(fontWeight: FontWeight.w800, color: x == y ? Colors.white : null),
                onSelected: (_) => setState(() => year = x))),
            ])),
            const SizedBox(height: 14),
            // summary strip
            if (res != null || top != null) Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFE9D08A), Brand.gold]), borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                if (res?['pass_percent'] != null) _stat('${_n(res!['pass_percent'])}%', 'Passed'),
                if (res?['distinctions'] != null) _stat('${res!['distinctions']}', 'scored 90%+'),
                if (res?['students'] != null && res?['distinctions'] == null) _stat('${res!['students']}', 'students'),
                if (top != null) _stat('${_n(top)}%', 'School top'),
              ]),
            ),
            if (res?['note'] != null && '${res!['note']}'.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${res['note']}', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
            const SizedBox(height: 18),
            if (podium.isNotEmpty) _Podium(podium),
            if (centums.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text('💯  CENTUMS · 100 / 100', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .6, fontSize: 12, color: cs.onSurfaceVariant)),
              for (final sub in subjects) ...[
                Padding(padding: const EdgeInsets.only(top: 14, bottom: 8), child: Text('$sub · ${bySubject[sub]!.length}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: context.tone(Brand.crimsonDeep)))),
                LayoutBuilder(builder: (_, c) {
                  final cols = c.maxWidth >= 520 ? 2 : 1;
                  final w = (c.maxWidth - (cols - 1) * 10) / cols;
                  return Wrap(spacing: 10, runSpacing: 10, children: [for (final r in bySubject[sub]!) SizedBox(width: w, child: _CentumCard(r))]);
                }),
              ],
            ],
            if (podium.isEmpty && centums.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: NoteBox('The names for $y are not added yet.', icon: Icons.hourglass_empty_rounded)),
          ]),
        );
      },
    );
  }

  Widget _stat(String a, String b) => Expanded(child: Column(children: [
    Text(a, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Brand.ink)),
    Text(b, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Brand.ink)),
  ]));
}

String _n(dynamic v) { final d = (v as num?)?.toDouble() ?? 0; return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1); }

/// A round photo with a gold ring; initials when there is no photo.
class Face extends StatelessWidget {
  final String name; final String? photo; final double size; final Color ring;
  const Face(this.name, this.photo, {super.key, this.size = 72, this.ring = Brand.gold});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size, padding: EdgeInsets.all(size * .05),
    decoration: BoxDecoration(shape: BoxShape.circle, color: ring),
    child: ClipOval(child: photo != null && photo!.isNotEmpty
        ? StorageImage(photo!, width: size, height: size)
        : Container(color: Brand.crimsonTint, alignment: Alignment.center, child: Text(initialsOf(name), style: TextStyle(color: Brand.crimsonDeep, fontWeight: FontWeight.w800, fontSize: size * .32)))),
  );
}

class _Podium extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _Podium(this.rows);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Map<String, dynamic>? at(int rank) => rows.where((r) => r['rank'] == rank).firstOrNull;
    Widget place(Map<String, dynamic>? r, int rank) {
      if (r == null) return const Expanded(child: SizedBox());
      final first = rank == 1;
      return Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        FadeRise(delayMs: rank == 1 ? 900 : rank == 2 ? 600 : 300, dy: 30, child: first
            ? ShineSweep(delay: const Duration(milliseconds: 1600), every: const Duration(milliseconds: 4000), child: Face(r['full_name'] ?? '', r['photo_path'], size: 96, ring: Brand.gold))
            : Face(r['full_name'] ?? '', r['photo_path'], size: 74, ring: rank == 2 ? const Color(0xFFB9BEC6) : const Color(0xFFC58B5A))),
        const SizedBox(height: 8),
        Text(r['full_name'] ?? '', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, fontSize: first ? 15.5 : 14)),
        if ((r['section'] ?? '').toString().isNotEmpty) Text('${r['section']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        if (r['percent'] != null) CountUp((r['percent'] as num).toDouble(), decimals: _n(r['percent']).contains('.') ? 1 : 0, suffix: '%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: first ? 18 : 16, color: context.tone(Brand.green))),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: Duration(milliseconds: 900 + rank * 150), curve: Curves.easeOutBack, builder: (_, v, child) => Container(height: (first ? 54 : rank == 2 ? 38 : 28) * v.clamp(0.0, 1.2), alignment: Alignment.center, clipBehavior: Clip.hardEdge, decoration: BoxDecoration(color: first ? Brand.gold : cs.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))), child: child),
          child: Container(alignment: Alignment.center,
          decoration: BoxDecoration(color: first ? Brand.gold : cs.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
          child: Text('$rank', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: first ? Colors.white : context.tone(Brand.crimsonDeep))))),
      ]));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [place(at(2), 2), const SizedBox(width: 8), place(at(1), 1), const SizedBox(width: 8), place(at(3), 3)]);
  }
}

class _CentumCard extends StatelessWidget {
  final Map<String, dynamic> r;
  const _CentumCard(this.r);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16)), child: Row(children: [
      Face(r['full_name'] ?? '', r['photo_path'], size: 44, ring: Brand.gold2),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r['full_name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text([if ((r['subject'] ?? '').toString().isNotEmpty) r['subject'], if ((r['section'] ?? '').toString().isNotEmpty) r['section']].join(' · '), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ])),
      Text('100', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: context.tone(Brand.amber))),
    ]));
  }
}

// ================================================================== hall of fame
class FameWall extends ConsumerStatefulWidget {
  const FameWall({super.key});
  @override
  ConsumerState<FameWall> createState() => _FameWallState();
}

class _FameWallState extends ConsumerState<FameWall> {
  String? category; int? batch;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ref.watch(hallOfFameProvider).when(
      loading: () => const GoldLoading(),
      error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not load: $e'))),
      data: (all) {
        if (all.isEmpty) return ListView(padding: const EdgeInsets.all(20), children: const [NoteBox('Our Hall of Fame will appear here once the school adds former students.', icon: Icons.star_outline_rounded, iconColor: Brand.gold)]);
        final spot = all.where((r) => r['spotlight'] == true).toList();
        final cats = {for (final r in all) (r['category'] ?? '') as String}.where((c) => c.isNotEmpty).toList()..sort();
        final batches = {for (final r in all) if (r['batch'] != null) (r['batch'] as num).toInt()}.toList()..sort((a, b) => b.compareTo(a));
        final shown = all.where((r) => (category == null || r['category'] == category) && (batch == null || r['batch'] == batch)).toList();
        Widget chip(String l, bool sel, VoidCallback onTap) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
            label: Text(l), selected: sel, showCheckmark: false, selectedColor: Brand.crimson,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, color: sel ? Colors.white : null), onSelected: (_) => onTap()));
        return RefreshIndicator(onRefresh: () async => ref.invalidate(hallOfFameProvider), child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
          for (final s in spot.take(2)) Padding(padding: const EdgeInsets.only(bottom: 14), child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(gradient: Brand.headerGradient, borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              Face(s['full_name'] ?? '', s['photo_path'], size: 72),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('IN THE SPOTLIGHT', style: TextStyle(color: Brand.gold2, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                Text(s['full_name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                Text([if (s['batch'] != null) 'Batch ${s['batch']}', s['achievement'] ?? ''].join(' · '), style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 13)),
              ])),
            ]))),
          SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
            chip('All', category == null, () => setState(() => category = null)),
            for (final c in cats) chip('${fameIcons[c] ?? '⭐'} $c', category == c, () => setState(() => category = category == c ? null : c)),
          ])),
          if (batches.length > 1) Padding(padding: const EdgeInsets.only(top: 6), child: SizedBox(height: 40, child: ListView(scrollDirection: Axis.horizontal, children: [
            chip('All batches', batch == null, () => setState(() => batch = null)),
            for (final b in batches) chip('$b', batch == b, () => setState(() => batch = batch == b ? null : b)),
          ]))),
          const SizedBox(height: 12),
          if (shown.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('No one here yet for this choice.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant))),
          LayoutBuilder(builder: (_, c) {
            final cols = c.maxWidth >= 640 ? 3 : 2;
            final w = (c.maxWidth - (cols - 1) * 12) / cols;
            return Wrap(spacing: 12, runSpacing: 12, children: [for (final r in shown) SizedBox(width: w, child: _FameCard(r))]);
          }),
        ]));
      },
    );
  }
}

class _FameCard extends StatelessWidget {
  final Map<String, dynamic> r;
  const _FameCard(this.r);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cat = (r['category'] ?? '') as String;
    return Container(
      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Brand.gold, width: 2)),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(children: [
        Stack(children: [
          AspectRatio(aspectRatio: 1.15, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: r['photo_path'] != null && '${r['photo_path']}'.isNotEmpty
              ? StorageImage(r['photo_path'])
              : Container(color: Brand.crimsonTint, alignment: Alignment.center, child: Text(initialsOf(r['full_name'] ?? ''), style: const TextStyle(color: Brand.crimsonDeep, fontSize: 34, fontWeight: FontWeight.w800))))),
          if (r['batch'] != null) Positioned(top: 8, left: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: const BoxDecoration(color: Brand.crimsonDeep, borderRadius: BorderRadius.horizontal(right: Radius.circular(8))),
              child: Text('${r['batch']}', style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)))),
        ]),
        const SizedBox(height: 8),
        Text(r['full_name'] ?? '', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
        Text(r['achievement'] ?? '', textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        if (cat.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${fameIcons[cat] ?? '⭐'} $cat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: context.tone(Brand.amber)))),
      ]),
    );
  }
}
