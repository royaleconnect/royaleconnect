import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/bus_map.dart';
import '../core/data2.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'family_screens.dart' show callNumber;
import '../widgets/royal_extras.dart' show GoldLoading;

Widget _loading() => const GoldLoading();

/// Parent / student side — only reachable when the student has a transport enrolment.
class BusScreen extends ConsumerStatefulWidget {
  const BusScreen({super.key});
  @override
  ConsumerState<BusScreen> createState() => _BusScreenState();
}
class _BusScreenState extends ConsumerState<BusScreen> {
  int tab = 1;   // opens on the live map
  String? trailFor; final trail = <List<double>>[];

  /// Today's trail for the running trip: fetched once, then grown from the live positions.
  void _syncTrail(Map<String, dynamic>? t) {
    if (t == null) { if (trailFor != null) { trailFor = null; trail.clear(); } return; }
    if (trailFor != t['id']) {
      trailFor = t['id']; trail.clear();
      final id = t['id'] as String;
      tripTrail(id).then((p) { if (mounted && trailFor == id) setState(() => trail.insertAll(0, p)); }).catchError((_) {});
    }
    final lat = (t['last_lat'] as num?)?.toDouble(), lng = (t['last_lng'] as num?)?.toDouble();
    if (lat != null && lng != null && (trail.isEmpty || metresBetween(trail.last[0], trail.last[1], lat, lng) > 15)) trail.add([lat, lng]);
  }
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
        Text(t == null ? 'Not running' : '${'${t['kind']}'.startsWith('morning') ? 'Morning' : 'Afternoon'} trip live', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))]));

  Widget _stops(Map<String, dynamic> r, List<Map<String, dynamic>> stops, Map<String, dynamic>? t, ColorScheme cs) {
    final morning = t == null ? DateTime.now().hour < 12 : '${t['kind']}'.startsWith('morning');
    final next = t?['next_stop_seq'] as int?;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Row(children: [
        Expanded(child: Text(t == null ? 'Next ${morning ? 'morning' : 'afternoon'} trip starts ${(morning ? r['morning_start'] : r['afternoon_start'])?.toString().substring(0, 5) ?? ''}' : 'Bus is ${next == null ? 'on the way' : 'heading to stop $next'} · updated ${t['last_fix_at'] == null ? '—' : DateFormat('h:mm a').format(DateTime.parse(t['last_fix_at']).toLocal())}', style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4))),
        IconButton.filledTonal(onPressed: () => callNumber(r['driver']?['phone']), icon: const Icon(Icons.call_rounded), tooltip: 'Call driver'),
        IconButton.filledTonal(onPressed: () => callNumber(r['conductor']?['phone']), icon: const Icon(Icons.support_agent_rounded), tooltip: 'Call bus assistant'),
      ])),
      const SizedBox(height: 16),
      for (final (i, s) in (morning ? stops : stops.reversed.toList()).indexed) Builder(builder: (_) {
        final mine = s['id'] == r['my_stop']?['id']; final done = t != null && (next == null || (morning ? (s['seq'] as int) < next : (s['seq'] as int) > next)); final current = next != null && s['seq'] == next;
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

  /// Live map: the bus glides along the real streets; your stop is the house. Card at the bottom: how far, how long, call.
  Widget _map(Map<String, dynamic> r, List<Map<String, dynamic>> stops, Map<String, dynamic>? t, ColorScheme cs) {
    if (stops.isEmpty) return const Center(child: Text('Stops not mapped yet.'));
    _syncTrail(t);
    final morning = t == null ? DateTime.now().hour < 12 : '${t['kind']}'.startsWith('morning');
    final order = travelOrder(stops, morning);
    final myId = r['my_stop']?['id'] as String?;
    final myIdx = order.indexWhere((x) => x['id'] == myId);
    final nSeq = t?['next_stop_seq'] as int?;
    final nIdx = t == null ? null : (nSeq == null ? null : order.indexWhere((x) => x['seq'] == nSeq));
    final lat = (t?['last_lat'] as num?)?.toDouble(), lng = (t?['last_lng'] as num?)?.toDouble();
    final age = t?['last_fix_at'] == null ? null : DateTime.now().difference(DateTime.parse(t!['last_fix_at']).toLocal()).inSeconds;
    String title, sub;
    if (t == null) {
      title = 'The bus is not on a trip right now';
      sub = 'Next ${morning ? 'morning' : 'afternoon'} trip starts ${(morning ? r['morning_start'] : r['afternoon_start'])?.toString().substring(0, 5) ?? ''}. You get a notification when it starts.';
    } else if (lat == null || lng == null) {
      title = 'Trip started · waiting for the bus location';
      sub = 'The bus will appear in a few seconds.';
    } else if (nIdx == null || nIdx < 0 || myIdx < 0 || myIdx < nIdx) {
      title = myIdx >= 0 && nIdx != null && nIdx > myIdx ? 'The bus has passed your stop' : 'Bus is on the way';
      sub = nIdx != null && nIdx >= 0 ? 'Next stop: ${order[nIdx]['name']}' : 'All stops done';
    } else {
      final (m, min) = etaTo(lat, lng, order, nIdx, myIdx);
      final away = myIdx - nIdx;
      title = away == 0 ? (m < 300 ? 'The bus is arriving at your stop' : 'Your stop is next · about $min min') : 'Bus is $away stop${away == 1 ? '' : 's'} away · about $min min';
      sub = 'Next stop: ${order[nIdx]['name']} · ${m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m'} to your stop';
    }
    return Stack(children: [
      Positioned.fill(child: BusMap(stops: order, myStopId: myId, busLat: lat, busLng: lng, trail: trail, nextIdx: nIdx, running: t != null, padding: const EdgeInsets.only(bottom: 170))),
      Positioned(left: 12, right: 12, bottom: 12, child: Material(color: cs.surface, elevation: 6, borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.all(14), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        if (age != null) Text(age < 15 ? '● Live · updated ${age < 2 ? 'just now' : '$age s ago'}' : '● Last update ${age ~/ 60 > 0 ? '${age ~/ 60} min' : '$age s'} ago — the bus may be in a low-network area',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.tone(age < 15 ? Brand.green : Brand.amber))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: r['driver']?['phone'] == null ? null : () => callNumber(r['driver']['phone']), icon: const Icon(Icons.call_rounded, size: 18), label: const Text('Driver'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: r['conductor']?['phone'] == null ? null : () => callNumber(r['conductor']['phone']), icon: const Icon(Icons.support_agent_rounded, size: 18), label: const Text('Bus assistant'))),
        ]),
      ])))),
    ]);
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

