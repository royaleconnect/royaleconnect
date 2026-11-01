import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/royal_motion.dart' show ConfettiBurst;
import '../widgets/common.dart' show Pill, NoteBox;
import '../auth/session.dart';
import 'staff_data.dart';
import 'staff_shell.dart';

/// Attendance in about 10 seconds: everyone starts as present; tap a name to mark absent (tap again: late, again: present).
/// Save tells the families of absent students straight away.
class StaffAttendanceScreen extends ConsumerStatefulWidget {
  const StaffAttendanceScreen({super.key});
  @override
  ConsumerState<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends ConsumerState<StaffAttendanceScreen> {
  String? section; DateTime day = DateTime.now();
  Map<String, dynamic>? sheet; final marks = <String, String>{}; bool loading = false, busy = false, saved = false;

  Future<void> _load() async {
    if (section == null) return;
    setState(() { loading = true; saved = false; });
    try {
      final r = Map<String, dynamic>.from(await db.rpc('attendance_sheet', params: {'p_section': section, 'p_day': DateFormat('yyyy-MM-dd').format(day)}) as Map);
      marks..clear()..addAll({for (final x in (r['students'] as List)) x['id'] as String: (x['status'] ?? 'present') as String});
      if (mounted) setState(() { sheet = r; loading = false; });
    } catch (e) { if (mounted) { setState(() => loading = false); toast(context, '$e'); } }
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      final ids = (String st) => [for (final e in marks.entries) if (e.value == st) e.key];
      final r = await db.rpc('attendance_save', params: {'p_section': section, 'p_day': DateFormat('yyyy-MM-dd').format(day), 'p_absent': ids('absent'), 'p_late': ids('late'), 'p_leave': ids('leave')});
      HapticFeedback.mediumImpact();
      final absent = (r as Map)['absent'] ?? 0;
      if (mounted) { setState(() { busy = false; saved = true; sheet = {...?sheet, 'marked': true}; }); toast(context, absent == 0 ? 'Saved ✓ Everyone present today.' : 'Saved ✓ $absent absent · their families have been told.'); }
    } catch (e) { if (mounted) { setState(() => busy = false); toast(context, '$e'.replaceAll(RegExp(r'^.*?message: |, code.*$'), '')); } }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final secs = ref.watch(mySectionsProvider).value ?? const <Map<String, dynamic>>[];
    final me = ref.watch(sessionProvider).value?.staff?['id'];
    // the class teacher's own class first (the office sees every class)
    final mine = [for (final s in secs) if (s['class_teacher_id'] == me) s];
    final list = mine.isNotEmpty ? mine : secs;
    if (section == null && list.isNotEmpty) { section = list.first['id'] as String; WidgetsBinding.instance.addPostFrameCallback((_) => _load()); }
    final students = [for (final x in (sheet?['students'] as List? ?? const [])) Map<String, dynamic>.from(x)];
    final absent = marks.values.where((v) => v == 'absent').length, late = marks.values.where((v) => v == 'late').length;
    final canMark = sheet?['can_mark'] == true;
    return StaffPage(title: 'Attendance', subtitle: 'Everyone starts as present. Tap the students who are absent, then Save. Families of absent students are told at once.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (list.length > 1) DropdownButton<String>(value: section, items: [for (final s in list) DropdownMenuItem(value: s['id'] as String, child: Text(_label(s)))],
              onChanged: (v) { setState(() => section = v); _load(); }),
          if (list.length == 1) Text(_label(list.first), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          OutlinedButton.icon(onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: day, firstDate: DateTime.now().subtract(const Duration(days: 60)), lastDate: DateTime.now());
            if (d != null) { setState(() => day = d); _load(); }
          }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(DateFormat('EEE, d MMM').format(day))),
          if (sheet?['marked'] == true) const Pill('Marked ✓', fg: Brand.green, bg: Brand.greenTint),
        ])),
        if (list.isEmpty) const NoteBox('Attendance is taken by the class teacher. You are not class teacher of a section this year.')
        else if (loading || sheet == null) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
        else ...[
          if (!canMark) const NoteBox('Only the class teacher (or the office) can take attendance for this class. You can see it here.'),
          Panel(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final st in students) _Chip(name: st['name'] ?? '', roll: st['roll'], status: marks[st['id']] ?? 'present', onTap: !canMark ? null : () {
              HapticFeedback.selectionClick();
              setState(() { saved = false; marks[st['id']] = switch (marks[st['id']]) { 'present' => 'absent', 'absent' => 'late', 'late' => 'present', 'leave' => 'present', _ => 'absent' }; });
            }),
          ])),
          if (canMark) Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            Row(children: [
              Expanded(child: Text('${students.length - absent - late - marks.values.where((v) => v == 'leave').length} present · $absent absent · $late late', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant))),
              FilledButton.icon(onPressed: busy ? null : _save, style: FilledButton.styleFrom(backgroundColor: Brand.crimson, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
                  icon: Icon(saved ? Icons.check_circle_rounded : Icons.save_rounded), label: Text(busy ? 'Saving…' : saved ? 'Saved' : 'Save attendance')),
            ]),
            if (saved) const Positioned(right: 40, child: IgnorePointer(child: SizedBox(width: 160, height: 120, child: ConfettiBurst()))),
          ]),
        ],
      ]));
  }
}

String _label(Map<String, dynamic> s) => '${s['grade']?['code'] ?? ''}-${s['name'] ?? ''}';

class _Chip extends StatelessWidget {
  final String name; final int? roll; final String status; final VoidCallback? onTap;
  const _Chip({required this.name, required this.roll, required this.status, this.onTap});
  @override
  Widget build(BuildContext context) {
    final (bg, fg, tag) = switch (status) {
      'absent' => (Brand.crimson, Colors.white, 'Absent'),
      'late' => (const Color(0xFFE0A21B), Colors.white, 'Late'),
      'leave' => (Brand.violet, Colors.white, 'Leave'),
      _ => (Theme.of(context).colorScheme.surfaceContainerHighest, Theme.of(context).colorScheme.onSurface, null),
    };
    return Material(color: bg, borderRadius: BorderRadius.circular(12), child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap,
      child: AnimatedContainer(duration: const Duration(milliseconds: 180), width: 168, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          if (roll != null) Text('$roll  ', style: TextStyle(color: fg.withValues(alpha: .7), fontWeight: FontWeight.w800, fontSize: 12)),
          Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13))),
          if (tag != null) Text(tag, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 11)),
        ]))));
  }
}
