import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/session.dart';
import '../core/bus_map.dart';
import '../core/data2.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../core/wake_lock.dart';
import '../widgets/common.dart';
import '../widgets/empty_state.dart';
import '../widgets/bus_ring.dart';
import '../widgets/royal_extras.dart' show GoldLoading, PressScale;
import 'family_screens.dart' show callNumber;

/// Bus pages.
///  • Parents: one page — live map, "about 2.4 km · about 8 min", today's driver and bus assistant, and the family's own
///    private pickup point (from the address; the family can correct it once).
///  • Crew (driver / bus assistant): one round Start trip button, "Which bus today?", the live map with the children's
///    pickup points (first names only) and one End trip button.

Widget _loading() => const GoldLoading();
void _snack(BuildContext context, String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
bool _morningKind(Object? kind) => '$kind'.startsWith('morning');
double? _d(Object? v) => (v as num?)?.toDouble();

/// Light-weight one-shot position (null when location is off / refused / slow).
Future<Position?> _hereNow({Duration timeout = const Duration(seconds: 10)}) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout));
  } catch (_) {
    try { return await Geolocator.getLastKnownPosition(); } catch (_) { return null; }
  }
}

// ======================================================================= parents
class BusScreen extends ConsumerStatefulWidget {
  const BusScreen({super.key});
  @override
  ConsumerState<BusScreen> createState() => _BusScreenState();
}

class _BusScreenState extends ConsumerState<BusScreen> {
  String? trailFor;
  final trail = <List<double>>[];
  bool placing = false, saving = false;   // "Move the pin on the map" mode
  bool? _shown;
  late final StateController<bool> _visible = ref.read(busPageVisibleProvider.notifier);

