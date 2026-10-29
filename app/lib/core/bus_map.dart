import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'theme.dart';

/// Live bus map used by the driver / bus assistant and by parents.
/// Free street map (OpenStreetMap — no account, no card, no key), drawn by flutter_map on Android, iPhone and the website alike.
/// Map pictures are kept on the phone after the first look, so the same streets are not downloaded again.
/// [stops] in the order the bus visits them; [nextIdx] = index of the next stop (null when not running / finished).
/// The bus glides smoothly to each new position and the map follows it until the user moves the map.
class BusMap extends StatefulWidget {
  final List<Map<String, dynamic>> stops;
  final String? myStopId;
  final double? busLat, busLng;
  final List<List<double>> trail;
  final int? nextIdx;
  final bool running;
  final Duration glide;
  final EdgeInsets padding;
  const BusMap({super.key, required this.stops, this.myStopId, this.busLat, this.busLng, this.trail = const [], this.nextIdx, this.running = false,
      this.glide = const Duration(seconds: 3), this.padding = EdgeInsets.zero});
  @override
  State<BusMap> createState() => _BusMapState();
}

class _BusMapState extends State<BusMap> with SingleTickerProviderStateMixin {
  final _mc = MapController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: widget.glide)..addListener(_tick);
  LatLng? _from, _to, _shown;
  bool _follow = true, _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.busLat != null) _shown = _to = LatLng(widget.busLat!, widget.busLng!);
  }

  @override
  void didUpdateWidget(BusMap old) {
    super.didUpdateWidget(old);
    if (widget.busLat == null) { _shown = _to = null; return; }
    final p = LatLng(widget.busLat!, widget.busLng!);
    if (_to == p) return;
    _from = _shown ?? p; _to = p;
    _anim.duration = widget.glide;
    _anim.forward(from: 0);
  }

  void _tick() {
    if (_from == null || _to == null) return;
    final t = _anim.value;
    final p = LatLng(_from!.latitude + (_to!.latitude - _from!.latitude) * t, _from!.longitude + (_to!.longitude - _from!.longitude) * t);
    setState(() => _shown = p);
    if (_follow && _ready) { try { _mc.move(p, _mc.camera.zoom); } catch (_) {} }
  }

  /// null = this stop is not pinned on the map yet (it is simply not drawn)
  LatLng? _ll(Map<String, dynamic> s) => s['lat'] == null || s['lng'] == null ? null : LatLng((s['lat'] as num).toDouble(), (s['lng'] as num).toDouble());

  void _fitAll() {
    final pts = [for (final s in widget.stops) if (_ll(s) != null) _ll(s)!, if (_shown != null) _shown!];
    if (pts.isEmpty || !_ready) return;
    try {
      if (pts.length == 1) { _mc.move(pts.first, 15); return; }
      _mc.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: EdgeInsets.fromLTRB(40, 60, 40, 40 + widget.padding.bottom)));
    } catch (_) {}
  }

  @override
  void dispose() { _anim.dispose(); _mc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final stops = widget.stops;
    final next = widget.nextIdx;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ahead = <LatLng>[
      if (_shown != null && widget.running) _shown!,
      for (final (i, s) in stops.indexed) if ((!widget.running || next == null || i >= next) && _ll(s) != null) _ll(s)!,
    ];
    final trail = [for (final p in widget.trail) LatLng(p[0], p[1]), if (_shown != null && widget.trail.isNotEmpty) _shown!];
    final start = _shown ?? stops.map(_ll).whereType<LatLng>().firstOrNull ?? const LatLng(13.0244, 77.6410);

    Widget stopDot(int i, Map<String, dynamic> s) {
      final mine = s['id'] == widget.myStopId;
      final done = widget.running && (next == null || i < next);
      if (mine) {
        return Tooltip(message: '${s['name']} · your stop', child: Container(
          decoration: BoxDecoration(color: Brand.crimson, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]),
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 18)));
      }
      return Tooltip(message: '${s['name']}', child: Container(
        decoration: BoxDecoration(color: done ? const Color(0xFF9A9A9A) : Colors.white, shape: BoxShape.circle, border: Border.all(color: done ? Colors.white : Brand.crimson, width: 3))));
    }

    return Stack(children: [
      FlutterMap(
        mapController: _mc,
        options: MapOptions(
          initialCenter: start, initialZoom: 15, minZoom: 10, maxZoom: 18,
          onMapReady: () { _ready = true; if (_shown == null) _fitAll(); },
          onPositionChanged: (camera, hasGesture) { if (hasGesture && _follow) setState(() => _follow = false); },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            fallbackUrl: 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
            userAgentPackageName: 'in.rcis.royale_connect',
            tileBuilder: dark ? darkModeTileBuilder : null,
          ),
          PolylineLayer(polylines: [
            if (ahead.length > 1) Polyline(points: ahead, color: const Color(0xFF6E6E6E), strokeWidth: 4, pattern: StrokePattern.dashed(segments: const [14, 10])),
            if (trail.length > 1) Polyline(points: trail, color: Brand.crimson, strokeWidth: 6, borderColor: Colors.white, borderStrokeWidth: 1.5),
          ]),
          MarkerLayer(markers: [
            for (final (i, s) in stops.indexed) if (_ll(s) != null) Marker(point: _ll(s)!, width: s['id'] == widget.myStopId ? 34 : 18, height: s['id'] == widget.myStopId ? 34 : 18, child: stopDot(i, s)),
            if (_shown != null) Marker(point: _shown!, width: 52, height: 52, child: Container(
              decoration: BoxDecoration(color: Brand.green, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [BoxShadow(color: Brand.green.withValues(alpha: .45), blurRadius: 14, spreadRadius: 4)]),
              child: const Center(child: Text('🚌', style: TextStyle(fontSize: 24))))),
          ]),
          const SimpleAttributionWidget(source: Text('© OpenStreetMap contributors')),
        ],
      ),
      Positioned(right: 12, top: 12, child: Column(children: [
        if (_shown != null) FloatingActionButton.small(heroTag: null, tooltip: 'Follow the bus', backgroundColor: _follow ? Brand.green : Colors.white,
            onPressed: () { setState(() => _follow = true); try { _mc.move(_shown!, math.max(_mc.camera.zoom, 15)); } catch (_) {} },
            child: Icon(Icons.directions_bus_rounded, color: _follow ? Colors.white : Brand.green)),
        const SizedBox(height: 8),
        FloatingActionButton.small(heroTag: null, tooltip: 'Whole route', backgroundColor: Colors.white,
            onPressed: () { setState(() => _follow = false); _fitAll(); }, child: const Icon(Icons.route_rounded, color: Brand.crimsonDeep)),
      ])),
    ]);
  }
}
