import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data2.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'family_screens.dart' show callNumber;

Widget _loading() => const Center(child: CircularProgressIndicator());

/// Parent / student side — only reachable when the student has a transport enrolment.
class BusScreen extends ConsumerStatefulWidget {
  const BusScreen({super.key});
  @override
  ConsumerState<BusScreen> createState() => _BusScreenState();
}
class _BusScreenState extends ConsumerState<BusScreen> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final route = ref.watch(routeDetailProvider);
    final trip = ref.watch(liveTripProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(20, 14, 20, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(route.value?['name'] ?? 'Bus', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            Text('${route.value?['bus_reg_no'] ?? ''} · Stop: ${route.value?['my_stop']?['name'] ?? ''}', style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 13)),
          ])),
          _livePill(trip.value),
        ]),
        const SizedBox(height: 12),
        Row(children: [for (final (i, l) in ['Stops', 'Live map', 'Alerts'].indexed) Expanded(child: GestureDetector(onTap: () => setState(() => tab = i), child: Container(margin: const EdgeInsets.only(right: 8), height: 36, alignment: Alignment.center,
          decoration: BoxDecoration(color: tab == i ? Colors.white : Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)), child: Text(l, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: tab == i ? Brand.crimsonDeep : Colors.white)))))]),
      ])),
      Expanded(child: route.when(loading: _loading, error: (e, _) => Center(child: Text('$e')), data: (r) {
        if (r == null) return const Center(child: Text('No bus route on record.'));
        final stops = List<Map<String, dynamic>>.from(r['route_stop'] ?? [])..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
        return switch (tab) { 0 => _stops(r, stops, trip.value, cs), 1 => _map(r, stops, trip.value, cs), _ => _alerts(cs) };
      })),
    ]));
  }

  Widget _livePill(Map<String, dynamic>? t) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: t == null ? Colors.white.withValues(alpha: .14) : Brand.green, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: t == null ? Colors.white54 : Colors.white, shape: BoxShape.circle)), const SizedBox(width: 6),
        Text(t == null ? 'Not running' : '${t['kind'] == 'morning' ? 'Morning' : 'Afternoon'} trip live', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))]));

  Widget _stops(Map<String, dynamic> r, List<Map<String, dynamic>> stops, Map<String, dynamic>? t, ColorScheme cs) {
    final morning = t == null ? DateTime.now().hour < 12 : t['kind'] == 'morning';
    final next = t?['next_stop_seq'] as int?;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Row(children: [
        Expanded(child: Text(t == null ? 'Next ${morning ? 'morning' : 'afternoon'} trip starts ${(morning ? r['morning_start'] : r['afternoon_start'])?.toString().substring(0, 5) ?? ''}' : 'Bus is ${next == null ? 'on the way' : 'heading to stop $next'} · updated ${t['last_fix_at'] == null ? '—' : DateFormat('h:mm a').format(DateTime.parse(t['last_fix_at']).toLocal())}', style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4))),
        IconButton.filledTonal(onPressed: () => callNumber(r['driver']?['phone']), icon: const Icon(Icons.call_rounded), tooltip: 'Call driver'),
        IconButton.filledTonal(onPressed: () => callNumber(r['conductor']?['phone']), icon: const Icon(Icons.support_agent_rounded), tooltip: 'Call conductor'),
      ])),
      const SizedBox(height: 16),
      for (final (i, s) in stops.indexed) Builder(builder: (_) {
        final mine = s['id'] == r['my_stop']?['id']; final done = next != null && (s['seq'] as int) < next; final current = next != null && s['seq'] == next;
        return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 54, child: Text((morning ? s['morning_eta'] : s['afternoon_eta'])?.toString().substring(0, 5) ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant))),
          Column(children: [
            Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, color: current ? Brand.green : done ? Brand.muted : mine ? Brand.crimson : cs.surface, border: Border.all(color: mine ? Brand.crimson : Brand.muted, width: 2))),
            if (i < stops.length - 1) Expanded(child: Container(width: 2, color: done ? Brand.muted : cs.outline)),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['name'], style: TextStyle(fontWeight: mine ? FontWeight.w800 : FontWeight.w600, color: done ? cs.onSurfaceVariant : cs.onSurface)),
            if (mine) Text('Your stop', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: context.tone(Brand.crimsonDeep))),
            if (current) Text('Bus approaching', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: context.tone(Brand.green))),
          ]))),
        ]));
      }),
    ]);
  }

  /// Lightweight map: stops plotted on their own extent, bus marker from the last GPS fix. No map tiles, no API key.
  Widget _map(Map<String, dynamic> r, List<Map<String, dynamic>> stops, Map<String, dynamic>? t, ColorScheme cs) {
    if (stops.isEmpty) return const Center(child: Text('Stops not mapped yet.'));
    final lats = stops.map((s) => s['lat'] as double).toList(), lngs = stops.map((s) => s['lng'] as double).toList();
    if (t?['last_lat'] != null) { lats.add(t!['last_lat']); lngs.add(t['last_lng']); }
    final minLat = lats.reduce(math.min), maxLat = lats.reduce(math.max), minLng = lngs.reduce(math.min), maxLng = lngs.reduce(math.max);
    Offset pos(double lat, double lng, Size sz) => Offset(((lng - minLng) / math.max(maxLng - minLng, 1e-6)) * (sz.width - 48) + 24, (1 - (lat - minLat) / math.max(maxLat - minLat, 1e-6)) * (sz.height - 48) + 24);
    return Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      Expanded(child: Container(decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(22)), clipBehavior: Clip.antiAlias, child: LayoutBuilder(builder: (_, c) {
        final sz = Size(c.maxWidth, c.maxHeight);
        return Stack(children: [
          CustomPaint(size: sz, painter: _RoutePainter([for (final s in stops) pos(s['lat'], s['lng'], sz)], cs.outline)),
          for (final s in stops) Positioned(left: pos(s['lat'], s['lng'], sz).dx - 7, top: pos(s['lat'], s['lng'], sz).dy - 7, child: Tooltip(message: s['name'], child: Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: s['id'] == r['my_stop']?['id'] ? Brand.crimson : cs.surface, border: Border.all(color: Brand.crimsonDeep, width: 2))))),
          if (t?['last_lat'] != null) Positioned(left: pos(t!['last_lat'], t['last_lng'], sz).dx - 16, top: pos(t['last_lat'], t['last_lng'], sz).dy - 16, child: Container(width: 32, height: 32, decoration: BoxDecoration(color: Brand.green, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Brand.green.withValues(alpha: .4), blurRadius: 12)]), child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 18))),
          Positioned(left: 12, bottom: 10, child: Text(t == null ? 'Bus is not on a trip right now' : 'Live · ${t['last_fix_at'] == null ? 'waiting for GPS' : DateFormat('h:mm:ss a').format(DateTime.parse(t['last_fix_at']).toLocal())}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
        ]);
      }))),
      const SizedBox(height: 12),
      const NoteBox('Position comes from the conductor\'s phone every 10 seconds while the trip is running. Street map tiles can be added later if the school wants them.'),
    ]));
  }

  Widget _alerts(ColorScheme cs) {
    final p = ref.watch(etaPrefProvider);
    return p.when(loading: _loading, error: (e, _) => Center(child: Text('$e')), data: (m) {
      final prefs = Map<String, dynamic>.from(m);
      Widget sw(String k, String t, String s) => SwitchListTile(value: prefs[k] == true, title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(s), onChanged: (v) async { prefs[k] = v; await saveEtaPref(prefs); ref.invalidate(etaPrefProvider); });
      return ListView(padding: const EdgeInsets.all(20), children: [Container(decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Column(children: [
        sw('trip_started', 'Trip started', 'When the bus leaves school / the first stop'),
        sw('two_stops', 'Two stops away', 'Time to come down'),
        sw('ten_min', '10 minutes away', 'Based on the live position'),
        sw('at_stop', 'Bus at your stop', ''),
        sw('trip_ended', 'Trip ended', 'Bus reached school / last stop'),
      ])), const SizedBox(height: 12), const NoteBox('Bus alerts always come through, even during quiet hours.')]);
    });
  }
}