  /// The Bus tab stays alive behind the other tabs; it polls fast only while it is really on screen.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final on = TickerMode.valuesOf(context).enabled;
    if (on != _shown) { _shown = on; final v = _visible; Future.microtask(() => v.state = on); }
  }

  @override
  void dispose() { final v = _visible; Future.microtask(() => v.state = false); super.dispose(); }

  /// Today's trail for the running trip: fetched once, then grown from the live positions (the road already covered).
  void _syncTrail(Map<String, dynamic>? t) {
    if (t == null) { if (trailFor != null) { trailFor = null; trail.clear(); } return; }
    if (trailFor != t['id']) {
      trailFor = t['id']; trail.clear();
      final id = t['id'] as String;
      tripTrail(id).then((p) { if (mounted && trailFor == id) setState(() => trail.insertAll(0, p)); }).catchError((_) {});
    }
    final lat = _d(t['last_lat']), lng = _d(t['last_lng']);
    if (lat != null && lng != null && (trail.isEmpty || metresBetween(trail.last[0], trail.last[1], lat, lng) > 15)) trail.add([lat, lng]);
  }

  Future<void> _save(String sid, double lat, double lng, String done) async {
    setState(() => saving = true);
    try {
      await savePin(sid, lat, lng);
      ref.invalidate(busFamilyProvider);
      ref.invalidate(myPickupTimeProvider);
      if (mounted) _snack(context, done);
    } catch (e) {
      if (mounted) _snack(context, friendlyError(e));
    }
    if (mounted) setState(() { saving = false; placing = false; });
  }

  Future<void> _change(String sid) async {
    final cs = Theme.of(context).colorScheme;
    final pick = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (c) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Your pickup point', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Placed from your address in the school records. If it is not right, fix it once — it stays saved. Only your family can see it.',
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
        const SizedBox(height: 16),
        SizedBox(height: 52, child: PrimaryButton('Use my location now', icon: Icons.my_location_rounded, onPressed: () => Navigator.pop(c, 'here'))),
        const SizedBox(height: 10),
        SizedBox(height: 50, child: OutlinedButton.icon(onPressed: () => Navigator.pop(c, 'map'), icon: const Icon(Icons.touch_app_rounded), label: const Text('Move the pin on the map'))),
        const SizedBox(height: 4),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
      ]),
    )));
    if (!mounted || pick == null) return;
    if (pick == 'map') { setState(() => placing = true); _snack(context, 'Tap the map where your pickup point is'); return; }
    setState(() => saving = true);
    final p = await _hereNow();
    if (!mounted) return;
    if (p == null) { setState(() => saving = false); _snack(context, 'Please allow location for this app, or move the pin on the map instead.'); return; }
    await _save(sid, p.latitude, p.longitude, 'Saved ✓ Your pickup point is where you are standing');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sid = ref.watch(sessionProvider).value?.active?.id;
    final async = ref.watch(busFamilyProvider);
    final b = async.value;
    final t = b?['trip'] as Map?;
    _syncTrail(t == null ? null : Map<String, dynamic>.from(t));
    final title = b == null ? 'Bus' : 'Bus ${b['bus']}';
    final sub = t != null ? '● ${_morningKind(t['kind']) ? 'Morning' : 'Afternoon'} trip live' : b == null ? '' : 'Bus parked';

    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(20, 12, 8, 14), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          if (sub.isNotEmpty) Text(sub, style: TextStyle(color: t != null ? const Color(0xFFB8F0CF) : Colors.white.withValues(alpha: .85), fontSize: 13, fontWeight: FontWeight.w700)),
        ])),
        if (b != null) IconButton(onPressed: () => _alertsSheet(context), tooltip: 'Bus alerts', icon: const Icon(Icons.notifications_active_outlined, color: Colors.white)),
      ])),
      Expanded(child: async.when(
        loading: _loading,
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (b) {
          if (b == null || sid == null) return const EmptyState(kind: EmptyKind.bus, title: 'No bus route', line: 'Your child is not on a school bus route. The transport office can add one.');
          return _body(b, sid, cs);
        },
      )),
    ]));
  }

  Widget _body(Map<String, dynamic> b, String sid, ColorScheme cs) {
    final t = b['trip'] == null ? null : Map<String, dynamic>.from(b['trip'] as Map);
    final pin = b['pin'] == null ? null : Map<String, dynamic>.from(b['pin'] as Map);
    final home = pin == null ? null : LatLng(_d(pin['lat'])!, _d(pin['lng'])!);
    final lat = _d(t?['last_lat']), lng = _d(t?['last_lng']);
    // laptops and tablets: the cards sit at the bottom left (460 px wide), so the map stays in view
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return Stack(children: [
      Positioned.fill(child: BusMap(
        stops: const [], busLat: lat, busLng: lng, trail: trail, running: t != null, home: home,
        padding: wide ? const EdgeInsets.only(left: 480) : const EdgeInsets.only(bottom: 260),
        onTap: placing && !saving ? (p) => _save(sid, p.latitude, p.longitude, 'Saved ✓ Your pickup point is on the map') : null,
      )),
      if (placing) Positioned(left: 12, right: 12, top: 12, child: Material(color: Brand.crimsonDeep, borderRadius: BorderRadius.circular(14), child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(children: [
          const Expanded(child: Text('Tap the map where your pickup point is', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          TextButton(onPressed: () => setState(() => placing = false), child: const Text('Cancel', style: TextStyle(color: Colors.white))),
        ])))),
      Positioned(left: 12, right: wide ? null : 12, width: wide ? 460 : null, bottom: 12, child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _statusCard(b, t, pin, cs),
        const SizedBox(height: 10),
        _pinCard(sid, pin, cs),
      ]))),
    ]);
  }

  Widget _card(ColorScheme cs, Widget child) => Material(color: cs.surface, elevation: 6, shadowColor: Colors.black26, borderRadius: BorderRadius.circular(20),
      child: Padding(padding: const EdgeInsets.all(14), child: child));

  Widget _statusCard(Map<String, dynamic> b, Map<String, dynamic>? t, Map<String, dynamic>? pin, ColorScheme cs) {
    final drv = b['driver'] as Map?, ast = b['assistant'] as Map?;
    final calls = Row(children: [
      Expanded(child: OutlinedButton.icon(onPressed: drv?['phone'] == null ? null : () => callNumber('${drv!['phone']}'),
          icon: const Icon(Icons.call_rounded, size: 18), label: Text(drv?['name'] == null ? 'Driver' : '${drv!['name']} · driver', overflow: TextOverflow.ellipsis))),
      const SizedBox(width: 8),
      Expanded(child: OutlinedButton.icon(onPressed: ast?['phone'] == null ? null : () => callNumber('${ast!['phone']}'),
          icon: const Icon(Icons.call_rounded, size: 18), label: Text(ast?['name'] == null ? 'Bus assistant' : '${ast!['name']} · assistant', overflow: TextOverflow.ellipsis))),
    ]);

    if (t == null) {
      final last = b['last'] as Map?;
      final head = last?['ended_at'] == null ? 'The bus is not on a trip right now'
          : 'Bus parked · ${_morningKind(last!['kind']) ? 'morning' : 'afternoon'} trip ended ${time12Iso(last['ended_at'] as String?)}';
      final next = b['next'] as String?;
      return _card(cs, Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(head, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        Text('${next == null ? '' : '$next. '}You get a notification when it starts.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.35)),
        const SizedBox(height: 10),
        calls,
      ]));
    }

    final lat = _d(t['last_lat']);
    final age = t['last_fix_at'] == null ? null : DateTime.now().difference(DateTime.parse(t['last_fix_at']).toLocal()).inSeconds;
    final eta = t['eta'] as Map?;
    String head; String? line; int? mins;
    if (lat == null) {
      head = 'Trip started · waiting for the bus location';
      line = 'The bus will appear on the map in a few seconds.';
    } else if (t['passed'] == true) {
      head = _morningKind(t['kind']) ? 'The bus has passed your pickup point' : 'The bus has reached your drop point';
    } else if (pin == null || eta == null) {
      head = 'The bus is on the way';
      line = 'Set your pickup point below to see how far away it is.';
    } else {
      mins = (eta['minutes'] as num).round();
      final m = eta['metres'] as num;
      head = m < 250 ? 'The bus is almost at your pickup point' : 'Bus is about ${distText(m)} away';
      line = 'about $mins min · Expected about ${time12(DateTime.now().add(Duration(minutes: mins)))}';
    }
    final isLive = age != null && age < 20;
    final warn = age == null || isLive ? null
        : age >= 600 ? ('● No update for ${age ~/ 60} min — the bus phone may be out of network. Call the driver if you are worried.', Brand.crimson)
        : ('● Last update ${age >= 60 ? '${age ~/ 60} min' : '$age s'} ago — low network area', Brand.amber);
    return _card(cs, Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        if (mins != null) ...[RepaintBoundary(child: BusCountdownRing(minutes: mins, size: 64)), const SizedBox(width: 14)],
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(head, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 2),
          Text.rich(TextSpan(children: [
            if (line != null) TextSpan(text: line),
            if (line != null && isLive) const TextSpan(text: ' · '),
            if (isLive) TextSpan(text: '● Live', style: TextStyle(color: context.tone(Brand.green), fontWeight: FontWeight.w800)),
          ]), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          if (warn != null) Padding(padding: const EdgeInsets.only(top: 2),
              child: Text(warn.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.tone(warn.$2)))),
        ])),
      ]),
      const SizedBox(height: 10),
      calls,
    ]));
  }

  Widget _pinCard(String sid, Map<String, dynamic>? pin, ColorScheme cs) {
    final from = pin == null ? 'Not set yet — place it once for the bus times'
        : switch ('${pin['source']}') {
            'parent' => 'Set by you',
            'staff' => 'Set by the transport office',
            _ => 'From your address${pin['area'] == null ? '' : ' · ${pin['area']}'}',
          };
    return _card(cs, Row(children: [
      const Icon(Icons.home_rounded, color: Brand.crimsonDeep, size: 26),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Pickup point', style: TextStyle(fontWeight: FontWeight.w800)),
        Text(from, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
      ])),
      saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          // a small button: the app's buttons are full-width by default, which squeezed the words beside it into one letter per line
          : FilledButton.tonal(onPressed: () => _change(sid), style: FilledButton.styleFrom(minimumSize: const Size(84, 44), padding: const EdgeInsets.symmetric(horizontal: 18)),
              child: Text(pin == null ? 'Set' : 'Change')),
    ]));
  }

  void _alertsSheet(BuildContext context) => showModalBottomSheet(context: context, showDragHandle: true, isScrollControlled: true,
      builder: (_) => const SafeArea(child: _BusAlerts()));
}

