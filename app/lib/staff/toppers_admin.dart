import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../core/data.dart';
import '../core/data3.dart';
import '../core/theme.dart';
import 'package:go_router/go_router.dart';
import '../auth/session.dart';
import '../screens/toppers_screen.dart' show Face, ToppersView, FameWall;
import '../widgets/common.dart';
import 'staff_screens_2.dart' show pickAndUpload;
import 'staff_shell.dart';

/// Office / IT / Principal: add Board Toppers (top 3 + centums, per year) and Hall of Fame entries.
/// Families see them under Home → Toppers. No consent step is needed for topper photos (school decision).
String _msg(Object e) => e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');
const _photoExt = ['jpg', 'jpeg', 'png', 'webp'];

/// What every teacher sees: the same Board Toppers and Hall of Fame as families. The office also gets “Edit”.
class StaffToppersScreen extends ConsumerStatefulWidget {
  const StaffToppersScreen({super.key});
  @override
  ConsumerState<StaffToppersScreen> createState() => _StaffToppersScreenState();
}

class _StaffToppersScreenState extends ConsumerState<StaffToppersScreen> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    final canEdit = s.isOffice;
    return StaffPage(
      title: 'Board Toppers & Hall of Fame', scroll: false,
      subtitle: 'The same page families see in the app.',
      actions: [if (canEdit) FilledButton.icon(onPressed: () => context.go('/staff/toppers/edit'), icon: const Icon(Icons.edit_rounded, size: 18), label: const Text('Add or change'))],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (i, l) in const [(0, 'Class X'), (1, 'Class XII'), (2, 'Hall of Fame')])
            ChoiceChip(label: Text(l), selected: tab == i, showCheckmark: false, selectedColor: Brand.crimson,
                labelStyle: TextStyle(fontWeight: FontWeight.w800, color: tab == i ? Colors.white : null), onSelected: (_) => setState(() => tab = i)),
        ]),
        const SizedBox(height: 8),
        Expanded(child: tab == 2 ? const FameWall() : ToppersView(key: ValueKey(tab), boardClass: tab == 0 ? 'X' : 'XII')),
      ]),
    );
  }
}

class ToppersAdminScreen extends ConsumerStatefulWidget {
  const ToppersAdminScreen({super.key});
  @override
  ConsumerState<ToppersAdminScreen> createState() => _ToppersAdminScreenState();
}

class _ToppersAdminScreenState extends ConsumerState<ToppersAdminScreen> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    return StaffPage(
      title: 'Board Toppers & Hall of Fame · add or change',
      actions: [OutlinedButton.icon(onPressed: () => context.go('/staff/toppers'), icon: const Icon(Icons.visibility_rounded, size: 18), label: const Text('See it as families do'))],
      subtitle: 'What families see under Home → Toppers. Add the top 3 and the subject centums for each year, and former students for the Hall of Fame.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (i, l, ic) in const [(0, 'Class X', Icons.emoji_events_rounded), (1, 'Class XII', Icons.emoji_events_rounded), (2, 'Hall of Fame', Icons.workspace_premium_rounded)])
            ChoiceChip(avatar: Icon(ic, size: 18, color: tab == i ? Colors.white : Brand.crimsonDeep), label: Text(l), selected: tab == i, showCheckmark: false,
                selectedColor: Brand.crimson, labelStyle: TextStyle(fontWeight: FontWeight.w800, color: tab == i ? Colors.white : null), onSelected: (_) => setState(() => tab = i)),
        ]),
        const SizedBox(height: 16),
        if (tab == 2) const _FameAdmin() else _ToppersAdmin(key: ValueKey(tab), boardClass: tab == 0 ? 'X' : 'XII'),
      ]),
    );
  }
}

// ================================================================== toppers of one class
class _ToppersAdmin extends ConsumerStatefulWidget {
  final String boardClass;
  const _ToppersAdmin({super.key, required this.boardClass});
  @override
  ConsumerState<_ToppersAdmin> createState() => _ToppersAdminState();
}

