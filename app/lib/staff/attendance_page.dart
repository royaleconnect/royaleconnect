import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../core/data.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import '../screens/family_screens.dart' show StorageImage;
import '../widgets/royal_motion.dart' show ConfettiBurst;
import '../widgets/common.dart' show Pill, NoteBox, Avatar;
import '../auth/session.dart';
import 'staff_data.dart';
import 'staff_shell.dart';

/// Attendance: the class teacher types who is absent ("aarv, priya, 15" — spelling mistakes are fine, or use the keyboard mic),
/// taps Find, checks the faces, taps Save. Everyone else is present.
/// Families of absent children are told at 10:00 (straight away if saved after 10:00).
/// Only the class teacher marks (the office / IT can correct a past day). Coordinator, vice principal, principal: view only.
class StaffAttendanceScreen extends ConsumerStatefulWidget {
  const StaffAttendanceScreen({super.key});
  @override
  ConsumerState<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends ConsumerState<StaffAttendanceScreen> {
  String? section; DateTime day = DateUtils.dateOnly(DateTime.now());
  Map<String, dynamic>? sheet; final marks = <String, String>{}; bool loading = false, busy = false, saved = false, showAll = false;
  final input = TextEditingController();
  List<AbsentQuery> pending = []; List<String> notFound = [];

  @override
  void dispose() { input.dispose(); super.dispose(); }

  List<Map<String, dynamic>> get _students => [for (final x in (sheet?['students'] as List? ?? const [])) Map<String, dynamic>.from(x)];

  Future<void> _load() async {
    if (section == null) return;
    setState(() { loading = true; saved = false; pending = []; notFound = []; });
    try {
      final r = Map<String, dynamic>.from(await db.rpc('attendance_sheet', params: {'p_section': section, 'p_day': DateFormat('yyyy-MM-dd').format(day)}) as Map);
      marks..clear()..addAll({for (final x in (r['students'] as List)) x['id'] as String: (x['status'] ?? 'present') as String});
      if (mounted) setState(() { sheet = r; loading = false; showAll = r['can_mark'] != true; });
    } catch (e) { if (mounted) { setState(() => loading = false); toast(context, friendlyError(e)); } }
  }

  void _find() {
    final kids = [for (final s in _students) Kid(s['id'] as String, '${s['name'] ?? ''}', s['roll'] as int?)];
    final left = <String>[]; final many = <AbsentQuery>[]; final none = <String>[];
    for (final part in input.text.split(RegExp(r'[,\n;]+'))) {
      final m = matchAbsent(part, kids);
      if (m == null) continue;
      if (m.one != null) { marks[m.one!.id] = 'absent'; }
      else if (m.many.isNotEmpty) { many.add(m); }
      else { none.add(m.query); left.add(m.query); }
    }
    HapticFeedback.selectionClick();
    // the box keeps only what was not found, so a spelling can be fixed and Find tapped again
    setState(() { saved = false; pending = [...pending, ...many]; notFound = none; input.text = left.join(', '); });
  }

  Future<void> _save() async {
    if (pending.isNotEmpty) { toast(context, 'First choose which child for the names in yellow.'); return; }
    setState(() => busy = true);
    try {
      List<String> ids(String st) => [for (final e in marks.entries) if (e.value == st) e.key];
      final r = Map<String, dynamic>.from(await db.rpc('attendance_save', params: {'p_section': section, 'p_day': DateFormat('yyyy-MM-dd').format(day), 'p_absent': ids('absent'), 'p_late': ids('late'), 'p_leave': ids('leave')}) as Map);
      HapticFeedback.mediumImpact();
      final absent = (r['absent'] ?? 0) as int;
      final isToday = DateUtils.isSameDay(day, DateTime.now());
      final msg = absent == 0 ? 'Saved ✓ · everyone present'
          : sheet?['closed'] == true || !isToday ? 'Saved ✓ · $absent absent'
          : r['told_now'] == true ? 'Saved ✓ · $absent ${absent == 1 ? 'family' : 'families'} told “marked absent today”'
          : 'Saved ✓ · $absent absent. Their families are told at 10:00.';
      if (mounted) { setState(() { busy = false; saved = true; sheet = {...?sheet, 'marked': true}; }); toast(context, msg); }
    } catch (e) { if (mounted) { setState(() => busy = false); toast(context, friendlyError(e)); } }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(sessionProvider).value;
    final secs = ref.watch(mySectionsProvider).value ?? const <Map<String, dynamic>>[];
    final me = s?.staff?['id'];
    final canCorrectOld = (s?.hasRole('office') ?? false) || (s?.hasRole('it_admin') ?? false);
    // the class teacher's own class first; a plain class teacher sees only her class (office / coordinator see more, view only)
    final mine = [for (final x in secs) if (x['class_teacher_id'] == me) x];
    final seesMore = (s?.isOffice ?? false) || (s?.hasRole('coordinator') ?? false);
    final list = seesMore ? [...mine, for (final x in secs) if (x['class_teacher_id'] != me) x] : mine;
    if (section == null && list.isNotEmpty) { section = list.first['id'] as String; WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
    final students = _students;
    final canMark = sheet?['can_mark'] == true;
    final label = '${sheet?['label'] ?? ''}';
    final absent = marks.values.where((v) => v == 'absent').length, leave = marks.values.where((v) => v == 'leave').length;
    final present = students.length - absent - leave;
    final today = DateUtils.dateOnly(DateTime.now());

    return StaffPage(title: 'Attendance',
      subtitle: canMark || sheet == null ? 'Type who is absent, tap Find, then Save. Everyone else is present. Families of absent children are told at 10:00.' : 'See who was present and absent. The class teacher marks attendance.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(padding: const EdgeInsets.all(12), child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (list.length > 1) DropdownButton<String>(value: section, items: [for (final x in list) DropdownMenuItem(value: x['id'] as String, child: Text(sectionLabel(x)))],
              onChanged: (v) { setState(() => section = v); _load(); }),
          if (list.length == 1) Text(sectionLabel(list.first), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          OutlinedButton.icon(onPressed: () async {
            // teachers: today and the 7 days before (the server refuses older); the office / IT can correct further back
            final d = await showDatePicker(context: context, initialDate: day, firstDate: today.subtract(Duration(days: canCorrectOld ? 365 : 7)), lastDate: today);
            if (d != null) { setState(() => day = d); _load(); }
          }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(DateFormat('EEEE, d MMMM').format(day))),
          if (sheet != null) Text('${students.length} students', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
          if (sheet?['marked'] == true) const Pill('Marked ✓', fg: Brand.green, bg: Brand.greenTint),
        ])),
        if (list.isEmpty) const NoteBox('Attendance is taken by the class teacher. You are not class teacher of a class this year.')
        else if (loading || sheet == null) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
        else ...[
          if (sheet?['closed'] == true) const NoteBox('The school is closed on this day (Sunday or a holiday). No need to take attendance, and families are not sent alerts.', icon: Icons.beach_access_rounded),
          if (!canMark) const NoteBox('You can see attendance here. Only the class teacher marks it (the office can correct a past day).', icon: Icons.visibility_rounded),
          if (canMark) Panel(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('WHO IS ABSENT TODAY?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextField(controller: input, minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.none, keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(hintText: 'Type names or roll numbers, e.g. rahul, priya, 15')),
            const SizedBox(height: 6),
            Text('Spelling mistakes are fine · 🎤 use the keyboard mic to speak', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: _find, style: FilledButton.styleFrom(backgroundColor: Brand.crimson, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                icon: const Icon(Icons.search_rounded), label: const Text('Find')),
          ])),
          if (canMark && (absent > 0 || pending.isNotEmpty || notFound.isNotEmpty)) Panel(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('ABSENT · $absent', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2, color: cs.onSurfaceVariant)),
            for (final st in students) if (marks[st['id']] == 'absent') _KidRow(st: st, trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              const Pill('Absent', fg: Colors.white, bg: Brand.crimson),
              IconButton(tooltip: 'Remove', icon: const Icon(Icons.close_rounded), onPressed: () => setState(() { saved = false; marks[st['id']] = 'present'; })),
            ])),
            for (final (i, m) in pending.indexed) Container(
              margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Brand.amberTint, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Which “${m.query}”?', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF6B4A00))),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [for (final k in m.many) ActionChip(
                  label: Text('${k.name}${k.roll != null ? ' · roll ${k.roll}' : ''}'),
                  onPressed: () => setState(() { saved = false; marks[k.id] = 'absent'; pending = [...pending]..removeAt(i); }),
                )]),
              ])),
            for (final q in notFound) Container(
              margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Brand.crimsonTint, borderRadius: BorderRadius.circular(12)),
              child: Text('“$q” is not in $label — check the spelling', style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.crimsonDeep))),
          ])),
          Panel(padding: const EdgeInsets.fromLTRB(14, 4, 14, 4), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            InkWell(onTap: () => setState(() => showAll = !showAll), child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(children: [
              Expanded(child: Text(canMark ? 'Full class list (tap a child to change)' : 'Class list · $present present, $absent absent', style: const TextStyle(fontWeight: FontWeight.w800))),
              Icon(showAll ? Icons.expand_less_rounded : Icons.expand_more_rounded),
            ]))),
            if (showAll) for (final st in students) _KidRow(st: st, rollFirst: true,
              onTap: !canMark ? null : () {
                HapticFeedback.selectionClick();
                setState(() { saved = false; marks[st['id']] = marks[st['id']] == 'absent' ? 'present' : 'absent'; });
              },
              trailing: _statusPill(marks[st['id']] ?? 'present')),
          ])),
          if (canMark) Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: busy ? null : _save,
              style: FilledButton.styleFrom(backgroundColor: Brand.crimson, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
              icon: Icon(saved ? Icons.check_circle_rounded : Icons.save_rounded),
              label: Text(busy ? 'Saving…' : saved ? 'Saved' : absent == 0 ? 'Save · everyone present${leave > 0 ? ' ($leave on leave)' : ''}' : 'Save · $absent absent, $present present${leave > 0 ? ', $leave on leave' : ''}'))),
            if (saved) const Positioned(right: 40, child: IgnorePointer(child: SizedBox(width: 160, height: 120, child: ConfettiBurst()))),
          ]),
        ],
      ]));
  }
}

