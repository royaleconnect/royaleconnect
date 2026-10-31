import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/data3.dart';
import '../core/signature_data.dart';
import '../core/theme.dart';
import '../widgets/royal_motion.dart';
import 'family_screens.dart' show StorageImage;

/// From the Principal's Desk.
/// • The Principal's welcome shows full screen the first time anyone opens the app (one for families, one for staff).
/// • Each new message (RoMUN, RoAI Hackathon, Annual Day, Sports Day …) shows full screen once, on everyone's next
///   opening, in a design picked from its title; after that it stays in "From the Principal's Desk".
/// Which messages were already shown is remembered on the phone.

class DeskMessage {
  final String id, kind, audience, title, body;
  final String? picturePath, linkUrl, linkLabel;
  final DateTime createdAt;
  final String? endsOn;
  final bool active;
  DeskMessage.fromRow(Map<String, dynamic> r)
      : id = r['id'] as String, kind = r['kind'] as String, audience = r['audience'] as String,
        title = (r['title'] ?? '') as String, body = (r['body'] ?? '') as String,
        picturePath = (r['picture_path'] as String?)?.isEmpty ?? true ? null : r['picture_path'] as String,
        linkUrl = (r['link_url'] as String?)?.isEmpty ?? true ? null : r['link_url'] as String,
        linkLabel = r['link_label'] as String?,
        createdAt = DateTime.parse(r['created_at'] as String).toLocal(),
        endsOn = r['ends_on'] as String?, active = r['active'] != false;
  bool get isWelcome => kind == 'welcome';
  bool forMe(bool staff) => audience == 'everyone' || audience == (staff ? 'staff' : 'families');
  DeskTheme get theme => isWelcome ? DeskTheme.royal : DeskTheme.forTitle(title);
}

/// Every message this person may see, newest first (the database already hides the others).
final deskMessagesProvider = FutureProvider.autoDispose<List<DeskMessage>>((ref) async {
  ref.watch(sessionProvider);
  final rows = await db.from('principal_message').select().order('created_at', ascending: false).limit(200);
  return [for (final r in rows) DeskMessage.fromRow(Map<String, dynamic>.from(r))];
});

/// The Principal's name and photo, as set on the Principal's Desk page.
({String name, String? photo}) principalInfo(Map<String, String>? settings) {
  final n = (settings?['principal_name'] ?? '').trim();
  final p = (settings?['principal_photo'] ?? '').trim();
  return (name: n.isEmpty ? 'Mrs. Rekha Vinod' : n, photo: p.isEmpty ? null : p);
}

String _viewerKey(Session s) => s.isStaff ? 's:${s.staff?['id']}' : 'f:${([for (final x in s.students) x.id]..sort()).join(',')}';

Future<Set<String>> _seen(Session s) async => ((await SharedPreferences.getInstance()).getStringList('rc_desk_${_viewerKey(s)}') ?? const []).toSet();

/// Remember that [m] was shown (and, for an event, every older event too, so only the newest one is ever shown).
Future<void> markDeskSeen(Session s, DeskMessage m, List<DeskMessage> all) async {
  final p = await SharedPreferences.getInstance();
  final k = 'rc_desk_${_viewerKey(s)}';
  final set = (p.getStringList(k) ?? const []).toSet()..add(m.id);
  if (!m.isWelcome) set.addAll(all.where((x) => !x.isWelcome).map((x) => x.id));
  await p.setStringList(k, set.toList());
}

/// The message to show full screen now, if any: first the welcome, later the newest event message.
final deskPendingProvider = FutureProvider.autoDispose<DeskMessage?>((ref) async {
  final s = ref.watch(sessionProvider).value;
  if (s == null || s.viewOnly || s.kind == 'crew') return null;
  final all = (await ref.watch(deskMessagesProvider.future)).where((m) => m.active && m.forMe(s.isStaff)).toList();
  final seen = await _seen(s);
  for (final m in all) { if (m.isWelcome && !seen.contains(m.id)) return m; }
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final events = all.where((m) => !m.isWelcome && DateTime.now().difference(m.createdAt).inDays <= 45 && (m.endsOn == null || m.endsOn!.compareTo(today) >= 0)).toList();
  if (events.isNotEmpty && !seen.contains(events.first.id)) return events.first;
  return null;
});

/// Shows the pending message (if any) full screen before the app itself.
class DeskGate extends ConsumerWidget {
  final Widget child;
  const DeskGate({super.key, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(deskPendingProvider).value;
    // the app stays underneath (nothing is rebuilt); the message fades in over it
    return Stack(children: [
      child,
      if (m != null) Positioned.fill(child: TweenAnimationBuilder<double>(
        key: ValueKey(m.id), tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 700), curve: Curves.easeOut,
        builder: (_, v, c) => Opacity(opacity: v, child: c),
        child: DeskShowScreen(message: m, onDone: () async {
          final s = ref.read(sessionProvider).value;
          if (s != null) await markDeskSeen(s, m, ref.read(deskMessagesProvider).value ?? const []);
          ref.invalidate(deskPendingProvider);
        }),
      )),
    ]);
  }
}