/// Which bus notifications this family wants (one switch per kind; bus alerts always come through, even in quiet hours).
class _BusAlerts extends ConsumerWidget {
  const _BusAlerts();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(etaPrefProvider);
    return Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 12), child: p.when(
      loading: () => const SizedBox(height: 200, child: GoldLoading()),
      error: (e, _) => Padding(padding: const EdgeInsets.all(24), child: Text(friendlyError(e))),
      data: (m) {
        final prefs = Map<String, dynamic>.from(m);
        Widget sw(String k, String t, String s) => SwitchListTile(value: prefs[k] == true, title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: s.isEmpty ? null : Text(s), onChanged: (v) async {
              prefs[k] = v;
              try { await saveEtaPref(prefs); } catch (e) { if (context.mounted) _snack(context, friendlyError(e)); }
              ref.invalidate(etaPrefProvider);
            });
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 6), child: Align(alignment: Alignment.centerLeft, child: Text('Bus alerts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)))),
          sw('trip_started', 'Trip started', 'When the bus starts its trip'),
          sw('ten_min', '10 and 5 minutes away', 'Before the bus reaches your pickup point'),
          sw('at_stop', 'Bus at your pickup point', ''),
          sw('trip_ended', 'Trip ended', 'The bus reached school / finished the drop trip'),
          const Padding(padding: EdgeInsets.fromLTRB(16, 6, 16, 0), child: NoteBox('Bus alerts always come through, even during quiet hours.')),
        ]);
      },
    ));
  }
}

