import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../auth/session.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'import_excel.dart';
import 'staff_data.dart';
import 'staff_shell.dart';

/// School setup: the school adds and changes its own records — no import sheet, no IT person needed.
///   Students · Staff · Classes · Fees · Bus routes
/// Every save goes through one checked database function (0016_school_setup.sql) that also writes the activity log.

// ------------------------------------------------------------------ who sees which tab
// Students, Staff and Bus routes now live on their own pages (Students · Staff · Transport).
const _tabRoles = {
  'classes': ['office', 'it_admin', 'principal', 'vice_principal'],
  'fees': ['accounts', 'it_admin', 'principal'],
  'import': ['office', 'accounts', 'transport_incharge', 'it_admin', 'principal', 'vice_principal'],
};
const _tabNames = {'students': 'Students', 'staff': 'Staff', 'classes': 'Classes', 'fees': 'Fees', 'transport': 'Bus routes', 'import': 'Import from Excel'};
const _tabIcons = {'students': Icons.school_rounded, 'staff': Icons.badge_rounded, 'classes': Icons.class_rounded, 'fees': Icons.currency_rupee_rounded, 'transport': Icons.directions_bus_rounded, 'import': Icons.upload_file_rounded};
const setupRoles = ['office', 'accounts', 'transport_incharge', 'it_admin', 'principal', 'vice_principal'];

String _msg(Object e) => e is PostgrestException ? e.message : e.toString().replaceFirst('Exception: ', '');
String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String _time12(dynamic t) {
  if (t == null || t.toString().length < 5) return '—';
  final p = t.toString().split(':');
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, int.parse(p[0]), int.parse(p[1])));
}

Widget _loading() => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
Widget _err(Object e) => Padding(padding: const EdgeInsets.all(24), child: Text(_msg(e), style: const TextStyle(color: Brand.crimsonDeep)));
Widget _label(BuildContext context, String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .4, color: Theme.of(context).colorScheme.onSurfaceVariant)));

/// A centred form dialog that scrolls and fits phones.
Widget _form(BuildContext context, {required String title, required List<Widget> children, required List<Widget> actions, double maxWidth = 520}) => Dialog(
  insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
  child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 16), child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ...children,
      const SizedBox(height: 18),
      Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
    ]))),
);

Future<bool> _confirm(BuildContext context, String title, String body, String yes) async => (await showDialog<bool>(context: context, builder: (c) => AlertDialog(
  title: Text(title), content: Text(body),
  actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes))],
))) == true;

void _slip(BuildContext context, String title, String text) => showDialog(context: context, builder: (ctx) => AlertDialog(
  title: Text(title),
  content: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', height: 1.6)),
  actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
));

// ------------------------------------------------------------------ data
final setupSectionsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await db.from('section')
      .select('id,name,class_teacher_id,academic_year_id,grade:grade_id(id,code,name,sort_order),class_teacher:class_teacher_id(display_name),enrolment(count),teaching_assignment(subject_id,staff_id)')
      .eq('status', 'active').eq('placeholder', false);
  final rows = List<Map<String, dynamic>>.from(data);
  rows.sort((a, b) {
    final g = ((a['grade']?['sort_order'] ?? 0) as int).compareTo((b['grade']?['sort_order'] ?? 0) as int);
    return g != 0 ? g : (a['name'] as String).compareTo(b['name'] as String);
  });
  return rows;
});

bool _isCrew(Map<String, dynamic> st) => List<String>.from(st['roles'] ?? const []).any((r) => r == 'driver' || r == 'conductor');

/// Active teaching staff, for "class teacher" / "subject teacher" pickers.
final _teachersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await ref.watch(staffListProvider.future);
  return rows.where((s) => s['active'] == true && !_isCrew(s)).toList();
});

final _feePlanProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, gradeId) async {
  final yearId = await gradeYearId(gradeId);
  final data = await db.from('fee_plan').select('id,amount,due_on,optional,fee_head:fee_head_id(id,name,kind,sort_order)')
      .eq('academic_year_id', yearId).eq('grade_id', gradeId);
  final rows = List<Map<String, dynamic>>.from(data);
  rows.sort((a, b) => ((a['due_on'] ?? '') as String).compareTo((b['due_on'] ?? '') as String));
  return rows;
});
final _feeHeadsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async =>
    List<Map<String, dynamic>>.from(await db.from('fee_head').select('id,name,kind').order('sort_order', ascending: true)));

final _routeStudentsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, routeId) async {
  final data = await db.from('transport_enrolment').select('student_id,stop_id,student:student_id(full_name,admission_no),stop:stop_id(name,seq)').eq('route_id', routeId);
  final rows = List<Map<String, dynamic>>.from(data);
  rows.sort((a, b) => ((a['stop']?['seq'] ?? 0) as int).compareTo((b['stop']?['seq'] ?? 0) as int));
  return rows;
});

// ------------------------------------------------------------------ screen
class SchoolSetupScreen extends ConsumerStatefulWidget {
  const SchoolSetupScreen({super.key});
  @override
  ConsumerState<SchoolSetupScreen> createState() => _SchoolSetupScreenState();
}

class _SchoolSetupScreenState extends ConsumerState<SchoolSetupScreen> {
  String? tab;
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    final tabs = [for (final e in _tabRoles.entries) if (e.value.any(s.hasRole)) e.key];
    if (tabs.isEmpty) return const StaffPage(title: 'Classes & fees', body: NoteBox('Your role does not include this page.'));
    final t = tabs.contains(tab) ? tab! : tabs.first;
    return StaffPage(
      title: 'Classes & fees',
      subtitle: 'Sections and their teachers, the fee plan for each grade, and loading lists from Excel. Every change is saved at once and recorded in the activity log.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          for (final k in tabs) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
            avatar: Icon(_tabIcons[k], size: 18, color: k == t ? Colors.white : Brand.crimsonDeep),
            label: Text(_tabNames[k]!), selected: k == t, showCheckmark: false,
            selectedColor: Brand.crimson, labelStyle: TextStyle(fontWeight: FontWeight.w800, color: k == t ? Colors.white : null),
            onSelected: (_) => setState(() => tab = k))),
        ])),
        const SizedBox(height: 16),
        switch (t) {
          'classes' => const _ClassesTab(),
          'fees' => const _FeesTab(),
          'import' => const ImportTab(),
          _ => const _ClassesTab(),
        },
      ]),
    );
  }
}

// ================================================================== STUDENTS
/// Add or change one student (new admission, class, phones, bus, leaving). Opened from the Students page.
class StudentEditor extends ConsumerStatefulWidget {
  final String? studentId; final String? sectionId;
  const StudentEditor({super.key, this.studentId, this.sectionId});
  @override
  ConsumerState<StudentEditor> createState() => StudentEditorState();
}

