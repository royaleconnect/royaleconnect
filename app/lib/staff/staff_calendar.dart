import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/data.dart';
import '../core/theme.dart';
import 'staff_data.dart';
import 'staff_shell.dart';

/// Office: add, change or remove holidays and events. Families see changes at once in their calendar and "Your day" card.
/// Who can edit: office, principal, vice principal, IT admin (database rule cal_write). Every change is recorded in audit_log.

final staffCalendarProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await db.from('calendar_event')
      .select('id,title,starts_on,ends_on,kind,grades,note,academic_year!inner(is_current)')
      .eq('academic_year.is_current', true).order('starts_on', ascending: true);
  return List<Map<String, dynamic>>.from(data);
});

const _kinds = {'holiday': 'Holiday', 'event': 'Event', 'exam': 'Exam', 'ptm': 'Parents’ meeting'};
const _kindColors = {
  'holiday': (Brand.crimsonDeep, Brand.crimsonTint),
  'event': (Brand.blue, Brand.blueTint),
  'exam': (Brand.amber, Brand.amberTint),
  'ptm': (Brand.violet, Brand.violetTint),
};
String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String _who(Map<String, dynamic> e) {
  final g = List<String>.from(e['grades'] ?? const []);
  return g.isEmpty ? 'Whole school' : g.join(', ');
}
bool _on(Map<String, dynamic> e, String day) => (e['starts_on'] as String).compareTo(day) <= 0 && ((e['ends_on'] ?? e['starts_on']) as String).compareTo(day) >= 0;

class StaffCalendarScreen extends ConsumerStatefulWidget {
  const StaffCalendarScreen({super.key});
  @override
  ConsumerState<StaffCalendarScreen> createState() => _StaffCalendarScreenState();
}