// ======================================================================= crew (driver / bus assistant)
/// What a driver or bus assistant sees after signing in: one round Start trip button; while running, the live map and one End trip button.
/// The phone that starts the trip sends its location every second (Android keeps going with the screen off through the
/// "Bus trip running" notification; on the website the screen is kept on).
class DriverScreen extends ConsumerStatefulWidget {
  const DriverScreen({super.key});
  @override
  ConsumerState<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends ConsumerState<DriverScreen> {
  StreamSubscription<Position>? sub;
  Timer? sender, poll;
  AppLifecycleListener? life;
  String? tripId, myDevice;
  Position? latest, here;
  bool sending = false, busy = false, resumed = false, stopping = false;
  DateTime? lastSentAt;
  final trail = <List<double>>[];

  @override
  void initState() {
    super.initState();
    deviceId().then((d) { if (mounted) setState(() => myDevice = d); });
    // refresh the trip picture: every 3 s while another phone sends; every 9 s while this phone sends; else every 30 s
    var n = 0;
    poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      n++;
      final st = ref.read(crewStateProvider).value;
      final running = st?['trip'] != null;
      if ((running && tripId == null) || (tripId != null && n % 3 == 0) || n % 10 == 0) ref.invalidate(crewStateProvider);
      if (!running && n % 10 == 0 && st?['morning_now'] == false) _refreshHere();
    });
    life = AppLifecycleListener(onResume: () { if (tripId != null) keepScreenOn(true); ref.invalidate(crewStateProvider); });
    _refreshHere();
  }

  @override
  void dispose() { sub?.cancel(); sender?.cancel(); poll?.cancel(); life?.dispose(); keepScreenOn(false); super.dispose(); }

  /// Where the phone is now (only to show the school-gate locks; the server checks again).
  Future<void> _refreshHere() async {
    final p = await _hereNow(timeout: const Duration(seconds: 8));
    if (p != null && mounted) setState(() => here = p);
  }

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
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) _snack(context, 'Turn on Location (GPS) in the phone, then try again.');
      try { await Geolocator.openLocationSettings(); } catch (_) {}
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (mounted) _snack(context, 'Location is needed. Open the phone settings → Permissions → Location → Allow.');
      return false;
    }
    return true;
  }

  /// Start reading GPS and sending it from this phone.
  Future<void> _track(String id) async {
    tripId = id;
    sub?.cancel(); sender?.cancel();
    keepScreenOn(true);
    if (trail.isEmpty) { try { trail.addAll(await tripTrail(id)); } catch (_) {} }
    sub = Geolocator.getPositionStream(locationSettings: _settings()).listen((p) {
      latest = p; here = p;
      final t = trail.isEmpty ? null : trail.last;
      if (t == null || metresBetween(t[0], t[1], p.latitude, p.longitude) > 15) trail.add([p.latitude, p.longitude]);
      if (mounted) setState(() {});
    }, onError: (_) {});
    // send the newest position every second; with a slow network never queue old ones
    sender = Timer.periodic(const Duration(seconds: 1), (_) async {
      final p = latest; final t = tripId;
      if (p == null || t == null || sending) return;
      sending = true; latest = null;
      try {
        final r = await pushFix(t, p.latitude, p.longitude, p.speed < 0 ? null : p.speed * 3.6, p.accuracy);
        if (r['running'] == false) { await _stopLocal('This trip has ended.'); return; }
        if (r['elsewhere'] == true) { await _stopLocal('The other phone is now sharing the location.'); return; }
        lastSentAt = DateTime.now();
        if (mounted) setState(() {});
      } catch (_) {
        latest ??= p;   // keep it and try again next second
      } finally { sending = false; }
    });
    if (mounted) setState(() {});
  }

  Future<void> _stopLocal([String? msg]) async {
    if (stopping) return;
    stopping = true;
    await sub?.cancel(); sub = null; sender?.cancel(); sender = null; tripId = null; latest = null; lastSentAt = null;
    keepScreenOn(false);
    ref.invalidate(crewStateProvider);
    stopping = false;
    if (mounted) { setState(() {}); if (msg != null) _snack(context, msg); }
  }

  /// ONE simple screen the first time on Android: let the app run when the screen is off (battery saving).
  Future<void> _batteryOnce() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final p = await SharedPreferences.getInstance();
    if (p.getBool('rc_battery_ok') == true || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _BatteryPage()));
    await p.setBool('rc_battery_ok', true);
  }

  Future<void> _startTapped(Map<String, dynamic> st, bool locked) async {
    if (locked) { _snack(context, 'The afternoon trip starts at school'); return; }
    await _batteryOnce();
    if (!mounted) return;
    final usual = st['usual']?['bus']?.toString() ?? '';
    final pick = await showModalBottomSheet<(String, bool)>(context: context, isScrollControlled: true, showDragHandle: true,
        builder: (_) => _WhichBusSheet(usual: usual));
    if (pick == null || !mounted) return;
    setState(() => busy = true);
    try {
      if (!await _ready()) { setState(() => busy = false); return; }
      final p = await _hereNow();
      final id = await crewStart(pick.$1, p?.latitude, p?.longitude, takeOver: pick.$2);
      trail.clear();
      await _track(id);
      ref.invalidate(crewStateProvider);
      if (mounted) _snack(context, pick.$2 ? 'You are now running bus ${pick.$1} ✓' : 'Trip started on bus ${pick.$1} ✓ Parents of bus ${pick.$1} are told');
    } catch (e) {
      if (mounted) _snack(context, friendlyError(e));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _takeOver(String id) async {
    setState(() => busy = true);
    try {
      if (!await _ready()) { setState(() => busy = false); return; }
      await takeOverTrip(id);
      await _track(id);
      ref.invalidate(crewStateProvider);
    } catch (e) { if (mounted) _snack(context, friendlyError(e)); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _end(String id, bool locked) async {
    if (locked) { _snack(context, 'You can end the morning trip at school'); return; }
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('End this trip?'),
      content: const Text('Parents will stop seeing the bus.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('End trip'))],
    ));
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      // send the very latest position first, so the school-gate check uses where the bus is now
      final p = here;
      if (p != null && tripId != null) { try { await pushFix(id, p.latitude, p.longitude, null, p.accuracy); } catch (_) {} }
      await endTrip(id);
      trail.clear();
      await _stopLocal();
      if (mounted) _snack(context, 'Trip ended ✓');
    } catch (e) { if (mounted) _snack(context, friendlyError(e)); }
    if (mounted) setState(() => busy = false);
  }

  bool _atSchool(Map<String, dynamic>? gate, double? lat, double? lng) {
    if (gate == null) return true;                    // gate not set: no lock
    if (lat == null || lng == null) return false;
    return metresBetween(lat, lng, _d(gate['lat'])!, _d(gate['lng'])!) <= (_d(gate['r']) ?? 400);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final async = ref.watch(crewStateProvider);
    final st = async.value;
    final trip = st?['trip'] == null ? null : Map<String, dynamic>.from(st!['trip'] as Map);
    // carry on sending after the app was reopened — only on the phone that was sending
    if (trip != null && tripId == null && !resumed && myDevice != null && trip['tracker'] == myDevice) {
      resumed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async { if (await _ready()) _track(trip['id']); });
    }
    // the trip was ended elsewhere (transport office, or by itself at school)
    if (st != null && !async.isLoading && trip == null && tripId != null && !busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _stopLocal('This trip has ended.'));
    }
    final me = st?['me'] as Map?;
    final sub = trip != null
        ? '● ${_morningKind(trip['kind']) ? 'Morning' : 'Afternoon'} trip · Bus ${trip['bus']}${tripId != null ? ' · sharing location' : ''}'
        : st?['usual'] == null ? '' : 'Usual bus: ${st!['usual']['bus']}';

    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(20, 8, 8, 14), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(me == null ? '' : '${me['name']} · ${me['role']}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          if (sub.isNotEmpty) Text(sub, style: TextStyle(color: trip != null ? const Color(0xFFB8F0CF) : Colors.white.withValues(alpha: .9), fontSize: 13, fontWeight: FontWeight.w700)),
        ])),
        IconButton(onPressed: () async {
          if (tripId != null) { _snack(context, 'End the trip before signing out.'); return; }
          await ref.read(sessionProvider.notifier).signOut();
          if (context.mounted) context.go('/login');
        }, icon: const Icon(Icons.logout_rounded, color: Colors.white), tooltip: 'Sign out'),
      ])),
      Expanded(child: async.when(
        skipLoadingOnRefresh: true, skipLoadingOnReload: true,
        loading: _loading,
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(friendlyError(e), textAlign: TextAlign.center))),
        data: (st) {
          if (st == null) return const SizedBox();
          return trip == null ? _idle(st, cs) : _running(st, trip, cs);
        },
      )),
    ]));
  }

  Widget _idle(Map<String, dynamic> st, ColorScheme cs) {
    final morning = st['morning_now'] != false;
    final gate = st['gate'] == null ? null : Map<String, dynamic>.from(st['gate'] as Map);
    final locked = !morning && !_atSchool(gate, here?.latitude, here?.longitude);
    return Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('${morning ? 'Good morning' : 'Afternoon'} · no trip running', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 28),
      _RoundButton(label: 'Start trip', icon: Icons.play_arrow_rounded, size: 200, colors: const [Color(0xFF2FA56A), Brand.green],
          locked: locked, busy: busy, onTap: () => _startTapped(st, locked)),
      const SizedBox(height: 18),
      Text(locked ? 'You are not at school yet' : 'Sharing starts when you press Start', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
    ])));
  }

  Widget _running(Map<String, dynamic> st, Map<String, dynamic> trip, ColorScheme cs) {
    final mine = tripId != null;
    final morning = _morningKind(trip['kind']);
    final gate = st['gate'] == null ? null : Map<String, dynamic>.from(st['gate'] as Map);
    final busLat = mine ? here?.latitude ?? _d(trip['last_lat']) : _d(trip['last_lat']);
    final busLng = mine ? here?.longitude ?? _d(trip['last_lng']) : _d(trip['last_lng']);
    final locked = morning && !_atSchool(gate, busLat, busLng);
    final kids = [for (final k in (trip['kids'] as List? ?? const [])) Map<String, dynamic>.from(k as Map)];
    final left = (trip['left'] as num?)?.toInt() ?? 0;
    final next = trip['next'] as Map?;
    // nearest child not passed yet — measured from this phone's own position when it is the one sending
    var nextLine = next == null ? null : 'Next: ${next['first']}${next['area'] == null ? '' : ' (${next['area']})'}';
    num? nextM = next?['metres'] as num?;
    if (mine && busLat != null && busLng != null) {
      double from(Map<String, dynamic> k) => metresBetween(busLat, busLng, _d(k['lat'])!, _d(k['lng'])!);
      final todo = kids.where((k) => k['passed'] != true && k['lat'] != null).toList()..sort((a, b) => from(a).compareTo(from(b)));
      if (todo.isNotEmpty) {
        final k = todo.first;
        nextLine = 'Next: ${k['first']}${k['area'] == null ? '' : ' (${k['area']})'}';
        nextM = from(k) * 1.3;
      }
    }
    final verb = morning ? 'pick up' : 'drop';
    final detail = kids.isEmpty ? 'No pickup points on this bus yet'
        : left == 0 ? 'All children ${morning ? 'picked up' : 'dropped'}'
        : '${nextM == null ? '' : '${distText(nextM)} · '}$left ${left == 1 ? 'child' : 'children'} still to $verb';
    final fresh = lastSentAt != null && DateTime.now().difference(lastSentAt!).inSeconds < 10;

    return Stack(children: [
      Positioned.fill(child: BusMap(
        stops: const [], busLat: busLat, busLng: busLng, trail: trail, running: true,
        glide: Duration(seconds: mine ? 1 : 3), padding: const EdgeInsets.only(bottom: 280),
        pins: [for (final k in kids) if (k['lat'] != null)
          MapPin(lat: _d(k['lat'])!, lng: _d(k['lng'])!, label: '${k['first']}', color: k['passed'] == true ? const Color(0xFF9A9A9A) : Brand.crimsonDeep)],
      )),
      Positioned(left: 12, right: 12, bottom: 12, child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(color: cs.surface, elevation: 6, borderRadius: BorderRadius.circular(18), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.place_rounded, color: Brand.crimsonDeep, size: 26),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nextLine ?? (morning ? 'Morning pick-up' : 'Afternoon drop'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              Text(detail, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ])),
            if (mine) Pill(fresh ? '● Live' : '● GPS…', fg: fresh ? Brand.green : Brand.amber, bg: fresh ? Brand.greenTint : Brand.amberTint),
          ]),
          if (!mine) ...[
            const SizedBox(height: 8),
            Text('The location is coming from ${trip['tracker_name'] ?? 'the other crew phone'}’s phone.', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: busy ? null : () => _takeOver(trip['id']), child: const Text('Share from this phone instead'))),
          ],
        ]))),
        const SizedBox(height: 12),
        Center(child: _RoundButton(label: 'End trip', icon: Icons.stop_rounded, size: 132, colors: const [Brand.crimson, Brand.crimsonDeep],
            locked: locked, busy: busy, onTap: () => _end(trip['id'], locked))),
        const SizedBox(height: 6),
        Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: cs.surface.withValues(alpha: .9), borderRadius: BorderRadius.circular(99)),
            child: Text(locked ? 'Ends when the bus reaches the school gate' : 'Press when the trip is over', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)))),
      ]))),
    ]);
  }
}

