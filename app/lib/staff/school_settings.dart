import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/data3.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'staff_data.dart';
import 'staff_shell.dart';
import '../widgets/hub_tabs.dart';
import '../core/cache.dart';

/// School settings (IT): who can use which page, features on/off, the move-up dates and the school's details.
/// Everything is stored in school_setting and takes effect the next time a page opens.
String _msg(Object e) => friendlyError(e);

Future<void> saveSettings(WidgetRef ref, Map<String, String> values) async {
  final me = ref.read(sessionProvider).value?.staff?['id'];
  await db.from('school_setting').upsert([for (final e in values.entries) {'key': e.key, 'value': e.value, 'updated_by': me, 'updated_at': DateTime.now().toUtc().toIso8601String()}], onConflict: 'key');
  ref.invalidate(appSettingsProvider);
}

final yearMovePlanProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async => Map<String, dynamic>.from(await db.rpc('year_move_plan') as Map));

class SchoolSettingsScreen extends ConsumerStatefulWidget {
  const SchoolSettingsScreen({super.key});
  @override
  ConsumerState<SchoolSettingsScreen> createState() => _SchoolSettingsScreenState();
}

class _SchoolSettingsScreenState extends ConsumerState<SchoolSettingsScreen> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    if (!s.hasRole('it_admin') && !s.hasRole('principal')) return const StaffPage(title: 'School settings', body: NoteBox('Only IT can change school settings.'));
    final settings = ref.watch(appSettingsProvider);
    return StaffPage(
      title: 'School settings', hub: Hub.schoolSetup,
      subtitle: 'Who can use what, which features are on, the move-up dates and the school’s details. Changes apply at once.',
      body: settings.when(
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
        error: (e, _) => Text(_msg(e)),
        data: (m) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, l, ic) in [(0, 'Who can use what', Icons.lock_person_rounded), (1, 'Sections on / off', Icons.toggle_on_rounded), (2, 'Year dates', Icons.event_repeat_rounded), (3, 'School details', Icons.apartment_rounded), if (s.hasRole('it_admin')) (4, 'Branches', Icons.account_tree_rounded)])
              ChoiceChip(avatar: Icon(ic, size: 18, color: tab == i ? Colors.white : Brand.crimsonDeep), label: Text(l), selected: tab == i, showCheckmark: false,
                  selectedColor: Brand.crimson, labelStyle: TextStyle(fontWeight: FontWeight.w800, color: tab == i ? Colors.white : null), onSelected: (_) => setState(() => tab = i)),
          ]),
          const SizedBox(height: 16),
          switch (tab) {
            0 => _AccessTab(settings: m),
            1 => _FeaturesTab(settings: m),
            2 => _YearTab(settings: m),
            4 => const BranchesTab(),
            _ => _DetailsTab(settings: m),
          },
        ]),
      ),
    );
  }
}

// ================================================================== who can use what
class _AccessTab extends ConsumerStatefulWidget {
  final Map<String, String> settings;
  const _AccessTab({required this.settings});
  @override
  ConsumerState<_AccessTab> createState() => _AccessTabState();
}

class _AccessTabState extends ConsumerState<_AccessTab> {
  late final Map<String, Set<String>> chosen = {
    for (final m in [...staffMenu, ...staffSubPages]) if (!m.locked) m.path: chosenRolesOf(m, staffAccessOf(widget.settings)).toSet(),
  };
  bool busy = false;

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      // store only the pages that differ from the normal choice
      final out = <String, List<String>>{};
      for (final m in [...staffMenu, ...staffSubPages]) {
        if (m.locked) continue;
        final c = chosen[m.path]!;
        final normal = defaultRolesOf(m).toSet();
        if (c.length != normal.length || !c.containsAll(normal)) out[m.path] = c.toList();
      }
      await saveSettings(ref, {'staff_access': jsonEncode(out)});
      if (mounted) toast(context, 'Saved. Staff see the change the next time they open the app.');
    } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String? group;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(title: 'Who can use what', trailing: FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Tick the roles that see each page in their menu. Only roles that are allowed to see that information can be ticked.', style: TextStyle(color: cs.onSurfaceVariant)),
        for (final m in [...staffMenu, ...staffSubPages]) if (!m.locked) ...[
          if (group != m.group) ...[Padding(padding: const EdgeInsets.only(top: 16, bottom: 4), child: Text(group = m.group, style: const TextStyle(fontSize: 11.5, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: Brand.muted)))],
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: CardRow(children: [
            SizedBox(width: isNarrow(context) ? null : 190, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.icon, size: 18, color: Brand.crimson), const SizedBox(width: 8), Flexible(child: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w800)))])),
            const SizedBox(width: 10),
            Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in maxRolesOf(m)) FilterChip(
                label: Text(roleLabel(r), style: const TextStyle(fontSize: 12.5)), selected: chosen[m.path]!.contains(r), visualDensity: VisualDensity.compact,
                onSelected: (v) => setState(() => v ? chosen[m.path]!.add(r) : chosen[m.path]!.remove(r))),
            ])),
          ])),
        ],
      ])),
      const NoteBox('Today, My settings, Help and School settings are always available to the people who need them. What a person can see inside a page still follows their role (for example, a class teacher sees only their own class).'),
    ]);
  }
}

