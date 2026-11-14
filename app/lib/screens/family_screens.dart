import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth/session.dart';
import '../core/data2.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/empty_state.dart';
import 'academics_screens.dart' show AppPage;
import '../widgets/royal_motion.dart' show loopWhileVisible;
import '../widgets/royal_extras.dart' show GoldLoading;
import '../widgets/hub_tabs.dart';
import 'package:go_router/go_router.dart';
import '../core/data3.dart';
import '../core/config.dart';
import '../core/errors.dart';

Widget _loading() => const GoldLoading();
Widget _empty(BuildContext c, String t) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, height: 1.5))));

/// Image from the private bucket via a signed URL.
class StorageImage extends ConsumerWidget {
  final String path; final BoxFit fit; final double? width, height; final BorderRadius? radius;
  const StorageImage(this.path, {super.key, this.fit = BoxFit.cover, this.width, this.height, this.radius});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // sample albums / moments of the test school: a painted picture, no outside website needed (and no real children)
    if (path.startsWith('sample:')) return ClipRRect(borderRadius: radius ?? BorderRadius.zero, child: SizedBox(width: width, height: height, child: SamplePhoto(path)));
    final url = ref.watch(signedUrlProvider(path));
    final ph = Container(width: width, height: height, color: Theme.of(context).colorScheme.surfaceContainerHighest);
    return ClipRRect(borderRadius: radius ?? BorderRadius.zero, child: url.when(loading: () => ph, error: (_, __) => ph,
        data: (u) => LayoutBuilder(builder: (context, c) {
          // kept on the device by its file name (the web link changes every hour, the photo does not), and decoded
          // only as large as it is shown (the given width, else the space it sits in), so lists of photos scroll smoothly
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final shown = width != null && width!.isFinite ? width! : (c.hasBoundedWidth ? c.maxWidth : null);
          return CachedNetworkImage(imageUrl: u, cacheKey: path, fit: fit, width: width, height: height,
              memCacheWidth: shown == null || fit == BoxFit.contain ? null : (shown * dpr).round(),
              fadeInDuration: const Duration(milliseconds: 220), placeholder: (_, __) => ph, errorWidget: (_, __, ___) => ph);
        })));
  }
}

/// A soft "event light" picture for the sample school: deep colour, a warm glow and floating lights (the same picture
/// for the same name, so albums look stable). Marked "Sample" so nobody takes it for a real photo.
class SamplePhoto extends StatelessWidget {
  final String name;
  const SamplePhoto(this.name, {super.key});
  static const _palettes = [
    [Color(0xFF7A0E14), Color(0xFFC8102E), Color(0xFFF3C969)],   // crimson & gold
    [Color(0xFF0E3B2E), Color(0xFF1F7A5A), Color(0xFFF1D58A)],   // emerald
    [Color(0xFF1B1F4B), Color(0xFF3A4FA0), Color(0xFFF6C1A8)],   // royal blue & rose
    [Color(0xFF6B2D0B), Color(0xFFE07A1F), Color(0xFFFFE3A3)],   // saffron (festivals)
    [Color(0xFF123B4A), Color(0xFF2F8FA3), Color(0xFFE9F2C9)],   // teal (sports day)
    [Color(0xFF3D1340), Color(0xFF9B3D8F), Color(0xFFF7D6E8)],   // plum (annual day)
  ];
  @override
  Widget build(BuildContext context) {
    final seed = name.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff);
    return Stack(fit: StackFit.expand, children: [
      CustomPaint(painter: _SamplePainter(seed, _palettes[seed % _palettes.length])),
      Positioned(right: 6, bottom: 5, child: Text('Sample', style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: .6))),
    ]);
  }
}

