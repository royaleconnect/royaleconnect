import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../auth/session.dart';
import '../core/bus_map.dart';
import '../core/config.dart';
import '../core/data2.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_extras.dart' show GoldLoading;
import 'staff_shell.dart';

/// "Check pins" (transport in-charge / office / IT): each child's home pickup point, bus by bus.
/// Green = OK, amber = please check (the address was vague), none = no pin yet.
/// Tap a child, then tap the map where the home really is → saved. "Place pins from addresses" asks Google Maps once.
/// Families never see other families' pins; this page is only for transport / office / IT (the server checks).
class BusPinsPage extends ConsumerStatefulWidget {
  const BusPinsPage({super.key});
  @override
  ConsumerState<BusPinsPage> createState() => _BusPinsPageState();
}

const _amberPin = Color(0xFFE0A100);

class _BusPinsPageState extends ConsumerState<BusPinsPage> {
  String? routeId, selected;
  bool placing = false, saving = false;

  String _initials(String n) {
    final p = n.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    return p.isEmpty ? '?' : (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
  }

  Future<void> _placeAll(String rid) async {
    setState(() => placing = true);
    try {
      final s = ref.read(sessionProvider).value!;
      final r = await http.post(Uri.parse('${AppConfig.functionsUrl}/geocode'),
          headers: {'content-type': 'application/json', 'apikey': AppConfig.supabaseAnonKey, 'authorization': 'Bearer ${s.token}'},
          body: jsonEncode({'route_id': rid}));
      Map<String, dynamic> j;
      try { j = jsonDecode(r.body) as Map<String, dynamic>; } catch (_) { j = {}; }
      if (!mounted) return;
      if (r.statusCode >= 400 || j['ok'] != true) {
        // our own function answers in plain English ("Map key not set yet", "Not allowed." …)
        final m = j['error'] as String?;
        toast(context, m != null && m.length < 160 ? m : 'Something went wrong. Please try again in a minute.');
      } else {
        final placed = j['placed'] ?? 0, vague = j['vague'] ?? 0, failed = j['failed'] ?? 0, left = j['left'] ?? 0, none = j['no_address'] ?? 0;
        toast(context, [
          placed == 0 ? 'No new pins to place' : '$placed pins placed',
          if (vague > 0) '$vague to check (amber)',
          if (failed > 0) '$failed addresses not found',
          if (none > 0) '$none without an address',
          if (left > 0) 'press again for the other $left',
        ].join(' · '));
        ref.invalidate(pinsForRouteProvider(rid));
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
    if (mounted) setState(() => placing = false);
  }

  Future<void> _put(String rid, Map<String, dynamic> kid, double lat, double lng) async {
    setState(() => saving = true);
    try {
      await savePin(kid['student_id'] as String, lat, lng);
      ref.invalidate(pinsForRouteProvider(rid));
      if (mounted) toast(context, '${kid['name']} — pin saved ✓');
      selected = null;
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final routes = ref.watch(busRoutesProvider);
    return StaffPage(
      title: 'Check pins',
      subtitle: 'Each child’s home pickup point, bus by bus. Amber means the address was vague — tap the child, then tap the right spot on the map.',
      body: routes.when(
        loading: () => const SizedBox(height: 240, child: GoldLoading()),
        error: (e, _) => NoteBox(friendlyError(e)),
        data: (rs) {
          if (rs.isEmpty) return const NoteBox('No buses yet. Add a route on the Transport page first.');
          final rid = routeId ?? rs.first['id'] as String;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in rs) ChoiceChip(
                label: Text('Bus ${RegExp(r'\d+').firstMatch('${r['name']}')?.group(0) ?? r['name']}'),
                selected: r['id'] == rid, showCheckmark: false, selectedColor: Brand.crimson,
                labelStyle: TextStyle(fontWeight: FontWeight.w800, color: r['id'] == rid ? Colors.white : null),
                onSelected: (_) => setState(() { routeId = r['id'] as String; selected = null; }),
              ),
            ]),
            const SizedBox(height: 14),
            _route(rid, cs),
          ]);
        },
      ),
    );
  }

  Widget _route(String rid, ColorScheme cs) {
    final kids = ref.watch(pinsForRouteProvider(rid));
    return kids.when(
      loading: () => const SizedBox(height: 240, child: GoldLoading()),
      error: (e, _) => NoteBox(friendlyError(e)),
      data: (list) {
        final sel = list.where((k) => k['student_id'] == selected).firstOrNull;
        final toCheck = list.where((k) => k['lat'] == null || k['quality'] == 'check').length;
        final narrow = isNarrow(context);
        final map = Panel(padding: EdgeInsets.zero, child: SizedBox(height: narrow ? 340 : 520, child: Stack(children: [
          Positioned.fill(child: BusMap(
            key: ValueKey(rid), stops: const [],
            pins: [for (final k in list) if (k['lat'] != null) MapPin(
              lat: (k['lat'] as num).toDouble(), lng: (k['lng'] as num).toDouble(),
              label: '${k['name']}'.split(' ').first,
              color: k['quality'] == 'check' ? _amberPin : Brand.green, selected: k['student_id'] == selected)],
            onTap: saving ? null : (p) {
              if (sel == null) { toast(context, 'First tap a child in the list'); return; }
              _put(rid, sel, p.latitude, p.longitude);
            },
          )),
          if (sel != null) Positioned(left: 10, right: 70, top: 10, child: Material(color: Brand.crimsonDeep, borderRadius: BorderRadius.circular(12), child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('Tap the map where ${sel['name']}’s home is', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))))),
        ])));
        final listPanel = Panel(
          title: '${list.length} children',
          trailing: FilledButton.tonalIcon(onPressed: placing ? null : () => _placeAll(rid),
              icon: placing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: const Text('Place pins from addresses')),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (list.isEmpty) Text('No children on this bus yet.', style: TextStyle(color: cs.onSurfaceVariant)),
            for (final k in list) _row(k, cs),
            const SizedBox(height: 8),
            Text(list.isEmpty ? '' : toCheck == 0 ? 'All pins checked ✓' : '$toCheck ${toCheck == 1 ? 'pin' : 'pins'} to check',
                style: TextStyle(fontWeight: FontWeight.w700, color: context.tone(toCheck == 0 ? Brand.green : Brand.amber))),
          ]),
        );
        return narrow
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [map, Text('Tap a child, then tap the map where the home really is.', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)), const SizedBox(height: 8), listPanel])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: map), const SizedBox(width: 14), Expanded(flex: 2, child: listPanel)]);
      },
    );
  }

  Widget _row(Map<String, dynamic> k, ColorScheme cs) {
    final has = k['lat'] != null, ok = has && k['quality'] != 'check', on = k['student_id'] == selected;
    final (label, fg, bg) = !has ? ('No pin', Brand.muted, Brand.surface2) : ok ? ('OK', Brand.green, Brand.greenTint) : ('Check', Brand.amber, Brand.amberTint);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => selected = on ? null : k['student_id'] as String),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(color: on ? Brand.amberTint.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? .2 : 1) : null, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Avatar(_initials('${k['name']}'), size: 38, bg: bg, fg: fg),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${k['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${k['address'] ?? 'No address in the records'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ])),
          Pill(label, fg: fg, bg: bg),
        ]),
      ),
    );
  }
}
