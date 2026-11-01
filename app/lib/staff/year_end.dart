import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_motion.dart' show loopWhileVisible, liteMotion;
import '../widgets/royal_extras.dart' show GoldLoading;
import 'staff_shell.dart';

/// Year-end checklist for IT (shared with the Principal).
/// Shows on the dashboard from 15 February to 30 June, in two parts: "By 1 March" and "By 15 May".
/// Items tick themselves when the app can see they are done; the rest are ticked by hand.
/// It goes away when everything is done, or after 30 June.

final yearEndProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  ref.cacheFor();
  final s = ref.watch(sessionProvider).value;
  if (s == null || !(s.hasRole('it_admin') || s.hasRole('principal'))) return null;
  try {
    return Map<String, dynamic>.from(await db.rpc('year_end_status') as Map);
  } catch (_) {
    return null;   // database step not run yet: no card
  }
});

List<Map<String, dynamic>> _items(Map<String, dynamic> d) => [for (final x in (d['items'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];

/// For the IT / Principal dashboard. Hidden outside 15 Feb – 30 June and once everything is done.
class YearEndCard extends ConsumerStatefulWidget {
  const YearEndCard({super.key});
  @override
  ConsumerState<YearEndCard> createState() => _YearEndCardState();
}

class _YearEndCardState extends ConsumerState<YearEndCard> with SingleTickerProviderStateMixin {
  late final AnimationController glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool get _it => ref.read(sessionProvider).value?.hasRole('it_admin') ?? false;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); if (_it) loopWhileVisible(context, glow, reverse: true); }
  @override
  void dispose() { glow.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(yearEndProvider).value;
    if (d == null || d['show'] != true) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final items = _items(d);
    final done = items.where((i) => i['done'] == true).length;
    final p1Open = items.where((i) => i['part'] == 1 && i['done'] != true).length;
    final today = DateTime.parse(d['today']);
    final p1By = DateTime.parse(d['part1_by']), p2By = DateTime.parse(d['part2_by']);
    final next = p1Open > 0 ? 'Part 1 by ${DateFormat('d MMMM').format(p1By)}${today.isAfter(p1By) ? ' — overdue' : ''}' : 'Part 2 by ${DateFormat('d MMMM').format(p2By)}${today.isAfter(p2By) ? ' — overdue' : ''}';
    final late = (p1Open > 0 && today.isAfter(p1By)) || today.isAfter(p2By);
    final it = _it;

    final card = Material(color: cs.surface, borderRadius: BorderRadius.circular(18), child: InkWell(
      borderRadius: BorderRadius.circular(18), onTap: () => context.go('/staff/year-end'),
      child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        Container(width: 44, height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Brand.gold2, Brand.gold])),
            child: const Icon(Icons.event_available_rounded, color: Brand.crimsonDeep)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Getting ready for ${d['next']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 2),
          Text('$done of ${items.length} done · $next', style: TextStyle(fontSize: 12.5, color: late ? context.tone(Brand.crimson) : cs.onSurfaceVariant, fontWeight: late ? FontWeight.w800 : FontWeight.w500)),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: items.isEmpty ? 0 : done / items.length, minHeight: 7, backgroundColor: cs.surfaceContainerHighest, color: Brand.gold)),
        ])),
        const SizedBox(width: 8),
        Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
      ])),
    ));

    // IT: a soft gold glow around the card (still in lite mode)
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: RepaintBoundary(child: AnimatedBuilder(
      animation: glow,
      builder: (_, child) {
        final v = it && !liteMotion(context) ? glow.value : (it ? .6 : 0.0);
        return Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
            border: Border.all(color: it ? Brand.gold.withValues(alpha: .55 + .45 * v) : cs.outline.withValues(alpha: .6), width: it ? 1.6 : 1),
            // the glow itself is a still shadow (no moving blur); only the gold border breathes
            boxShadow: it ? [BoxShadow(color: Brand.gold.withValues(alpha: .28), blurRadius: 14)] : null),
          child: child);
      },
      child: card,
    )));
  }
}