// ================================================================== designs
enum DeskTheme {
  royal, annual, tech, sports, mun;

  static DeskTheme forTitle(String t) {
    final x = ' ${t.toLowerCase()} ';
    if (x.contains('annual')) return annual;
    if (x.contains('hackathon') || x.contains('roai') || x.contains('robotic') || x.contains('coding') || x.contains(' ai ') || x.contains('science fair') || x.contains('tech')) return tech;
    if (x.contains('sport') || x.contains('athletic') || x.contains('race') || x.contains('marathon')) return sports;
    if (x.contains('mun') || x.contains('model united') || x.contains('debate')) return mun;
    return royal;
  }

  List<Color> get bg => switch (this) {
        royal => const [Color(0xFF5A0B12), Color(0xFF2A070B), Color(0xFF110405)],
        annual => const [Color(0xFF3A1408), Color(0xFF1C0706), Color(0xFF0E0404)],
        tech => const [Color(0xFF0B2440), Color(0xFF07152A), Color(0xFF040A14)],
        sports => const [Color(0xFFC2410C), Color(0xFF7C1D0A), Color(0xFF2A0905)],
        mun => const [Color(0xFF13285A), Color(0xFF0B1838), Color(0xFF070E22)],
      };
  Color get accent => switch (this) { tech => const Color(0xFF28D7FF), sports => Colors.white, _ => const Color(0xFFE8C97A) };
  Color get text => switch (this) { tech => const Color(0xFFD7F6FF), sports => const Color(0xFFFFF3E6), mun => const Color(0xFFE6ECFF), _ => const Color(0xFFEAD9BD) };
  Color get ink => switch (this) { tech => const Color(0xFF9FF3FF), sports => Colors.white, _ => const Color(0xFFF3DA95) };
  Color get dust => switch (this) { tech => const Color(0xFF9FF3FF), sports => const Color(0xFFFFE2C2), _ => const Color(0xFFF6E2A6) };
  String get label => switch (this) { royal => 'Royal', annual => 'Stage', tech => 'Circuits', sports => 'Track', mun => 'Globe' };
}

// ================================================================== the full-screen message
class DeskShowScreen extends ConsumerStatefulWidget {
  final DeskMessage message;
  final VoidCallback? onDone;   // null = opened from the list: Continue just goes back
  const DeskShowScreen({super.key, required this.message, this.onDone});
  @override
  ConsumerState<DeskShowScreen> createState() => _DeskShowScreenState();
}