/// The big round Start / End button.
class _RoundButton extends StatelessWidget {
  final String label; final IconData icon; final double size; final List<Color> colors; final bool locked, busy; final VoidCallback onTap;
  const _RoundButton({required this.label, required this.icon, required this.size, required this.colors, required this.onTap, this.locked = false, this.busy = false});
  @override
  Widget build(BuildContext context) => Semantics(button: true, label: label, child: PressScale(enabled: !busy, child: GestureDetector(
    onTap: busy ? null : onTap,
    child: Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: locked ? null : LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        color: locked ? Brand.muted.withValues(alpha: .45) : null,
        border: Border.all(color: Colors.white, width: 5),
        boxShadow: locked ? null : [BoxShadow(color: colors.last.withValues(alpha: .4), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      child: busy ? const Center(child: SizedBox(width: 34, height: 34, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)))
          : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: Colors.white, size: size * .3),
              Text(label, style: TextStyle(color: Colors.white, fontSize: size * .12, fontWeight: FontWeight.w900)),
              if (locked) const Padding(padding: EdgeInsets.only(top: 2), child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_rounded, color: Colors.white, size: 13),
                SizedBox(width: 3),
                Text('at school only', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ])),
            ]),
    ),
  )));
}

/// "Which bus today?" — the usual bus is typed in; Continue, or "Take over bus 12" when that bus is already running.
/// Returns (bus number, take over).
class _WhichBusSheet extends StatefulWidget {
  final String usual;
  const _WhichBusSheet({required this.usual});
  @override
  State<_WhichBusSheet> createState() => _WhichBusSheetState();
}