class _ToppersAdminState extends ConsumerState<_ToppersAdmin> {
  int? year;
  final extraYears = <int>{};

  void _refresh() { ref.invalidate(toppersProvider(widget.boardClass)); ref.invalidate(boardResultsProvider(widget.boardClass)); }

  /// Board results come out in May: a year can be added only from 15 May of that year (no empty future years).
  static int get latestYear { final d = DateTime.now(); return (d.month > 5 || (d.month == 5 && d.day >= 15)) ? d.year : d.year - 1; }

  Future<void> _addYear() async {
    final c = TextEditingController(text: '$latestYear');
    final y = await showDialog<int>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add a year'),
      content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'Year of the board exam', hintText: 'e.g. 2019')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: const Text('Add'))],
    ));
    if (y == null || y < 1980) return;
    if (y > latestYear) { if (mounted) toast(context, 'The $y board results come out in May $y. You can add $y from 15 May $y.'); return; }
    setState(() { extraYears.add(y); year = y; });
  }

  Future<void> _edit({Map<String, dynamic>? row, required int y, required String kind, int? rank}) async {
    final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _TopperEditor(row: row, year: y, boardClass: widget.boardClass, kind: kind, rank: rank));
    if (saved == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = ref.watch(toppersProvider(widget.boardClass));
    final results = ref.watch(boardResultsProvider(widget.boardClass)).value ?? const {};
    return all.when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
      error: (e, _) => Text(_msg(e), style: const TextStyle(color: Brand.crimsonDeep)),
      data: (rows) {
        final years = {for (final r in rows) (r['year'] as num).toInt(), ...results.keys, ...extraYears}.toList()..sort((a, b) => b.compareTo(a));
        final y = years.contains(year) ? year : (years.isEmpty ? null : years.first);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Panel(title: 'Class ${widget.boardClass} · years', trailing: FilledButton.icon(onPressed: _addYear, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add a year')),
            child: years.isEmpty
                ? Text('No years yet. Start with “Add a year” — for example the latest board results, then older years back to 2015 or earlier.', style: TextStyle(color: cs.onSurfaceVariant))
                : Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final x in years) ChoiceChip(label: Text('$x'), selected: x == y, showCheckmark: false, selectedColor: Brand.crimson,
                        labelStyle: TextStyle(fontWeight: FontWeight.w800, color: x == y ? Colors.white : null), onSelected: (_) => setState(() => year = x)),
                  ])),
          if (y != null) ...[
            _ResultPanel(key: ValueKey('${widget.boardClass}-$y'), boardClass: widget.boardClass, year: y, row: results[y], onSaved: _refresh),
            Panel(title: 'Top 3 · $y', child: Column(children: [
              for (final rank in [1, 2, 3]) Builder(builder: (_) {
                final r = rows.where((x) => (x['year'] as num).toInt() == y && x['kind'] == 'rank' && x['rank'] == rank).firstOrNull;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: r == null ? CircleAvatar(backgroundColor: Brand.surface2, child: Text('$rank', style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.muted))) : Face(r['full_name'] ?? '', r['photo_path'], size: 46),
                  title: Text(r == null ? '${const ['1st', '2nd', '3rd'][rank - 1]} place — not added' : '${const ['1st', '2nd', '3rd'][rank - 1]} · ${r['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: r == null ? null : Text([if (r['percent'] != null) '${r['percent']}%', if ((r['section'] ?? '').toString().isNotEmpty) r['section'], r['photo_path'] == null ? 'no photo yet' : 'photo added'].join(' · ')),
                  trailing: r == null ? OutlinedButton(onPressed: () => _edit(y: y, kind: 'rank', rank: rank), child: const Text('Add')) : const Icon(Icons.edit_rounded),
                  onTap: () => _edit(row: r, y: y, kind: 'rank', rank: rank),
                );
              }),
            ])),
            Panel(title: '💯 Centums · $y', trailing: OutlinedButton.icon(onPressed: () => _edit(y: y, kind: 'centum'), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add a centum')),
              child: Builder(builder: (_) {
                final c = rows.where((x) => (x['year'] as num).toInt() == y && x['kind'] == 'centum').toList()
                  ..sort((a, b) { final o = ((a['sort'] ?? 100) as int).compareTo((b['sort'] ?? 100) as int); return o != 0 ? o : '${a['subject']}'.compareTo('${b['subject']}'); });
                if (c.isEmpty) return Text('Students who scored 100 / 100 in a subject. One line per student per subject.', style: TextStyle(color: cs.onSurfaceVariant));
                return Column(children: [for (final r in c) ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Face(r['full_name'] ?? '', r['photo_path'], size: 40),
                  title: Text(r['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([r['subject'] ?? '', if ((r['section'] ?? '').toString().isNotEmpty) r['section']].join(' · ')),
                  trailing: const Icon(Icons.edit_rounded), onTap: () => _edit(row: r, y: y, kind: 'centum'),
                )]);
              })),
          ],
        ]);
      },
    );
  }
}

