import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/data3.dart' show appSettingsProvider, featureOn;
import '../widgets/royal_motion.dart';

/// Year in Review: an Instagram-style story of the child's school year (each May–June).
/// Plays by itself (about 3.6 s a slide). Tap the right side for next, the left side for back; hold to pause.
/// Slides without data are skipped. The gold end card can be shared (as a picture inside a PDF), or copied as text.
String _msg(Object e) => e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');

DateTime _nowIst() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
/// 15 May – 30 June (India time).
bool yearReviewWindowNow() { final n = _nowIst(); return (n.month == 5 && n.day >= 15) || n.month == 6; }

final yearReviewProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, studentId) async {
  ref.cacheFor();
  final r = await db.rpc('year_review', params: {'p_student': studentId});
  return r == null ? null : Map<String, dynamic>.from(r as Map);
});

const _cream = Color(0xFFF3DE9C);

class YearReviewScreen extends ConsumerWidget {
  /// Staff may open a particular student's story (preview): /year-review?student=<id>
  final String? studentId;
  const YearReviewScreen({super.key, this.studentId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    final id = studentId ?? s?.active?.id;
    final on = featureOn(ref.watch(appSettingsProvider).value, 'year_review');
    final preview = s != null && (s.isStaff || s.viewOnly);
    Widget msg(String t) => _Frame(child: Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(t, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5)))));
    if (id == null) return msg('Open this from the family app.');
    if (!on) return msg('Year in Review is not shown in the app at the moment.');
    if (!preview && !yearReviewWindowNow()) return msg('Your Year in Review opens on 15 May.');
    return ref.watch(yearReviewProvider(id)).when(
      loading: () => const _Frame(child: Center(child: CircularProgressIndicator(color: _cream))),
      error: (e, _) => msg('Could not load the story. ${_msg(e)}'),
      data: (d) => d == null ? msg('The story is not ready yet.') : _Story(d),
    );
  }
}

/// Black backdrop; on a wide screen the story sits in a tall phone-shaped card in the middle.
class _Frame extends StatelessWidget {
  final Widget child;
  const _Frame({required this.child});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, body: LayoutBuilder(builder: (_, c) {
        final wide = c.maxWidth > 620;
        if (!wide) return child;
        final h = c.maxHeight - 40;
        final w = (h * .56).clamp(320.0, 470.0);
        return Center(child: ClipRRect(borderRadius: BorderRadius.circular(26), child: SizedBox(width: w, height: h, child: child)));
      }));
}

class _Slide {
  final String key; final Gradient bg; final bool dust; final bool light;
  final Widget Function(BuildContext) build;
  const _Slide(this.key, this.bg, this.build, {this.dust = true, this.light = false});
}

class _Story extends StatefulWidget {
  final Map<String, dynamic> d;
  const _Story(this.d);
  @override
  State<_Story> createState() => _StoryState();
}

class _StoryState extends State<_Story> with SingleTickerProviderStateMixin {
  static const perSlide = Duration(milliseconds: 3600);
  late final AnimationController prog = AnimationController(vsync: this, duration: perSlide);
  late final List<_Slide> slides = _buildSlides();
  final endKey = GlobalKey();
  int i = 0;
  bool sharing = false;

  Map<String, dynamic> get d => widget.d;
  String get first => (d['first_name'] as String?)?.trim().isNotEmpty == true ? d['first_name'] as String : 'Friend';

