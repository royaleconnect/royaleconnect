import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/brand_images.dart';
import '../core/data.dart';
import '../core/data2.dart';
import '../core/data3.dart';
import '../widgets/royal_motion.dart';
import 'academics_screens.dart' show AppPage;
import 'family_screens.dart' show StorageImage;

/// The student's ID card, exactly like the printed one: yellow for bus students, purple for the others.
/// Move the mouse over it (or drag a finger) for the hologram shine; tap to turn it over.
class IdCardScreen extends ConsumerWidget {
  const IdCardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider).value;
    final e = ref.watch(enrolmentProvider).value;
    final bus = ref.watch(transportProvider).value;
    final route = ref.watch(routeDetailProvider).value;
    final year = ref.watch(yearLabelProvider).value;
    final settings = ref.watch(appSettingsProvider).value;
    if (p == null) return const AppPage(title: 'ID card', body: Center(child: CircularProgressIndicator()));
    final phones = List<Map<String, dynamic>>.from(p['family_phone'] ?? const []);
    String? phoneFor(String who) => (phones.where((x) => (x['label'] ?? '').toString().toLowerCase().contains(who)).firstOrNull ?? (phones.isEmpty ? null : phones[who == 'father' ? 0 : math.min(1, phones.length - 1)]))?['phone'];
    final data = IdCardData(
      name: (p['full_name'] ?? '').toString(), admNo: (p['admission_no'] ?? '').toString(), blood: p['blood_group'],
      father: p['father_name'], fatherPhone: phoneFor('father'), mother: p['mother_name'], motherPhone: phoneFor('mother'),
      grade: (e?['section']?['grade']?['code'] ?? '').toString(), photoPath: p['photo_path'], address: p['address'],
      route: bus == null ? null : RegExp(r'\d+').firstMatch((route?['name'] ?? bus['route']?['name'] ?? '').toString())?.group(0) ?? (route?['name'] ?? '').toString(),
      year: _yearText(year), principal: (settings?['principal_name'] ?? 'Principal').replaceFirst(RegExp(r'^(Mrs?|Ms|Dr)\.?\s+'), ''),
    );
    return AppPage(title: 'ID card', body: ListView(padding: const EdgeInsets.all(20), children: [
      Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 340), child: IdCard(data: data))),
      const SizedBox(height: 16),
      Text('Tap the card to turn it over. Show it at the gate or on the bus.', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]));
  }
  static String _yearText(String? y) {
    final m = RegExp(r'(\d{4})\D+(\d{2,4})').firstMatch(y ?? '');
    if (m == null) return y ?? '';
    final b = m.group(2)!;
    return '${m.group(1)} - ${b.length == 2 ? '20$b' : b}';
  }
}

class IdCardData {
  final String name, admNo, grade, year, principal; final String? blood, father, fatherPhone, mother, motherPhone, photoPath, address, route;
  const IdCardData({required this.name, required this.admNo, required this.grade, required this.year, required this.principal,
    this.blood, this.father, this.fatherPhone, this.mother, this.motherPhone, this.photoPath, this.address, this.route});
  bool get bus => route != null;
}

class IdCard extends StatefulWidget {
  final IdCardData data;
  const IdCard({super.key, required this.data});
  @override
  State<IdCard> createState() => _IdCardState();
}