// ================================================================== features
class _FeaturesTab extends ConsumerStatefulWidget {
  final Map<String, String> settings;
  const _FeaturesTab({required this.settings});
  @override
  ConsumerState<_FeaturesTab> createState() => _FeaturesTabState();
}

class _FeaturesTabState extends ConsumerState<_FeaturesTab> {
  String branch = 'KN';                          // the main branch keeps the old "features" setting
  String get _key => branch == 'KN' ? 'features' : 'features:$branch';
  late Map<String, bool> on = _read();
  Map<String, bool> _read() {
    final m = {...widget.settings, 'features': widget.settings[_key] ?? (branch == 'KN' ? widget.settings['features'] ?? '{}' : '{}')};
    return {for (final f in featureList) f.$1: featureOn(m, f.$1)};
  }
  bool busy = false;
  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await saveSettings(ref, {_key: jsonEncode(on)});
      if (mounted) toast(context, 'Saved. Everyone sees the change the next time they open the app.');
    } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => busy = false);
  }
  @override
  Widget build(BuildContext context) {
    final it = ref.watch(sessionProvider).value?.hasRole('it_admin') ?? false;
    final branches = it ? (ref.watch(branchesProvider).value ?? const <Map<String, dynamic>>[]) : const <Map<String, dynamic>>[];
    return Panel(title: 'Sections on / off', trailing: FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Switch off a section the school does not use: it disappears from menus, Home and Help for everyone. Nothing is deleted; switch it on again and it is all back.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      // the branch box appears only for IT, and only matters once a second branch is started
      if (branches.length > 1) Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [
        const Text('Branch: ', style: TextStyle(fontWeight: FontWeight.w800)), const SizedBox(width: 8),
        Expanded(child: DropdownButton<String>(isExpanded: true, value: branch, items: [for (final b in branches) DropdownMenuItem(value: b['code'] as String,
            child: Text('${b['name']}${b['status'] == 'active' ? '' : ' · Not started yet'}', overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() { branch = v!; on = _read(); }))),
      ])),
      const SizedBox(height: 6),
      for (final (k, l, d) in featureList) SwitchListTile(contentPadding: EdgeInsets.zero, value: on[k]!, onChanged: (v) => setState(() => on[k] = v),
          title: Text(l, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(d)),
    ]));
  }
}

// ================================================================== branches (IT)
final branchesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  return List<Map<String, dynamic>>.from(await db.from('branch').select().order('sort'));
});

/// All branches of the group. Only Kalyan Nagar is running; the others are ready for when they start.
/// Starting a branch: fill its details here, set "Running", then load its students and staff with Import from Excel.
class BranchesTab extends ConsumerWidget {
  const BranchesTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ref.watch(branchesProvider).when(
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
      error: (e, _) => Text(_msg(e)),
      data: (list) => Panel(title: 'Branches', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Every branch of Royale Concorde. Families and staff never see this list; it is only for IT. A branch that has not started stays hidden everywhere.', style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        for (final b in list) ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: CircleAvatar(backgroundColor: b['status'] == 'active' ? Brand.greenTint : Brand.surface2, child: Icon(Icons.apartment_rounded, color: b['status'] == 'active' ? Brand.green : Brand.muted)),
          title: Text(b['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text([b['status'] == 'active' ? 'Running' : 'Not started yet', if (b['board'] != null) b['board'], if (b['affiliation_no'] != null) 'Affiliation ${b['affiliation_no']}', if (b['receipt_prefix'] != null) 'Receipts ${b['receipt_prefix']}…'].join(' · ')),
          trailing: const Icon(Icons.edit_rounded, size: 18),
          onTap: () async { if (await showDialog<bool>(context: context, builder: (_) => _BranchEditor(b: b)) == true) ref.invalidate(branchesProvider); }),
      ])),
    );
  }
}