  @override
  void initState() {
    super.initState();
    prog.addStatusListener((st) { if (st == AnimationStatus.completed && i < slides.length - 1) _go(i + 1); });
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) prog.forward(from: 0); });
  }

  @override
  void dispose() { prog.dispose(); super.dispose(); }

  void _go(int n) {
    if (n < 0) n = 0;
    if (n >= slides.length) { _close(); return; }
    setState(() => i = n);
    prog.forward(from: 0);
  }

  void _close() => context.canPop() ? context.pop() : context.go('/');

  // ------------------------------------------------------------------ slides
  List<_Slide> _buildSlides() {
    final out = <_Slide>[];
    final year = (d['year'] as String? ?? '').replaceAll('-', ' – ');
    out.add(_Slide('title', const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF9A0F15), Color(0xFF4A0609)]), (c) => Column(mainAxisSize: MainAxisSize.min, children: [
      Text('ROYALE CONNECT PRESENTS', style: GoogleFonts.cinzel(color: _cream, fontSize: 12, letterSpacing: 2.6, fontWeight: FontWeight.w700)),
      const SizedBox(height: 14),
      FadeRise(delayMs: 200, child: Text("$first's Year\nat Royale", textAlign: TextAlign.center, style: GoogleFonts.cinzel(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: 1))),
      const SizedBox(height: 10),
      FadeRise(delayMs: 600, child: GoldText(year, style: GoogleFonts.greatVibes(fontSize: 44))),
    ])));

    final days = (d['days_present'] as num?)?.toInt() ?? 0;
    if (days > 0) {
      final pct = (d['attendance_pct'] as num?)?.toDouble();
      final streak = (d['longest_streak'] as num?)?.toInt() ?? 0;
      final chips = [if (pct != null) '${pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1)}% attendance', if (streak > 1) 'longest streak $streak days'];
      out.add(_Slide('days', const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1C1230), Color(0xFF3B2266)]), (c) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('You were in school for', style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 17)),
        const SizedBox(height: 6),
        _GoldCount(days, size: 92),
        const Text('days', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        if (chips.isNotEmpty) FadeRise(delayMs: 900, child: Container(margin: const EdgeInsets.only(top: 18), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(99)),
            child: Text(chips.join(' · '), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)))),
      ])));
    }

    final leap = d['leap'] is Map ? Map<String, dynamic>.from(d['leap'] as Map) : null;
    if (leap != null && (leap['gain'] as num? ?? 0) > 0) {
      final a = (leap['from'] as num).toDouble(), b = (leap['to'] as num).toDouble();
      out.add(_Slide('leap', const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0F3B2A), Color(0xFF1E7F4F)]), (c) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Your biggest leap', style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 17)),
        const SizedBox(height: 6),
        Text('${leap['subject']}', textAlign: TextAlign.center, style: GoogleFonts.cinzel(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 18),
        SizedBox(height: 200, child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          _Bar(label: '${leap['from_exam']}', pct: a, gold: false),
          const SizedBox(width: 26),
          _Bar(label: '${leap['to_exam']}', pct: b, gold: true),
        ])),
        const SizedBox(height: 14),
        FadeRise(delayMs: 1300, child: Text('▲ ${(b - a).round()} marks out of 100', style: const TextStyle(color: _cream, fontSize: 22, fontWeight: FontWeight.w900))),
      ])));
    }

    final moments = [for (final m in (d['moments'] as List? ?? const [])) '$m'].take(4).toList();
    if (moments.isNotEmpty) {
      const tiles = [[Color(0xFFC4161E), Color(0xFFF08A2C)], [Color(0xFF1F5FB8), Color(0xFF5FB0F0)], [Color(0xFF1E8A4C), Color(0xFF8FD69A)], [Color(0xFF5B3E99), Color(0xFFC3A6F0)]];
      out.add(_Slide('moments', const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2A1A0A), Color(0xFF6B4210)]), (c) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Moments you were part of', style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 17)),
        const SizedBox(height: 16),
        GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.15, children: [
          for (final (k, m) in moments.indexed) _Pop(delayMs: 150 + k * 170, child: Container(
            padding: const EdgeInsets.all(10), alignment: Alignment.bottomLeft,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: tiles[k % 4])),
            child: Text(m, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5, height: 1.25)),
          )),
        ]),
      ])));
    }

    final house = d['house'] as String?;
    final hp = (d['house_points'] as num?)?.toInt();
    if (house != null && hp != null) {
      final rank = (d['house_rank'] as num?)?.toInt();
      final c = const {'Athena': Color(0xFFE9B90F), 'Ares': Color(0xFFC8202A), 'Artemis': Color(0xFF1E8A4C), 'Apollo': Color(0xFF1F5FB8)}[house] ?? const Color(0xFF1F5FB8);
      final deep = Color.lerp(c, Colors.black, .55)!;
      out.add(_Slide('house', LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [deep, c]), (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('This year, House $house won', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .88), fontSize: 17)),
        const SizedBox(height: 6),
        CountUp(hp.toDouble(), decimals: 0, ms: 1300, style: GoogleFonts.cormorantGaramond(color: Colors.white, fontSize: 92, fontWeight: FontWeight.w700, height: 1)),
        const Text('points', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        if (rank != null) FadeRise(delayMs: 900, child: Padding(padding: const EdgeInsets.only(top: 14), child: Text(
            rank == 1 ? '$house finished first this year!' : '$house finished ${_ordinal(rank)} this year',
            style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 15, fontWeight: FontWeight.w600)))),
      ])));
    }

    final principal = d['principal'] as String?;
    if (principal != null) {
      final sign = principal.replaceFirst(RegExp(r'^(Mrs|Ms|Mr|Dr|Miss)\.?\s+', caseSensitive: false), '');
      out.add(_Slide('principal', const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFFDF8), Color(0xFFEFE4CF)]), dust: false, light: true, (c) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('A word from the Principal', style: TextStyle(color: Color(0xFF625E66), fontSize: 15)),
        const SizedBox(height: 18),
        FadeRise(delayMs: 200, child: Text('“Dear $first, ${_lowerFirst(d['closing'] as String? ?? 'we are proud of you.')}”', textAlign: TextAlign.center,
            style: GoogleFonts.cormorantGaramond(color: const Color(0xFF171519), fontSize: 24, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, height: 1.35))),
        const SizedBox(height: 20),
        FadeRise(delayMs: 900, child: Text(sign, style: GoogleFonts.greatVibes(color: const Color(0xFF1A2A6C), fontSize: 42))),
        const Text('Principal', style: TextStyle(color: Color(0xFF625E66), fontSize: 12.5)),
      ])));
    }

    out.add(_Slide('end', const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF8E6A1E), Color(0xFFE8C97A), Color(0xFF8E6A1E)]), (c) => Column(mainAxisSize: MainAxisSize.min, children: [
      RepaintBoundary(key: endKey, child: _EndCard(first: first, summary: _summary(), year: d['year'] as String? ?? '')),
      const SizedBox(height: 22),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3A2600), foregroundColor: _cream, minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 24), shape: const StadiumBorder(), textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        onPressed: sharing ? null : _share,
        icon: sharing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _cream)) : const Icon(Icons.ios_share_rounded, size: 20),
        label: const Text('Share with family'),
      ),
    ])));
    return out;
  }

  static String _lowerFirst(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);
  static String _ordinal(int n) => switch (n) { 1 => 'first', 2 => 'second', 3 => 'third', _ => 'fourth' };

  String _summary() {
    final parts = <String>[];
    final days = (d['days_present'] as num?)?.toInt() ?? 0;
    if (days > 0) parts.add('$days days');
    final leap = d['leap'];
    if (leap is Map && (leap['gain'] as num? ?? 0) > 0) parts.add('▲${leap['gain']} in ${leap['subject']}');
    if (d['house'] != null) parts.add('House ${d['house']}');
    return parts.join(' · ');
  }

  // ------------------------------------------------------------------ share
  Future<void> _share() async {
    prog.stop();
    setState(() => sharing = true);
    final text = "$first's Year at Royale ${d['year'] ?? ''}${_summary().isEmpty ? '' : ' — ${_summary()}'}. Shine on, $first! (Royale Concorde International School)";
    try {
      final box = endKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (box == null) throw 'no card';
      final img = await box.toImage(pixelRatio: 3);
      final png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final doc = pw.Document();
      final w = img.width / 3.0, h = img.height / 3.0;
      doc.addPage(pw.Page(pageFormat: PdfPageFormat(w + 40, h + 40, marginAll: 20), build: (_) => pw.Center(child: pw.Image(pw.MemoryImage(png)))));
      await Printing.sharePdf(bytes: await doc.save(), filename: 'Year-in-Review-$first.pdf', subject: "$first's Year at Royale", body: text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied. Paste it in a message to your family.'), behavior: SnackBarBehavior.floating));
    }
    if (mounted) setState(() => sharing = false);
  }

  // ------------------------------------------------------------------ frame
  @override
  Widget build(BuildContext context) {
    final sl = slides[i];
    return _Frame(child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (e) {
        final w = context.size?.width ?? MediaQuery.sizeOf(context).width;
        final box = context.findRenderObject() as RenderBox?;
        final x = box == null ? e.globalPosition.dx : box.globalToLocal(e.globalPosition).dx;
        _go(x < w / 3 ? i - 1 : i + 1);
      },
      onLongPressStart: (_) => prog.stop(),
      onLongPressEnd: (_) { if (i < slides.length - 1) prog.forward(); },
      child: Stack(fit: StackFit.expand, children: [
        AnimatedSwitcher(
          duration: Duration(milliseconds: reduceMotion(context) ? 0 : 600),
          transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child)),
          child: DecoratedBox(key: ValueKey(sl.key), decoration: BoxDecoration(gradient: sl.bg), child: Stack(fit: StackFit.expand, children: [
            if (sl.dust) const GoldParticles(count: 28, maxRadius: 1.8),
            SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(26, 64, 26, 30), child: Center(child: SingleChildScrollView(child: Builder(builder: sl.build))))),
          ])),
        ),
        // progress bars
        Positioned(top: 0, left: 0, right: 0, child: SafeArea(bottom: false, child: Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: Column(children: [
          AnimatedBuilder(animation: prog, builder: (_, __) => Row(children: [
            for (var k = 0; k < slides.length; k++) Expanded(child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2), height: 3, clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: (sl.light ? Colors.black : Colors.white).withValues(alpha: .25)),
              child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: k < i ? 1 : k == i ? prog.value : 0,
                  child: ColoredBox(color: sl.light ? const Color(0xFF3A2A08) : Colors.white)),
            )),
          ])),
          Align(alignment: Alignment.centerRight, child: IconButton(tooltip: 'Close', onPressed: _close,
              icon: Icon(Icons.close_rounded, color: sl.light ? const Color(0xFF3A2A08) : Colors.white, size: 26))),
        ])))),
      ]),
    ));
  }
}