class StudentEditorState extends ConsumerState<StudentEditor> {
  bool loading = true, busy = false;
  final adm = TextEditingController(), name = TextEditingController(), father = TextEditingController(), mother = TextEditingController(),
      guardian = TextEditingController(), address = TextEditingController(), blood = TextEditingController(), house = TextEditingController();
  final phones = [TextEditingController(), TextEditingController(), TextEditingController()];
  final labels = ['Father', 'Mother', 'Other'];
  DateTime? dob, tc;
  String? gender, sectionId, routeId, stopId, origRoute, origStop;
  String admissionType = 'Day Scholar';
  bool consent = false, active = true, addFees = true;

  bool get isNew => widget.studentId == null;

  @override
  void initState() {
    super.initState();
    sectionId = widget.sectionId;
    if (isNew) { loading = false; } else { _load(); }
  }

  Future<void> _load() async {
    try {
      final r = await db.from('student')
          .select('id,admission_no,full_name,dob,gender,blood_group,house,admission_type,address,father_name,mother_name,guardian_name,photo_consent,active,tc_issued_on,'
              'family_phone(phone,label,is_primary),enrolment(section_id,is_current),transport_enrolment(route_id,stop_id)')
          .eq('id', widget.studentId!).eq('enrolment.is_current', true).single();
      adm.text = r['admission_no'] ?? ''; name.text = r['full_name'] ?? '';
      father.text = r['father_name'] ?? ''; mother.text = r['mother_name'] ?? ''; guardian.text = r['guardian_name'] ?? '';
      address.text = r['address'] ?? ''; blood.text = r['blood_group'] ?? ''; house.text = r['house'] ?? '';
      dob = r['dob'] == null ? null : DateTime.parse(r['dob']);
      tc = r['tc_issued_on'] == null ? null : DateTime.parse(r['tc_issued_on']);
      gender = r['gender']; admissionType = r['admission_type'] ?? 'Day Scholar';
      consent = r['photo_consent'] == true; active = r['active'] != false;
      final ph = List<Map<String, dynamic>>.from(r['family_phone'] ?? const [])..sort((a, b) => (b['is_primary'] == true ? 1 : 0) - (a['is_primary'] == true ? 1 : 0));
      for (var i = 0; i < ph.length && i < 3; i++) { phones[i].text = ph[i]['phone'] ?? ''; labels[i] = ph[i]['label'] ?? labels[i]; }
      final en = r['enrolment'] as List?;
      if (en != null && en.isNotEmpty) sectionId = en.first['section_id'];
      final te = r['transport_enrolment'];
      final t = te is List ? (te.isEmpty ? null : te.first) : te;
      if (t != null) { routeId = origRoute = t['route_id']; stopId = origStop = t['stop_id']; }
    } catch (e) {
      if (mounted) toast(context, 'Could not open: ${_msg(e)}');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _save() async {
    if (adm.text.trim().isEmpty || name.text.trim().isEmpty || dob == null) { toast(context, 'Admission number, name and date of birth are needed.'); return; }
    final list = <Map<String, String>>[];
    for (var i = 0; i < 3; i++) {
      final d = phones[i].text.replaceAll(RegExp(r'\D'), '');
      if (d.isEmpty) continue;
      if (d.length < 10) { toast(context, 'Phone ${i + 1} needs 10 digits.'); return; }
      list.add({'phone': d.substring(d.length - 10), 'label': labels[i]});
    }
    if (list.isEmpty) { toast(context, 'Add at least one parent phone number — notifications and sign-in depend on it.'); return; }
    if (routeId != null && stopId == null) { toast(context, 'Pick the bus stop too.'); return; }
    setState(() => busy = true);
    try {
      String? n(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
      final id = await db.rpc('admin_save_student', params: {'p': {
        'id': widget.studentId, 'admission_no': adm.text.trim(), 'full_name': name.text.trim(), 'dob': _iso(dob!), 'gender': gender,
        'blood_group': n(blood), 'house': n(house), 'admission_type': admissionType, 'address': n(address),
        'father_name': n(father), 'mother_name': n(mother), 'guardian_name': n(guardian), 'photo_consent': consent, 'active': active,
        'section_id': sectionId, 'phones': list, 'add_fees': addFees,
      }}) as String;
      if (routeId != origRoute || stopId != origStop) {
        await db.rpc('admin_set_transport', params: {'p_student': id, 'p_route': routeId, 'p_stop': routeId == null ? null : stopId});
      }
      if (!active && tc != null) await db.from('student').update({'tc_issued_on': _iso(tc!)}).eq('id', id);
      // a student who leaves goes to Past students (the date is kept the first time only)
      if (!active) { try { await db.from('student').update({'left_on': _iso(tc ?? DateTime.now()), 'leaving_reason': tc != null ? 'Left with TC' : 'Left the school'}).eq('id', id).isFilter('left_on', null); } catch (_) {} }
      if (!active) { try { await callFunction(ref, 'password', {'action': 'signout_all', 'student_id': id}); } catch (_) {} }
      String? pw;
      if (isNew) {
        try { pw = (await callFunction(ref, 'password', {'action': 'reset', 'student_id': id, 'via': 'print'}))['first_use_password']?.toString(); } catch (_) {}
      }
      if (!mounted) return;
      final nav = Navigator.of(context); final outer = nav.context;
      nav.pop(true);
      if (pw != null && outer.mounted) {
        _slip(outer, 'Admitted — password slip', 'Royale Connect — first-use password\n\nStudent: ${name.text.trim()}\nAdmission no: ${adm.text.trim().toUpperCase()}\nPassword: $pw\n\nSign in with the admission number and this password, then set your own password. This slip is the only copy.');
      } else if (outer.mounted) {
        toast(outer, 'Saved.');
      }
    } catch (e) {
      if (mounted) { toast(context, _msg(e)); setState(() => busy = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Dialog(child: Padding(padding: EdgeInsets.all(40), child: Center(heightFactor: 1, child: CircularProgressIndicator())));
    final sections = ref.watch(setupSectionsProvider).value ?? const <Map<String, dynamic>>[];
    final routes = ref.watch(routesProvider).value ?? const <Map<String, dynamic>>[];
    final route = routes.where((r) => r['id'] == routeId).firstOrNull;
    final stops = List<Map<String, dynamic>>.from(route?['route_stop'] ?? const [])..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
    final df = DateFormat('d MMM yyyy');
    final narrow = isNarrow(context);
    Widget two(Widget a, Widget b) => narrow ? Column(children: [a, const SizedBox(height: 10), b]) : Row(children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]);

    return _form(context, title: isNew ? 'New admission' : 'Student details', maxWidth: 620, children: [
      _label(context, 'STUDENT'),
      two(TextField(controller: adm, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Admission number *', hintText: 'e.g. RC/1234/2026')),
          TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name *'))),
      const SizedBox(height: 10),
      two(OutlinedButton.icon(onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: dob ?? DateTime(DateTime.now().year - 8), firstDate: DateTime(1995), lastDate: DateTime.now());
            if (d != null) setState(() => dob = d);
          }, icon: const Icon(Icons.cake_rounded, size: 18), label: Text(dob == null ? 'Date of birth *' : 'Born ${df.format(dob!)}')),
          Wrap(spacing: 8, children: [for (final g in const ['Male', 'Female']) ChoiceChip(label: Text(g), selected: gender == g, onSelected: (v) => setState(() => gender = v ? g : null))])),
      const SizedBox(height: 10),
      two(PickField<String?>(label: 'Class', value: sectionId, onChanged: (v) => setState(() => sectionId = v),
              items: [
                if (sectionId != null && !sections.any((x) => x['id'] == sectionId)) DropdownMenuItem<String?>(value: sectionId, child: const Text('Keep the class it has now')),
                const DropdownMenuItem<String?>(value: null, child: Text('No class yet — placed later in New sections')),
                for (final s in sections) DropdownMenuItem<String?>(value: s['id'] as String, child: Text(sectionLabel(s))),
              ]),
          PickField<String>(label: 'Admission type', value: admissionType, onChanged: (v) => setState(() => admissionType = v ?? 'Day Scholar'),
              items: [for (final a in {'Day Scholar', 'Day Boarder', 'Boarder', admissionType}) DropdownMenuItem(value: a, child: Text(a))])),
      if (isNew) CheckboxListTile(contentPadding: EdgeInsets.zero, value: addFees, onChanged: (v) => setState(() => addFees = v ?? true),
          title: const Text('Add this year’s fees for the class'), subtitle: const Text('From the fee plan in Classes & fees → Fees. Concessions can be set in the Fees desk.')),

      _label(context, 'PARENTS’ PHONES — SIGN-IN AND NOTIFICATIONS'),
      for (var i = 0; i < 3; i++) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
        SizedBox(width: 110, child: DropdownButtonFormField<String>(value: labels[i], isExpanded: true, decoration: const InputDecoration(),
            items: [for (final l in {'Father', 'Mother', 'Guardian', 'Other', labels[i]}) DropdownMenuItem(value: l, child: Text(l))],
            onChanged: (v) => setState(() => labels[i] = v ?? labels[i]))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: phones[i], keyboardType: TextInputType.phone, decoration: InputDecoration(hintText: i == 0 ? '10-digit mobile *' : '10-digit mobile (optional)'))),
      ])),

      _label(context, 'FAMILY'),
      two(TextField(controller: father, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Father’s name')),
          TextField(controller: mother, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Mother’s name'))),
      const SizedBox(height: 10),
      TextField(controller: guardian, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Guardian (if different)')),
      const SizedBox(height: 10),
      TextField(controller: address, minLines: 2, maxLines: 3, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Address')),
      const SizedBox(height: 10),
      two(TextField(controller: blood, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Blood group', hintText: 'e.g. B+')),
          TextField(controller: house, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'House'))),

      _label(context, 'SCHOOL BUS'),
      two(PickField<String?>(label: 'Bus route', value: route == null ? null : routeId, onChanged: (v) => setState(() { routeId = v; stopId = null; }),
              items: [const DropdownMenuItem<String?>(value: null, child: Text('No school bus')), for (final r in routes) DropdownMenuItem<String?>(value: r['id'] as String, child: Text('${r['name']} · ${r['bus_reg_no'] ?? ''}'))]),
          PickField<String>(label: 'Stop', value: stops.any((s) => s['id'] == stopId) ? stopId : null, onChanged: routeId == null ? (_) {} : (v) => setState(() => stopId = v),
              items: [for (final s in stops) DropdownMenuItem(value: s['id'] as String, child: Text('${s['seq']}. ${s['name']}'))])),

      _label(context, 'STATUS'),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: consent, onChanged: (v) => setState(() => consent = v),
          title: const Text('Photos allowed'), subtitle: const Text('Parent has agreed that the child may appear in class photos.')),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => setState(() => active = v),
          title: const Text('Studying here'), subtitle: Text(active ? 'The family can use the app.' : 'Left the school — the family is signed out of every phone.')),
      if (!active) OutlinedButton.icon(onPressed: () async {
        final d = await showDatePicker(context: context, initialDate: tc ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime.now().add(const Duration(days: 60)));
        if (d != null) setState(() => tc = d);
      }, icon: const Icon(Icons.description_rounded, size: 18), label: Text(tc == null ? 'TC issued on (optional)' : 'TC issued ${df.format(tc!)}')),
    ], actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : isNew ? 'Admit student' : 'Save')),
    ]);
  }
}

// ================================================================== STAFF
const _staffRoles = ['teacher', 'class_teacher', 'coordinator', 'accounts', 'office', 'transport_incharge', 'vice_principal', 'principal', 'it_admin'];
const _divisions = {'pre_primary': 'Pre-primary', 'primary': 'Primary', 'middle': 'Middle', 'high_senior': 'High & senior'};

class StaffTab extends ConsumerStatefulWidget {
  const StaffTab({super.key});
  @override
  ConsumerState<StaffTab> createState() => StaffTabState();
}

class StaffTabState extends ConsumerState<StaffTab> {
  String q = ''; bool showLeft = false;