class _StaffCalendarScreenState extends ConsumerState<StaffCalendarScreen> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  Future<void> _edit([Map<String, dynamic>? e, DateTime? day]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _EventEditor(event: e, day: day));
    if (saved == true) ref.invalidate(staffCalendarProvider);
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(staffCalendarProvider);
    final cs = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1), last = DateTime(month.year, month.month + 1, 0);
    final inMonth = (events.value ?? const <Map<String, dynamic>>[]).where((e) =>
        (e['starts_on'] as String).compareTo(_iso(last)) <= 0 && ((e['ends_on'] ?? e['starts_on']) as String).compareTo(_iso(first)) >= 0).toList();
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final monthBar = Row(children: [
      IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left_rounded), tooltip: 'Previous month'),
      Text(DateFormat('MMMM yyyy').format(month), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right_rounded), tooltip: 'Next month'),
      const Spacer(),
      TextButton(onPressed: () => setState(() => month = DateTime(DateTime.now().year, DateTime.now().month)), child: const Text('This month')),
    ]);

    final list = Panel(padding: const EdgeInsets.fromLTRB(8, 8, 8, 8), child: inMonth.isEmpty
        ? Padding(padding: const EdgeInsets.all(14), child: Text('Nothing on the calendar in ${DateFormat('MMMM').format(month)} yet.', style: TextStyle(color: cs.onSurfaceVariant)))
        : Column(children: [for (final e in inMonth) _EventTile(e, onTap: () => _edit(e))]));

    return StaffPage(
      title: 'School calendar',
      subtitle: 'Holidays, events, exams and parents’ meetings. Changes reach families’ calendars straight away.',
      actions: [FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('Add holiday / event'))],
      body: events.when(
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
        error: (e, _) => Text('$e', style: const TextStyle(color: Brand.crimsonDeep)),
        data: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          monthBar,
          const SizedBox(height: 8),
          if (wide) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: Panel(padding: const EdgeInsets.all(10), child: _MonthGrid(month: month, events: inMonth, onTapEvent: (e) => _edit(e), onTapDay: (d) => _edit(null, d)))),
            const SizedBox(width: 14),
            Expanded(flex: 2, child: list),
          ]) else list,
        ]),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final Map<String, dynamic> e; final VoidCallback onTap;
  const _EventTile(this.e, {required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = _kindColors[e['kind']] ?? (Brand.muted, Brand.surface2);
    final s = DateTime.parse(e['starts_on']);
    final en = e['ends_on'] == null ? null : DateTime.parse(e['ends_on']);
    final when = en == null || !en.isAfter(s) ? DateFormat('EEE d MMM').format(s) : '${DateFormat('d MMM').format(s)} – ${DateFormat('d MMM').format(en)}';
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: context.tone(c.$1), shape: BoxShape.circle)),
      title: Text(e['title'], style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('$when · ${_kinds[e['kind']] ?? e['kind']} · ${_who(e)}${(e['note'] ?? '').toString().trim().isEmpty ? '' : '\n${e['note']}'}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      trailing: Icon(Icons.edit_outlined, size: 18, color: cs.onSurfaceVariant),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month; final List<Map<String, dynamic>> events;
  final void Function(Map<String, dynamic>) onTapEvent; final void Function(DateTime) onTapDay;
  const _MonthGrid({required this.month, required this.events, required this.onTapEvent, required this.onTapDay});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final start = first.subtract(Duration(days: first.weekday - 1));   // Monday on or before the 1st
    final today = _iso(DateTime.now());
    final weeks = <Widget>[];
    for (var w = 0; w < 6; w++) {
      final row = <Widget>[];
      for (var i = 0; i < 7; i++) {
        final d = DateTime(start.year, start.month, start.day + w * 7 + i);
        final key = _iso(d);
        final inMonth = d.month == month.month;
        final dayEvents = inMonth ? events.where((e) => _on(e, key)).toList() : const <Map<String, dynamic>>[];
        row.add(Expanded(child: Padding(padding: const EdgeInsets.all(2.5), child: InkWell(
          onTap: inMonth ? () => onTapDay(d) : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 86, padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: inMonth ? cs.surface : cs.surfaceContainerHighest.withValues(alpha: .4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: key == today ? Brand.crimson : cs.outline.withValues(alpha: .5), width: key == today ? 1.6 : .8),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d.day}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: !inMonth ? cs.onSurfaceVariant.withValues(alpha: .4) : d.weekday == DateTime.sunday ? context.tone(Brand.crimson) : cs.onSurfaceVariant)),
              for (final e in dayEvents.take(2)) Builder(builder: (_) {
                final c = _kindColors[e['kind']] ?? (Brand.muted, Brand.surface2);
                return GestureDetector(onTap: () => onTapEvent(e), child: Container(
                  margin: const EdgeInsets.only(top: 3), padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5), width: double.infinity,
                  decoration: BoxDecoration(color: c.$2, borderRadius: BorderRadius.circular(4)),
                  child: Text(e['title'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c.$1)),
                ));
              }),
              if (dayEvents.length > 2) Text('+${dayEvents.length - 2} more', style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant)),
            ]),
          ),
        ))));
      }
      weeks.add(Row(children: row));
      if (DateTime(start.year, start.month, start.day + (w + 1) * 7).month != month.month && w >= 3) break;
    }
    return Column(children: [
      Row(children: [for (final h in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) Expanded(child: Center(child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(h, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)))))]),
      ...weeks,
      Padding(padding: const EdgeInsets.only(top: 6), child: Text('Tap a day to add something on that date. Tap an item to change or delete it.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))),
    ]);
  }
}