/// The gold card that is shared (drawn on its own gold background so the picture looks right outside the app).
class _EndCard extends StatelessWidget {
  final String first, summary, year;
  const _EndCard({required this.first, required this.summary, required this.year});
  @override
  Widget build(BuildContext context) => Container(
        width: 320, padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFB08A35), Color(0xFFF3DC9A), Color(0xFFC9A24A)]),
            border: Border.all(color: const Color(0xFFFFF1C2), width: 1.5)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('ROYALE CONCORDE', style: GoogleFonts.cinzel(color: const Color(0xFF3A2600), fontSize: 13, letterSpacing: 2.6, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          ShineSweep(delay: const Duration(milliseconds: 700), child: Text('Shine on,\n$first', textAlign: TextAlign.center,
              style: GoogleFonts.greatVibes(color: const Color(0xFF3A2600), fontSize: 54, height: 1.1))),
          if (summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(summary, textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF3A2600), fontWeight: FontWeight.w800, fontSize: 14))),
          if (year.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Year in Review · $year',
              style: TextStyle(color: const Color(0xFF3A2600).withValues(alpha: .75), fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
      );
}

class _GoldCount extends StatelessWidget {
  final int value; final double size;
  const _GoldCount(this.value, {this.size = 80});
  @override
  Widget build(BuildContext context) {
    final st = GoogleFonts.cormorantGaramond(fontSize: size, fontWeight: FontWeight.w700, height: 1);
    if (reduceMotion(context)) return GoldText('$value', style: st);
    return TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: value.toDouble()), duration: const Duration(milliseconds: 1300), curve: Curves.easeOutCubic,
        builder: (_, v, __) => GoldText('${v.round()}', style: st));
  }
}

