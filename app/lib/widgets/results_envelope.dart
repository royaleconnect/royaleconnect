import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/school_docs.dart' show reportCardSummary;
import '../core/theme.dart';
import 'common.dart' show PrimaryButton;
import 'royal_motion.dart' show reduceMotion;

/// Results day: the first time a new report card is opened on this phone it arrives as a sealed envelope with a red
/// wax "R" seal. Tap — the seal fades, the flap opens, the card rises out and settles in front, a little larger, with
/// the grades and the overall grade; below it "Open full report (PDF)". After that the report opens directly.

const _seenKey = 'rc_env_seen';

/// Report cards already opened from their envelope on this phone.
Future<Set<String>> envelopesSeen() async => ((await SharedPreferences.getInstance()).getStringList(_seenKey) ?? const []).toSet();

Future<void> markEnvelopeSeen(String reportCardId) async {
  final p = await SharedPreferences.getInstance();
  final l = (p.getStringList(_seenKey) ?? const <String>[]).toSet()..add(reportCardId);
  await p.setStringList(_seenKey, l.toList());
}

/// The envelope as a pop-up (for a report that is not the newest one but has not been opened yet).
Future<void> showResultsEnvelope(BuildContext context, {required String reportCardId, required String term, required String year, required VoidCallback openPdf}) =>
    showGeneralDialog(context: context, barrierDismissible: true, barrierLabel: 'Close', barrierColor: Colors.black.withValues(alpha: .65),
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      pageBuilder: (c, _, __) => SafeArea(child: Center(child: Material(color: Colors.transparent, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
        ResultsEnvelope(reportCardId: reportCardId, term: term, year: year, onOpenPdf: () { Navigator.of(c).pop(); openPdf(); }, light: true),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
      ]))))));

class ResultsEnvelope extends StatefulWidget {
  final String reportCardId, term, year; final VoidCallback onOpenPdf;
  /// texts in white (on the dark pop-up background)
  final bool light;
  const ResultsEnvelope({super.key, required this.reportCardId, required this.term, required this.year, required this.onOpenPdf, this.light = false});
  @override
  State<ResultsEnvelope> createState() => _ResultsEnvelopeState();
}