class _SamplePainter extends CustomPainter {
  final int seed; final List<Color> p;
  _SamplePainter(this.seed, this.p);
  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    final rect = Offset.zero & size;
    final a = Alignment(r.nextDouble() * 2 - 1, -1), b = Alignment(r.nextDouble() * 2 - 1, 1);
    canvas.drawRect(rect, Paint()..shader = LinearGradient(begin: a, end: b, colors: [p[0], p[1]]).createShader(rect));
    final glow = Offset(size.width * (.25 + r.nextDouble() * .5), size.height * (.3 + r.nextDouble() * .4));
    canvas.drawCircle(glow, size.longestSide * .55, Paint()..shader = RadialGradient(colors: [p[2].withValues(alpha: .55), p[2].withValues(alpha: 0)])
        .createShader(Rect.fromCircle(center: glow, radius: size.longestSide * .55)));
    final dot = Paint();
    for (var i = 0; i < 22; i++) {
      final c = Offset(r.nextDouble() * size.width, r.nextDouble() * size.height);
      final rad = size.shortestSide * (.02 + r.nextDouble() * .09);
      dot
        ..color = (i.isEven ? p[2] : Colors.white).withValues(alpha: .10 + r.nextDouble() * .30)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rad * .35);
      canvas.drawCircle(c, rad, dot);
    }
    // a soft vignette, like a real photo
    canvas.drawRect(rect, Paint()..shader = RadialGradient(radius: .9, colors: [Colors.transparent, Colors.black.withValues(alpha: .28)]).createShader(rect));
  }
  @override
  bool shouldRepaint(covariant _SamplePainter o) => o.seed != seed;
}

// ---------------------------------------------------------------- gallery
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});
  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}
class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppPage(title: 'Gallery',
      headerExtra: Row(children: [for (final (i, l) in ['Class moments', 'School albums'].indexed) Expanded(child: GestureDetector(onTap: () => setState(() => tab = i), child: Container(
        margin: const EdgeInsets.only(right: 8), height: 36, alignment: Alignment.center, decoration: BoxDecoration(color: tab == i ? Colors.white : Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
        child: Text(l, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: tab == i ? Brand.crimsonDeep : Colors.white)))))]),
      body: tab == 0 ? _moments(cs) : _albums(cs));
  }

  Widget _moments(ColorScheme cs) {
    final m = ref.watch(momentsProvider);
    final me = ref.watch(sessionProvider).value!.active!;
    return m.when(loading: _loading, error: (e, _) => _empty(context, friendlyError(e)), data: (list) => list.isEmpty ? const EmptyState(kind: EmptyKind.photos, title: 'No class photos yet', line: 'Photos the class teacher shares from the classroom appear here.') :
      ListView.separated(padding: const EdgeInsets.all(20), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 14), itemBuilder: (_, i) {
        final mo = list[i]; final paths = List<String>.from(mo['photo_paths'] ?? []);
        final likes = (mo['moment_like'] as List); final liked = likes.any((l) => l['student_id'] == me.id);
        return Container(decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(20)), clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (paths.isNotEmpty) GestureDetector(onTap: () => _view(paths, 0), child: AspectRatio(aspectRatio: 4 / 3, child: LayoutBuilder(builder: (_, c) => StorageImage(paths.first, width: c.maxWidth, height: c.maxHeight)))),
          if (paths.length > 1) SizedBox(height: 64, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), children: [for (final (j, p) in paths.indexed) if (j > 0) Padding(padding: const EdgeInsets.only(right: 6), child: GestureDetector(onTap: () => _view(paths, j), child: StorageImage(p, width: 56, height: 56, radius: BorderRadius.circular(10))))])),
          Padding(padding: const EdgeInsets.fromLTRB(14, 10, 10, 10), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mo['caption'], style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
              Text('${mo['posted_by_staff']?['display_name'] ?? ''} · ${DateFormat('d MMM').format(DateTime.parse(mo['posted_at']).toLocal())}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ])),
            TextButton.icon(onPressed: () async { await toggleLike(mo['id'], me.id, liked); ref.invalidate(momentsProvider); },
              icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: Brand.crimson, size: 20), label: Text('${likes.length}', style: const TextStyle(color: Brand.crimson, fontWeight: FontWeight.w800))),
          ])),
        ]));
      }));
  }

  int? year;   // the school year shown in School albums (2026 = 2026-27)
  Widget _albums(ColorScheme cs) {
    final a = ref.watch(albumsProvider);
    return a.when(loading: _loading, error: (e, _) => _empty(context, friendlyError(e)), data: (list) {
      final now = DateTime.now();
      final thisYear = now.month >= 4 ? now.year : now.year - 1;
      final years = <int>{thisYear, thisYear - 1, for (final al in list) if (al['event_date'] != null) albumYear(DateTime.parse(al['event_date']))}.toList()..sort((x, y) => y.compareTo(x));
      final y = year ?? thisYear;
      final shown = [for (final al in list) if (al['event_date'] != null && albumYear(DateTime.parse(al['event_date'])) == y) al];
      return LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 1000 ? 3 : box.maxWidth >= 620 ? 2 : 1;
        return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 30), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [for (final yy in years) ChoiceChip(
            label: Text('$yy-${(yy + 1) % 100}'.replaceAllMapped(RegExp(r'-(\d)$'), (m) => '-0${m[1]}'), style: TextStyle(fontWeight: FontWeight.w800, color: yy == y ? Colors.white : null)),
            selected: yy == y, selectedColor: Brand.crimsonDeep, showCheckmark: false, onSelected: (_) => setState(() => year = yy))]),
          const SizedBox(height: 16),
          if (shown.isEmpty) const EmptyState(kind: EmptyKind.photos, title: 'No albums for this year', line: 'Each school year keeps its own events and teams.')
          else GridView.count(crossAxisCount: cols, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 1.25,
            children: [for (final al in shown) _AlbumCard(al, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AlbumScreen(al))))]),
        ]);
      });
    });
  }

  void _view(List<String> paths, int start) => Navigator.of(context).push(PageRouteBuilder(transitionDuration: const Duration(milliseconds: 450), pageBuilder: (_, __, ___) => _Viewer(paths, start),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child)));
}