class _BranchEditor extends StatefulWidget {
  final Map<String, dynamic> b;
  const _BranchEditor({required this.b});
  @override
  State<_BranchEditor> createState() => _BranchEditorState();
}

class _BranchEditorState extends State<_BranchEditor> {
  late final c = {for (final k in ['name', 'board', 'affiliation_no', 'address', 'phone', 'receipt_prefix']) k: TextEditingController(text: widget.b[k] ?? '')};
  late bool running = widget.b['status'] == 'active';
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    const labels = {'name': 'Branch name', 'board': 'Board (CBSE, Karnataka PU…)', 'affiliation_no': 'Affiliation number', 'address': 'Address (on certificates and receipts)', 'phone': 'Phone', 'receipt_prefix': 'Receipt number starts with'};
    return AlertDialog(title: Text(widget.b['name'] ?? 'Branch'), content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      for (final e in c.entries) Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: e.value, decoration: InputDecoration(labelText: labels[e.key]))),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: running, onChanged: widget.b['code'] == 'KN' ? null : (v) => setState(() => running = v),
          title: const Text('Running'), subtitle: Text(widget.b['code'] == 'KN' ? 'The main branch is always running.' : running ? 'The branch box appears for IT across the staff panel.' : 'Hidden everywhere until it starts.')),
    ]))), actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : () async {
        setState(() => busy = true);
        try {
          await db.from('branch').update({for (final e in c.entries) e.key: e.value.text.trim().isEmpty ? null : e.value.text.trim(), 'status': running ? 'active' : 'not_started', 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', widget.b['id']);
          if (context.mounted) Navigator.pop(context, true);
        } catch (e) { if (context.mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
      }, child: Text(busy ? 'Saving…' : 'Save')),
    ]);
  }
}

// ================================================================== year dates
class _YearTab extends ConsumerStatefulWidget {
  final Map<String, String> settings;
  const _YearTab({required this.settings});
  @override
  ConsumerState<_YearTab> createState() => _YearTabState();
}

class _YearTabState extends ConsumerState<_YearTab> {
  late String d1 = widget.settings['year_move_1_date'] ?? '03-01', d2 = widget.settings['year_move_2_date'] ?? '05-15';
  late Set<String> early = _set(widget.settings['year_move_1_grades'] ?? 'VIII,IX,XI');
  late Set<String> leaving = _set(widget.settings['year_leaving_grades'] ?? 'X,XII');
  late Set<String> keep = _set(widget.settings['year_keep_sections'] ?? 'XI');
  bool busy = false;
  static Set<String> _set(String v) => v.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toSet();
  static String _show(String mmdd) { final p = mmdd.split('-'); return DateFormat('d MMMM').format(DateTime(2001, int.parse(p[0]), int.parse(p[1]))); }

