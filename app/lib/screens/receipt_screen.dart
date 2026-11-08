import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/config.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/school_docs.dart' show openReceiptPdf;
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/r_refresh.dart';
import '../widgets/royal_extras.dart' show GoldLoading;
import '../widgets/royal_motion.dart' show reduceMotion;
import 'family_today.dart' show classNow;

/// After paying (in the app, or back from the web payment page `/pay/done?payment_id=…`) and from a pending receipt.
/// While the bank confirms: checks again every 5 seconds for up to 2 minutes (and pull down to check at once).
/// When it is confirmed: a gold tick pops in and draws itself, "Payment received · ₹X · thank you", and the receipt
/// slides out of a slot like a printed slip (school, phones, receipt number, student, class, what was paid, total).
class ReceiptScreen extends ConsumerStatefulWidget {
  final String paymentId;
  const ReceiptScreen({super.key, required this.paymentId});
  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  Timer? _poll;
  final _started = DateTime.now();
  bool _gaveUp = false, _refreshedFees = false, _switched = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final m = ref.read(paymentProvider(widget.paymentId)).value;
      final done = m != null && (m['status'] == 'success' || m['status'] == 'failed' || m['status'] == 'refunded');
      if (done) { _poll?.cancel(); return; }
      if (DateTime.now().difference(_started).inSeconds > 120) { _poll?.cancel(); setState(() => _gaveUp = true); return; }
      ref.invalidate(paymentProvider(widget.paymentId));
    });
  }

  @override
  void dispose() { _poll?.cancel(); super.dispose(); }

  void _close() => context.go('/fees');

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(paymentProvider(widget.paymentId));
    final m = p.value;
    // back from the web payment page with two or more children: show the app for the child this payment was for
    final sess = ref.read(sessionProvider).value;
    final sid = m?['student_id'] as String?;
    if (sid != null && sess != null && sess.kind == 'student' && sess.activeStudentId != sid && sess.students.any((x) => x.id == sid) && !_switched) {
      _switched = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(sessionProvider.notifier).selectStudent(sid));
    }
    if (m?['status'] == 'success' && !_refreshedFees) {
      _refreshedFees = true;
      WidgetsBinding.instance.addPostFrameCallback((_) { ref.invalidate(feesProvider); ref.invalidate(paymentsProvider); });
    }
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(8, 4, 20, 16), child: Row(children: [
        IconButton(onPressed: _close, tooltip: 'Close', icon: const Icon(Icons.close_rounded, color: Colors.white)),
        const Text('Receipt', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      ])),
      Expanded(child: RRefresh(
        onRefresh: () async { ref.invalidate(paymentProvider(widget.paymentId)); await ref.read(paymentProvider(widget.paymentId).future).catchError((_) => null); },
        child: p.when(
          skipLoadingOnRefresh: true, skipLoadingOnReload: true,
          loading: () => const GoldLoading(),
          error: (e, _) => ListView(padding: const EdgeInsets.all(32), children: [Text(friendlyError(e), textAlign: TextAlign.center)]),
          data: (m) {
            if (m == null) {
              return ListView(padding: const EdgeInsets.all(32), children: [
                Text('This receipt could not be found on this sign-in. Payments for a brother or sister show under that child.', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 20),
                PrimaryButton('Back to fees', onPressed: _close),
              ]);
            }
            if (m['status'] == 'success') return _Paid(m: m, onDone: _close);
            return _Pending(m: m, gaveUp: _gaveUp, onDone: _close);
          },
        ),
      )),
    ]));
  }
}