/// One bar of the "biggest leap" slide: the gold one grows.
class _Bar extends StatelessWidget {
  final String label; final double pct; final bool gold;
  const _Bar({required this.label, required this.pct, required this.gold});
  @override
  Widget build(BuildContext context) {
    final target = 130 * (pct.clamp(0, 100) / 100);
    return SizedBox(width: 92, child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      Text('${pct.round()}%', style: TextStyle(color: gold ? _cream : Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
      const SizedBox(height: 4),
      TweenAnimationBuilder<double>(
        tween: Tween(begin: gold && !reduceMotion(context) ? 0 : target, end: target),
        duration: const Duration(milliseconds: 1200), curve: Curves.easeOutCubic,
        builder: (_, h, __) => Container(width: 58, height: h, decoration: BoxDecoration(borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            gradient: gold ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF3DE9C), Color(0xFFC9A24A)]) : null,
            color: gold ? null : Colors.white.withValues(alpha: .3))),
      ),
      const SizedBox(height: 6),
      Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 11.5, height: 1.2)),
    ]));
  }
}

/// A tile that pops in (scale up from a slight tilt).
class _Pop extends StatelessWidget {
  final Widget child; final int delayMs;
  const _Pop({required this.child, this.delayMs = 0});
  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return FutureBuilder(future: Future.delayed(Duration(milliseconds: delayMs)), builder: (_, snap) {
      if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
      return TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 560), curve: Curves.easeOutBack, child: child,
          builder: (_, v, c) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.rotate(angle: (1 - v) * -.1, child: Transform.scale(scale: .6 + .4 * v, child: c))));
    });
  }
}