class _IdCardState extends State<IdCard> with SingleTickerProviderStateMixin {
  late final AnimationController idle = AnimationController(vsync: this, duration: const Duration(seconds: 7));
  Offset? pointer;          // 0..1 inside the card while the mouse / finger is on it
  bool back = false;
  @override
  void didChangeDependencies() { super.didChangeDependencies(); loopWhileVisible(context, idle); }
  @override
  void dispose() { idle.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AspectRatio(aspectRatio: 300 / 476, child: LayoutBuilder(builder: (_, box) {
    void move(Offset local) => setState(() => pointer = Offset((local.dx / box.maxWidth).clamp(0, 1), (local.dy / box.maxHeight).clamp(0, 1)));
    return MouseRegion(onHover: (e) => move(e.localPosition), onExit: (_) => setState(() => pointer = null),
      child: GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); setState(() => back = !back); },
        onPanUpdate: (e) => move(e.localPosition), onPanEnd: (_) => setState(() => pointer = null),
        child: TweenAnimationBuilder<double>(tween: Tween(end: back ? math.pi : 0), duration: const Duration(milliseconds: 700), curve: Curves.easeInOutCubic,
          builder: (_, flip, __) => AnimatedBuilder(animation: idle, builder: (_, __) {
            final t = idle.value * 2 * math.pi;
            final pt = pointer ?? Offset(.5 + math.sin(t) * .3, .5 + math.cos(t * .8) * .22);
            final showBack = flip > math.pi / 2;
            final m = Matrix4.identity()..setEntry(3, 2, .0012)
              ..rotateY(flip + (pt.dx - .5) * .4)..rotateX((.5 - pt.dy) * .34);
            final face = FittedBox(child: SizedBox(width: 300, height: 476, child: showBack ? _Back(widget.data) : _Front(widget.data)));
            return Transform(alignment: Alignment.center, transform: m, child: Transform(alignment: Alignment.center, transform: Matrix4.rotationY(showBack ? math.pi : 0),
              child: DecoratedBox(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x55281410), blurRadius: 30, offset: Offset(0, 18))]),
                child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Stack(fit: StackFit.expand, children: [
                  face,
                  // the hologram: a band of gold, mint and pink light that follows the mouse / finger
                  IgnorePointer(child: Opacity(opacity: .22, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                    begin: Alignment(-1.6 + pt.dx * 2.2, -1.2 + pt.dy * 1.2), end: Alignment(.4 + pt.dx * 2.2, 1.2 + pt.dy * 1.2),
                    colors: const [Colors.transparent, Color(0xFFFFD782), Color(0xFF96FFE1), Color(0xFFFFA0E1), Colors.transparent], stops: const [.2, .38, .46, .54, .7]))))),
                  IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(center: Alignment(pt.dx * 2 - 1, pt.dy * 2 - 1), radius: .7,
                      colors: [Colors.white.withValues(alpha: .28), Colors.transparent])))),
                ])),
              )));
          }),
        )));
  }));
}

/// A still picture of one side of the card, no animation (the office ID cards page shows many at once).
class IdCardFace extends StatelessWidget {
  final IdCardData data; final bool back;
  const IdCardFace(this.data, {super.key, this.back = false});
  @override
  Widget build(BuildContext context) => RepaintBoundary(child: AspectRatio(aspectRatio: 300 / 476, child: ClipRRect(borderRadius: BorderRadius.circular(8),
      child: FittedBox(child: SizedBox(width: 300, height: 476, child: back ? _Back(data) : _Front(data))))));
}

const _yellow = [Color(0xFFF8C537), Color(0xFFF2A61C)];
const _purple = [Color(0xFF7A4BB8), Color(0xFF58308F)];

class _Front extends StatelessWidget {
  final IdCardData d;
  const _Front(this.d);
  @override
  Widget build(BuildContext context) {
    final band = d.bus ? _yellow : _purple;
    final accent = d.bus ? const Color(0xFFEE8A22) : const Color(0xFF6A3FA8);
    final nameColour = d.bus ? const Color(0xFF8E1B1B) : Colors.white;
    final serif = GoogleFonts.cormorantGaramond(fontWeight: FontWeight.w700, color: nameColour, height: 1.02);
    Widget row(IconData ic, String? text, {bool phone = false}) => text == null || text.isEmpty ? const SizedBox(height: 28) : SizedBox(height: 28, child: Row(children: [
      Container(width: 16, height: 16, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF2A65A)), child: Icon(ic, size: 10, color: const Color(0xFF7A4A1A))),
      const SizedBox(width: 12),
      Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: phone ? const Color(0xFF6B3FB6) : const Color(0xFF333333)))),
    ]));
    return ColoredBox(color: Colors.white, child: Stack(children: [
      Positioned(left: 0, right: 0, top: 0, height: 250, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: band)))),
      Positioned(left: 150 - 320, top: 150, width: 640, height: 640, child: const DecoratedBox(decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
      Positioned(left: 10, top: 20, width: 48, child: Image.memory(logoClear, fit: BoxFit.contain)),
      Positioned(left: 60, right: 8, top: 14, child: Column(children: [
        Text('ROYALE CONCORDE', style: serif.copyWith(fontSize: 17.5, letterSpacing: .6)),
        Text('INTERNATIONAL SCHOOL', style: serif.copyWith(fontSize: 14.5, letterSpacing: .6)),
        const SizedBox(height: 3),
        Text('Kalyan Nagar, Bangalore - 560043', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: nameColour)),
      ])),
      Positioned(left: 94, top: 76, width: 112, height: 134, child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF2A2A2A), width: 2.5), color: const Color(0xFF2F7D6D)),
        clipBehavior: Clip.antiAlias,
        child: d.photoPath != null ? StorageImage(d.photoPath!, width: 112, height: 134)
            : Center(child: Text(d.name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase(),
                style: GoogleFonts.cinzel(fontSize: 34, fontWeight: FontWeight.w700, color: Colors.white))))),
      if ((d.blood ?? '').isNotEmpty) Positioned(right: 18, top: 150, child: Column(children: [
        const Icon(Icons.water_drop_rounded, color: Color(0xFFD0242B), size: 24),
        Text(d.blood!.contains('ve') ? d.blood! : '${d.blood}ve', style: const TextStyle(color: Color(0xFFD0242B), fontWeight: FontWeight.w800, fontSize: 12)),
      ])),
      Positioned(left: 26, right: 44, top: 226, child: Text(d.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFFC3262E), fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: .3))),
      Positioned(left: 26, right: 44, top: 258, child: Text('Adm # : ${d.admNo}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF1D1D1D)))),
      Positioned(left: 26, right: 50, top: 290, child: Column(children: [
        row(Icons.person_rounded, d.father), row(Icons.call_rounded, d.fatherPhone, phone: true),
        row(Icons.person_rounded, d.mother), row(Icons.call_rounded, d.motherPhone, phone: true),
      ])),
      Positioned(right: 10, top: 290, bottom: 70, child: RotatedBox(quarterTurns: 3, child: Center(child: Text('Grade - ${d.grade}', style: TextStyle(color: accent, fontSize: 24, fontWeight: FontWeight.w500))))),
      Positioned(right: 16, bottom: 12, child: Column(children: [
        Text(d.principal.split(' ').first, style: GoogleFonts.greatVibes(fontSize: 24, color: const Color(0xFF2F7A3A), height: .9)),
        const Text('Principal', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2E6B35))),
      ])),
    ]));
  }
}