class _DeskShowScreenState extends ConsumerState<DeskShowScreen> {
  int step = 0; bool sigDone = false, canSkip = false;
  final sc = ScrollController();
  final _timers = <Timer>[];
  late final List<String> paras = widget.message.body.split(RegExp(r'\n\s*\n')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  int get _sigStep => 4 + paras.length;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timers.isNotEmpty || step > 0) return;
    if (reduceMotion(context)) { step = 99; sigDone = true; canSkip = true; return; }
    final event = !widget.message.isWelcome;
    final start = event ? 1500 : 500;
    void at(int ms, VoidCallback f) => _timers.add(Timer(Duration(milliseconds: ms), () { if (mounted) setState(f); }));
    at(start, () => step = 1);
    at(start + 1100, () => step = 2);
    at(start + 2200, () => step = 3);
    for (var i = 0; i <= paras.length; i++) {
      at(start + 3000 + i * 1000, () {
        step = 4 + i;
        if (step == _sigStep) WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
      });
    }
    at(2000, () => canSkip = true);
  }

  void _toBottom() { if (sc.hasClients) sc.animateTo(sc.position.maxScrollExtent, duration: const Duration(milliseconds: 1200), curve: Curves.easeInOutCubic); }

  void _skip() { for (final t in _timers) { t.cancel(); } setState(() { step = 99; sigDone = true; }); WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom()); }

  void _continue() { if (widget.onDone != null) { widget.onDone!(); } else { Navigator.of(context).maybePop(); } }

  @override
  void dispose() { for (final t in _timers) { t.cancel(); } sc.dispose(); super.dispose(); }

  String _greeting(Session? s) {
    if (s == null) return '';
    if (s.isStaff) return 'Dear ${s.staff?['name'] ?? 'colleague'},';
    final names = [for (final x in s.students) x.fullName.trim().split(RegExp(r'\s+')).first];
    if (names.isEmpty) return 'Dear parents,';
    final who = names.length == 1 ? names.first : '${names.sublist(0, names.length - 1).join(', ')} & ${names.last}';
    return 'Dear $who & family,';
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message, th = m.theme, event = !m.isWelcome;
    final info = principalInfo(ref.watch(appSettingsProvider).value);
    final sess = ref.watch(sessionProvider).value;
    final size = MediaQuery.sizeOf(context);
    final artH = math.min(size.height * .42, 380.0);
    final serif = GoogleFonts.cormorantGaramond(fontWeight: FontWeight.w700, color: Colors.white);
    final bodyStyle = GoogleFonts.manrope(fontSize: 15, height: 1.7, color: th.text, fontWeight: FontWeight.w500);

    Widget reveal(bool on, Widget child) => AnimatedOpacity(opacity: on ? 1 : 0, duration: const Duration(milliseconds: 900), curve: Curves.easeOut,
        child: AnimatedSlide(offset: on ? Offset.zero : const Offset(0, .12), duration: const Duration(milliseconds: 900), curve: Curves.easeOutCubic, child: child));

    final sig = SizedBox(width: math.min(size.width * .68, 300), child: AnimatedSignature(
      paths: signaturePaths, color: th.ink, start: step >= _sigStep, ms: event ? 2300 : 3200,
      bounds: Rect.fromLTWH(signatureBounds.left, signatureBounds.top, signatureBounds.width, signatureBounds.height),
      onDone: () { if (mounted) setState(() => sigDone = true); },
      instant: step >= 99,
      key: ValueKey('sig${step >= 99}'),
    ));
    final finished = sigDone || step >= 99;

    final content = Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (!event) ...[
        reveal(step >= 1, Text('ROYALE CONCORDE INTERNATIONAL SCHOOL', textAlign: TextAlign.center, style: GoogleFonts.manrope(fontSize: 10, letterSpacing: 3, fontWeight: FontWeight.w800, color: th.accent))),
        const SizedBox(height: 6),
        reveal(step >= 1, GoldText("From the Principal's Desk", style: GoogleFonts.cormorantGaramond(fontSize: 33, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, height: 1.1))),
        const SizedBox(height: 20),
        reveal(step >= 2, PrincipalPortrait(name: info.name, photo: info.photo, size: 138, shine: true)),
        const SizedBox(height: 18),
        reveal(step >= 3, Text(_greeting(sess), textAlign: TextAlign.center, style: serif.copyWith(fontSize: 23, color: const Color(0xFFFFF3DC)))),
      ] else ...[
        reveal(step >= 1, Text("FROM THE PRINCIPAL'S DESK", textAlign: TextAlign.center, style: GoogleFonts.manrope(fontSize: 10.5, letterSpacing: 3.2, fontWeight: FontWeight.w800, color: th.accent))),
        const SizedBox(height: 8),
        reveal(step >= 2, Text(m.title, textAlign: TextAlign.center, style: serif.copyWith(fontSize: 34, height: 1.08))),
        const SizedBox(height: 10),
        reveal(step >= 3, Text(_greeting(sess), textAlign: TextAlign.center, style: serif.copyWith(fontSize: 19, color: th.text))),
      ],
      const SizedBox(height: 6),
      for (var i = 0; i < paras.length; i++) Padding(padding: const EdgeInsets.only(top: 12), child: reveal(step >= 4 + i, Text(paras[i], textAlign: TextAlign.center, style: bodyStyle))),
      if (m.picturePath != null) Padding(padding: const EdgeInsets.only(top: 18), child: reveal(step >= _sigStep, ClipRRect(borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 320), child: StorageImage(m.picturePath!, fit: BoxFit.cover))))),
      const SizedBox(height: 14),
      if (step >= _sigStep) sig else SizedBox(width: math.min(size.width * .68, 300), height: math.min(size.width * .68, 300) / (signatureBounds.width / signatureBounds.height)),
      AnimatedOpacity(opacity: finished ? 1 : 0, duration: const Duration(milliseconds: 800), child: Column(children: [
        if (event) Padding(padding: const EdgeInsets.only(bottom: 8), child: PrincipalPortrait(name: info.name, photo: info.photo, size: 46)),
        Text(info.name, style: serif.copyWith(fontSize: 20, color: th.accent)),
        const SizedBox(height: 2),
        Text('Principal · Royale Concorde International School, Kalyan Nagar', textAlign: TextAlign.center, style: GoogleFonts.manrope(fontSize: 11.5, color: th.text.withValues(alpha: .75))),
        const SizedBox(height: 22),
        if (m.linkUrl != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: OutlinedButton.icon(
          onPressed: finished ? () => launchUrl(Uri.parse(m.linkUrl!), mode: LaunchMode.externalApplication) : null,
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), side: BorderSide(color: th.accent), foregroundColor: th.accent, shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 26)),
          icon: const Icon(Icons.open_in_new_rounded, size: 18), label: Text((m.linkLabel ?? '').isEmpty ? 'Know more' : m.linkLabel!),
        )),
        _GoldButton(label: widget.onDone == null ? 'Close' : 'Continue  →', onTap: finished ? _continue : null, tech: th == DeskTheme.tech),
        const SizedBox(height: 30),
      ])),
    ]);

    return PopScope(
      canPop: widget.onDone == null,
      child: Scaffold(
        backgroundColor: th.bg.last,
        body: Stack(children: [
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(center: const Alignment(0, -1), radius: 1.35, colors: th.bg, stops: const [0, .5, 1])))),
          Positioned.fill(child: GoldParticles(count: 55, color: th.dust, speed: th == DeskTheme.sports ? 1.6 : 1)),
          if (event) Positioned(top: 0, left: 0, right: 0, height: artH, child: _EventArt(th, title: m.title)),
          SafeArea(child: SingleChildScrollView(controller: sc, padding: EdgeInsets.fromLTRB(26, event ? artH - 40 : 30, 26, 20),
              child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 540), child: content)))),
          SafeArea(child: Align(alignment: Alignment.topRight, child: Padding(padding: const EdgeInsets.all(10), child: AnimatedOpacity(
            opacity: canSkip && !finished || widget.onDone == null ? 1 : 0, duration: const Duration(milliseconds: 500),
            child: widget.onDone == null
                ? IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.close_rounded, color: Colors.white), style: IconButton.styleFrom(backgroundColor: Colors.black26))
                : TextButton(onPressed: canSkip && !finished ? _skip : null, style: TextButton.styleFrom(foregroundColor: th.accent, side: BorderSide(color: th.accent.withValues(alpha: .4)), shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 16)),
                    child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w800))),
          )))),
        ]),
      ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  final String label; final VoidCallback? onTap; final bool tech;
  const _GoldButton({required this.label, this.onTap, this.tech = false});
  @override
  Widget build(BuildContext context) => Material(color: Colors.transparent, child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(99), child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 15),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99),
            gradient: tech ? const LinearGradient(colors: [Color(0xFF7FEBFF), Color(0xFF28D7FF)]) : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF6E2A6), Color(0xFFC9A24A), Color(0xFFE8C97A)], stops: [0, .55, 1]),
            boxShadow: [BoxShadow(color: (tech ? const Color(0xFF28D7FF) : const Color(0xFFC9A24A)).withValues(alpha: .4), blurRadius: 26, offset: const Offset(0, 8))]),
        child: ShineSweep(delay: const Duration(milliseconds: 900), every: const Duration(milliseconds: 2600), shine: const Color(0xAAFFFFFF),
            child: Text(label, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: .8, color: const Color(0xFF2B1608)))),
      )));
}