/// The school year an event belongs to (April – March): 2026 means 2026-27.
int albumYear(DateTime d) => d.month >= 4 ? d.year : d.year - 1;

List<String> _albumPhotos(Map<String, dynamic> al) => (List<Map<String, dynamic>>.from(al['album_photo'] ?? [])
  ..sort((x, y) => (x['sort_order'] as int).compareTo(y['sort_order'] as int))).map((p) => p['path'] as String).toList();

class _AlbumCard extends StatelessWidget {
  final Map<String, dynamic> al; final VoidCallback onTap;
  const _AlbumCard(this.al, {required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final photos = _albumPhotos(al);
    final cover = (al['cover_path'] as String?) ?? (photos.isNotEmpty ? photos.first : null);
    final created = DateTime.tryParse('${al['created_at'] ?? ''}');
    // "New": added in the last 7 days, for a recent event (old events put in later do not shout "New")
    final ev = DateTime.tryParse('${al['event_date'] ?? ''}');
    final isNew = created != null && DateTime.now().difference(created).inDays < 7 && ev != null && DateTime.now().difference(ev).inDays <= 30;
    return Material(color: cs.surface, borderRadius: BorderRadius.circular(20), clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: Stack(fit: StackFit.expand, children: [
        cover != null ? LayoutBuilder(builder: (_, c) => StorageImage(cover, width: c.maxWidth, height: c.maxHeight)) : const _NoPhotosYet(),
        Positioned(left: 10, top: 10, child: Row(children: [
          if (al['team'] != null) const _Tag('🏅 Student team', fg: Color(0xFF6B4A08), bg: Color(0xFFF7E9C6)),
        ])),
        if (isNew) const Positioned(right: 10, top: 10, child: _Tag('New', fg: Colors.white, bg: Brand.crimson)),
      ])),
      Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(al['title'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text('${al['event_date'] != null ? DateFormat('d MMMM yyyy').format(DateTime.parse(al['event_date'])) : ''} · ${photos.isEmpty ? 'photos coming soon' : '${photos.length} photo${photos.length == 1 ? '' : 's'}'}',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
      ])),
    ])));
  }
}

class _Tag extends StatelessWidget {
  final String text; final Color fg, bg;
  const _Tag(this.text, {required this.fg, required this.bg});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.w800)));
}

class _NoPhotosYet extends StatelessWidget {
  const _NoPhotosYet();
  @override
  Widget build(BuildContext context) => Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.crimsonDeep, Brand.crimson])),
      child: Center(child: Icon(Icons.photo_library_rounded, size: 40, color: Colors.white.withValues(alpha: .5))));
}