  Future<void> _open([Map<String, dynamic>? st]) async {
    final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _StaffEditor(staff: st));
    if (saved == true) ref.invalidate(staffListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ref.watch(staffListProvider).when(loading: _loading, error: (e, _) => _err(e), data: (all) {
      final rows = all.where((s) => !_isCrew(s) && (showLeft || s['active'] == true) &&
          (q.trim().isEmpty || '${s['full_name']} ${s['display_name']} ${s['email']}'.toLowerCase().contains(q.trim().toLowerCase()))).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(title: 'Staff · ${rows.length}', trailing: FilledButton.icon(onPressed: () => _open(), icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text('Add staff')),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PickRow(children: [
              Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Name or email'), onChanged: (v) => setState(() => q = v))),
              const SizedBox(width: 10),
              FilterChip(label: const Text('Show staff who left'), selected: showLeft, onSelected: (v) => setState(() => showLeft = v)),
            ]),
            const SizedBox(height: 6),
            for (final st in rows) ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Avatar(((st['full_name'] ?? '') as String).trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join(), size: 40),
              title: Text(st['display_name'] ?? st['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${st['email']} · ${List<String>.from(st['roles'] ?? const []).map(roleLabel).join(', ')}', style: TextStyle(color: cs.onSurfaceVariant)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (st['active'] != true) const Pill('Left', fg: Brand.muted, bg: Brand.surface2),
                const Icon(Icons.chevron_right_rounded),
              ]),
              onTap: () => _open(st),
            ),
          ])),
        const NoteBox('Drivers and bus assistants are set up in Transport with their dr / as login IDs.'),
      ]);
    });
  }
}

class _StaffEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic>? staff;
  const _StaffEditor({this.staff});
  @override
  ConsumerState<_StaffEditor> createState() => _StaffEditorState();
}

