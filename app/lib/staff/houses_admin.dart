import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/data3.dart' show appSettingsProvider, featureOn, yearLabelProvider;
import '../screens/houses_screen.dart';
import '../widgets/common.dart';
import '../widgets/hub_tabs.dart';
import '../widgets/royal_extras.dart' show GoldLoading;
import 'school_settings.dart' show saveSettings;
import 'staff_shell.dart';

/// Staff: the same flags board, and (for the people allowed) a simple "Add points" panel and the recent entries.
String _msg(Object e) => e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');

final houseCanAddProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.cacheFor();
  final s = ref.watch(sessionProvider).value;
  if (s == null || !s.isStaff) return false;
  return (await db.rpc('house_can_add')) == true;
});

final houseEntriesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  final rows = await db.from('house_point').select('id,house,points,reason,created_at,by:added_by(display_name)').order('created_at', ascending: false).limit(40);
  return List<Map<String, dynamic>>.from(rows);
});

final _activeStaffProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await db.from('staff').select('id,display_name').eq('active', true).order('display_name');
  return List<Map<String, dynamic>>.from(rows);
});

class StaffHousesScreen extends ConsumerWidget {
  const StaffHousesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).value;
    final s = ref.watch(sessionProvider).value;
    final totals = ref.watch(houseTotalsProvider);
    final canAdd = ref.watch(houseCanAddProvider).value ?? false;
    final year = ref.watch(yearLabelProvider).value;
    final boss = s != null && (s.hasRole('it_admin') || s.hasRole('principal'));
    void refresh() { ref.invalidate(houseTotalsProvider); ref.invalidate(houseEntriesProvider); }
    final board = totals.when(
      loading: () => const GoldLoading(),
      error: (e, _) => NoteBox('Could not load the house points. ${_msg(e)}'),
      data: (t) => HouseFlagsBoard(totals: t, caption: year == null ? 'House points' : 'House points · $year'),
    );
    return StaffPage(
      title: 'Houses',
      subtitle: 'Athena, Ares, Artemis and Apollo — this school year’s points.',
      hub: Hub.staffHonours,
      body: !featureOn(settings, 'houses')
          ? const NoteBox('House points are switched off in School settings.')
          : LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 860;
              final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (canAdd) _AddPointsPanel(onAdded: refresh)
                else const Panel(child: NoteBox('House points are added by the house in-charges, coordinators, the office and the Principal.')),
                if (boss) const _InchargePanel(),
              ]);
              final entries = _EntriesPanel(canDelete: canAdd, refresh: refresh);
              if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [board, const SizedBox(height: 14), side, entries]);
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [board, const SizedBox(height: 14), entries])),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: side),
              ]);
            }),
    );
  }
}

class _AddPointsPanel extends ConsumerStatefulWidget {
  final VoidCallback onAdded;
  const _AddPointsPanel({required this.onAdded});
  @override
  ConsumerState<_AddPointsPanel> createState() => _AddPointsPanelState();
}

class _AddPointsPanelState extends ConsumerState<_AddPointsPanel> {
  String? house;
  final points = TextEditingController(), reason = TextEditingController();
  bool busy = false;

  @override
  void dispose() { points.dispose(); reason.dispose(); super.dispose(); }

  Future<void> _add() async {
    final p = int.tryParse(points.text.trim());
    if (house == null) { toast(context, 'Please choose a house.'); return; }
    if (p == null || p <= 0 || p > 500) { toast(context, 'Please type the points (1 to 500).'); return; }
    if (reason.text.trim().isEmpty) { toast(context, 'Please write a short reason.'); return; }
    setState(() => busy = true);
    try {
      await db.rpc('house_points_add', params: {'p_house': house, 'p_points': p, 'p_reason': reason.text.trim()});
      if (!mounted) return;
      toast(context, 'Added $p points to $house ✓');
      setState(() { points.clear(); reason.clear(); house = null; });
      widget.onAdded();
    } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Panel(title: 'Add points', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.6, children: [
        for (final h in houseNames) Builder(builder: (_) {
          final on = house == h;
          final c = houseColors[h]!;
          final fg = h == 'Athena' ? const Color(0xFF2A1F00) : Colors.white;
          return AnimatedScale(scale: on ? 1.0 : (house == null ? 1.0 : .96), duration: const Duration(milliseconds: 160), child: Material(
            color: house == null || on ? c : c.withValues(alpha: .45), borderRadius: BorderRadius.circular(16),
            child: InkWell(borderRadius: BorderRadius.circular(16), onTap: busy ? null : () => setState(() => house = h), child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: on ? cs.onSurface : Colors.transparent, width: 3)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (on) Padding(padding: const EdgeInsets.only(right: 6), child: Icon(Icons.check_circle_rounded, color: fg, size: 20)),
                Text(h, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 17)),
              ]),
            )),
          ));
        }),
      ]),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: TextField(controller: points, enabled: !busy, keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: const InputDecoration(labelText: 'Points', hintText: '10'))),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: reason, enabled: !busy, maxLength: 120, textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Reason', hintText: 'e.g. Sports Day relay — 1st', counterText: ''),
            onSubmitted: (_) => _add())),
      ]),
      const SizedBox(height: 12),
      Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: busy ? null : _add,
          icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.add_rounded),
          label: Text(house == null ? 'Add' : 'Add to $house'))),
    ]));
  }
}