/// One event: the student team card on top (when there is one), then the photos.
class AlbumScreen extends StatelessWidget {
  final Map<String, dynamic> al;
  const AlbumScreen(this.al, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final photos = _albumPhotos(al);
    final team = al['team'] is Map ? Map<String, dynamic>.from(al['team']) : null;
    return AppPage(title: al['title'], body: LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 900 ? 5 : box.maxWidth >= 600 ? 4 : 3;
      final cell = (box.maxWidth - 40 - 8 * (cols - 1)) / cols;
      return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 30), children: [
        if (al['event_date'] != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(DateFormat('d MMMM yyyy').format(DateTime.parse(al['event_date'])), style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700))),
        if (team != null) TeamCard(team),
        if (photos.isEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Photos of this event will appear here soon.', style: TextStyle(color: cs.onSurfaceVariant)))
        else Wrap(spacing: 8, runSpacing: 8, children: [for (final (i, p) in photos.indexed) GestureDetector(
          onTap: () => Navigator.of(context).push(PageRouteBuilder(transitionDuration: const Duration(milliseconds: 450), pageBuilder: (_, __, ___) => _Viewer(photos, i), transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child))),
          child: Hero(tag: 'ph$p', child: StorageImage(p, width: cell, height: cell, radius: BorderRadius.circular(14))))]),
      ]);
    }));
  }
}

/// "The student team behind …": names only, all the same size. Teachers who guided it on top; the Council helpers below;
/// a thank-you to all teachers and staff at the end.
class TeamCard extends StatelessWidget {
  final Map<String, dynamic> team;
  const TeamCard(this.team, {super.key});
  static const _gold = Color(0xFFA8822F), _ink = Color(0xFF5A3A06);
  List<List<String>> _rows(String k) => [for (final r in (team[k] as List? ?? const [])) [for (final x in (r as List)) '$x']];
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final soft = Theme.of(context).colorScheme.onSurfaceVariant;
    final guide = _rows('guide'), lead = _rows('lead'), support = _rows('support');
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(t, style: const TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w900, color: _gold)));
    Widget people(List<List<String>> rows, {bool small = false}) => LayoutBuilder(builder: (_, c) {
      final per = c.maxWidth >= 720 ? 3 : c.maxWidth >= 440 ? 2 : 1;
      final w = (c.maxWidth - 8 * (per - 1)) / per;
      return Wrap(spacing: 8, runSpacing: 8, children: [for (final r in rows) Container(width: w, padding: EdgeInsets.symmetric(horizontal: 12, vertical: small ? 8 : 10),
        decoration: BoxDecoration(color: dark ? const Color(0xFF2A2420) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF0E3C4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.first, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _gold)),
          const SizedBox(height: 2),
          Text(r.length > 1 ? r[1] : '', style: TextStyle(fontSize: small ? 14 : 15, fontWeight: FontWeight.w800)),
        ]))]);
    });
    return Container(margin: const EdgeInsets.only(bottom: 18), clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE7CF8E)),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: dark ? const [Color(0xFF2B241B), Color(0xFF241E17)] : const [Color(0xFFFFFCF4), Color(0xFFFFF8E8)])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 4, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFC9A24A), Color(0xFFF3DE9C), Color(0xFFC9A24A)]))),
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('🏅', style: TextStyle(fontSize: 20)), const SizedBox(width: 8),
            Expanded(child: Text('${team['title'] ?? 'The student team'}', style: GoogleFonts.playfairDisplay(fontSize: 21, fontWeight: FontWeight.w700, color: dark ? const Color(0xFFF1D58A) : _ink))),
          ]),
          if ((team['note'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${team['note']}', style: TextStyle(color: soft, height: 1.4))),
          if (guide.isNotEmpty) ...[label('GUIDED BY'), people(guide)],
          label(support.isNotEmpty ? 'LED BY' : 'STUDENTS'), people(lead),
          if (support.isNotEmpty) ...[label('WITH SUPPORT FROM THE STUDENT COUNCIL'), people(support, small: true),
            Padding(padding: const EdgeInsets.only(top: 12), child: Text('With help from all the other members of the Student Council.', style: TextStyle(color: soft, fontStyle: FontStyle.italic)))],
          const SizedBox(height: 12),
          Container(height: 1, color: const Color(0xFFF0E3C4)),
          Padding(padding: const EdgeInsets.only(top: 10), child: Text('With grateful thanks to our teachers and staff, whose guidance and hard work made it all possible.', style: TextStyle(color: soft, fontStyle: FontStyle.italic))),
        ])),
      ]));
  }
}