// ---------------------------------------------------------------- add / change / delete
class _EventEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic>? event; final DateTime? day;
  const _EventEditor({this.event, this.day});
  @override
  ConsumerState<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends ConsumerState<_EventEditor> {
  late String kind = widget.event?['kind'] ?? 'holiday';
  late final title = TextEditingController(text: widget.event?['title'] ?? '');
  late final note = TextEditingController(text: widget.event?['note'] ?? '');
  late DateTime from = widget.event == null ? (widget.day ?? DateTime.now()) : DateTime.parse(widget.event!['starts_on']);
  late DateTime to = widget.event?['ends_on'] == null ? from : DateTime.parse(widget.event!['ends_on']);
  late final Set<String> grades = Set<String>.from(widget.event?['grades'] ?? const []);
  late bool tell = widget.event == null;
  bool busy = false;

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2025), lastDate: DateTime(2030));

  Future<void> _save() async {
    if (title.text.trim().isEmpty) { toast(context, 'Please type a title.'); return; }
    if (to.isBefore(from)) { toast(context, '“To” date is before the “From” date.'); return; }
    setState(() => busy = true);
    try {
      final year = await ref.read(yearProvider.future);
      final row = {
        'title': title.text.trim(), 'kind': kind, 'starts_on': _iso(from), 'ends_on': _iso(to) == _iso(from) ? null : _iso(to),
        'grades': grades.toList(), 'audience_all': grades.isEmpty, 'note': note.text.trim().isEmpty ? null : note.text.trim(),
        'updated_by': myId(ref), 'updated_at': nowIso(),
      };
      String id;
      if (widget.event == null) {
        id = (await db.from('calendar_event').insert({...row, 'academic_year_id': year['id']}).select('id').single())['id'];
      } else {
        id = widget.event!['id'];
        await db.from('calendar_event').update(row).eq('id', id);
      }
      var sent = 0;
      if (tell) sent = (await db.rpc('notify_calendar_event', params: {'eid': id})) as int;
      if (mounted) { toast(context, tell ? 'Saved. $sent families are being told.' : 'Saved.'); Navigator.pop(context, true); }
    } catch (e) {
      if (mounted) { toast(context, 'Could not save: $e'); setState(() => busy = false); }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Delete this item?'),
      content: Text('“${widget.event!['title']}” will disappear from every family’s calendar.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))],
    ));
    if (ok != true) return;
    setState(() => busy = true);
    try {
      await db.from('calendar_event').delete().eq('id', widget.event!['id']);
      if (mounted) { toast(context, 'Deleted.'); Navigator.pop(context, true); }
    } catch (e) {
      if (mounted) { toast(context, 'Could not delete: $e'); setState(() => busy = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allGrades = ref.watch(gradesProvider).value ?? const <Map<String, dynamic>>[];
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .4, color: cs.onSurfaceVariant)));
    final df = DateFormat('d MMM yyyy');
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text(widget.event == null ? 'Add to calendar' : 'Change calendar item', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        label('WHAT IS IT'),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final k in _kinds.entries) ChoiceChip(label: Text(k.value), selected: kind == k.key, onSelected: (_) => setState(() => kind = k.key))]),
        label('TITLE'),
        TextField(controller: title, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'e.g. Deepavali, Science Expo, Periodic Test 2')),
        label('DATE'),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () async { final d = await _pick(from); if (d != null) setState(() { from = d; if (to.isBefore(d)) to = d; }); }, icon: const Icon(Icons.event_rounded, size: 18), label: Text('From ${df.format(from)}'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: () async { final d = await _pick(to.isBefore(from) ? from : to); if (d != null) setState(() => to = d); }, icon: const Icon(Icons.event_rounded, size: 18), label: Text('To ${df.format(to)}'))),
        ]),
        label('FOR'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          FilterChip(label: const Text('Whole school'), selected: grades.isEmpty, onSelected: (_) => setState(grades.clear)),
          for (final g in allGrades) FilterChip(label: Text(g['code']), selected: grades.contains(g['code']), onSelected: (v) => setState(() => v ? grades.add(g['code']) : grades.remove(g['code']))),
        ]),
        label('NOTE FOR PARENTS (OPTIONAL)'),
        TextField(controller: note, minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'e.g. Students may come in house T-shirts.')),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero, value: tell, onChanged: (v) => setState(() => tell = v),
          title: const Text('Tell families now', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(grades.isEmpty ? 'Sends a notification to every family' : 'Sends a notification to grades ${grades.join(', ')}'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          if (widget.event != null) TextButton.icon(onPressed: busy ? null : _delete, icon: const Icon(Icons.delete_outline_rounded, color: Brand.crimson), label: const Text('Delete', style: TextStyle(color: Brand.crimson))),
          const Spacer(),
          TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
          const SizedBox(width: 8),
          FilledButton(onPressed: busy ? null : _save, child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
        ]),
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('Every change is recorded with who made it.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))),
      ]))),
    );
  }
}