class _ResultPanel extends StatefulWidget {
  final String boardClass; final int year; final Map<String, dynamic>? row; final VoidCallback onSaved;
  const _ResultPanel({super.key, required this.boardClass, required this.year, required this.row, required this.onSaved});
  @override
  State<_ResultPanel> createState() => _ResultPanelState();
}

class _ResultPanelState extends State<_ResultPanel> {
  late final students = TextEditingController(text: widget.row?['students']?.toString() ?? '');
  late final pass = TextEditingController(text: widget.row?['pass_percent']?.toString() ?? '');
  late final dist = TextEditingController(text: widget.row?['distinctions']?.toString() ?? '');
  late final note = TextEditingController(text: widget.row?['note'] ?? '');
  bool busy = false;

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await db.from('board_result').upsert({
        'year': widget.year, 'board_class': widget.boardClass,
        'students': int.tryParse(students.text.trim()), 'pass_percent': num.tryParse(pass.text.trim()),
        'distinctions': int.tryParse(dist.text.trim()), 'note': note.text.trim().isEmpty ? null : note.text.trim(),
      }, onConflict: 'year,board_class');
      widget.onSaved();
      if (mounted) toast(context, 'Saved.');
    } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget f(TextEditingController c, String l) => Expanded(child: TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l)));
    return Panel(title: 'Results ${widget.year} (optional)', trailing: FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')), child: Column(children: [
      PickRow(children: [f(students, 'Students who wrote'), const SizedBox(width: 10), f(pass, 'Passed (%)'), const SizedBox(width: 10), f(dist, 'Scored 90% or more')]),
      const SizedBox(height: 10),
      TextField(controller: note, decoration: const InputDecoration(labelText: 'One line for families (optional)', hintText: 'e.g. 100% results for the 8th year running')),
    ]));
  }
}

class _TopperEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic>? row; final int year; final String boardClass, kind; final int? rank;
  const _TopperEditor({this.row, required this.year, required this.boardClass, required this.kind, this.rank});
  @override
  ConsumerState<_TopperEditor> createState() => _TopperEditorState();
}

class _TopperEditorState extends ConsumerState<_TopperEditor> {
  late final name = TextEditingController(text: widget.row?['full_name'] ?? '');
  late final section = TextEditingController(text: widget.row?['section'] ?? '');
  late final percent = TextEditingController(text: widget.row?['percent']?.toString() ?? '');
  late final subject = TextEditingController(text: widget.row?['subject'] ?? '');
  late final order = TextEditingController(text: '${widget.row?['sort'] ?? 100}');
  late String? photo = widget.row?['photo_path'];
  bool busy = false;
  bool get centum => widget.kind == 'centum';