class _Viewer extends StatelessWidget {
  final List<String> paths; final int start;
  const _Viewer(this.paths, this.start);
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: PageView(controller: PageController(initialPage: start), children: [for (final p in paths) InteractiveViewer(child: Center(child: Hero(tag: 'ph$p', child: _SlowDrift(child: StorageImage(p, fit: BoxFit.contain)))))]));
}

// ---------------------------------------------------------------- leave
class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});
  static const st = {'pending': (Brand.amber, Brand.amberTint), 'approved': (Brand.green, Brand.greenTint), 'rejected': (Brand.crimsonDeep, Brand.crimsonTint)};
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaves = ref.watch(leavesProvider);
    final cs = Theme.of(context).colorScheme;
    return AppPage(title: 'Leave', hub: Hub.attendance, actions: [TextButton.icon(onPressed: () => _apply(context, ref), icon: const Icon(Icons.add_rounded, color: Colors.white), label: const Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)))],
      body: leaves.when(loading: _loading, error: (e, _) => _empty(context, friendlyError(e)), data: (list) => list.isEmpty ? const EmptyState(kind: EmptyKind.calendar, title: 'No leave applied', line: 'Tap Apply to inform the class teacher.') :
        ListView(padding: const EdgeInsets.all(20), children: [for (final l in list) Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Pill(l['status'], fg: (st[l['status']] ?? (Brand.muted, Brand.surface2)).$1, bg: (st[l['status']] ?? (Brand.muted, Brand.surface2)).$2), const Spacer(),
            Text(l['from_date'] == l['to_date'] ? DateFormat('d MMM yyyy').format(DateTime.parse(l['from_date'])) : '${DateFormat('d MMM').format(DateTime.parse(l['from_date']))} – ${DateFormat('d MMM yyyy').format(DateTime.parse(l['to_date']))}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))]),
          const SizedBox(height: 8),
          Text(l['reason'], style: const TextStyle(fontWeight: FontWeight.w700)),
          if (l['note'] != null) Text(l['note'], style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          if (l['decided_at'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${l['status'] == 'approved' ? 'Approved' : 'Declined'} by ${l['decided_by_staff']?['display_name'] ?? 'class teacher'} · ${DateFormat('d MMM').format(DateTime.parse(l['decided_at']).toLocal())}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
        ]))])));
  }

  void _apply(BuildContext context, WidgetRef ref) {
    DateTime from = DateTime.now(), to = DateTime.now(); String reason = 'Sick'; final note = TextEditingController(); bool busy = false;
    showModalBottomSheet(context: context, isScrollControlled: true, showDragHandle: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Apply for leave', style: Theme.of(ctx).textTheme.headlineSmall), const SizedBox(height: 14),
      Row(children: [for (final (i, l) in ['From', 'To'].indexed) Expanded(child: Padding(padding: EdgeInsets.only(right: i == 0 ? 8 : 0), child: OutlinedButton.icon(onPressed: () async {
        final d = await showDatePicker(context: ctx, initialDate: i == 0 ? from : to, firstDate: DateTime.now().subtract(const Duration(days: 7)), lastDate: DateTime.now().add(const Duration(days: 120)));
        if (d != null) set(() { if (i == 0) { from = d; if (to.isBefore(from)) to = from; } else { to = d.isBefore(from) ? from : d; } });
      }, icon: const Icon(Icons.event_rounded, size: 18), label: Text('$l ${DateFormat('d MMM').format(i == 0 ? from : to)}'))))]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [for (final r in ['Sick', 'Family function', 'Travel', 'Medical appointment', 'Other']) ChoiceChip(label: Text(r), selected: reason == r, onSelected: (_) => set(() => reason = r))]),
      const SizedBox(height: 12),
      TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Note for the class teacher (optional)')),
      const SizedBox(height: 16),
      PrimaryButton('Send to class teacher', busy: busy, onPressed: () async {
        set(() => busy = true);
        try { await applyLeave(ref.read(sessionProvider).value!.active!.id, from, to, reason, note.text.trim().isEmpty ? null : note.text.trim()); ref.invalidate(leavesProvider); if (ctx.mounted) Navigator.pop(ctx); }
        catch (e) { set(() => busy = false); if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(friendlyError(e)))); }
      }),
    ]))));
  }
}