class _Back extends StatelessWidget {
  final IdCardData d;
  const _Back(this.d);
  @override
  Widget build(BuildContext context) {
    final band = d.bus ? _yellow : _purple;
    final bandText = d.bus ? const Color(0xFF2A1A00) : Colors.white;
    const label = TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1D1D1D));
    return ColoredBox(color: Colors.white, child: Column(children: [
      Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (d.bus) ...[
          Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5), decoration: BoxDecoration(color: const Color(0xFF5B2E9E), borderRadius: BorderRadius.circular(99)),
              child: const Text('School Transport', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)))),
          const SizedBox(height: 10),
          Row(children: [
            Container(width: 30, height: 30, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFE5452F), border: Border.all(color: Colors.white, width: 2)),
                child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 16)),
            Container(transform: Matrix4.translationValues(-6, 0, 0), padding: const EdgeInsets.fromLTRB(14, 4, 12, 4), color: const Color(0xFFE5452F),
                child: const Text('Route No :', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE5452F), width: 2)),
                child: Text(d.route ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22))),
          ]),
          const SizedBox(height: 8),
        ],
        Row(children: [const Text('Name :  ', style: label), Expanded(child: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: label.copyWith(fontWeight: FontWeight.w700)))]),
        const SizedBox(height: 7),
        Row(children: [
          Container(width: 22, height: 22, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF222222)), child: const Icon(Icons.call_rounded, color: Colors.white, size: 12)),
          Text('  :  ${d.fatherPhone ?? d.motherPhone ?? ''}', style: label),
        ]),
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), decoration: BoxDecoration(color: const Color(0xFFDCEAF6), borderRadius: BorderRadius.circular(8)),
          child: Column(children: [
            Container(width: 24, height: 24, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF173E86)), child: const Icon(Icons.home_rounded, color: Colors.white, size: 14)),
            const SizedBox(height: 4),
            Text(d.address ?? '', maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.4)),
          ])),
        // the logo takes the space that is left, so it never touches the address or the band
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 160, maxHeight: 62),
            child: Image.memory(logoClear, fit: BoxFit.contain))))),
      ]))),
      Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(10, 6, 10, 5), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: band)),
        child: Text('6th B Main, HRBR Layout, 2nd Block, Kalyan Nagar, Bengaluru - 560043\nPh : 080-25435454/55   Mob : 9535216115', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9.6, fontWeight: FontWeight.w700, color: bandText, height: 1.35))),
      Container(color: band.last, padding: const EdgeInsets.fromLTRB(12, 0, 12, 10), child: Container(width: double.infinity, color: const Color(0xFF1B1B1B), padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text('Academic Year ${d.year}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)))),
    ]));
  }
}