/// The Principal in a gold oval frame; her initials until a photo is added.
class PrincipalPortrait extends StatelessWidget {
  final String name; final String? photo; final double size; final bool shine;
  const PrincipalPortrait({super.key, required this.name, this.photo, this.size = 120, this.shine = false});
  static String initials(String n) => n.replaceAll(RegExp(r'^(mrs|ms|mr|dr|smt)\.?\s+', caseSensitive: false), '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
  @override
  Widget build(BuildContext context) {
    final h = size * 1.18, big = size > 80;
    final inner = ClipOval(child: SizedBox(width: size - 6, height: h - 6, child: photo != null
        ? StorageImage(photo!, fit: BoxFit.cover)
        : DecoratedBox(decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(0, -.3), colors: [Color(0xFFFBF1DC), Color(0xFFD9C29A), Color(0xFF9C8058)])),
            child: Center(child: Text(initials(name), style: GoogleFonts.cormorantGaramond(fontSize: size * .36, fontWeight: FontWeight.w700, color: const Color(0xFF6B4E22)))))));
    Widget frame = Container(width: size, height: h, padding: const EdgeInsets.all(3),
        decoration: const ShapeDecoration(shape: OvalBorder(), gradient: SweepGradient(colors: [Color(0xFF7A5A1E), Color(0xFFF6E2A6), Color(0xFFC9A24A), Color(0xFFFFF3CF), Color(0xFF9C7A2E), Color(0xFFF6E2A6), Color(0xFF7A5A1E)])),
        child: inner);
    if (shine) frame = ShineSweep(delay: const Duration(milliseconds: 900), every: const Duration(milliseconds: 5000), child: frame);
    if (!big) return frame;
    return Container(padding: const EdgeInsets.all(8), decoration: ShapeDecoration(shape: OvalBorder(side: BorderSide(color: const Color(0xFFE8C97A).withValues(alpha: .35)))),
        child: Container(decoration: BoxDecoration(boxShadow: [BoxShadow(color: const Color(0xFFE8C97A).withValues(alpha: .25), blurRadius: 40)], shape: BoxShape.circle), child: frame));
  }
}