class _RoutePainter extends CustomPainter {
  final List<Offset> pts; final Color color;
  _RoutePainter(this.pts, this.color);
  @override
  void paint(Canvas c, Size s) {
    if (pts.length < 2) return;
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final o in pts.skip(1)) { p.lineTo(o.dx, o.dy); }
    c.drawPath(p, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 4..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
  }
  @override
  bool shouldRepaint(covariant _RoutePainter o) => o.pts != pts;
}

// ---------------------------------------------------------------- crew (driver / conductor)
/// What a driver or conductor sees after OTP login: route, Start / End trip, nothing else.
/// While a trip runs, the phone sends a GPS fix every 10 s.
class DriverScreen extends ConsumerStatefulWidget {
  const DriverScreen({super.key});
  @override
  ConsumerState<DriverScreen> createState() => _DriverScreenState();
}
class _DriverScreenState extends ConsumerState<DriverScreen> {
  StreamSubscription<Position>? sub; String? tripId; int fixes = 0; String? status; bool busy = false;

  @override
  void dispose() { sub?.cancel(); super.dispose(); }

  Future<void> _start(String routeId, String kind) async {
    setState(() { busy = true; status = null; });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) { setState(() { status = 'Location permission is needed to share the bus position.'; busy = false; }); return; }
      final s = ref.read(sessionProvider).value!;
      tripId = await startTrip(routeId, kind, s.crew!['staff_id']);
      sub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15)).listen((p) async {
        try { await pushFix(tripId!, p.latitude, p.longitude, p.speed * 3.6, p.accuracy); if (mounted) setState(() => fixes++); } catch (_) {}
      });
      ref.invalidate(crewTripProvider);
    } catch (e) { status = 'Could not start: $e'; }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _end(String id) async {
    setState(() => busy = true);
    await sub?.cancel(); sub = null;
    try { await endTrip(id); tripId = null; fixes = 0; ref.invalidate(crewTripProvider); } catch (e) { status = 'Could not end: $e'; }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value; final route = ref.watch(crewRouteProvider); final trip = ref.watch(crewTripProvider);
    final cs = Theme.of(context).colorScheme; final crew = s?.crew ?? {};
    return Scaffold(body: Column(children: [
      BrandHeader(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Eyebrow('Bus crew', color: Colors.white), const Spacer(), IconButton(onPressed: () async { await sub?.cancel(); await ref.read(sessionProvider.notifier).signOut(); if (context.mounted) context.go('/login'); }, icon: const Icon(Icons.logout_rounded, color: Colors.white))]),
        Text(crew['name'] ?? '', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
        Text('${crew['role'] ?? ''} · ${route.value?['name'] ?? crew['route'] ?? ''} · ${route.value?['bus_reg_no'] ?? crew['bus'] ?? ''}', style: TextStyle(color: Colors.white.withValues(alpha: .9))),
      ])),
      Expanded(child: route.when(loading: _loading, error: (e, _) => Center(child: Text('$e')), data: (r) {
        if (r == null) return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No active route is assigned to this number. Please contact the transport in-charge.', textAlign: TextAlign.center)));
        final running = trip.value;
        return ListView(padding: const EdgeInsets.all(20), children: [
          if (running == null) ...[
            Text('Start a trip', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 6),
            Text('Keep this phone on and with you. Parents see the bus position until you press End trip.', style: TextStyle(color: cs.onSurfaceVariant, height: 1.45)), const SizedBox(height: 18),
            PrimaryButton('Start morning trip', icon: Icons.wb_sunny_rounded, busy: busy, onPressed: () => _start(r['id'], 'morning')), const SizedBox(height: 12),
            PrimaryButton('Start afternoon trip', icon: Icons.wb_twilight_rounded, busy: busy, onPressed: () => _start(r['id'], 'afternoon')),
          ] else ...[
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Brand.greenTint, borderRadius: BorderRadius.circular(22)), child: Column(children: [
              const Icon(Icons.gps_fixed_rounded, color: Brand.green, size: 40), const SizedBox(height: 10),
              Text('${running['kind'] == 'morning' ? 'Morning' : 'Afternoon'} trip running', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Brand.green)),
              Text('Since ${DateFormat('h:mm a').format(DateTime.parse(running['started_at']).toLocal())} · $fixes position updates sent', style: TextStyle(color: cs.onSurfaceVariant)),
            ])),
            const SizedBox(height: 18),
            OutlinedButton.icon(onPressed: busy ? null : () => _end(running['id']), icon: const Icon(Icons.stop_circle_rounded, color: Brand.crimson), label: const Text('End trip')),
          ],
          if (status != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(status!, style: TextStyle(color: context.tone(Brand.crimsonDeep), fontWeight: FontWeight.w700))),
          const SizedBox(height: 16),
          NoteBox('Stops on this route: ${(List<Map<String, dynamic>>.from(r['route_stop'] ?? [])..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int))).map((x) => x['name']).join(' → ')}'),
        ]);
      })),
    ]));
  }
}