class _StaffEditorState extends ConsumerState<_StaffEditor> {
  late final st = widget.staff;
  late final name = TextEditingController(text: st?['full_name'] ?? '');
  late final shown = TextEditingController(text: st?['display_name'] ?? '');
  late final email = TextEditingController(text: st?['email'] ?? '');
  late final phone = TextEditingController(text: st?['phone'] ?? '');
  late final Set<String> roles = Set<String>.from(st?['roles'] ?? const ['teacher']);
  late String? division = st?['division'];
  late bool active = st?['active'] != false;
  bool busy = false;

  Future<void> _save() async {
    if (name.text.trim().isEmpty || !email.text.contains('@')) { toast(context, 'Name and a valid email are needed.'); return; }
    if (roles.isEmpty) { toast(context, 'Pick at least one role.'); return; }
    final me = ref.read(sessionProvider).value;
    if (st != null && st!['id'] == me?.staff?['id'] && !roles.contains('it_admin') && !roles.contains('principal')) {
      if (!await _confirm(context, 'Remove your own access?', 'You are taking away your own IT / Principal role. You will no longer be able to open this page.', 'Yes, save')) return;
    }
    setState(() => busy = true);
    try {
      final id = await db.rpc('admin_save_staff', params: {'p': {
        'id': st?['id'], 'email': email.text.trim(), 'full_name': name.text.trim(), 'display_name': shown.text.trim(),
        'phone': phone.text.trim(), 'roles': roles.toList(), 'division': division, 'active': active,
      }}) as String;
      String? pw;
      if (st == null) {
        try { pw = (await callFunction(ref, 'password', {'action': 'reset_staff', 'staff_id': id}))['first_use_password']?.toString(); } catch (_) {}
      }
      if (!mounted) return;
      final nav = Navigator.of(context); final outer = nav.context;
      nav.pop(true);
      if (pw != null && outer.mounted) {
        _slip(outer, 'Staff added — one-time password', '${name.text.trim()}\n${email.text.trim().toLowerCase()}\n\nPassword: $pw\n\nSign in at “School staff? Sign in here” with this email and password, then set your own password.');
      } else if (outer.mounted) {
        toast(outer, 'Saved.');
      }
    } catch (e) {
      if (mounted) { toast(context, _msg(e)); setState(() => busy = false); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _form(context, title: st == null ? 'Add staff' : 'Staff details', children: [
      _label(context, 'NAME'),
      TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name *', hintText: 'e.g. Kavitha Ramesh')),
      const SizedBox(height: 10),
      TextField(controller: shown, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name parents see', hintText: 'e.g. Ms. Kavitha R.')),
      _label(context, 'SIGN-IN'),
      TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'School email *', hintText: 'name@rcis.in')),
      const SizedBox(height: 10),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile (optional)')),
      _label(context, 'ROLES — WHAT THEY CAN SEE AND DO'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final r in _staffRoles) FilterChip(label: Text(roleLabel(r)), selected: roles.contains(r), onSelected: (v) => setState(() => v ? roles.add(r) : roles.remove(r))),
      ]),
      if (roles.contains('coordinator')) ...[
        _label(context, 'COORDINATOR FOR'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in _divisions.entries) ChoiceChip(label: Text(d.value), selected: division == d.key, onSelected: (v) => setState(() => division = v ? d.key : null)),
        ]),
      ],
      const SizedBox(height: 8),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => setState(() => active = v),
          title: const Text('Working here'), subtitle: Text(active ? 'Can sign in.' : 'Left — signed out everywhere and cannot sign in.')),
      if (st != null) Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: busy ? null : () async {
        try {
          final r = await callFunction(ref, 'password', {'action': 'reset_staff', 'staff_id': st!['id']});
          if (context.mounted) _slip(context, 'One-time password', '${st!['full_name']}\n${st!['email']}\n\nPassword: ${r['first_use_password']}\n\nThey must change it at first sign-in.');
        } catch (e) { if (context.mounted) toast(context, _msg(e)); }
      }, icon: const Icon(Icons.key_rounded, size: 18), label: const Text('Give a new one-time password'))),
    ], actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : st == null ? 'Add staff' : 'Save')),
    ]);
  }
}

// ================================================================== CLASSES
class _ClassesTab extends ConsumerWidget {
  const _ClassesTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, [Map<String, dynamic>? sec]) async {
    final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _SectionEditor(section: sec));
    if (saved == true) { ref.invalidate(setupSectionsProvider); ref.invalidate(mySectionsProvider); }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final subjects = ref.watch(subjectsProvider).value ?? const <Map<String, dynamic>>[];
    return ref.watch(setupSectionsProvider).when(loading: _loading, error: (e, _) => _err(e), data: (rows) {
      final byGrade = <String, List<Map<String, dynamic>>>{};
      for (final s in rows) { byGrade.putIfAbsent(s['grade']?['name'] ?? '', () => []).add(s); }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Panel(title: 'Classes this year · ${rows.length} sections', trailing: FilledButton.icon(onPressed: () => _edit(context, ref), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add section')),
          child: rows.isEmpty ? Text('No sections yet.', style: TextStyle(color: cs.onSurfaceVariant)) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final g in byGrade.entries) ...[
              Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text(g.key, style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.crimsonDeep))),
              for (final s in g.value) ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: CircleAvatar(backgroundColor: Brand.crimsonTint, child: Text(s['name'] ?? '', style: const TextStyle(color: Brand.crimsonDeep, fontWeight: FontWeight.w800, fontSize: 13))),
                title: Text('${sectionLabel(s)} · ${s['class_teacher']?['display_name'] ?? 'No class teacher yet'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${(s['enrolment'] as List?)?.firstOrNull?['count'] ?? 0} students · ${(s['teaching_assignment'] as List?)?.length ?? 0} of ${subjects.length} subjects have a teacher',
                    style: TextStyle(color: cs.onSurfaceVariant)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _edit(context, ref, s),
              ),
            ],
          ])),
        const NoteBox('Class teachers can enter report cards, the diary and attendance for their class. Subject teachers can post homework and enter marks for their subject.'),
      ]);
    });
  }
}

class _SectionEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic>? section;
  const _SectionEditor({this.section});
  @override
  ConsumerState<_SectionEditor> createState() => _SectionEditorState();
}

class _SectionEditorState extends ConsumerState<_SectionEditor> {
  late final sec = widget.section;
  late String? gradeId = sec?['grade']?['id'];
  late final name = TextEditingController(text: sec?['name'] ?? '');
  late String? classTeacher = sec?['class_teacher_id'];
  late final Map<String, String> teachers = {
    for (final t in List<Map<String, dynamic>>.from(sec?['teaching_assignment'] ?? const [])) t['subject_id'] as String: t['staff_id'] as String,
  };
  late final Map<String, String> original = Map.of(teachers);
  bool busy = false, changed = false;
  final newSubject = TextEditingController();