/// Route '/staff/year-end' — the full checklist.
class YearEndScreen extends ConsumerStatefulWidget {
  const YearEndScreen({super.key});
  @override
  ConsumerState<YearEndScreen> createState() => _YearEndScreenState();
}

class _YearEndScreenState extends ConsumerState<YearEndScreen> {
  final busy = <String>{};

  Future<void> _tick(String id, bool on) async {
    setState(() => busy.add(id));
    try {
      await db.rpc('year_end_tick', params: {'p_item': id, 'p_done': on});
      ref.invalidate(yearEndProvider);
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e');
    }
    if (mounted) setState(() => busy.remove(id));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value;
    final cs = Theme.of(context).colorScheme;
    if (s == null || !(s.hasRole('it_admin') || s.hasRole('principal'))) {
      return const StaffPage(title: 'Year-end checklist', body: Panel(child: Text('This checklist is for IT and the Principal.')));
    }
    final data = ref.watch(yearEndProvider);
    return StaffPage(
      title: 'Year-end checklist',
      subtitle: 'Getting the app ready for the new school year. Items tick themselves when the app can see they are done.',
      actions: [OutlinedButton.icon(onPressed: () => ref.invalidate(yearEndProvider), icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Check again'))],
      body: data.when(
        loading: () => const Padding(padding: EdgeInsets.all(32), child: GoldLoading()),
        error: (e, _) => Panel(child: Text('Could not load: $e')),
        data: (d) {
          if (d == null) return Panel(child: Text('The checklist is not ready yet — the database step of this update has not been run.', style: TextStyle(color: cs.onSurfaceVariant)));
          final items = _items(d);
          Widget part(int n, String title) {
            final list = items.where((i) => i['part'] == n).toList();
            final open = list.where((i) => i['done'] != true).length;
            return Panel(title: title, trailing: Pill(open == 0 ? 'All done' : '$open to do', fg: open == 0 ? Brand.green : Brand.amber, bg: open == 0 ? Brand.greenTint : Brand.amberTint),
                child: Column(children: [for (final it in list) _row(it, cs)]));
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (d['in_window'] != true) const Padding(padding: EdgeInsets.only(bottom: 14), child: NoteBox('This checklist shows on your first page from 15 February to 30 June. You can look at it any time here.')),
            if (d['all_done'] == true) const Padding(padding: EdgeInsets.only(bottom: 14), child: NoteBox('Everything is done. The school is ready for the new year.', icon: Icons.verified_rounded, iconColor: Brand.green)),
            part(1, 'By ${DateFormat('d MMMM').format(DateTime.parse(d['part1_by']))}'),
            part(2, 'By ${DateFormat('d MMMM').format(DateTime.parse(d['part2_by']))}'),
            Text('Ticks are saved for the whole school, so IT and the Principal see the same list.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ]);
        },
      ),
    );
  }

  Widget _row(Map<String, dynamic> it, ColorScheme cs) {
    final id = '${it['id']}';
    final done = it['done'] == true;
    final autoDone = it['auto'] == true;
    final manual = it['auto'] == null;
    final ticked = it['ticked'] is Map ? Map<String, dynamic>.from(it['ticked']) : null;
    final route = it['route'] as String?;
    final note = autoDone ? 'Done — the app can see it' : ticked != null ? 'Ticked by ${ticked['by'] ?? 'staff'}' : manual ? 'Tick when done' : 'Ticks itself when done';
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: route == null ? null : () => context.go(route),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: done ? context.tone(Brand.green) : cs.outline, size: 24)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${it['title']}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: done ? cs.onSurfaceVariant : cs.onSurface)),
          if (!done && (it['hint'] ?? '').toString().isNotEmpty) Text('${it['hint']}', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          Text(note, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: done ? context.tone(Brand.green) : cs.onSurfaceVariant)),
        ])),
        // one tick box: for hand-ticked items, and as a way to mark an automatic item done when the school does it differently
        if (!autoDone) busy.contains(id)
            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
            : Checkbox(value: ticked != null, onChanged: (v) => _tick(id, v ?? false)),
      ])),
    ));
  }
}
