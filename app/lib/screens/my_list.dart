import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/royal_motion.dart' show ConfettiBurst;
import '../widgets/r_refresh.dart';

/// "My list" — the family's homework checklist, the second tab of the Diary. One fixed rule, nothing to set:
///  * homework and projects with a due date, and anything to hand in, appear by themselves (from the class diary);
///  * the family can add their own items (a line and, if they like, a date);
///  * ticked items stay until the end of the day, then disappear; overdue items show in red;
///  * everything goes away 30 days after its date. Only this family can see the list.

/// Which Diary tab to show: 0 = Today, 1 = My list (Home's "See all" opens My list).
final diaryTabProvider = StateProvider<int>((ref) => 0);

class MyListItem {
  final String key, title, kind; final String? diaryId, itemId, subject; final DateTime? date; final bool done, mine;
  const MyListItem({required this.key, required this.title, required this.kind, this.diaryId, this.itemId, this.subject, this.date, required this.done, required this.mine});
  factory MyListItem.fromJson(Map<String, dynamic> j) => MyListItem(key: j['key'], title: j['title'] ?? '', kind: j['kind'] ?? '', diaryId: j['diary_id'], itemId: j['item_id'],
      subject: j['subject'], date: j['date'] == null ? null : DateTime.parse(j['date']), done: j['done'] == true, mine: j['mine'] == true);
  MyListItem withDone(bool d) => MyListItem(key: key, title: title, kind: kind, diaryId: diaryId, itemId: itemId, subject: subject, date: date, done: d, mine: mine);
  bool overdue(DateTime today) => !done && date != null && date!.isBefore(today);
}

DateTime _today() { final n = DateTime.now(); return DateTime(n.year, n.month, n.day); }

final myListProvider = FutureProvider.autoDispose<List<MyListItem>>((ref) async {
  ref.cacheFor();
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return [];
  final r = await db.rpc('my_list', params: {'p_student': s.id});
  return [for (final x in (r as List? ?? const [])) MyListItem.fromJson(Map<String, dynamic>.from(x as Map))];
});

String _when(MyListItem i, DateTime today) {
  if (i.date == null) return '';
  final d = i.date!.difference(today).inDays;
  if (i.overdue(today)) return 'Overdue · was due ${DateFormat('EEE d MMM').format(i.date!)}';
  if (d == 0) return 'Due today';
  if (d == 1) return 'Due tomorrow';
  return 'Due ${DateFormat('EEE d MMM').format(i.date!)}';
}

/// The full list (Diary → My list).
class MyListView extends ConsumerStatefulWidget {
  const MyListView({super.key});
  @override
  ConsumerState<MyListView> createState() => _MyListViewState();
}

class _MyListViewState extends ConsumerState<MyListView> {
  final Map<String, bool> _local = {};   // ticks shown at once, before the database answers
  final Set<String> _gone = {};          // own items swiped away (hidden at once)
  int _burst = 0; bool _toast = false; Timer? _toastTimer;

  @override
  void dispose() { _toastTimer?.cancel(); super.dispose(); }

  void _say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  Future<void> _tick(List<MyListItem> all, MyListItem it, bool done) async {
    if (viewOnlyMode) { _say('View only: ticks are not saved.'); return; }
    final st = ref.read(sessionProvider).value?.active;
    if (st == null) return;
    setState(() => _local[it.key] = done);
    final open = all.where((x) => !(_local[x.key] ?? x.done)).length;
    if (done && open == 0) _celebrate();
    try {
      await db.rpc('my_list_tick', params: {'p_student': st.id, 'p_diary': it.diaryId, 'p_item': it.itemId, 'p_done': done});
    } catch (e) {
      if (!mounted) return;
      setState(() => _local.remove(it.key));
      _say('Could not save the tick. Please try again.');
    }
  }

  void _celebrate() {
    _toastTimer?.cancel();
    setState(() { _burst++; _toast = true; });
    _toastTimer = Timer(const Duration(milliseconds: 2800), () { if (mounted) setState(() => _toast = false); });
  }