  Future<void> _save() async {
    if (gradeId == null || name.text.trim().isEmpty) { toast(context, 'Pick the grade and type the section name (e.g. A).'); return; }
    setState(() => busy = true);
    try {
      final id = await db.rpc('admin_save_section', params: {'p_id': sec?['id'], 'p_grade': gradeId, 'p_name': name.text.trim(), 'p_class_teacher': classTeacher}) as String;
      final subjects = {...original.keys, ...teachers.keys};
      for (final sub in subjects) {
        if (original[sub] == teachers[sub]) continue;
        await db.rpc('admin_set_teacher', params: {'p_section': id, 'p_subject': sub, 'p_staff': teachers[sub]});
      }
      if (mounted) { toast(context, 'Saved.'); Navigator.pop(context, true); }
    } catch (e) {
      if (mounted) { toast(context, _msg(e)); setState(() => busy = false); }
    }
  }

  Future<void> _addSubject() async {
    if (newSubject.text.trim().isEmpty) return;
    try {
      await db.rpc('admin_add_subject', params: {'p_name': newSubject.text.trim(), 'p_short': ''});
      newSubject.clear();
      ref.invalidate(subjectsProvider);
      changed = true;
    } catch (e) { if (mounted) toast(context, _msg(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grades = ref.watch(gradesProvider).value ?? const <Map<String, dynamic>>[];
    final staff = ref.watch(_teachersProvider).value ?? const <Map<String, dynamic>>[];
    final subjects = ref.watch(subjectsProvider).value ?? const <Map<String, dynamic>>[];
    List<DropdownMenuItem<String?>> staffItems(String none) => [
      DropdownMenuItem<String?>(value: null, child: Text(none, style: TextStyle(color: cs.onSurfaceVariant))),
      for (final t in staff) DropdownMenuItem<String?>(value: t['id'] as String, child: Text(t['display_name'] ?? t['full_name'] ?? '')),
    ];
    String? known(String? id) => id != null && staff.any((t) => t['id'] == id) ? id : null;
    return _form(context, title: sec == null ? 'Add section' : 'Class ${sectionLabel(sec!)}', maxWidth: 600, children: [
      _label(context, 'SECTION'),
      PickRow(children: [
        Expanded(child: PickField<String>(label: 'Grade', value: grades.any((x) => x['id'] == gradeId) ? gradeId : null, onChanged: sec == null ? (v) => setState(() => gradeId = v) : (_) {},
            items: [for (final g in grades) DropdownMenuItem(value: g['id'] as String, child: Text(g['name'] ?? g['code']))])),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: name, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Section', hintText: 'A, B, Sci, Com…'))),
      ]),
      const SizedBox(height: 10),
      PickField<String?>(label: 'Class teacher', value: known(classTeacher), onChanged: (v) => setState(() => classTeacher = v), items: staffItems('Not chosen yet')),
      _label(context, 'SUBJECT TEACHERS'),
      for (final sub in subjects) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
        SizedBox(width: isNarrow(context) ? 110 : 170, child: Text(sub['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        Expanded(child: DropdownButtonFormField<String?>(isExpanded: true, value: known(teachers[sub['id']]), items: staffItems('—'),
            onChanged: (v) => setState(() { if (v == null) { teachers.remove(sub['id']); } else { teachers[sub['id'] as String] = v; } }))),
      ])),
      Row(children: [
        Expanded(child: TextField(controller: newSubject, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Subject not in the list? Type it here'))),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: _addSubject, child: const Text('Add subject')),
      ]),
    ], actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context, changed), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')),
    ]);
  }
}

// ================================================================== FEES
class _FeesTab extends ConsumerStatefulWidget {
  const _FeesTab();
  @override
  ConsumerState<_FeesTab> createState() => _FeesTabState();
}

class _FeesTabState extends ConsumerState<_FeesTab> {
  String? gradeId; bool busy = false;

  Future<void> _edit(Map<String, dynamic> grade, [Map<String, dynamic>? line]) async {
    final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _FeeLineEditor(grade: grade, line: line));
    if (saved == true) { ref.invalidate(_feePlanProvider(grade['id'])); ref.invalidate(_feeHeadsProvider); }
  }

  Future<void> _apply(Map<String, dynamic> grade) async {
    if (!await _confirm(context, 'Give these fees to ${grade['name']}?',
        'Every student now in ${grade['name']} gets any fee line they do not have yet. Unpaid lines are updated to the new amount and due date. Paid fees are never changed.', 'Yes, apply')) return;
    setState(() => busy = true);
    try {
      final r = Map<String, dynamic>.from(await db.rpc('admin_apply_fee_plan', params: {'p_grade': grade['id']}) as Map);
      if (mounted) toast(context, 'Done: ${r['added']} fee lines added, ${r['updated']} unpaid lines updated.');
    } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grades = ref.watch(gradesProvider).value ?? const <Map<String, dynamic>>[];
    final grade = grades.where((g) => g['id'] == gradeId).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(title: 'Fee plan for each grade · this year', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [for (final g in grades) ChoiceChip(label: Text(g['code'] ?? ''), selected: g['id'] == gradeId, onSelected: (_) => setState(() => gradeId = g['id']))]),
        const SizedBox(height: 12),
        if (grade == null) Text('Pick a grade.', style: TextStyle(color: cs.onSurfaceVariant))
        else ref.watch(_feePlanProvider(grade['id'])).when(loading: _loading, error: (e, _) => _err(e), data: (lines) {
          final total = lines.where((l) => l['optional'] != true).fold<num>(0, (a, l) => a + (num.tryParse('${l['amount']}') ?? 0));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (lines.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('No fees set for ${grade['name']} yet.', style: TextStyle(color: cs.onSurfaceVariant))),
            for (final l in lines) ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: Text(l['fee_head']?['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Due ${l['due_on'] == null ? '—' : DateFormat('d MMM yyyy').format(DateTime.parse(l['due_on']))}${l['optional'] == true ? ' · optional (only for those who choose it)' : ''}', style: TextStyle(color: cs.onSurfaceVariant)),
              trailing: Text(inr(num.tryParse('${l['amount']}') ?? 0), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              onTap: () => _edit(grade, l),
            ),
            const Divider(),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: [
              const Expanded(child: Text('Total for the year (compulsory)', style: TextStyle(fontWeight: FontWeight.w800))),
              Text(inr(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Brand.crimsonDeep)),
            ])),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: () => _edit(grade), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add fee line')),
              FilledButton.icon(onPressed: busy || lines.isEmpty ? null : () => _apply(grade), icon: const Icon(Icons.group_add_rounded, size: 18), label: Text(busy ? 'Applying…' : 'Give to all ${grade['code']} students')),
            ]),
          ]);
        }),
      ])),
      const NoteBox('Changing the plan does not touch any student until you press “Give to all … students”. New admissions get the plan automatically. Concessions for one student stay in the Fees desk.'),
    ]);
  }
}

class _FeeLineEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic> grade; final Map<String, dynamic>? line;
  const _FeeLineEditor({required this.grade, this.line});
  @override
  ConsumerState<_FeeLineEditor> createState() => _FeeLineEditorState();
}