  Future<void> _save() async {
    if (name.text.trim().isEmpty) { toast(context, 'Please type the name.'); return; }
    if (centum && subject.text.trim().isEmpty) { toast(context, 'Please type the subject.'); return; }
    setState(() => busy = true);
    try {
      final data = {
        'year': widget.year, 'board_class': widget.boardClass, 'kind': widget.kind, 'rank': centum ? null : widget.rank,
        'full_name': name.text.trim(), 'section': section.text.trim().isEmpty ? null : section.text.trim(),
        'percent': centum ? null : num.tryParse(percent.text.trim()), 'subject': centum ? subject.text.trim() : null, 'photo_path': photo, 'sort': int.tryParse(order.text.trim()) ?? 100,
      };
      if (widget.row == null) { await db.from('board_topper').insert(data); } else { await db.from('board_topper').update(data).eq('id', widget.row!['id']); }
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
  }

  Future<void> _delete() async {
    setState(() => busy = true);
    try { await db.from('board_topper').delete().eq('id', widget.row!['id']); if (mounted) Navigator.pop(context, true); }
    catch (e) { if (mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(centum ? 'Centum · ${widget.year}' : '${const ['1st', '2nd', '3rd'][(widget.rank ?? 1) - 1]} place · Class ${widget.boardClass} · ${widget.year}'),
    content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Face(name.text, photo, size: 86)),
      const SizedBox(height: 8),
      Center(child: Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: busy ? null : () async {
          try { final p = await pickAndUpload(context, 'toppers', ext: _photoExt, maxMb: 5); if (p != null) setState(() => photo = p); } catch (e) { if (context.mounted) toast(context, _msg(e)); }
        }, icon: const Icon(Icons.photo_camera_rounded, size: 18), label: Text(photo == null ? 'Add photo' : 'Change photo')),
        if (photo != null) TextButton(onPressed: () => setState(() => photo = null), child: const Text('Remove photo')),
      ])),
      const SizedBox(height: 12),
      TextField(controller: name, textCapitalization: TextCapitalization.words, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Student’s name *')),
      const SizedBox(height: 10),
      if (centum) ...[
        TextField(controller: subject, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Subject with 100 / 100 *', hintText: 'e.g. Mathematics')),
        const SizedBox(height: 10),
        TextField(controller: order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Subject order (1 = shown first)', helperText: 'Use the same number for every student of a subject, e.g. Social Science 1, English 2, A.I. 3')),
        const SizedBox(height: 10),
      ] else ...[
        TextField(controller: percent, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Percentage', hintText: 'e.g. 98.6')),
        const SizedBox(height: 10),
      ],
      TextField(controller: section, decoration: const InputDecoration(labelText: 'Class / stream (optional)', hintText: 'e.g. X-B or Science')),
    ]))),
    actions: [
      if (widget.row != null) TextButton(onPressed: busy ? null : _delete, child: const Text('Delete', style: TextStyle(color: Brand.crimson))),
      TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')),
    ],
  );
}

// ================================================================== hall of fame
class _FameAdmin extends ConsumerWidget {
  const _FameAdmin();

  Future<void> _edit(BuildContext context, WidgetRef ref, [Map<String, dynamic>? row]) async {
    final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _FameEditor(row: row));
    if (saved == true) ref.invalidate(hallOfFameProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ref.watch(hallOfFameProvider).when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
      error: (e, _) => Text(_msg(e), style: const TextStyle(color: Brand.crimsonDeep)),
      data: (rows) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(title: 'Hall of Fame · ${rows.length}', trailing: FilledButton.icon(onPressed: () => _edit(context, ref), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add a person')),
          child: rows.isEmpty
              ? Text('Former students and where they are today — e.g. “Dr. Priya S. · Batch 2015 · MBBS, AIIMS New Delhi”.', style: TextStyle(color: cs.onSurfaceVariant))
              : Column(children: [for (final r in rows) ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Face(r['full_name'] ?? '', r['photo_path'], size: 46),
                  title: Text('${r['full_name']}${r['batch'] != null ? ' · Batch ${r['batch']}' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${fameIcons[r['category']] ?? '⭐'} ${r['category']} · ${r['achievement']}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [if (r['spotlight'] == true) const Pill('Spotlight', fg: Brand.amber, bg: Brand.amberTint), const Icon(Icons.edit_rounded)]),
                  onTap: () => _edit(context, ref, r),
                )])),
        const NoteBox('“In the spotlight” puts the person in the big red banner at the top. Keep it to one or two people.'),
      ]),
    );
  }
}