// ---------------------------------------------------------------- crew (driver / bus assistant)
/// What a driver or bus assistant sees after signing in (dr7 / as7): the live map of their route, Start / End trip, nothing else.
/// The phone that presses Start sends the location every second — with the screen off or other apps open
/// (a "Bus trip running" notification keeps it going). The other crew phone can take over with one tap.
class DriverScreen extends ConsumerStatefulWidget {
  const DriverScreen({super.key});
  @override
  ConsumerState<DriverScreen> createState() => _DriverScreenState();
}
class _DriverScreenState extends ConsumerState<DriverScreen> {
  StreamSubscription<Position>? sub; Timer? sender, poll;
  String? tripId, myDevice; Position? latest, lastPos; bool sending = false;
  int sent = 0; DateTime? lastSentAt; double? accuracy; int? nextSeq; String? status; bool busy = false, resumed = false;
  final trail = <List<double>>[];

  @override
  void initState() {
    super.initState();
    deviceId().then((d) { if (mounted) setState(() => myDevice = d); });
    // while another phone is sending, refresh the trip every 3 s so this map moves too
    poll = Timer.periodic(const Duration(seconds: 3), (_) { if (tripId == null && mounted) ref.invalidate(crewTripProvider); });
  }

  @override
  void dispose() { sub?.cancel(); sender?.cancel(); poll?.cancel(); super.dispose(); }