class _WhichBusSheetState extends State<_WhichBusSheet> {
  late final ctrl = TextEditingController(text: widget.usual);
  Timer? deb;
  Map<String, dynamic>? info; String? checked; bool checking = false;

  @override
  void initState() { super.initState(); if (widget.usual.isNotEmpty) _check(); }
  @override
  void dispose() { deb?.cancel(); ctrl.dispose(); super.dispose(); }

  Future<void> _check() async {
    final v = ctrl.text.trim();
    if (v.isEmpty) { setState(() { info = null; checked = null; }); return; }
    setState(() => checking = true);
    try {
      final r = await checkBus(v);
      if (mounted && ctrl.text.trim() == v) setState(() { info = r; checked = v; });
    } catch (e) {
      if (mounted) setState(() { info = {'ok': false, 'message': friendlyError(e)}; checked = v; });
    }
    if (mounted) setState(() => checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = ctrl.text.trim();
    final ready = info != null && checked == v && info!['ok'] == true;
    final takeOver = ready && info!['running'] == true && info!['mine'] != true;
    final warn = checked == v ? (info?['message'] as String?) : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 18 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Which bus today?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('Your usual bus is filled in. Change it only if you are on another bus today.', style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
        const SizedBox(height: 16),
        TextField(
          controller: ctrl, autofocus: widget.usual.isEmpty, textAlign: TextAlign.center, keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z ]'))],
          style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: 2),
          decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), contentPadding: const EdgeInsets.symmetric(vertical: 10)),
          onChanged: (_) { setState(() {}); deb?.cancel(); deb = Timer(const Duration(milliseconds: 450), _check); },
          onSubmitted: (_) => _check(),
        ),
        if (warn != null) Container(
          margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Brand.amberTint, borderRadius: BorderRadius.circular(12)),
          child: Text(warn, style: const TextStyle(color: Brand.amber, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 16),
        SizedBox(height: 56, child: PrimaryButton(takeOver ? 'Take over bus ${info!['bus']}' : 'Continue',
            busy: checking, onPressed: ready ? () => Navigator.pop(context, ('${info!['bus']}', takeOver)) : null)),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ]),
    );
  }
}

/// First Start trip on Android: one screen, one button — let the app keep sharing the location with the screen off.
class _BatteryPage extends StatelessWidget {
  const _BatteryPage();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(appBar: AppBar(), body: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(28, 0, 28, 28), child: Column(children: [
      const Spacer(),
      const Icon(Icons.battery_charging_full_rounded, size: 84, color: Brand.green),
      const SizedBox(height: 20),
      const Text('Keep the bus location going', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      Text('Some phones stop apps to save battery.\nTap Allow, then choose Battery → “No restrictions” and come back.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 1.5, color: cs.onSurfaceVariant)),
      const Spacer(),
      SizedBox(width: double.infinity, height: 60, child: PrimaryButton('Allow', icon: Icons.check_rounded, onPressed: () async {
        try { await Geolocator.openAppSettings(); } catch (_) {}
        if (context.mounted) Navigator.pop(context);
      })),
    ]))));
  }
}