/// Family Home: shown only from 15 May to 30 June (and to IT / the Principal in "View as family", to preview).
class YearReviewHomeCard extends ConsumerWidget {
  const YearReviewHomeCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    final st = s?.active;
    if (s == null || s.isStaff || st == null) return const SizedBox.shrink();
    if (!featureOn(ref.watch(appSettingsProvider).value, 'year_review')) return const SizedBox.shrink();
    if (!yearReviewWindowNow() && !s.viewOnly) return const SizedBox.shrink();
    final first = st.fullName.trim().split(RegExp(r'\s+')).first;
    final name = first.isEmpty ? '' : first[0].toUpperCase() + first.substring(1).toLowerCase();
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: ShineSweep(delay: const Duration(milliseconds: 1100), every: const Duration(seconds: 8), child: Material(
      color: Colors.transparent,
      child: InkWell(onTap: () => context.push('/year-review'), borderRadius: BorderRadius.circular(20), child: Ink(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF9A0F15), Color(0xFF4A0609)]),
            border: Border.all(color: const Color(0xFFE8C97A).withValues(alpha: .5))),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('YEAR IN REVIEW', style: GoogleFonts.cinzel(color: _cream, fontSize: 11.5, letterSpacing: 2, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            GoldText("$name's year at Royale", align: TextAlign.left, style: GoogleFonts.greatVibes(fontSize: 30, height: 1.2)),
            Text('A short story of the year · tap to play', style: TextStyle(color: Colors.white.withValues(alpha: .78), fontSize: 12.5)),
          ])),
          Container(width: 48, height: 48, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFF3DE9C), Color(0xFFC9A24A)])),
              child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF3A2600), size: 30)),
        ]),
      )),
    )));
  }
}