  Future<void> _add() async {
    if (viewOnlyMode) { _say('View only: changes are not saved.'); return; }
    final st = ref.read(sessionProvider).value?.active;
    if (st == null) return;
    final got = await showDialog<(String, DateTime?)>(context: context, builder: (_) => const _AddDialog());
    if (got == null) return;
    try {
      await db.rpc('my_list_add', params: {'p_student': st.id, 'p_title': got.$1, 'p_due': got.$2 == null ? null : DateFormat('yyyy-MM-dd').format(got.$2!)});
      _local.clear();
      ref.invalidate(myListProvider);
    } catch (e) {
      if (mounted) _say('Could not add it. Please try again.');
    }
  }

  Future<void> _remove(MyListItem it) async {
    final st = ref.read(sessionProvider).value?.active;
    if (st == null || it.itemId == null) return;
    setState(() => _gone.add(it.key));
    try {
      await db.rpc('my_list_remove', params: {'p_student': st.id, 'p_item': it.itemId});
      if (mounted) _say('Removed “${it.title}”.');
    } catch (e) {
      if (mounted) _say('Could not remove it.');
    }
    _local.clear();
    ref.invalidate(myListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(myListProvider);
    final cs = Theme.of(context).colorScheme;
    final today = _today();
    final addBtn = TextButton.icon(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('Add my own'));
    final body = list.when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
      error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text('Could not load the list. Pull down to try again.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)))),
      data: (rows) {
        final items = [for (final r in rows) if (!_gone.contains(r.key)) r.withDone(_local[r.key] ?? r.done)];
        if (items.isEmpty) {
          return ListView(padding: const EdgeInsets.all(20), children: [
            const EmptyState(kind: EmptyKind.homework, title: 'Nothing on your list', line: 'Homework with a due date appears here by itself. You can add your own things to do too.'),
            Center(child: addBtn),
          ]);
        }
        final open = items.where((i) => !i.done).length;
        return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 40), children: [
          Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(open == 0 ? 'All done ✨' : '$open to do', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 14), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Column(children: [
            for (final (n, it) in items.indexed) _row(items, it, today, cs, last: n == items.length - 1),
          ])),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: addBtn),
        ]);
      });
    return Stack(children: [
      RRefresh(onRefresh: () async { _local.clear(); ref.invalidate(myListProvider); await ref.read(myListProvider.future).catchError((_) => <MyListItem>[]); }, child: body),
      if (_burst > 0) Positioned.fill(child: IgnorePointer(child: ConfettiBurst(key: ValueKey(_burst), count: 60, origin: const Alignment(0, -.1), ms: 2000))),
      Positioned(left: 0, right: 0, bottom: 28, child: IgnorePointer(child: Center(child: AnimatedSlide(
        offset: _toast ? Offset.zero : const Offset(0, 1.2), duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic,
        child: AnimatedOpacity(opacity: _toast ? 1 : 0, duration: const Duration(milliseconds: 350), child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(color: Brand.ink, borderRadius: BorderRadius.circular(99), border: Border.all(color: Brand.gold.withValues(alpha: .6))),
          child: const Text('All done for today ✨', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)))))))),
    ]);
  }

  Widget _row(List<MyListItem> all, MyListItem it, DateTime today, ColorScheme cs, {required bool last}) {
    final when = _when(it, today);
    final red = it.overdue(today);
    final sub = [if (it.subject != null) it.subject!, if (it.mine) 'My item', if (when.isNotEmpty) when].join(' · ');
    final row = InkWell(onTap: () => _tick(all, it, !it.done), child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: cs.outline.withValues(alpha: .6)))),
      child: Row(children: [
        _GoldBox(done: it.done),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedDefaultTextStyle(duration: const Duration(milliseconds: 250),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: it.done ? cs.onSurfaceVariant.withValues(alpha: .7) : (red ? context.tone(Brand.crimson) : cs.onSurface),
                decoration: it.done ? TextDecoration.lineThrough : null),
            child: Text(it.title)),
          if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 12, color: red ? context.tone(Brand.crimson) : cs.onSurfaceVariant, fontWeight: red ? FontWeight.w700 : FontWeight.w500)),
        ])),
      ])));
    if (!it.mine) return row;
    return Dismissible(key: ValueKey('mine-${it.key}'), direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 12), child: Icon(Icons.delete_outline_rounded, color: context.tone(Brand.crimson))),
      onDismissed: (_) => _remove(it), child: row);
  }
}

