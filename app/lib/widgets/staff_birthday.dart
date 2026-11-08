import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/data3.dart' show appSettingsProvider, featureOn;
import '../core/theme.dart';
import '../staff/staff_shell.dart' show Panel, toast;
import 'royal_extras.dart' show EmojiDrift, DriftMode;
import 'royal_motion.dart' show ConfettiBurst, FadeRise, GoldText, GoldParticles;
import '../core/errors.dart';

/// Staff birthdays.
///  • the birthday person: a full-screen wish on their birthday (or "belated" within 7 days), once a year — [StaffBirthdayGate]
///  • the Principal: "Today: Ms. X’s birthday" on her dashboard — [StaffBirthdayLine]
///  • IT: the list of staff birthdays, and where dates of birth are added — [StaffBirthdaysPanel]
///  • on the Principal’s birthday every active staff member gets a notification (server job, f_polish.sql)
/// Other teachers see nothing about anyone else’s birthday.

/// My own date of birth (ISO) or null.
final myBirthdayProvider = FutureProvider.autoDispose<String?>((ref) async {
  final s = ref.watch(sessionProvider).value;
  if (s == null || !s.isStaff || s.viewOnly) return null;
  try { final r = await db.rpc('my_birthday'); return r is String ? r : null; } catch (_) { return null; }
});

/// Everyone's birthdays — only IT and the Principal may ask (the server refuses others).
final staffBirthdaysProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final s = ref.watch(sessionProvider).value;
  if (s == null || !(s.hasRole('it_admin') || s.hasRole('principal'))) return [];
  final r = await db.rpc('staff_birthdays');
  return [for (final x in (r as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
});

/// Shows the birthday wish over the staff panel on my birthday (or within the 6 days after), once a year per phone.
class StaffBirthdayGate extends ConsumerStatefulWidget {
  final Widget child;
  const StaffBirthdayGate({super.key, required this.child});
  @override
  ConsumerState<StaffBirthdayGate> createState() => _StaffBirthdayGateState();
}

class _StaffBirthdayGateState extends ConsumerState<StaffBirthdayGate> {
  bool show = false; int late = 0; String? _checked;

  Future<void> _check(String staffId, String dobIso) async {
    if (_checked == '$staffId$dobIso') return;
    _checked = '$staffId$dobIso';
    final dob = DateTime.tryParse(dobIso);
    if (dob == null) return;
    final now = DateTime.now(), today = DateTime(now.year, now.month, now.day);
    var d = -1; DateTime? day;
    for (final y in [now.year, now.year - 1]) {
      var b = DateTime(y, dob.month, dob.day);
      if (dob.month == 2 && dob.day == 29 && b.month != 2) b = DateTime(y, 2, 28);
      final n = today.difference(b).inDays;
      if (n >= 0 && n <= 6) { d = n; day = b; break; }
    }
    if (d < 0 || day == null) return;
    final p = await SharedPreferences.getInstance();
    final key = 'rc_staff_bday_${staffId}_${day.year}';
    if (p.getBool(key) == true) return;
    await p.setBool(key, true);
    if (mounted) setState(() { show = true; late = d; });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value;
    final on = featureOn(ref.watch(appSettingsProvider).value, 'birthdays');
    final dob = on ? ref.watch(myBirthdayProvider).value : null;
    if (s?.staff?['id'] != null && dob != null) WidgetsBinding.instance.addPostFrameCallback((_) => _check('${s!.staff!['id']}', dob));
    final first = '${s?.staff?['name'] ?? ''}'.trim().split(RegExp(r'\s+')).where((w) => !RegExp(r'^(mr|mrs|ms|miss|dr)\.?$', caseSensitive: false).hasMatch(w)).firstOrNull ?? '';
    return Stack(children: [
      widget.child,
      if (show) Positioned.fill(child: TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 700),
          builder: (_, v, c) => Opacity(opacity: v, child: c),
          child: _StaffWish(name: first, belated: late > 0, onClose: () => setState(() => show = false)))),
    ]);
  }
}

class _StaffWish extends StatelessWidget {
  final String name; final bool belated; final VoidCallback onClose;
  const _StaffWish({required this.name, required this.belated, required this.onClose});
  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF140506),
        child: Stack(children: [
          const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(center: Alignment(0, -.6), radius: 1.3, colors: [Color(0xFF5A0B12), Color(0xFF2A070B), Color(0xFF110405)])))),
          const Positioned.fill(child: GoldParticles(count: 40)),
          const Positioned.fill(child: EmojiDrift(emojis: ['🎈', '🎉', '🎁', '🎈'], mode: DriftMode.rise, count: 16, size: 40)),
          const Positioned.fill(child: ConfettiBurst(count: 140, origin: Alignment(0, -.3), ms: 3400)),
          SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const FadeRise(delayMs: 300, child: Text('🎂', style: TextStyle(fontSize: 80))),
            const SizedBox(height: 10),
            FadeRise(delayMs: 700, child: GoldText(belated ? 'Happy belated birthday,' : 'Happy Birthday,', style: GoogleFonts.greatVibes(fontSize: 48, height: 1.2))),
            FadeRise(delayMs: 1100, child: FittedBox(fit: BoxFit.scaleDown, child: GoldText('$name!', style: GoogleFonts.greatVibes(fontSize: 62, height: 1.15)))),
            const SizedBox(height: 16),
            FadeRise(delayMs: 1600, child: Text('Thank you for all you do for our children.\nWishing you a wonderful year ahead — from everyone at Royale Concorde.', textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 16, height: 1.6, color: const Color(0xFFEAD9BD)))),
            const SizedBox(height: 30),
            FadeRise(delayMs: 2200, child: FilledButton(onPressed: onClose,
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE8C97A), foregroundColor: const Color(0xFF2B1608), minimumSize: const Size(200, 52), shape: const StadiumBorder()),
                child: const Text('Thank you! 💛'))),
          ])))),
        ]),
      );
}