// ================================================================== event artwork (top of the screen)
class _EventArt extends StatefulWidget {
  final DeskTheme theme; final String title;
  const _EventArt(this.theme, {required this.title});
  @override
  State<_EventArt> createState() => _EventArtState();
}

class _EventArtState extends State<_EventArt> with TickerProviderStateMixin {
  late final AnimationController intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final AnimationController loop = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  @override
  void didChangeDependencies() { super.didChangeDependencies(); if (intro.value == 0) { reduceMotion(context) ? intro.value = 1 : intro.forward(); } }
  @override
  void dispose() { intro.dispose(); loop.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final fade = ShaderMask(blendMode: BlendMode.dstIn, shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Colors.white, Colors.transparent], stops: [0, .7, 1]).createShader(r),
        child: AnimatedBuilder(animation: Listenable.merge([intro, loop]), builder: (_, __) => switch (widget.theme) {
              DeskTheme.annual => _stage(),
              DeskTheme.tech => CustomPaint(size: Size.infinite, painter: _CircuitPainter(intro.value, loop.value)),
              DeskTheme.sports => _track(),
              DeskTheme.mun => _globe(),
              DeskTheme.royal => _royal(),
            }));
    return IgnorePointer(child: fade);
  }

  double _i(double a, double b) => Curves.easeInOutCubic.transform(((intro.value - a) / (b - a)).clamp(0.0, 1.0));

  Widget _stage() {
    final open = _i(.15, .85);
    return LayoutBuilder(builder: (_, c) => Stack(children: [
      Positioned.fill(child: Opacity(opacity: _i(.45, 1), child: CustomPaint(painter: _BeamsPainter(loop.value)))),
      Center(child: Opacity(opacity: _i(.55, 1), child: Transform.scale(scale: .85 + .15 * _i(.55, 1), child: Text('✦', style: TextStyle(fontSize: 64, color: const Color(0xFFF6E2A6).withValues(alpha: .9), shadows: const [Shadow(color: Color(0xFFFFC870), blurRadius: 30)]))))),
      for (final left in [true, false]) Positioned(top: 0, bottom: 0, left: left ? 0 : null, right: left ? null : 0, width: c.maxWidth * .52,
          child: Transform(alignment: left ? Alignment.centerLeft : Alignment.centerRight, transform: Matrix4.identity()..scale(1 - .62 * open, 1.0),
              child: const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment(-1, 0), end: Alignment(-.86, 0), tileMode: TileMode.mirror,
                  colors: [Color(0xFF5C070D), Color(0xFFA3121B), Color(0xFF7E0A12)]))))),
      Positioned(top: 0, left: 0, right: 0, height: 54, child: Container(decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF6B0910), Color(0xFF8F0E16)]),
          border: Border(bottom: BorderSide(color: Color(0xFFE8C97A), width: 3)), boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6))]))),
    ]));
  }

  Widget _track() => LayoutBuilder(builder: (_, c) => Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _LanesPainter(_i(0, .6)))),
        Positioned(right: 18, top: 50, child: Text("'${DateTime.now().year % 100}", style: GoogleFonts.manrope(fontSize: 84, fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: .1)))),
        Positioned(top: c.maxHeight * .26, left: -60 + (c.maxWidth * .7 + 60) * _i(.2, .95), child: const Text('🏃', style: TextStyle(fontSize: 54))),
      ]));

  Widget _globe() => Stack(alignment: Alignment.center, children: [
        Opacity(opacity: _i(0, .6), child: Transform.scale(scale: .75 + .25 * _i(0, .6), child: SizedBox(width: 220, height: 220, child: CustomPaint(painter: _GlobePainter(loop.value))))),
        Positioned(bottom: 30, child: Row(children: [
          for (final (i, f) in ['🇮🇳', '🇯🇵', '🇧🇷', '🇫🇷', '🇰🇪', '🇦🇺', '🇨🇦'].indexed)
            Opacity(opacity: _i(.45 + i * .06, .65 + i * .06), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Text(f, style: const TextStyle(fontSize: 22)))),
        ])),
      ]);

  Widget _royal() => Center(child: Opacity(opacity: _i(0, .6), child: Transform.scale(scale: .8 + .2 * _i(0, .6), child: ShineSweep(delay: const Duration(milliseconds: 1400), every: const Duration(milliseconds: 4000), child: Container(
        width: 118, height: 118, padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SweepGradient(colors: [Color(0xFF7A5A1E), Color(0xFFF6E2A6), Color(0xFFC9A24A), Color(0xFFFFF3CF), Color(0xFF7A5A1E)])),
        child: Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFFDF8)), padding: const EdgeInsets.all(22), child: Image.asset('assets/images/monogram.png')),
      )))));
}