class _FeeLineEditorState extends ConsumerState<_FeeLineEditor> {
  late final l = widget.line;
  late final head = TextEditingController(text: l?['fee_head']?['name'] ?? '');
  late final amount = TextEditingController(text: l == null ? '' : '${num.tryParse('${l!['amount']}')?.round() ?? ''}');
  late String kind = l?['fee_head']?['kind'] ?? 'tuition';
  late DateTime? due = l?['due_on'] == null ? null : DateTime.parse(l!['due_on']);
  late bool optional = l?['optional'] == true;
  bool busy = false;

  Future<void> _save() async {
    final a = num.tryParse(amount.text.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (head.text.trim().isEmpty || a == null || a <= 0) { toast(context, 'Type the fee name and the amount.'); return; }
    if (due == null) { toast(context, 'Pick the due date.'); return; }
    setState(() => busy = true);
    try {
      if (l != null && (l!['fee_head']?['name'] ?? '').toString().toLowerCase() != head.text.trim().toLowerCase()) {
        await db.rpc('admin_delete_fee_plan', params: {'p_id': l!['id']});   // renamed: replace the line
      }
      await db.rpc('admin_save_fee_plan', params: {'p_grade': widget.grade['id'], 'p_head_name': head.text.trim(), 'p_kind': kind, 'p_amount': a, 'p_due': _iso(due!), 'p_optional': optional});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { toast(context, _msg(e)); setState(() => busy = false); }
    }
  }

  Future<void> _delete() async {
    if (!await _confirm(context, 'Remove this fee line?', 'It is removed from the plan for ${widget.grade['name']}. Fees already given to students stay as they are.', 'Remove')) return;
    setState(() => busy = true);
    try {
      await db.rpc('admin_delete_fee_plan', params: {'p_id': l!['id']});
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
  }

  @override
  Widget build(BuildContext context) {
    final heads = ref.watch(_feeHeadsProvider).value ?? const <Map<String, dynamic>>[];
    return _form(context, title: '${l == null ? 'Add fee' : 'Change fee'} · ${widget.grade['name']}', children: [
      _label(context, 'FEE NAME'),
      TextField(controller: head, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'e.g. Tuition fee — Term 1')),
      if (heads.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final h in heads.take(12)) ActionChip(label: Text(h['name'] ?? ''), onPressed: () => setState(() { head.text = h['name'] ?? ''; kind = h['kind'] ?? kind; })),
      ])),
      _label(context, 'TYPE'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final k in const {'tuition': 'Tuition', 'transport': 'Transport', 'misc': 'Books, uniform & other', 'other': 'Other'}.entries)
          ChoiceChip(label: Text(k.value), selected: kind == k.key, onSelected: (_) => setState(() => kind = k.key)),
      ]),
      _label(context, 'AMOUNT AND DUE DATE'),
      PickRow(children: [
        Expanded(child: TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(prefixText: '₹ ', hintText: 'Amount'))),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(onPressed: () async {
          final d = await showDatePicker(context: context, initialDate: due ?? DateTime.now(), firstDate: DateTime(2025), lastDate: DateTime(2030));
          if (d != null) setState(() => due = d);
        }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(due == null ? 'Due date' : 'Due ${DateFormat('d MMM yyyy').format(due!)}'))),
      ]),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: optional, onChanged: (v) => setState(() => optional = v),
          title: const Text('Optional'), subtitle: const Text('Only for families who choose it (e.g. transport, activities). Not added to every student.')),
    ], actions: [
      if (l != null) TextButton(onPressed: busy ? null : _delete, child: const Text('Remove', style: TextStyle(color: Brand.crimsonDeep))),
      TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')),
    ]);
  }
}

// ================================================================== BUS ROUTES
class TransportTab extends ConsumerWidget {
  const TransportTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    Future<void> editRoute([Map<String, dynamic>? r]) async {
      final ok = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _RouteEditor(route: r));
      if (ok == true) ref.invalidate(routesProvider);
    }
    Future<void> editStops(Map<String, dynamic> r) async {
      final ok = await Navigator.of(context, rootNavigator: true).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _StopsEditor(route: r)));
      if (ok == true) ref.invalidate(routesProvider);
    }
    Future<void> riders(Map<String, dynamic> r) async {
      await showDialog(context: context, builder: (_) => _RouteStudents(route: r));
      ref.invalidate(routesProvider);
    }
    return ref.watch(routesProvider).when(loading: _loading, error: (e, _) => _err(e), data: (rows) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(title: 'Bus routes · ${rows.length}', trailing: FilledButton.icon(onPressed: () => editRoute(), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add route')),
        child: rows.isEmpty ? Text('No routes yet.', style: TextStyle(color: cs.onSurfaceVariant)) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final r in rows) Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: cs.outline.withValues(alpha: .6))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${r['name']} · ${r['bus_reg_no'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                Pill(r['active'] == true ? 'Active' : 'Not running', fg: r['active'] == true ? Brand.green : Brand.muted, bg: r['active'] == true ? Brand.greenTint : Brand.surface2),
              ]),
              const SizedBox(height: 4),
              Text('${(r['route_stop'] as List?)?.length ?? 0} stops · ${(r['transport_enrolment'] as List?)?.length ?? 0} students · morning ${_time12(r['morning_start'])} · afternoon ${_time12(r['afternoon_start'])}',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(onPressed: () => editStops(r), icon: const Icon(Icons.map_rounded, size: 18), label: const Text('Stops on the map')),
                OutlinedButton.icon(onPressed: () => riders(r), icon: const Icon(Icons.groups_rounded, size: 18), label: const Text('Students')),
                OutlinedButton.icon(onPressed: () => editRoute(r), icon: const Icon(Icons.edit_rounded, size: 18), label: const Text('Bus & timings')),
              ]),
            ]),
          ),
        ])),
      const NoteBox('Driver and bus assistant logins (dr / as + route number) are made in Transport. Stops are placed by tapping the map — or stand at the stop and press “Add stop where I am”.'),
    ]));
  }
}

class _RouteEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic>? route;
  const _RouteEditor({this.route});
  @override
  ConsumerState<_RouteEditor> createState() => _RouteEditorState();
}

class _RouteEditorState extends ConsumerState<_RouteEditor> {
  late final r = widget.route;
  late final name = TextEditingController(text: r?['name'] ?? '');
  late final bus = TextEditingController(text: r?['bus_reg_no'] ?? '');
  late TimeOfDay? morning = _tod(r?['morning_start']), afternoon = _tod(r?['afternoon_start']);
  late bool active = r?['active'] != false;
  bool busy = false;