// ---------------------------------------------------------------- still confirming / not completed
class _Pending extends StatelessWidget {
  final Map<String, dynamic> m; final bool gaveUp; final VoidCallback onDone;
  const _Pending({required this.m, required this.gaveUp, required this.onDone});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final failed = m['status'] == 'failed';
    final title = failed ? 'Payment not completed' : 'Confirming payment…';
    final line = failed
        ? 'The payment did not go through. If money left your account, the bank returns it by itself within a few days.'
        : gaveUp
            ? 'This is taking longer than usual. If money left your account, the receipt appears under Fees → Receipts within a few minutes. Pull down to check again.'
            : 'This usually takes under a minute. We check again every few seconds — or pull down to check now.';
    return ListView(padding: const EdgeInsets.fromLTRB(24, 40, 24, 24), children: [
      Center(child: Container(width: 76, height: 76, alignment: Alignment.center,
          decoration: BoxDecoration(color: failed ? Brand.crimsonTint : Brand.amberTint, shape: BoxShape.circle),
          child: Icon(failed ? Icons.close_rounded : Icons.hourglass_top_rounded, color: failed ? Brand.crimson : Brand.amber, size: 38))),
      const SizedBox(height: 18),
      Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(line, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, height: 1.5)),
      const SizedBox(height: 18),
      Text(inr(m['amount'] as num), textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
      if (!failed && !gaveUp) const Padding(padding: EdgeInsets.only(top: 18), child: SizedBox(height: 40, child: GoldLoading())),
      const SizedBox(height: 26),
      PrimaryButton('Back to fees', onPressed: onDone),
    ]);
  }
}

// ---------------------------------------------------------------- paid: gold tick + printed slip
class _Paid extends ConsumerStatefulWidget {
  final Map<String, dynamic> m; final VoidCallback onDone;
  const _Paid({required this.m, required this.onDone});
  @override
  ConsumerState<_Paid> createState() => _PaidState();
}

class _PaidState extends ConsumerState<_Paid> with SingleTickerProviderStateMixin {
  // 0–0.55 s tick pops in · 0.45–0.9 s the tick draws · 1.0–2.3 s the receipt slides out of the slot
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    reduceMotion(context) ? c.value = 1 : c.forward();
  }

  @override
  void dispose() { c.dispose(); super.dispose(); }

  double _seg(double a, double b, [Curve curve = Curves.easeOut]) => curve.transform(((c.value * 2.4 - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(sessionProvider).value;
    final sid = m['student_id'] as String?;
    final st = s?.students.where((x) => x.id == sid).firstOrNull;
    final cls = st == null ? '' : (st.id == s?.active?.id ? classNow(ref, st) : st.cls);
    final name = (m['student']?['full_name'] ?? st?.fullName ?? '').toString();
    final lines = [for (final l in (m['payment_line'] as List? ?? const [])) ('${l['fee_ledger']?['title'] ?? 'Fee'}', l['amount'] as num)];
    final amount = m['amount'] as num;

    return DecoratedBox(
      decoration: BoxDecoration(gradient: RadialGradient(center: const Alignment(0, -.45), radius: 1.1,
          colors: dark ? const [Color(0xFF2A2420), Color(0xFF171417)] : const [Color(0xFFFFFDF6), Color(0xFFF3EBDD)])),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 44, 20, 30), children: [
        // the gold tick
        Center(child: RepaintBoundary(child: AnimatedBuilder(animation: c, builder: (_, __) {
          final pop = _seg(0, .55, Curves.elasticOut);
          return Transform.scale(scale: pop, child: Container(width: 96, height: 96,
              decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: const RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xFFFBEFC0), Color(0xFFC9A24A), Color(0xFF9C7428)], stops: [0, .6, 1]),
                  boxShadow: [BoxShadow(color: const Color(0xFF9C7428).withValues(alpha: .55), blurRadius: 26, offset: const Offset(0, 12))]),
              child: CustomPaint(painter: _TickPainter(_seg(.45, .9, Curves.easeInOut)))));
        }))),
        const SizedBox(height: 14),
        const Text('Payment received', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
        const SizedBox(height: 2),
        Text('${inr(amount)} · thank you', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
        const SizedBox(height: 24),
        // the slot and the slip coming out of it
        Center(child: SizedBox(width: 280, child: Column(children: [
          Container(height: 11, margin: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: const Color(0xFF2A2228), borderRadius: BorderRadius.circular(6),
              boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2))])),
          Transform.translate(offset: const Offset(0, -5), child: ClipRect(child: AnimatedBuilder(animation: c, builder: (_, child) {
            final t = _seg(1.0, 2.3, const Cubic(.25, .8, .3, 1));
            return Align(alignment: Alignment.bottomCenter, heightFactor: t, child: child);
          }, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _Slip(name: name, cls: cls, receiptNo: '${m['receipt_no'] ?? '—'}',
              when: m['paid_at'] == null ? null : DateTime.parse(m['paid_at']).toLocal(), lines: lines, total: amount, mode: '${m['mode'] ?? ''}'))))),
        ]))),
        const SizedBox(height: 18),
        Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OutlinedButton.icon(onPressed: () => openReceiptPdf(context, m['id'], receiptNo: m['receipt_no']), icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('Receipt PDF — download, share or print')),
          const SizedBox(height: 10),
          PrimaryButton('Done', onPressed: widget.onDone),
        ]))),
      ]),
    );
  }
}