Widget _statusPill(String status) => switch (status) {
  'absent' => const Pill('Absent', fg: Colors.white, bg: Brand.crimson),
  'late' => const Pill('Late', fg: Brand.amber, bg: Brand.amberTint),
  'leave' => const Pill('Leave', fg: Brand.violet, bg: Brand.violetTint),
  _ => const Pill('Present', fg: Brand.green, bg: Brand.greenTint),
};

/// One child: photo (or initials / roll), name, roll number.
class _KidRow extends StatelessWidget {
  final Map<String, dynamic> st; final Widget trailing; final VoidCallback? onTap; final bool rollFirst;
  const _KidRow({required this.st, required this.trailing, this.onTap, this.rollFirst = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = '${st['name'] ?? ''}';
    final photo = st['photo'] as String?;
    final initials = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final Widget face = rollFirst
        ? Avatar('${st['roll'] ?? initials}', size: 36, bg: cs.surfaceContainerHighest, fg: cs.onSurface)
        : (photo != null && photo.isNotEmpty) ? StorageImage(photo, width: 40, height: 40, radius: BorderRadius.circular(13)) : Avatar(initials, size: 40);
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
      face, const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        if (!rollFirst && st['roll'] != null) Text('Roll ${st['roll']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ])),
      trailing,
    ])));
  }
}