// ---------------------------------------------------------------- profile
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}
class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final p = ref.watch(profileProvider); final e = ref.watch(enrolmentProvider); final r = ref.watch(routeDetailProvider);
    final cs = Theme.of(context).colorScheme;
    final tabs = ['Student', 'Academic', if (r.value != null) 'Transport'];
    Widget row(String k, String? v) => v == null || v.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 130, child: Text(k, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))), Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700)))]));
    return AppPage(title: 'Profile',
      headerExtra: Row(children: [for (final (i, l) in tabs.indexed) Expanded(child: GestureDetector(onTap: () => setState(() => tab = i), child: Container(margin: const EdgeInsets.only(right: 8), height: 36, alignment: Alignment.center,
        decoration: BoxDecoration(color: tab == i ? Colors.white : Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)), child: Text(l, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: tab == i ? Brand.crimsonDeep : Colors.white)))))]),
      body: p.when(loading: _loading, error: (err, _) => _empty(context, friendlyError(err)), data: (m) {
        if (m == null) return _empty(context, 'Profile not available.');
        final sec = e.value?['section']; final phones = List<Map<String, dynamic>>.from(m['family_phone'] ?? []);
        return ListView(padding: const EdgeInsets.all(20), children: [
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(20)), child: Row(children: [
            m['photo_path'] != null ? StorageImage(m['photo_path'], width: 64, height: 64, radius: BorderRadius.circular(20)) : Avatar(m['full_name'].toString().split(' ').take(2).map((w) => w[0]).join(), size: 64),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m['full_name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), Text('${sec?['grade']?['name'] ?? ''} ${shownSection(sec) ?? '(section to be announced)'} · ${m['admission_no']}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))])),
          ])),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(20)), child: Column(children: [
            if (tabs[tab] == 'Student') ...[
              row('Date of birth', m['dob'] == null ? null : DateFormat('d MMMM yyyy').format(DateTime.parse(m['dob']))), row('Gender', m['gender']), row('Blood group', m['blood_group']), row('House', m['house']),
              row('Father', m['father_name']), row('Mother', m['mother_name']), row('Guardian', m['guardian_name']),
              for (final ph in phones) row(ph['label'] ?? 'Phone', ph['phone']),
              row('Address', m['address']),
            ] else if (tabs[tab] == 'Academic') ...[
              row('Academic year', e.value?['academic_year']?['label']), row('Class', '${sec?['grade']?['name'] ?? ''} – ${shownSection(sec) ?? 'section to be announced'}'), row('Roll number', e.value?['roll_no']?.toString()),
              row('Class teacher', sec?['class_teacher']?['display_name']), row('Admission type', m['admission_type']), row('Division', sec?['grade']?['division']?.toString()),
            ] else ...[
              row('Route', r.value?['name']), row('Bus', r.value?['bus_reg_no']), row('Stop', r.value?['my_stop']?['name']),
              row('Morning pickup', r.value?['my_stop']?['morning_eta']?.toString().substring(0, 5)), row('Afternoon drop', r.value?['my_stop']?['afternoon_eta']?.toString().substring(0, 5)),
              row('Driver', r.value?['driver']?['display_name']), row('Conductor', r.value?['conductor']?['display_name']),
            ],
          ])),
          const SizedBox(height: 12),
          const NoteBox('To correct any detail, message the class teacher or write to the school office. Changes are made by the office only.'),
          const SizedBox(height: 12),
          _ProfileActions(),
        ]);
      }));
  }
}

