import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/session.dart';
import '../core/theme.dart';

/// IT admin only: a 4-digit PIN on this device. Set once after signing in; asked when the app is opened again
/// after 5 minutes or more away (and every time the app is started). 5 wrong tries → signed out (sign in with the
/// password and set a new PIN). Nobody else gets a PIN. The PIN never leaves the device.
class PinGate extends ConsumerStatefulWidget {
  final Widget child;
  const PinGate({super.key, required this.child});
  @override
  ConsumerState<PinGate> createState() => _PinGateState();
}

class _PinGateState extends ConsumerState<PinGate> with WidgetsBindingObserver {
  static final _store = FlutterSecureStorage();
  static const away = Duration(minutes: 5);
  String? forStaff;          // whose PIN is loaded
  String? saved;             // the PIN on this device ('' = none set yet)
  bool locked = true;
  DateTime? leftAt;
  String typed = '', first = ''; int wrong = 0; String? note;
  final focus = FocusNode();

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); focus.dispose(); super.dispose(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) leftAt ??= DateTime.now();
    if (s == AppLifecycleState.resumed) {
      if (leftAt != null && DateTime.now().difference(leftAt!) >= away && (saved ?? '').isNotEmpty) setState(() { locked = true; typed = ''; note = null; });
      leftAt = null;
    }
  }

  String _key(String id) => 'rc_pin_$id';
  Future<String?> _read(String id) async => kIsWeb ? (await SharedPreferences.getInstance()).getString(_key(id)) : _store.read(key: _key(id));
  Future<void> _write(String id, String? v) async {
    if (kIsWeb) { final p = await SharedPreferences.getInstance(); v == null ? await p.remove(_key(id)) : await p.setString(_key(id), v); }
    else { v == null ? await _store.delete(key: _key(id)) : await _store.write(key: _key(id), value: v); }
  }

  Future<void> _load(String id) async {
    forStaff = id; saved = null;
    final v = await _read(id);
    if (mounted && forStaff == id) setState(() { saved = v ?? ''; locked = true; typed = ''; first = ''; wrong = 0; note = null; });
  }

  Future<void> _signOutAndForget() async {
    final id = forStaff;
    if (id != null) await _write(id, null);
    setState(() { saved = ''; typed = ''; first = ''; wrong = 0; note = null; });
    await ref.read(sessionProvider.notifier).signOut();
  }

  void _press(String k) {
    if (k == '⌫') { setState(() { typed = typed.isEmpty ? '' : typed.substring(0, typed.length - 1); note = null; }); return; }
    if (typed.length >= 4) return;
    setState(() { typed += k; note = null; });
    if (typed.length == 4) Future.delayed(const Duration(milliseconds: 180), _done);
  }

  Future<void> _done() async {
    final id = forStaff; if (id == null || !mounted) return;
    if ((saved ?? '').isEmpty) {           // setting the PIN: type it twice
      if (first.isEmpty) { setState(() { first = typed; typed = ''; }); return; }
      if (first != typed) { setState(() { first = ''; typed = ''; note = 'The two PINs didn’t match. Start again.'; }); return; }
      await _write(id, typed);
      if (mounted) setState(() { saved = typed; locked = false; typed = ''; first = ''; });
      return;
    }
    if (typed == saved) { setState(() { locked = false; typed = ''; wrong = 0; }); return; }
    wrong++;
    if (wrong >= 5) { await _signOutAndForget(); return; }
    setState(() { typed = ''; note = 'Wrong PIN · ${5 - wrong} ${5 - wrong == 1 ? 'try' : 'tries'} left'; });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value;
    final needs = s != null && s.isStaff && !s.viewOnly && !s.mustChangePassword && s.hasRole('it_admin');
    final id = needs ? '${s.staff?['id'] ?? ''}' : null;
    if (!needs || id == null || id.isEmpty) { forStaff = null; return widget.child; }
    if (forStaff != id) { _load(id); return const _Plain(); }
    if (saved == null) return const _Plain();
    if (saved!.isNotEmpty && !locked) return widget.child;

    final setting = saved!.isEmpty;
    final title = setting ? (first.isEmpty ? 'Set your 4-digit PIN' : 'Type the PIN again') : 'Enter your PIN';
    final line = setting ? 'Only for IT. You’ll be asked for it when you open the app after being away for 5 minutes.'
        : 'Welcome back${s.staff?['name'] != null ? ', ${s.staff!['name']}' : ''}';
    focus.requestFocus();
    return Focus(focusNode: focus, autofocus: true, onKeyEvent: (_, e) {
      if (e is! KeyDownEvent) return KeyEventResult.ignored;
      final ch = e.character;
      if (ch != null && RegExp(r'^\d$').hasMatch(ch)) { _press(ch); return KeyEventResult.handled; }
      if (e.logicalKey == LogicalKeyboardKey.backspace) { _press('⌫'); return KeyEventResult.handled; }
      return KeyEventResult.ignored;
    }, child: Material(child: Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFC4161E), Color(0xFF7E0A10), Color(0xFF4E060A)])),
      child: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Container(
        constraints: const BoxConstraints(maxWidth: 380), padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(26)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(color: Brand.crimson, borderRadius: BorderRadius.circular(16)), alignment: Alignment.center,
              child: Text('R', style: GoogleFonts.playfairDisplay(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700))),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(line, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 0; i < 4; i++) AnimatedContainer(duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 7), width: 16, height: 16,
            decoration: BoxDecoration(shape: BoxShape.circle, color: i < typed.length ? Brand.gold : Colors.transparent, border: Border.all(color: Brand.gold, width: 2)))]),
          SizedBox(height: 30, child: Center(child: Text(note ?? '', style: const TextStyle(color: Brand.crimson, fontWeight: FontWeight.w800)))),
          GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.6, children: [
            for (final k in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'])
              k.isEmpty ? const SizedBox() : Material(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(16),
                child: InkWell(borderRadius: BorderRadius.circular(16), onTap: () => _press(k), child: Center(child: k == '⌫'
                    ? const Icon(Icons.backspace_outlined) : Text(k, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))))),
          ]),
          const SizedBox(height: 10),
          TextButton(onPressed: _signOutAndForget, child: Text(setting ? 'Sign out' : 'Forgot PIN? Sign in with your password', style: const TextStyle(color: Brand.crimson, fontWeight: FontWeight.w800))),
        ]))))))));
  }
}

class _Plain extends StatelessWidget {
  const _Plain();
  @override
  Widget build(BuildContext context) => const Material(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFC4161E), Color(0xFF7E0A10)])), child: SizedBox.expand()));
}