  static TimeOfDay? _tod(dynamic t) {
    if (t == null || t.toString().length < 5) return null;
    final p = t.toString().split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }
  String? _t(TimeOfDay? t) => t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    if (name.text.trim().isEmpty || bus.text.trim().isEmpty) { toast(context, 'Type the route name (e.g. Route 7) and the bus number.'); return; }
    setState(() => busy = true);
    try {
      await db.rpc('admin_save_route', params: {'p_id': r?['id'], 'p_name': name.text.trim(), 'p_bus': bus.text.trim(), 'p_morning': _t(morning), 'p_afternoon': _t(afternoon), 'p_active': active});
      if (mounted) { toast(context, 'Saved.'); Navigator.pop(context, true); }
    } catch (e) { if (mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
  }

  @override
  Widget build(BuildContext context) {
    Widget timeBtn(String label, TimeOfDay? v, ValueChanged<TimeOfDay> set) => OutlinedButton.icon(
      onPressed: () async { final t = await showTimePicker(context: context, initialTime: v ?? const TimeOfDay(hour: 7, minute: 0)); if (t != null) setState(() => set(t)); },
      icon: const Icon(Icons.schedule_rounded, size: 18), label: Text(v == null ? label : '$label ${v.format(context)}'));
    return _form(context, title: r == null ? 'Add bus route' : 'Bus & timings', children: [
      _label(context, 'ROUTE'),
      TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Route name', hintText: 'e.g. Route 7')),
      const SizedBox(height: 10),
      TextField(controller: bus, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Bus number', hintText: 'e.g. KA 03 AB 1234')),
      _label(context, 'LEAVES AT'),
      PickRow(children: [
        Expanded(child: timeBtn('Morning', morning, (t) => morning = t)),
        const SizedBox(width: 10),
        Expanded(child: timeBtn('Afternoon', afternoon, (t) => afternoon = t)),
      ]),
      SwitchListTile(contentPadding: EdgeInsets.zero, value: active, onChanged: (v) => setState(() => active = v), title: const Text('Running this year')),
    ], actions: [
      TextButton(onPressed: busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : 'Save')),
    ]);
  }
}

/// Full-screen stop editor: map on top (tap to place), ordered list below (drag to reorder).
class _StopsEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic> route;
  const _StopsEditor({required this.route});
  @override
  ConsumerState<_StopsEditor> createState() => _StopsEditorState();
}

class _Stop {
  String? id; String name; double? lat, lng; TimeOfDay? morning, afternoon;
  _Stop({this.id, required this.name, this.lat, this.lng, this.morning, this.afternoon});
  /// null = not pinned on the map yet (e.g. imported from Excel without a location)
  LatLng? get ll => lat == null || lng == null ? null : LatLng(lat!, lng!);
}

class _StopsEditorState extends ConsumerState<_StopsEditor> {
  final _mc = MapController();
  final stops = <_Stop>[];
  bool loading = true, busy = false, dirty = false;
  int? moving;   // index of the stop being moved by the next map tap

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final rows = await db.from('route_stop').select('id,seq,name,lat,lng,morning_eta,afternoon_eta').eq('route_id', widget.route['id']).order('seq', ascending: true);
      for (final s in rows) {
        stops.add(_Stop(id: s['id'], name: s['name'] ?? '', lat: (s['lat'] as num?)?.toDouble(), lng: (s['lng'] as num?)?.toDouble(),
            morning: _RouteEditorState._tod(s['morning_eta']), afternoon: _RouteEditorState._tod(s['afternoon_eta'])));
      }
    } catch (e) { if (mounted) toast(context, _msg(e)); }
    if (mounted) setState(() => loading = false);
  }

  void _fit() {
    if (stops.isEmpty) return;
    try {
      final pts = [for (final s in stops) if (s.ll != null) s.ll!];
      if (pts.isEmpty) return;
      if (pts.length == 1) { _mc.move(pts.first, 16); return; }
      _mc.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(40)));
    } catch (_) {}
  }

  Future<String?> _askName([String initial = '']) async {
    final c = TextEditingController(text: initial);
    return showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Stop name'),
      content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'e.g. HRBR 1st Block bus stand'),
          onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK'))],
    ));
  }

  Future<void> _tap(LatLng p) async {
    if (moving != null) {
      setState(() { stops[moving!].lat = p.latitude; stops[moving!].lng = p.longitude; moving = null; dirty = true; });
      return;
    }
    final n = await _askName();
    if (n == null || n.trim().isEmpty) return;
    setState(() { stops.add(_Stop(name: n.trim(), lat: p.latitude, lng: p.longitude)); dirty = true; });
  }

  Future<void> _here() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) { if (mounted) toast(context, 'Please allow location for Royale Connect.'); return; }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      if (pos.accuracy > 60) toast(context, 'GPS is rough here (±${pos.accuracy.round()} m). Check the pin on the map and move it if needed.');
      final p = LatLng(pos.latitude, pos.longitude);
      try { _mc.move(p, 17); } catch (_) {}
      await _tap(p);
    } catch (e) { if (mounted) toast(context, 'Could not get your location: ${_msg(e)}'); }
  }

  Future<void> _save() async {
    if (stops.isEmpty) { toast(context, 'Add at least one stop.'); return; }
    final unpinned = stops.where((s) => s.ll == null).length;
    if (unpinned > 0) toast(context, '$unpinned stop${unpinned == 1 ? '' : 's'} still without a map pin — saved, but bus alerts for them start once they are pinned.');
    setState(() => busy = true);
    String? t(TimeOfDay? x) => x == null ? null : '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
    try {
      await db.rpc('admin_save_stops', params: {'p_route': widget.route['id'], 'p_stops': [
        for (final s in stops) {'id': s.id, 'name': s.name, 'lat': s.lat, 'lng': s.lng, 'morning_eta': t(s.morning), 'afternoon_eta': t(s.afternoon)},
      ]});
      if (mounted) { toast(context, 'Stops saved.'); Navigator.pop(context, true); }
    } catch (e) { if (mounted) { toast(context, _msg(e)); setState(() => busy = false); } }
  }

  Future<bool> _leave() async => !dirty || await _confirm(context, 'Leave without saving?', 'Your changes to the stops will be lost.', 'Leave');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final start = stops.where((s) => s.ll != null).firstOrNull?.ll ?? const LatLng(13.0244, 77.6410);   // the school
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final map = Stack(children: [
      FlutterMap(
        mapController: _mc,
        options: MapOptions(initialCenter: start, initialZoom: 14, minZoom: 10, maxZoom: 19, onMapReady: _fit, onTap: (_, p) => _tap(p)),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', fallbackUrl: 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
              userAgentPackageName: 'in.rcis.royale_connect', tileBuilder: dark ? darkModeTileBuilder : null),
          PolylineLayer(polylines: [
            if (stops.where((s) => s.ll != null).length > 1) Polyline(points: [for (final s in stops) if (s.ll != null) s.ll!], color: Brand.crimson.withValues(alpha: .7), strokeWidth: 4, pattern: StrokePattern.dashed(segments: const [12, 8])),
          ]),
          MarkerLayer(markers: [
            for (final (i, s) in stops.indexed) if (s.ll != null) Marker(point: s.ll!, width: 30, height: 30, child: Container(
              decoration: BoxDecoration(color: moving == i ? Brand.gold : Brand.crimson, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)]),
              child: Center(child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13))))),
          ]),
          const SimpleAttributionWidget(source: Text('© OpenStreetMap contributors')),
        ],
      ),
      Positioned(left: 12, right: 12, top: 12, child: Material(elevation: 3, borderRadius: BorderRadius.circular(12), color: moving != null ? Brand.amberTint : cs.surface,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Text(
          moving != null ? 'Tap the map where stop ${moving! + 1} (${stops[moving!].name}) really is.' : 'Tap the map to add a stop. Drag the list to change the order.',
          style: const TextStyle(fontWeight: FontWeight.w700))))),
      Positioned(right: 12, bottom: 12, child: FloatingActionButton.extended(heroTag: null, onPressed: _here, backgroundColor: Brand.green, foregroundColor: Colors.white,
          icon: const Icon(Icons.my_location_rounded), label: const Text('Add stop where I am'))),
    ]);

    final list = stops.isEmpty
        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('No stops yet. Tap the map to add the first stop after the school.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant))))
        : ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: stops.length,
            onReorder: (a, b) => setState(() { if (b > a) b--; stops.insert(b, stops.removeAt(a)); dirty = true; }),
            itemBuilder: (_, i) {
              final s = stops[i];
              return ListTile(
                key: ObjectKey(s),
                leading: CircleAvatar(radius: 15, backgroundColor: moving == i ? Brand.gold : Brand.crimson, child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
                title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(s.ll == null ? 'Not on the map yet — tap here, then tap the map where it is' : 'Morning ${s.morning?.format(context) ?? '—'} · Afternoon ${s.afternoon?.format(context) ?? '—'}',
                    style: TextStyle(color: s.ll == null ? context.tone(Brand.amber) : cs.onSurfaceVariant, fontSize: 12, fontWeight: s.ll == null ? FontWeight.w700 : null)),
                onTap: () { if (s.ll == null) { setState(() => moving = i); return; } try { _mc.move(s.ll!, 17); } catch (_) {} },
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'name') { final n = await _askName(s.name); if (n != null && n.trim().isNotEmpty) setState(() { s.name = n.trim(); dirty = true; }); }
                    if (v == 'move') { setState(() => moving = i); if (s.ll != null) { try { _mc.move(s.ll!, 17); } catch (_) {} } }
                    if (v == 'am' || v == 'pm') {
                      if (!mounted) return;
                      final t = await showTimePicker(context: context, initialTime: (v == 'am' ? s.morning : s.afternoon) ?? (v == 'am' ? const TimeOfDay(hour: 7, minute: 15) : const TimeOfDay(hour: 15, minute: 45)));
                      if (t != null) setState(() { if (v == 'am') { s.morning = t; } else { s.afternoon = t; } dirty = true; });
                    }
                    if (v == 'del') setState(() { stops.removeAt(i); moving = null; dirty = true; });
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'name', child: Text('Rename')),
                    PopupMenuItem(value: 'move', child: Text('Move on the map')),
                    PopupMenuItem(value: 'am', child: Text('Morning pick-up time')),
                    PopupMenuItem(value: 'pm', child: Text('Afternoon drop time')),
                    PopupMenuItem(value: 'del', child: Text('Remove stop')),
                  ],
                ),
              );
            });

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async { if (!didPop && await _leave() && context.mounted) Navigator.of(context).pop(false); },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Stops · ${widget.route['name']}'),
          actions: [Padding(padding: const EdgeInsets.only(right: 12), child: FilledButton(onPressed: busy || loading ? null : _save, child: Text(busy ? 'Saving…' : 'Save')))],
        ),
        body: loading ? _loading() : wide
            ? Row(children: [Expanded(flex: 3, child: map), SizedBox(width: 380, child: list)])
            : Column(children: [Expanded(flex: 5, child: map), Expanded(flex: 4, child: list)]),
      ),
    );
  }
}