class _BeamsPainter extends CustomPainter {
  final double t; _BeamsPainter(this.t);
  @override
  void paint(Canvas canvas, Size s) {
    for (final (x, sway) in [(.22, 1.0), (.78, -1.0)]) {
      final top = Offset(s.width * x, -10);
      final a = math.sin(t * 6.28) * .06 * sway;
      final p = Path()..moveTo(top.dx - 8, top.dy)..lineTo(top.dx + 8, top.dy)
        ..lineTo(s.width * (.5 + a) + s.width * .26, s.height)..lineTo(s.width * (.5 + a) - s.width * .26, s.height)..close();
      canvas.drawPath(p, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66FFE6AA), Color(0x00FFE6AA)]).createShader(Offset.zero & s));
    }
  }
  @override
  bool shouldRepaint(_BeamsPainter o) => o.t != t;
}

class _CircuitPainter extends CustomPainter {
  final double p, t; _CircuitPainter(this.p, this.t);
  static const lines = [
    [[0, .2], [.3, .2], [.3, .4], [.41, .4]], [[1, .15], [.72, .15], [.72, .37], [.59, .37]], [[0, .72], [.23, .72], [.23, .58], [.41, .58]],
    [[1, .8], [.77, .8], [.77, .61], [.59, .61]], [[.5, 0], [.5, .33]], [[.1, 0], [.1, .1], [.36, .1], [.36, .33], [.43, .33]], [[.9, 1], [.9, .92], [.64, .92], [.64, .68], [.57, .68]],
  ];
  @override
  void paint(Canvas canvas, Size s) {
    const c = Color(0xFF28D7FF);
    final glow = Paint()..color = c.withValues(alpha: .55)..style = PaintingStyle.stroke..strokeWidth = 5..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final line = Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 1.6;
    for (var i = 0; i < lines.length; i++) {
      final k = ((p * 1.6 - i * .08)).clamp(0.0, 1.0);
      if (k == 0) continue;
      final path = Path();
      for (final (j, pt) in lines[i].indexed) { final o = Offset(pt[0] * s.width, pt[1] * s.height); j == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy); }
      for (final m in path.computeMetrics()) {
        final part = m.extractPath(0, m.length * k);
        canvas.drawPath(part, glow); canvas.drawPath(part, line);
        // a pulse of light running along each finished line
        if (k == 1) { final pos = m.getTangentForOffset(m.length * ((t * 2 + i * .13) % 1))?.position; if (pos != null) canvas.drawCircle(pos, 3, Paint()..color = const Color(0xFFE8FDFF)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)); }
      }
    }
    final chip = Rect.fromCenter(center: Offset(s.width * .5, s.height * .5), width: s.width * .2, height: s.height * .36);
    final on = ((p - .55) / .3).clamp(0.0, 1.0);
    canvas.drawRRect(RRect.fromRectAndRadius(chip, const Radius.circular(14)), Paint()..color = const Color(0xFF071A2E));
    canvas.drawRRect(RRect.fromRectAndRadius(chip, const Radius.circular(14)), Paint()..color = c.withValues(alpha: .3 + .7 * on)..style = PaintingStyle.stroke..strokeWidth = 2);
    final tp = TextPainter(text: TextSpan(text: 'AI', style: TextStyle(fontSize: chip.height * .28, fontWeight: FontWeight.w800, letterSpacing: 2, color: const Color(0xFF9FF3FF).withValues(alpha: on),
        shadows: const [Shadow(color: Color(0xFF28D7FF), blurRadius: 14)])), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, chip.center - Offset(tp.width / 2, tp.height / 2));
  }
  @override
  bool shouldRepaint(_CircuitPainter o) => true;
}

class _LanesPainter extends CustomPainter {
  final double p; _LanesPainter(this.p);
  @override
  void paint(Canvas canvas, Size s) {
    canvas.save();
    canvas.translate(-s.width * .2, s.height * .2);
    canvas.rotate(-.2);
    for (var i = 0; i < 6; i++) {
      final k = ((p * 1.5) - i * .08).clamp(0.0, 1.0);
      final y = 40.0 + i * s.height * .12;
      canvas.drawLine(Offset(0, y), Offset(s.width * 1.5 * k, y), Paint()..color = Colors.white.withValues(alpha: .85)..strokeWidth = 3);
    }
    canvas.restore();
  }
  @override
  bool shouldRepaint(_LanesPainter o) => o.p != p;
}