  Future<void> _pick(bool first) async {
    final cur = (first ? d1 : d2).split('-');
    final d = await showDatePicker(context: context, initialDate: DateTime(DateTime.now().year, int.parse(cur[0]), int.parse(cur[1])),
        firstDate: DateTime(DateTime.now().year - 1), lastDate: DateTime(DateTime.now().year + 2), helpText: 'Pick the day (the year does not matter)');
    if (d == null) return;
    final v = DateFormat('MM-dd').format(d);
    setState(() => first ? d1 = v : d2 = v);
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await saveSettings(ref, {'year_move_1_date': d1, 'year_move_2_date': d2, 'year_move_1_grades': early.join(','), 'year_leaving_grades': leaving.join(','), 'year_keep_sections': keep.join(',')});
      ref.invalidate(yearMovePlanProvider);
      if (mounted) toast(context, 'Saved.');
    } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _runNow(int step) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('Move classes up now (step $step)?'),
      content: Text(step == 1
          ? 'Grades ${early.join(', ')} move up one class for the new year. Students see their new class with “section to be announced” until you publish the new sections.'
          : 'Every other class moves up one class, the new year becomes the current year, and Grades ${leaving.join(', ')} become past students (their records are kept for ever).'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes, move up'))],
    ));
    if (ok != true) return;
    setState(() => busy = true);
    try {
      final r = await db.rpc('year_move_now', params: {'p_stage': step});
      ref.invalidate(yearMovePlanProvider); ref.invalidate(yearProvider);
      if (mounted) toast(context, r is Map && r['ok'] == true ? '${r['moved']} students moved up${(r['left'] ?? 0) > 0 ? ', ${r['left']} became past students' : ''}.' : '${(r as Map?)?['message'] ?? 'Done.'}');
    } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grades = ref.watch(gradesProvider).value ?? const <Map<String, dynamic>>[];
    final plan = ref.watch(yearMovePlanProvider).value;
    Widget gradeChips(Set<String> set) => Wrap(spacing: 6, runSpacing: 6, children: [
      for (final g in grades) FilterChip(label: Text('${g['code']}'), selected: set.contains(g['code']), visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() => v ? set.add(g['code']) : set.remove(g['code']))),
    ]);
    Widget step(int n, String date, bool? done, String what) => Container(
      margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: done == true ? Brand.greenTint : cs.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(14)),
      child: CardRow(children: [
        CircleAvatar(radius: 16, backgroundColor: done == true ? Brand.green : Brand.crimson, child: done == true ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Step $n · $date', style: TextStyle(fontWeight: FontWeight.w800, color: done == true ? Brand.ink : null)),
          Text(what, style: TextStyle(fontSize: 13, color: done == true ? Brand.muted : cs.onSurfaceVariant)),
        ])),
        if (done != true) OutlinedButton(onPressed: busy ? null : () => _runNow(n), child: const Text('Run now')),
      ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (plan != null) Panel(title: 'Coming move-up: ${plan['current']} → ${plan['next']}', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        step(1, DateFormat('d MMM yyyy').format(DateTime.parse(plan['step1_on'])), plan['step1_done'] == true, '${plan['step1_grades']} move up · ${keep.join(', ')} keep their sections and students'),
        step(2, DateFormat('d MMM yyyy').format(DateTime.parse(plan['step2_on'])), plan['step2_done'] == true, 'All other classes move up · ${plan['leaving']} become past students'),
        Text('It happens by itself early in the morning on these days. IT and the Principal get a reminder one week before.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
      ])),
      Panel(title: 'Dates and classes', trailing: FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Step 1 — early classes', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.event_rounded, size: 18), label: Text('Every year on ${_show(d1)}'))),
        const SizedBox(height: 8), Text('Grades that move up on this day:', style: TextStyle(color: cs.onSurfaceVariant)), const SizedBox(height: 6), gradeChips(early),
        const SizedBox(height: 10), Text('Grades that keep the same sections and students (streams):', style: TextStyle(color: cs.onSurfaceVariant)), const SizedBox(height: 6), gradeChips(keep),
        const Divider(height: 32),
        const Text('Step 2 — everyone else', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.event_rounded, size: 18), label: Text('Every year on ${_show(d2)}'))),
        const SizedBox(height: 8), Text('Grades that leave the school on this day (become past students):', style: TextStyle(color: cs.onSurfaceVariant)), const SizedBox(height: 6), gradeChips(leaving),
      ])),
    ]);
  }
}

// ================================================================== school details
class _DetailsTab extends ConsumerStatefulWidget {
  final Map<String, String> settings;
  const _DetailsTab({required this.settings});
  @override
  ConsumerState<_DetailsTab> createState() => _DetailsTabState();
}

class _DetailsTabState extends ConsumerState<_DetailsTab> {
  static const fields = [
    ('school_name', 'School name'), ('school_address', 'Address'), ('school_phone', 'Office phone'), ('school_email', 'Office email'),
    ('cbse_affiliation_no', 'CBSE affiliation number'), ('cbse_school_code', 'CBSE school code'),
  ];
  late final ctl = {for (final (k, _) in fields) k: TextEditingController(text: widget.settings[k] ?? '')};
  bool busy = false;
  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await saveSettings(ref, {for (final (k, _) in fields) k: ctl[k]!.text.trim()});
      if (mounted) toast(context, 'Saved. Receipts and report cards use the new details.');
    } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => busy = false);
  }
  @override
  Widget build(BuildContext context) => Panel(title: 'School details', trailing: FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')), child: Column(children: [
    for (final (k, l) in fields) Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(controller: ctl[k], minLines: 1, maxLines: k == 'school_address' ? 3 : 1, decoration: InputDecoration(labelText: l))),
    const NoteBox('These are printed on fee receipts and report cards.'),
  ]));
}