class _EntriesPanel extends ConsumerWidget {
  final bool canDelete; final VoidCallback refresh;
  const _EntriesPanel({required this.canDelete, required this.refresh});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final rows = ref.watch(houseEntriesProvider);
    return Panel(title: 'Recent points', child: rows.when(
      loading: () => const GoldLoading(lines: 2),
      error: (e, _) => Text(_msg(e)),
      data: (list) => list.isEmpty
          ? Text('No points added yet this year.', style: TextStyle(color: cs.onSurfaceVariant))
          : Column(children: [
              for (final (i, r) in list.indexed) ...[
                if (i > 0) Divider(height: 14, color: cs.outline.withValues(alpha: .6)),
                Row(children: [
                  Container(width: 10, height: 34, decoration: BoxDecoration(color: houseColors[r['house']] ?? Colors.grey, borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${r['house']}  ', style: TextStyle(fontWeight: FontWeight.w900, color: houseTextColor(context, r['house'] as String))),
                      TextSpan(text: '${(r['points'] as num) > 0 ? '+' : ''}${r['points']}', style: const TextStyle(fontWeight: FontWeight.w900)),
                      TextSpan(text: '  ·  ${r['reason'] ?? ''}'),
                    ]), maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text([r['by']?['display_name'], _when(r['created_at'] as String?)].whereType<String>().join(' · '),
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ])),
                  if (canDelete) IconButton(tooltip: 'Delete', icon: Icon(Icons.delete_outline_rounded, color: cs.onSurfaceVariant), onPressed: () async {
                    try {
                      await db.rpc('house_points_delete', params: {'p_id': r['id']});
                      refresh();
                      if (context.mounted) showUndo(context, 'House points', refresh);
                    } catch (e) { if (context.mounted) toast(context, _msg(e)); }
                  }),
                ]),
              ],
            ]),
    ));
  }

  static String? _when(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    return d == null ? null : DateFormat('d MMM, h:mm a').format(d);
  }
}

/// IT / Principal: which other teachers (e.g. the PE teacher, house in-charges) may add points.
class _InchargePanel extends ConsumerWidget {
  const _InchargePanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final ids = _ids(ref.watch(appSettingsProvider).value?['house_incharge_staff_ids']);
    final staff = ref.watch(_activeStaffProvider).value ?? const [];
    final names = [for (final st in staff) if (ids.contains(st['id'])) st['display_name'] as String];
    return Panel(title: 'House in-charges', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Coordinators, the office and the Principal can always add points. You can also let a few teachers add them (for example the PE teacher).',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.45)),
      const SizedBox(height: 10),
      Text(names.isEmpty ? 'No teachers chosen yet.' : names.join(', '), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(icon: const Icon(Icons.edit_rounded, size: 18), label: const Text('Choose teachers'),
          onPressed: () => showDialog(context: context, builder: (_) => _PickInchargesDialog(chosen: ids.toSet())))),
    ]));
  }
}

List<String> _ids(String? v) => (v ?? '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

class _PickInchargesDialog extends ConsumerStatefulWidget {
  final Set<String> chosen;
  const _PickInchargesDialog({required this.chosen});
  @override
  ConsumerState<_PickInchargesDialog> createState() => _PickInchargesDialogState();
}

class _PickInchargesDialogState extends ConsumerState<_PickInchargesDialog> {
  late final Set<String> on = {...widget.chosen};
  String q = '';
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(_activeStaffProvider);
    return AlertDialog(
      title: const Text('Who else can add house points?'),
      content: SizedBox(width: 440, height: 420, child: Column(children: [
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search a name'), onChanged: (v) => setState(() => q = v.trim().toLowerCase())),
        const SizedBox(height: 8),
        Expanded(child: staff.when(
          loading: () => const GoldLoading(),
          error: (e, _) => Text(_msg(e)),
          data: (list) => ListView(children: [
            for (final st in list) if (q.isEmpty || (st['display_name'] as String).toLowerCase().contains(q))
              CheckboxListTile(dense: true, value: on.contains(st['id']), title: Text(st['display_name'] as String),
                  onChanged: (v) => setState(() => v == true ? on.add(st['id'] as String) : on.remove(st['id']))),
          ]),
        )),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : () async {
          setState(() => busy = true);
          try {
            await saveSettings(ref, {'house_incharge_staff_ids': on.join(',')});
            ref.invalidate(houseCanAddProvider);
            if (context.mounted) { Navigator.pop(context); toast(context, 'Saved ✓'); }
          } catch (e) { if (context.mounted) toast(context, _msg(e)); setState(() => busy = false); }
        }, child: const Text('Save')),
      ],
    );
  }
}