class _GlobePainter extends CustomPainter {
  final double t; _GlobePainter(this.t);
  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero), r = s.width / 2 - 4;
    canvas.drawCircle(c, r, Paint()..shader = const RadialGradient(center: Alignment(-.3, -.3), colors: [Color(0xFF2F56B0), Color(0xFF0A1A44)]).createShader(Rect.fromCircle(center: c, radius: r)));
    final gold = Paint()..color = const Color(0xFFE8C97A).withValues(alpha: .6)..style = PaintingStyle.stroke..strokeWidth = 1.1;
    canvas.drawCircle(c, r, gold..color = const Color(0xFFE8C97A));
    gold.color = const Color(0xFFE8C97A).withValues(alpha: .55);
    for (final k in [.38, .72]) { canvas.drawOval(Rect.fromCenter(center: c, width: r * 2, height: r * 2 * k), gold); }
    canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), gold);
    canvas.drawLine(c - Offset(0, r), c + Offset(0, r), gold);
    for (var i = 0; i < 3; i++) {
      final w = (math.cos((t + i / 3) * 6.283)).abs() * r * 2;
      canvas.drawOval(Rect.fromCenter(center: c, width: w, height: r * 2), gold);
    }
    // laurel arcs
    final laurel = Paint()..color = const Color(0xFFE8C97A)..style = PaintingStyle.stroke..strokeWidth = 3..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r + 14), math.pi * .62, math.pi * .5, false, laurel);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r + 14), -math.pi * .12, math.pi * .5, false, laurel);
  }
  @override
  bool shouldRepaint(_GlobePainter o) => o.t != t;
}

// ================================================================== list ("From the Principal's Desk")
/// Families: /desk. Staff: /staff/desk (IT and the Principal also write and change messages there).
typedef DeskEditor = Future<void> Function(BuildContext context, WidgetRef ref, DeskMessage? existing);

class DeskListScreen extends ConsumerWidget {
  final bool staff;
  final DeskEditor? editor;                                   // staff panel only: write / change messages
  final Future<String?> Function(BuildContext)? pickPhoto;     // staff panel only: upload her photo
  const DeskListScreen({super.key, this.staff = false, this.editor, this.pickPhoto});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    final admin = staff && editor != null && s != null && (s.hasRole('it_admin') || s.hasRole('principal'));
    final info = principalInfo(ref.watch(appSettingsProvider).value);
    final list = ref.watch(deskMessagesProvider);
    final cs = Theme.of(context).colorScheme;
    void show(DeskMessage m) => Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500), pageBuilder: (_, __, ___) => DeskShowScreen(message: m),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child)));

    final header = Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const RadialGradient(center: Alignment(-.6, -1), radius: 1.6, colors: [Color(0xFF5A0B12), Color(0xFF2A070B), Color(0xFF140506)])),
      child: Row(children: [
        PrincipalPortrait(name: info.name, photo: info.photo, size: 64, shine: true),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GoldText("From the Principal's Desk", align: TextAlign.left, style: GoogleFonts.cormorantGaramond(fontSize: 24, fontStyle: FontStyle.italic, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(info.name, style: const TextStyle(color: Color(0xFFF3E2C4), fontWeight: FontWeight.w800)),
          Text('Principal · Royale Concorde International School', style: TextStyle(color: const Color(0xFFF3E2C4).withValues(alpha: .7), fontSize: 12)),
        ])),
      ]),
    );

    return Scaffold(
      appBar: AppBar(title: const Text("Principal's Desk")),
      floatingActionButton: admin ? FloatingActionButton.extended(onPressed: () => editor!(context, ref, null), icon: const Icon(Icons.edit_rounded), label: const Text('New message')) : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(deskMessagesProvider),
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(padding: const EdgeInsets.all(20), children: [header, const SizedBox(height: 16), Text('Could not load the messages. Pull down to try again.', style: TextStyle(color: cs.onSurfaceVariant))]),
          data: (all) {
            final mine = all.where((m) => admin || (m.active && m.forMe(staff))).toList();
            final welcomes = mine.where((m) => m.isWelcome).toList(), events = mine.where((m) => !m.isWelcome).toList();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: staggered([
              header,
              if (admin) Padding(padding: const EdgeInsets.only(top: 12), child: _AdminBar(info: info, pickPhoto: pickPhoto)),
              const SizedBox(height: 18),
              for (final m in events) _MessageTile(m, admin: admin, editor: editor, onOpen: () => show(m)),
              if (events.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(admin ? 'No messages yet. Tap "New message" to write one — it opens full screen for everyone the next time they open the app.' : 'Messages from the Principal appear here.', style: TextStyle(color: cs.onSurfaceVariant))),
              const SizedBox(height: 10),
              for (final m in welcomes) _MessageTile(m, admin: admin, editor: editor, onOpen: () => show(m)),
            ], stepMs: 60));
          },
        ),
      ),
    );
  }
}