  LocationSettings _settings() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0, intervalDuration: const Duration(seconds: 1),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Bus trip running',
          notificationText: 'Sharing the bus location with parents. Press End trip in the app when the trip is over.',
          enableWakeLock: true,
        ),
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 0);
  }

  Future<bool> _ready() async {
    if (!await Geolocator.isLocationServiceEnabled()) { setState(() => status = 'Turn on Location (GPS) in the phone settings, then try again.'); await Geolocator.openLocationSettings(); return false; }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      setState(() => status = 'Location permission is needed. Tap “Phone settings” below → Permissions → Location → Allow.');
      return false;
    }
    return true;
  }

  /// Start reading GPS and sending it from this phone.
  Future<void> _track(String id) async {
    tripId = id;
    sub?.cancel(); sender?.cancel();
    if (trail.isEmpty) { try { trail.addAll(await tripTrail(id)); } catch (_) {} }
    sub = Geolocator.getPositionStream(locationSettings: _settings()).listen((p) {
      latest = p; lastPos = p;
      final t = trail.isEmpty ? null : trail.last;
      if (t == null || metresBetween(t[0], t[1], p.latitude, p.longitude) > 15) trail.add([p.latitude, p.longitude]);
      if (mounted) setState(() {});
    }, onError: (_) {});
    // send the newest position every second; if the network is slow, never queue up old ones
    sender = Timer.periodic(const Duration(seconds: 1), (_) async {
      final p = latest; final t = tripId;
      if (p == null || t == null || sending) return;
      sending = true; latest = null;
      try {
        final r = await pushFix(t, p.latitude, p.longitude, p.speed < 0 ? null : p.speed * 3.6, p.accuracy);
        if (r['running'] == false) { await _stopLocal('This trip has ended.'); return; }
        if (r['elsewhere'] == true) { await _stopLocal('The other phone is now sharing the location.'); return; }
        sent++; lastSentAt = DateTime.now(); accuracy = p.accuracy;
        if (r.containsKey('next_stop_seq')) nextSeq = r['next_stop_seq'] as int?;
        if (mounted) setState(() {});
      } catch (_) {
        latest ??= p;   // keep it and try again next second
      } finally { sending = false; }
    });
    if (mounted) setState(() {});
  }

  Future<void> _stopLocal([String? msg]) async {
    await sub?.cancel(); sub = null; sender?.cancel(); sender = null; tripId = null; latest = null;
    ref.invalidate(crewTripProvider);
    if (mounted) setState(() { status = msg; sent = 0; lastSentAt = null; });
  }

  Future<void> _start(String routeId, String kind) async {
    setState(() { busy = true; status = null; trail.clear(); nextSeq = null; });
    try {
      if (!await _ready()) { setState(() => busy = false); return; }
      final s = ref.read(sessionProvider).value!;
      final id = await startTrip(routeId, kind, s.crew!['staff_id']);
      await _track(id);
      ref.invalidate(crewTripProvider);
    } catch (e) { status = 'Could not start: $e'; }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _takeOver(String id) async {
    setState(() { busy = true; status = null; });
    try {
      if (!await _ready()) { setState(() => busy = false); return; }
      await takeOverTrip(id);
      await _track(id);
      ref.invalidate(crewTripProvider);
    } catch (e) { status = 'Could not take over: $e'; }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _end(String id) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('End this trip?'),
      content: const Text('Parents will stop seeing the bus. Only end the trip when all students are dropped / the bus has reached school.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('End trip'))],
    ));
    if (ok != true) return;
    setState(() => busy = true);
    try { await endTrip(id); trail.clear(); await _stopLocal(); } catch (e) { status = 'Could not end: $e'; }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value; final route = ref.watch(crewRouteProvider); final trip = ref.watch(crewTripProvider);
    final cs = Theme.of(context).colorScheme; final crew = s?.crew ?? {};
    final running = trip.value;
    // carry on sending after the app was reopened — only on the phone that was sending
    if (running != null && tripId == null && !resumed && myDevice != null && running['tracker'] == myDevice) {
      resumed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async { if (await _ready()) _track(running['id']); });
    }
    final mine = running != null && tripId != null;
    final elsewhere = running != null && !mine;
    final fresh = lastSentAt != null && DateTime.now().difference(lastSentAt!).inSeconds < 10;

    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(20, 8, 8, 14), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${crew['name'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          Text('${crew['role'] ?? ''} · ${route.value?['name'] ?? crew['route'] ?? ''} · ${route.value?['bus_reg_no'] ?? crew['bus'] ?? ''}', style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 13)),
        ])),
        if (running != null) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Brand.green, borderRadius: BorderRadius.circular(99)),
            child: const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
        IconButton(onPressed: () async {
          if (tripId != null) { setState(() => status = 'End the trip before signing out.'); return; }
          await ref.read(sessionProvider.notifier).signOut(); if (context.mounted) context.go('/login');
        }, icon: const Icon(Icons.logout_rounded, color: Colors.white), tooltip: 'Sign out'),
      ])),
      Expanded(child: route.when(loading: _loading, error: (e, _) => Center(child: Text('$e')), data: (r) {
        if (r == null) return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No active route is linked to this login. Please contact the transport office.', textAlign: TextAlign.center)));
        final morning = running == null ? DateTime.now().hour < 12 : '${running['kind']}'.startsWith('morning');
        final order = travelOrder(List<Map<String, dynamic>>.from(r['route_stop'] ?? []), morning);
        final nSeq = mine ? (nextSeq ?? running?['next_stop_seq'] as int?) : running?['next_stop_seq'] as int?;
        final nIdx = running == null ? null : (nSeq == null ? null : order.indexWhere((x) => x['seq'] == nSeq));
        final busLat = mine ? lastPos?.latitude : (running?['last_lat'] as num?)?.toDouble();
        final busLng = mine ? lastPos?.longitude : (running?['last_lng'] as num?)?.toDouble();
        String? nextLine;
        if (running != null && busLat != null && busLng != null) {
          if (nIdx == null || nIdx < 0) {
            nextLine = 'All stops done';
          } else {
            final (m, min) = etaTo(busLat, busLng, order, nIdx, nIdx);
            nextLine = 'Next stop: ${order[nIdx]['name']} · ${m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m'} · about $min min';
          }
        }
        return Stack(children: [
          Positioned.fill(child: BusMap(stops: order, busLat: busLat, busLng: busLng, trail: trail, nextIdx: nIdx, running: running != null,
              glide: Duration(seconds: mine ? 1 : 3), padding: const EdgeInsets.only(bottom: 200))),
          Positioned(left: 12, right: 12, bottom: 12, child: SafeArea(top: false, child: Material(
            color: cs.surface, elevation: 6, borderRadius: BorderRadius.circular(20),
            child: Padding(padding: const EdgeInsets.all(14), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (running == null) ...[
                Text('Press Start when the bus leaves. Keep Location on and the phone charging.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                const SizedBox(height: 10),
                SizedBox(height: 56, child: PrimaryButton('Start MORNING pick-up', icon: Icons.wb_sunny_rounded, busy: busy, onPressed: () => _start(r['id'], 'morning'))),
                const SizedBox(height: 8),
                SizedBox(height: 56, child: PrimaryButton('Start AFTERNOON drop', icon: Icons.wb_twilight_rounded, busy: busy, onPressed: () => _start(r['id'], 'afternoon'))),
              ] else ...[
                Text('${morning ? 'Morning pick-up' : 'Afternoon drop'}${nextLine == null ? '' : ' · $nextLine'}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                if (mine) Text(fresh ? '● Sharing from this phone · ${DateFormat('h:mm:ss a').format(lastSentAt!)}${accuracy == null ? '' : ' · GPS ${accuracy!.round()} m'}' : '● Waiting for GPS / network…',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.tone(fresh ? Brand.green : Brand.amber)))
                else ...[
                  Text('Location is coming from ${running['tracker_staff']?['display_name'] ?? 'the other crew phone'}’s phone.', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(onPressed: busy ? null : () => _takeOver(running['id']), icon: const Icon(Icons.phone_android_rounded), label: const Text('Share location from this phone instead')),
                ],
                const SizedBox(height: 8),
                SizedBox(height: 50, child: OutlinedButton.icon(onPressed: busy ? null : () => _end(running['id']), icon: const Icon(Icons.stop_circle_rounded, color: Brand.crimson), label: const Text('End trip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)))),
              ],
              if (status != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(status!, style: TextStyle(color: context.tone(Brand.crimsonDeep), fontWeight: FontWeight.w700))),
              Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => Geolocator.openAppSettings(), icon: const Icon(Icons.battery_charging_full_rounded, size: 18),
                  label: const Text('Phone settings: Battery → No restrictions (Xiaomi, Vivo, Oppo, Realme)', style: TextStyle(fontSize: 12)))),
            ])),
          ))),
        ]);
      })),
    ]));
  }
}