/// The Principal's line on her dashboard: "Today: Ms. Kavitha R.’s birthday 🎂". Nothing for anyone else, nothing on other days.
class StaffBirthdayLine extends ConsumerWidget {
  const StaffBirthdayLine({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    if (s == null || !s.hasRole('principal') || !featureOn(ref.watch(appSettingsProvider).value, 'birthdays')) return const SizedBox.shrink();
    final me = s.staff?['id'];
    final today = [for (final x in ref.watch(staffBirthdaysProvider).value ?? const []) if (x['days'] == 0 && x['id'] != me) '${x['name']}'];
    if (today.isEmpty) return const SizedBox.shrink();
    final names = today.length == 1 ? today.first : '${today.sublist(0, today.length - 1).join(', ')} and ${today.last}';
    return Container(
      margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Brand.amberTint, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.gold.withValues(alpha: .7))),
      child: Row(children: [
        const Text('🎂', style: TextStyle(fontSize: 20)), const SizedBox(width: 10),
        Expanded(child: Text.rich(TextSpan(children: [
          const TextSpan(text: 'Today: '),
          TextSpan(text: names, style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: today.length == 1 ? '’s birthday' : ' have their birthday'),
        ]), style: const TextStyle(fontSize: 14, color: Color(0xFF4A3410)))),
      ]),
    );
  }
}

/// IT: the next staff birthdays, and staff whose date of birth is still missing (tap a name to add it).
class StaffBirthdaysPanel extends ConsumerWidget {
  const StaffBirthdaysPanel({super.key});

  Future<void> _setDob(BuildContext context, WidgetRef ref, Map<String, dynamic> x) async {
    final cur = DateTime.tryParse('${x['dob'] ?? ''}');
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: cur ?? DateTime(now.year - 35, 1, 1), firstDate: DateTime(1940), lastDate: DateTime(now.year - 16, now.month, now.day),
        helpText: 'Date of birth · ${x['name']}', initialEntryMode: DatePickerEntryMode.input);
    if (d == null) return;
    try {
      await db.rpc('set_staff_dob', params: {'p_staff': x['id'], 'p_dob': DateFormat('yyyy-MM-dd').format(d)});
      ref.invalidate(staffBirthdaysProvider);
      if (context.mounted) toast(context, 'Saved ✓');
    } catch (e) { if (context.mounted) toast(context, friendlyError(e)); }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider).value;
    if (s == null || !s.hasRole('it_admin')) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final all = ref.watch(staffBirthdaysProvider).value ?? const [];
    final soon = [for (final x in all) if (x['days'] != null && (x['days'] as int) <= 30) x];
    final missing = [for (final x in all) if (x['dob'] == null) x];
    String when(int d) => d == 0 ? 'Today 🎂' : d == 1 ? 'Tomorrow' : 'in $d days';
    return Panel(title: 'Staff birthdays', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (soon.isEmpty) Text('No staff birthdays in the next 30 days.', style: TextStyle(color: cs.onSurfaceVariant)),
      for (final x in soon) InkWell(onTap: () => _setDob(context, ref, x), borderRadius: BorderRadius.circular(10), child: Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [
        Expanded(child: Text('${x['name']}', style: const TextStyle(fontWeight: FontWeight.w700))),
        Text('${DateFormat('d MMM').format(DateTime.parse('${x['dob']}'))} · ${when(x['days'] as int)}', style: TextStyle(fontSize: 13, color: x['days'] == 0 ? context.tone(Brand.crimson) : cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
      ]))),
      if (missing.isNotEmpty) ...[
        const SizedBox(height: 8),
        ExpansionTile(tilePadding: EdgeInsets.zero, shape: const Border(), collapsedShape: const Border(),
          title: Text('${missing.length} staff without a date of birth', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          subtitle: const Text('Tap a name to add it. Only IT and the Principal see staff birthdays.', style: TextStyle(fontSize: 12)),
          children: [for (final x in missing) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text('${x['name']}'),
              trailing: const Icon(Icons.edit_calendar_rounded, size: 18), onTap: () => _setDob(context, ref, x))]),
      ],
    ]));
  }
}