/// The white check mark, drawn from left to right as [t] goes 0 → 1.
class _TickPainter extends CustomPainter {
  final double t;
  _TickPainter(this.t);
  @override
  void paint(Canvas canvas, Size s) {
    if (t <= 0) return;
    final k = s.width / 96;                       // the mock: a 52-unit check (M14 27 L23 36 L39 17) in a 96 px circle
    final ox = (s.width - 52 * k) / 2, oy = (s.height - 52 * k) / 2;
    final path = Path()..moveTo(ox + 14 * k, oy + 27 * k)..lineTo(ox + 23 * k, oy + 36 * k)..lineTo(ox + 39 * k, oy + 17 * k);
    final metric = path.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * t), Paint()
      ..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 5 * k..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round);
  }
  @override
  bool shouldRepaint(_TickPainter o) => o.t != t;
}

/// The printed slip: white paper with a torn (scalloped) bottom edge.
class _Slip extends StatelessWidget {
  final String name, cls, receiptNo, mode; final DateTime? when; final List<(String, num)> lines; final num total;
  const _Slip({required this.name, required this.cls, required this.receiptNo, required this.when, required this.lines, required this.total, required this.mode});
  static const _ink = Color(0xFF2B2326), _muted = Color(0xFF7A6F72);
  @override
  Widget build(BuildContext context) {
    Widget row(String a, String b, {bool bold = false, double size = 12.5}) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(a, style: TextStyle(fontSize: size, color: bold ? _ink : _muted, fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
      const SizedBox(width: 10),
      Flexible(child: Text(b, textAlign: TextAlign.right, style: TextStyle(fontSize: size, color: _ink, fontWeight: bold ? FontWeight.w800 : FontWeight.w700))),
    ]));
    return MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: PhysicalShape(
      clipper: const _TornEdge(), color: Colors.white, elevation: 4, shadowColor: Colors.black54,
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 22), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('ROYALE CONCORDE', textAlign: TextAlign.center, style: GoogleFonts.cinzel(fontWeight: FontWeight.w700, fontSize: 15, color: Brand.crimsonDeep)),
        const Text('International School · Kalyan Nagar', textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: _muted)),
        const Text(AppConfig.officePhones, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: _muted)),
        const _Dashes(),
        row('Receipt', receiptNo, bold: true),
        if (when != null) row('Date', DateFormat('d MMM yyyy, h:mm a').format(when!)),
        row('Student', name),
        if (cls.isNotEmpty) row('Class', cls),
        const _Dashes(),
        for (final (t, a) in lines) row(t, inr(a)),
        const _Dashes(),
        row('Paid${mode.isEmpty ? '' : ' · ${mode.toUpperCase()}'}', inr(total), bold: true, size: 14),
      ])),
    ));
  }
}

class _Dashes extends StatelessWidget {
  const _Dashes();
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: LayoutBuilder(builder: (_, c) => Row(children: [
        for (var i = 0; i < (c.maxWidth / 7).floor(); i++) Container(width: 4, height: 1, margin: const EdgeInsets.only(right: 3), color: const Color(0xFFCCC4BC)),
      ])));
}

class _TornEdge extends CustomClipper<Path> {
  const _TornEdge();
  @override
  Path getClip(Size s) {
    final p = Path()..moveTo(0, 0)..lineTo(s.width, 0)..lineTo(s.width, s.height - 5);
    const w = 10.0;
    final n = math.max(1, (s.width / w).floor());
    final step = s.width / n;
    for (var i = n; i > 0; i--) {
      final x = i * step;
      p.arcToPoint(Offset(x - step, s.height - 5), radius: Radius.circular(step / 2), clockwise: true);
    }
    return p..close();
  }
  @override
  bool shouldReclip(covariant CustomClipper<Path> old) => false;
}