// ------------------------------------------------------------------ fuzzy matching of typed names (spelling mistakes are fine)
class Kid {
  final String id, name; final int? roll;
  const Kid(this.id, this.name, this.roll);
}

/// Result for one typed piece: exactly one child, several equally good (ask which), or none.
class AbsentQuery {
  final String query; final Kid? one; final List<Kid> many;
  const AbsentQuery(this.query, {this.one, this.many = const []});
}

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final x = prev[j] + 1, y = cur[j - 1] + 1, z = prev[j - 1] + cost;
      cur[j] = x < y ? (x < z ? x : z) : (y < z ? y : z);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// A roll number must match exactly. A name: distance on the first name (a typed beginning of 3+ letters counts as nearly exact),
/// plus an optional surname or its first letters ("ishan k"). More than 2 mistakes = not found.
AbsentQuery? matchAbsent(String raw, List<Kid> kids) {
  final q = raw.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();
  final shown = raw.trim();
  if (q.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(q)) {
    final n = int.parse(q);
    final k = kids.where((c) => c.roll == n).toList();
    return k.length == 1 ? AbsentQuery(shown, one: k.first) : k.length > 1 ? AbsentQuery(shown, many: k) : AbsentQuery(shown);
  }
  if (kids.isEmpty) return AbsentQuery(shown);
  final parts = q.split(RegExp(r'\s+'));
  final scored = <(Kid, double)>[];
  for (final c in kids) {
    final w = c.name.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ').trim().split(RegExp(r'\s+'));
    double s = levenshtein(parts[0], w[0]).toDouble();
    if (parts[0].length >= 3 && w[0].startsWith(parts[0]) && s > .5) s = .5;
    if (parts.length > 1) {
      final p1 = parts.sublist(1).join(' ');
      final last = w.length > 1 ? w.sublist(1).join(' ') : '';
      if (last.isEmpty) {
        s += 2;
      } else if (!last.startsWith(p1) && !w.skip(1).any((x) => x.startsWith(p1))) {
        final cut = last.length < p1.length ? last : last.substring(0, p1.length);
        final d = levenshtein(p1, cut);
        s += d < 2 ? d : 2;
      }
    }
    scored.add((c, s));
  }
  scored.sort((a, b) => a.$2.compareTo(b.$2));
  final best = scored.first.$2;
  if (best > 2) return AbsentQuery(shown);
  final tied = [for (final x in scored) if (x.$2 == best) x.$1];
  return tied.length > 1 ? AbsentQuery(shown, many: tied) : AbsentQuery(shown, one: tied.first);
}