class _ResultsEnvelopeState extends State<ResultsEnvelope> with SingleTickerProviderStateMixin {
  // seconds on this 2.7 s timeline: seal fades 0–0.3 · flap opens 0–0.6 · card rises 0.5–2.0 · envelope sinks 1.2–2.2
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2700));
  late final Future<({String term, String year, List<(String, String)> grades, String? overall})?> _summary =
      reportCardSummary(widget.reportCardId).then<({String term, String year, List<(String, String)> grades, String? overall})?>((v) => v).catchError((_) => null);
  bool opened = false;

  @override
  void dispose() { c.dispose(); super.dispose(); }

  void _open() {
    if (opened) return;
    setState(() => opened = true);
    HapticFeedback.mediumImpact();
    markEnvelopeSeen(widget.reportCardId);
    reduceMotion(context) ? c.value = 1 : c.forward();
  }

  double _seg(double a, double b, [Curve curve = Curves.easeInOut]) => curve.transform(((c.value * 2.7 - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = widget.light ? Colors.white : cs.onSurface;
    final sub = widget.light ? Colors.white70 : cs.onSurfaceVariant;
    return LayoutBuilder(builder: (context, box) {
      final w = math.min(300.0, box.maxWidth - 24);
      final h = w * .68;
      final room = h * .72;                       // space above the envelope for the card to rise into
      final cardH = h * .9;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${widget.term} report card is ready', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: text)),
        const SizedBox(height: 2),
        AnimatedOpacity(opacity: opened ? 0 : 1, duration: const Duration(milliseconds: 300),
            child: Text('Tap the envelope to open', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: sub))),
        GestureDetector(onTap: _open, child: SizedBox(width: w, height: room + h + 30, child: RepaintBoundary(child: AnimatedBuilder(animation: c, builder: (_, __) {
          final seal = 1 - _seg(0, .3, Curves.easeOut);
          final flap = _seg(0, .6);
          final sink = _seg(1.2, 2.2, Curves.easeOut);
          // the card: up and out (0.5–1.175 s), then down in front and a little larger (1.175–2.0 s)
          final r = _seg(.5, 2.0, const Cubic(.3, .9, .3, 1));
          final out = r < .45;
          final y = out ? -(h + 5) * (r / .45) : -(h + 5) + ((h + 5) - h * .34) * ((r - .45) / .55);
          final scale = out ? 1.0 : 1 + .14 * ((r - .45) / .55);
          final envTop = room + sink * 26;
          final envOpacity = 1 - .45 * sink;
          final card = Positioned(left: 14, right: 14, top: room + 12 + y, height: cardH, child: Transform.scale(scale: scale, child: _Card(summary: _summary, term: widget.term, year: widget.year, lifted: !out)));
          final flapWidget = Positioned(left: 0, right: 0, top: envTop, height: h * .6, child: Opacity(opacity: envOpacity, child: Transform(alignment: Alignment.topCenter,
              transform: Matrix4.identity()..setEntry(3, 2, .0016)..rotateX(math.pi * flap),
              child: ClipPath(clipper: _FlapClip(), child: const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFEADCC0), Color(0xFFD9C59E)])))))));
          return Stack(clipBehavior: Clip.none, children: [
            // back of the envelope
            Positioned(left: 0, right: 0, top: envTop, height: h, child: Opacity(opacity: envOpacity, child: DecoratedBox(decoration: BoxDecoration(color: const Color(0xFFE9DCC2), borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 14), spreadRadius: -10)])))),
            if (flap > .5) flapWidget,                 // once open, the flap stands up behind the card
            if (out) card,
            // front pocket
            Positioned(left: 0, right: 0, top: envTop, height: h, child: Opacity(opacity: envOpacity, child: ClipPath(clipper: _PocketClip(), child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF2E7D0), Color(0xFFE3D2B0)])))))),
            if (flap <= .5) flapWidget,
            // the red wax seal with the gold R
            if (seal > 0) Positioned(left: w / 2 - 23, top: envTop + h * .6 - 30, child: Opacity(opacity: seal, child: Container(width: 46, height: 46, alignment: Alignment.center,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xFFD3343B), Color(0xFF8E0D13)], stops: [0, .7]),
                    boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 6, offset: Offset(0, 3))]),
                child: Text('R', style: GoogleFonts.cinzel(fontSize: 20, fontWeight: FontWeight.w700, color: const Color(0xFFF6E3A1)))))),
            if (!out) card,
          ]);
        })))),
        const SizedBox(height: 12),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360), child: PrimaryButton('Open full report (PDF)', icon: Icons.picture_as_pdf_rounded, onPressed: () { _open(); widget.onOpenPdf(); })),
      ]);
    });
  }
}

/// The report card itself: term and year, each subject with its grade, the overall grade.
class _Card extends StatelessWidget {
  final Future<({String term, String year, List<(String, String)> grades, String? overall})?> summary;
  final String term, year; final bool lifted;
  const _Card({required this.summary, required this.term, required this.year, required this.lifted});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE6E0D6)),
            boxShadow: lifted ? const [BoxShadow(color: Color(0x73000000), blurRadius: 34, offset: Offset(0, 20), spreadRadius: -14)] : null),
        child: FutureBuilder(future: summary, builder: (_, snap) {
          final d = snap.data;
          final head = '${term.toUpperCase()} · ${d?.year ?? year}';
          return FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topCenter, child: SizedBox(width: 240, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(head, textAlign: TextAlign.center, style: GoogleFonts.cinzel(fontWeight: FontWeight.w700, fontSize: 13, color: Brand.crimsonDeep)),
            const SizedBox(height: 6),
            if (snap.connectionState != ConnectionState.done)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Brand.gold))))
            else if (d == null || d.grades.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Your report card is ready.\nOpen the full report below.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF4A3F42))))
            else ...[
              for (final (s, g) in d.grades) Container(
                padding: const EdgeInsets.symmetric(vertical: 3.5),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0EAE0)))),
                child: Row(children: [
                  Expanded(child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF3A3033)))),
                  Text(g, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF2B2326))),
                ])),
              if (d.overall != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Overall ${d.overall} ✨', textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF1E7A46)))),
            ],
          ])));
        }),
      );
}

class _PocketClip extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()..moveTo(0, 0)..lineTo(s.width / 2, s.height * .55)..lineTo(s.width, 0)..lineTo(s.width, s.height)..lineTo(0, s.height)..close();
  @override
  bool shouldReclip(covariant CustomClipper<Path> o) => false;
}

class _FlapClip extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()..moveTo(0, 0)..lineTo(s.width, 0)..lineTo(s.width / 2, s.height)..close();
  @override
  bool shouldReclip(covariant CustomClipper<Path> o) => false;
}