class _GoldBox extends StatelessWidget {
  final bool done;
  const _GoldBox({required this.done});
  @override
  Widget build(BuildContext context) => AnimatedContainer(duration: const Duration(milliseconds: 250), width: 22, height: 22, alignment: Alignment.center,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), border: Border.all(color: done ? const Color(0xFF9C7A2E) : Brand.gold, width: 2),
        gradient: done ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.gold2, Color(0xFF9C7A2E)]) : null),
    child: done ? const Icon(Icons.check_rounded, size: 15, color: Colors.white) : null);
}

class _AddDialog extends StatefulWidget {
  const _AddDialog();
  @override
  State<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends State<_AddDialog> {
  final _t = TextEditingController(); DateTime? _due;
  @override
  void dispose() { _t.dispose(); super.dispose(); }
  void _ok() { final v = _t.text.trim(); if (v.isNotEmpty) Navigator.pop(context, (v, _due)); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add to my list'),
    content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: _t, autofocus: true, maxLength: 200, textCapitalization: TextCapitalization.sentences, onSubmitted: (_) => _ok(),
          decoration: const InputDecoration(hintText: 'e.g. Revise the 7 times table')),
      OutlinedButton.icon(icon: const Icon(Icons.event_rounded, size: 18),
        label: Text(_due == null ? 'Add a date (if you like)' : DateFormat('EEE d MMM').format(_due!)),
        onPressed: () async {
          final t = _today();
          final d = await showDatePicker(context: context, firstDate: t, lastDate: t.add(const Duration(days: 180)), initialDate: _due ?? t.add(const Duration(days: 1)));
          if (d != null) setState(() => _due = d);
        }),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _ok, child: const Text('Add'))],
  );
}

/// For the family Home ("Your day" card): the first four items, tickable right here; "See all" opens Diary → My list.
/// Ticked items cross off and stay until the end of the day (same rule as the full list). Hidden when the list is empty.
class MyListHomeColumn extends ConsumerStatefulWidget {
  const MyListHomeColumn({super.key});
  @override
  ConsumerState<MyListHomeColumn> createState() => _MyListHomeColumnState();
}

class _MyListHomeColumnState extends ConsumerState<MyListHomeColumn> {
  final Map<String, bool> _local = {};

  Future<void> _tick(MyListItem it, bool done) async {
    if (viewOnlyMode) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('View only: ticks are not saved.'))); return; }
    final st = ref.read(sessionProvider).value?.active;
    if (st == null) return;
    setState(() => _local[it.key] = done);
    try {
      await db.rpc('my_list_tick', params: {'p_student': st.id, 'p_diary': it.diaryId, 'p_item': it.itemId, 'p_done': done});
    } catch (_) {
      if (!mounted) return;
      setState(() => _local.remove(it.key));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the tick. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = [for (final i in ref.watch(myListProvider).value ?? const <MyListItem>[]) i.withDone(_local[i.key] ?? i.done)];
    if (all.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final today = _today();
    // open items first (earliest date first), then the ones ticked today
    all.sort((a, b) => a.done != b.done ? (a.done ? 1 : -1) : (a.date ?? DateTime(9999)).compareTo(b.date ?? DateTime(9999)));
    final open = all.where((i) => !i.done).length;
    void seeAll() { ref.read(diaryTabProvider.notifier).state = 1; context.go('/diary'); }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: Text(open == 0 ? 'MY LIST' : 'MY LIST · $open TO DO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: dark ? Brand.gold2 : const Color(0xFFA8822F)))),
        InkWell(onTap: seeAll, borderRadius: BorderRadius.circular(8), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text('See all', style: TextStyle(color: context.tone(Brand.crimson), fontWeight: FontWeight.w800, fontSize: 12.5)))),
      ]),
      if (open == 0) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('All done ✨', style: TextStyle(fontWeight: FontWeight.w800, color: context.tone(Brand.green)))),
      for (final it in all.take(4)) InkWell(onTap: () => _tick(it, !it.done), borderRadius: BorderRadius.circular(10), child: Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [
        _GoldBox(done: it.done), const SizedBox(width: 12),
        Expanded(child: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5,
            color: it.done ? cs.onSurfaceVariant : cs.onSurface, decoration: it.done ? TextDecoration.lineThrough : null))),
        if (!it.done && it.date != null) Padding(padding: const EdgeInsets.only(left: 8), child: Text(it.overdue(today) ? 'Overdue' : _when(it, today).replaceFirst('Due ', ''),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: it.overdue(today) ? context.tone(Brand.crimson) : cs.onSurfaceVariant))),
      ]))),
    ]);
  }
}