/// Which students take this bus, and where they get on.
class _RouteStudents extends ConsumerStatefulWidget {
  final Map<String, dynamic> route;
  const _RouteStudents({required this.route});
  @override
  ConsumerState<_RouteStudents> createState() => _RouteStudentsState();
}

class _RouteStudentsState extends ConsumerState<_RouteStudents> {
  String q = ''; String? stopId;
  late final rid = widget.route['id'] as String;
  late final stops = List<Map<String, dynamic>>.from(widget.route['route_stop'] ?? const [])..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));

  Future<void> _set(String studentId, String? stop) async {
    try {
      await db.rpc('admin_set_transport', params: {'p_student': studentId, 'p_route': stop == null ? null : rid, 'p_stop': stop});
      ref.invalidate(_routeStudentsProvider(rid));
    } catch (e) { if (mounted) toast(context, _msg(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final riders = ref.watch(_routeStudentsProvider(rid));
    return _form(context, title: 'Students · ${widget.route['name']}', maxWidth: 600, children: [
      _label(context, 'ADD A STUDENT TO THIS BUS'),
      if (stops.isEmpty) Text('Add the stops first.', style: TextStyle(color: cs.onSurfaceVariant)) else ...[
        PickField<String>(label: 'Stop', value: stopId, onChanged: (v) => setState(() => stopId = v),
            items: [for (final s in stops) DropdownMenuItem(value: s['id'] as String, child: Text('${s['seq']}. ${s['name']}'))]),
        const SizedBox(height: 8),
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Student name or admission number'), onChanged: (v) => setState(() => q = v)),
        if (q.trim().length >= 2) ref.watch(studentSearchProvider(q)).when(loading: () => const LinearProgressIndicator(), error: (e, _) => _err(e), data: (rows) => Column(children: [
          for (final r in rows.take(8)) ListTile(dense: true, contentPadding: EdgeInsets.zero,
            title: Text(r['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${r['admission_no']}${(r['enrolment'] as List?)?.isNotEmpty == true ? ' · ${sectionLabelOf((r['enrolment'] as List).first['section'])}' : ''}'),
            trailing: TextButton(onPressed: stopId == null ? null : () { _set(r['id'], stopId); setState(() => q = ''); }, child: Text(stopId == null ? 'Pick stop' : 'Add')),
          ),
        ])),
      ],
      _label(context, 'ON THIS BUS'),
      riders.when(loading: () => const LinearProgressIndicator(), error: (e, _) => _err(e), data: (rows) => rows.isEmpty
          ? Text('No students yet.', style: TextStyle(color: cs.onSurfaceVariant))
          : Column(children: [for (final r in rows) ListTile(dense: true, contentPadding: EdgeInsets.zero,
              title: Text(r['student']?['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${r['student']?['admission_no'] ?? ''} · ${r['stop']?['name'] ?? 'no stop'}'),
              trailing: IconButton(tooltip: 'Remove from this bus', icon: const Icon(Icons.remove_circle_outline_rounded, color: Brand.crimsonDeep), onPressed: () => _set(r['student_id'], null)),
            )])),
    ], actions: [
      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
    ]);
  }
}