class _MessageTile extends ConsumerWidget {
  final DeskMessage m; final bool admin; final VoidCallback onOpen; final DeskEditor? editor;
  const _MessageTile(this.m, {required this.admin, required this.onOpen, this.editor});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme, th = m.theme;
    final who = switch (m.audience) { 'families' => 'Families', 'staff' => 'Staff', _ => 'Everyone' };
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Material(color: cs.surface, borderRadius: BorderRadius.circular(20), child: InkWell(
      onTap: onOpen, borderRadius: BorderRadius.circular(20),
      child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: cs.outline)),
        child: Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [th.bg.first, th.bg.last])),
              child: Icon(m.isWelcome ? Icons.waving_hand_rounded : switch (th) { DeskTheme.annual => Icons.theater_comedy_rounded, DeskTheme.tech => Icons.memory_rounded, DeskTheme.sports => Icons.directions_run_rounded, DeskTheme.mun => Icons.public_rounded, _ => Icons.auto_awesome_rounded }, color: th.accent)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.isWelcome ? 'Welcome message · for ${who.toLowerCase()}' : m.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text([if (!m.isWelcome) DateFormat('d MMM yyyy').format(m.createdAt), if (admin) who, if (!m.active) 'removed'].join(' · '), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ])),
          if (admin) PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit' && editor != null) { await editor!(context, ref, m); }
              if (v == 'remove' || v == 'restore') { await db.from('principal_message').update({'active': v == 'restore'}).eq('id', m.id); ref.invalidate(deskMessagesProvider); }
            },
            itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Change')), if (!m.isWelcome) PopupMenuItem(value: m.active ? 'remove' : 'restore', child: Text(m.active ? 'Remove' : 'Show again'))],
          ) else Icon(Icons.play_circle_outline_rounded, color: context.tone(Brand.crimson)),
        ]),
      ),
    )));
  }
}

class _AdminBar extends ConsumerWidget {
  final ({String name, String? photo}) info; final Future<String?> Function(BuildContext)? pickPhoto;
  const _AdminBar({required this.info, this.pickPhoto});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> save(String key, String value) async {
      await db.from('school_setting').upsert({'key': key, 'value': value});
      ref.invalidate(appSettingsProvider);
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)), icon: const Icon(Icons.photo_camera_outlined, size: 18), label: Text(info.photo == null ? 'Add her photo' : 'Change photo'),
          onPressed: pickPhoto == null ? null : () async { final p = await pickPhoto!(context); if (p != null) await save('principal_photo', p); }),
      OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)), icon: const Icon(Icons.badge_outlined, size: 18), label: const Text('Change name'),
          onPressed: () async {
            final c = TextEditingController(text: info.name);
            final v = await showDialog<String>(context: context, builder: (d) => AlertDialog(title: const Text("Principal's name"), content: TextField(controller: c, decoration: const InputDecoration(hintText: 'e.g. Mrs. Rekha Vinod')),
                actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save'))]));
            if (v != null && v.isNotEmpty) await save('principal_name', v);
          }),
    ]);
  }
}


// ================================================================== Home card
/// "From the Principal's Desk" on Home: the newest message (or her welcome), tap to open the list.
class DeskHomeCard extends ConsumerWidget {
  final bool staff;
  const DeskHomeCard({super.key, this.staff = false});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(deskMessagesProvider).value;
    if (all == null) return const SizedBox.shrink();
    final mine = all.where((m) => m.active && m.forMe(staff)).toList();
    if (mine.isEmpty) return const SizedBox.shrink();
    final recent = mine.where((m) => !m.isWelcome && DateTime.now().difference(m.createdAt).inDays <= 30).toList();
    final m = recent.isNotEmpty ? recent.first : mine.firstWhere((x) => x.isWelcome, orElse: () => mine.first);
    final info = principalInfo(ref.watch(appSettingsProvider).value);
    final isNew = recent.isNotEmpty && DateTime.now().difference(m.createdAt).inDays <= 3;
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Material(color: Colors.transparent, child: InkWell(
      onTap: () => context.push(staff ? '/staff/desk' : '/desk'), borderRadius: BorderRadius.circular(20),
      child: Ink(padding: const EdgeInsets.all(14), decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4A0910), Color(0xFF240609)]),
          border: Border.all(color: const Color(0xFFE8C97A).withValues(alpha: .35))),
        child: Row(children: [
          PrincipalPortrait(name: info.name, photo: info.photo, size: 46),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text("FROM THE PRINCIPAL'S DESK", style: GoogleFonts.manrope(fontSize: 10, letterSpacing: 1.6, fontWeight: FontWeight.w800, color: const Color(0xFFE8C97A))),
              if (isNew) Container(margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: const Color(0xFFE8C97A), borderRadius: BorderRadius.circular(6)),
                  child: const Text('NEW', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF2B1608)))),
            ]),
            const SizedBox(height: 3),
            Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            Text(info.name, style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFE8C97A)),
        ]),
      ),
    )));
  }
}