/// ID card · switch child · password · help & feedback · call the school office.
class _ProfileActions extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(sessionProvider).value;
    final settings = ref.watch(appSettingsProvider).value;
    Widget tile(IconData ic, String t, String sub, VoidCallback onTap, {Color? colour}) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
      leading: CircleAvatar(backgroundColor: (colour ?? Brand.crimson).withValues(alpha: .12), child: Icon(ic, color: colour ?? Brand.crimsonDeep, size: 20)),
      title: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(sub, style: TextStyle(color: cs.onSurfaceVariant)),
      trailing: const Icon(Icons.chevron_right_rounded), onTap: onTap));
    return Column(children: [
      if (featureOn(settings, 'idcard')) tile(Icons.badge_rounded, 'ID card', 'Show it at the gate or on the bus', () => context.push('/idcard'), colour: Brand.violet),
      if ((s?.students.length ?? 0) > 1) tile(Icons.swap_horiz_rounded, 'Switch child', s!.students.map((x) => x.fullName.split(' ').first).join(' · '), () => context.push('/students')),
      tile(Icons.lock_reset_rounded, 'Change password', 'And other settings', () => context.push('/settings'), colour: Brand.blue),
      tile(Icons.privacy_tip_outlined, 'Privacy policy', 'What we keep, why, and who sees it', () => context.push('/privacy'), colour: Brand.violet),
      tile(Icons.help_outline_rounded, 'Help & feedback', 'How to use the app · send us your thoughts', () => context.push('/help'), colour: Brand.green),
      tile(Icons.call_rounded, 'Call school office', AppConfig.officePhonesShort, () => launchUrl(Uri.parse('tel:${AppConfig.officePhone}')), colour: Brand.amber),
    ]);
  }
}

// ---------------------------------------------------------------- feedback
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});
  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}
class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  String cat = 'Suggestion'; bool anon = false, busy = false; final subj = TextEditingController(), body = TextEditingController();
  @override
  Widget build(BuildContext context) => AppPage(title: 'Feedback', body: ListView(padding: const EdgeInsets.all(20), children: [
    Wrap(spacing: 8, children: [for (final c in ['Suggestion', 'Appreciation', 'Concern', 'Transport', 'Fees', 'App']) ChoiceChip(label: Text(c), selected: cat == c, onSelected: (_) => setState(() => cat = c))]),
    const SizedBox(height: 14),
    TextField(controller: subj, decoration: const InputDecoration(labelText: 'Subject')), const SizedBox(height: 12),
    TextField(controller: body, maxLines: 5, decoration: const InputDecoration(labelText: 'Your message')), const SizedBox(height: 8),
    SwitchListTile(value: anon, onChanged: (v) => setState(() => anon = v), title: const Text('Send anonymously'), subtitle: const Text('The office sees the class, not the name'), contentPadding: EdgeInsets.zero),
    const SizedBox(height: 10),
    PrimaryButton('Send to the school office', busy: busy, onPressed: () async {
      if (subj.text.trim().isEmpty || body.text.trim().isEmpty) return;
      setState(() => busy = true);
      try {
        final s = ref.read(sessionProvider).value!.active!; final e = await ref.read(enrolmentProvider.future);
        await sendFeedback(s.id, e?['section']?['id'], cat, subj.text.trim(), body.text.trim(), anon);
        if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you — sent to the office.'))); Navigator.pop(context); }
      } catch (err) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(err)))); }
      if (mounted) setState(() => busy = false);
    }),
  ]));
}

Future<void> callNumber(String? n) async { if (n != null && n.isNotEmpty) await launchUrl(Uri.parse('tel:$n')); }


/// A slow, film-like zoom while a photo is open.
class _SlowDrift extends StatefulWidget {
  final Widget child;
  const _SlowDrift({required this.child});
  @override
  State<_SlowDrift> createState() => _SlowDriftState();
}

class _SlowDriftState extends State<_SlowDrift> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 14));
  @override
  void didChangeDependencies() { super.didChangeDependencies(); loopWhileVisible(context, c, reverse: true); }
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context) ? widget.child
      : AnimatedBuilder(animation: c, child: widget.child, builder: (_, child) => Transform.scale(scale: 1 + .06 * Curves.easeInOut.transform(c.value), child: child));
}