class _FameEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic>? row;
  const _FameEditor({this.row});
  @override
  ConsumerState<_FameEditor> createState() => _FameEditorState();
}

class _FameEditorState extends ConsumerState<_FameEditor> {
  late final name = TextEditingController(text: widget.row?['full_name'] ?? '');
  late final batch = TextEditingController(text: widget.row?['batch']?.toString() ?? '');
  late final what = TextEditingController(text: widget.row?['achievement'] ?? '');
  late final order = TextEditingController(text: (widget.row?['sort'] ?? 100).toString());
  late String category = widget.row?['category'] ?? 'Academics';
  late bool spotlight = widget.row?['spotlight'] == true;
  late String? photo = widget.row?['photo_path'];
  bool busy = false;

  Future<void> _save() async {
    if (name.text.trim().isEmpty || what.text.trim().isEmpty) { toast(context, 'Name and “where they are today” are needed.'); return; }
    setState(() => busy = true);
    try {
      final data = {'full_name': name.text.trim(), 'batch': int.tryParse(batch.text.trim()), 'achievement': what.text.trim(), 'category': category,
        'spotlight': spotlight, 'sort': int.tryParse(order.text.trim()) ?? 100, 'photo_path': photo};
      if (widget.row == null) { await db.from('hall_of_fame').insert(data); } else { await db.from('hall_of_fame').update(data).eq('id', widget.row!['id']); }
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.row == null ? 'Add to the Hall of Fame' : 'Hall of Fame'),
    content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Face(name.text, photo, size: 86)),
      const SizedBox(height: 8),
      Center(child: Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: busy ? null : () async {
          try { final p = await pickAndUpload(context, 'fame', ext: _photoExt, maxMb: 5); if (p != null) setState(() => photo = p); } catch (e) { if (context.mounted) toast(context, _msg(e)); }
        }, icon: const Icon(Icons.photo_camera_rounded, size: 18), label: Text(photo == null ? 'Add photo' : 'Change photo')),
        if (photo != null) TextButton(onPressed: () => setState(() => photo = null), child: const Text('Remove photo')),
      ])),
      const SizedBox(height: 12),
      TextField(controller: name, textCapitalization: TextCapitalization.words, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Name *', hintText: 'e.g. Dr. Priya S.')),
      const SizedBox(height: 10),
      TextField(controller: batch, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Batch (year they passed out)', hintText: 'e.g. 2015')),
      const SizedBox(height: 10),
      TextField(controller: what, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Where they are today *', hintText: 'e.g. MBBS, AIIMS New Delhi')),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(value: fameCategories.contains(category) ? category : null, isExpanded: true, decoration: const InputDecoration(labelText: 'Field'),
          items: [for (final c in fameCategories) DropdownMenuItem(value: c, child: Text('${fameIcons[c]} $c'))], onChanged: (v) => setState(() => category = v ?? category)),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: spotlight, onChanged: (v) => setState(() => spotlight = v), title: const Text('In the spotlight'), subtitle: const Text('Shown big at the top')),
      TextField(controller: order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Order (smaller first)')),
    ]))),
    actions: [
      if (widget.row != null) TextButton(onPressed: busy ? null : () async {
        setState(() => busy = true);
        try { await db.from('hall_of_fame').delete().eq('id', widget.row!['id']); if (context.mounted) Navigator.pop(context, true); }
        catch (e) { if (context.mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
      }, child: const Text('Delete', style: TextStyle(color: Brand.crimson))),
      TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')),
    ],
  );
}
