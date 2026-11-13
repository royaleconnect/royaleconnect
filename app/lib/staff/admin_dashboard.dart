import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'school_home.dart' show SchoolHome, glanceProvider, schoolHomeProvider;
import '../auth/session.dart';
import '../core/data.dart';
import '../core/errors.dart';
import '../core/school_docs.dart' show openMonthlyReport;
import '../core/theme.dart';
import 'staff_data.dart';
import 'staff_shell.dart';
import '../widgets/royal_extras.dart' show GoldLoading, FestiveBanner, FestiveSky, ShimmerPage;
import 'health_dot.dart';
import 'year_end.dart';
import 'password_requests.dart' show PasswordRequestsCard;
import '../widgets/guided_tour.dart' show TourTarget;
import '../widgets/staff_birthday.dart';

/// First screen for the IT admin, Principal and Vice Principal: the whole school at a glance.
/// Kept calm on purpose: six numbers, then Enrollment, Data checker and Leaving check, then the day.
/// Data comes from admin_dashboard (fees, app use, buses, calendar) and admin_overview (students, attendance,
/// notices read, data checks) and refreshes every minute. The health dot sits in the header.
/// Private chats stay private: only counts are shown, never message text.

bool isSchoolAdmin(Session s) => s.hasRole('it_admin') || s.hasRole('principal') || s.hasRole('vice_principal');

final adminDashProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
    Map<String, dynamic>.from(await db.rpc('admin_dashboard') as Map));

/// Students, attendance, notices read and the data checks (null until the database step of this update is run).
final adminOverviewProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  try {
    return Map<String, dynamic>.from(await db.rpc('admin_overview') as Map);
  } catch (_) {
    return null;
  }
});

class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});
  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends ConsumerState<AdminDashboard> {
  Timer? tick;
  @override
  void initState() { super.initState(); tick = Timer.periodic(const Duration(seconds: 60), (_) { ref.invalidate(adminDashProvider); ref.invalidate(glanceProvider); ref.invalidate(schoolHomeProvider); }); }
  @override
  void dispose() { tick?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    final dash = ref.watch(adminDashProvider);
    final h = DateTime.now().hour;
    final greet = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
    return FestiveSky(child: StaffPage(
      title: '$greet${s.staff?['name'] != null ? ', ${s.staff!['name']}' : ''}',
      subtitle: '${DateFormat('EEEE d MMMM yyyy').format(DateTime.now())} · the whole school at a glance${dash.value?['generated_at'] != null ? ' · updated ${DateFormat('h:mm a').format(DateTime.parse(dash.value!['generated_at']).toLocal())}' : ''}',
      actions: [
        const TourTarget('staff-health', child: HealthDot()),
        OutlinedButton.icon(onPressed: () => showDialog(context: context, builder: (c) => const Dialog(child: SizedBox(width: 520, child: SingleChildScrollView(padding: EdgeInsets.all(8), child: _ViewAsFamily())))),
            icon: const Icon(Icons.family_restroom_rounded, size: 18), label: const Text('View as family')),
        FilledButton.icon(onPressed: () => _monthly(context), icon: const Icon(Icons.picture_as_pdf_rounded, size: 18), label: const Text('Monthly report')),
      ],
      body: dash.when(
        loading: () => const ShimmerPage(),
        error: (e, _) => Panel(child: Text('Could not load the dashboard. ${friendlyError(e)}', style: const TextStyle(color: Brand.crimsonDeep))),
        data: (d) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const FestiveBanner(slim: true), const StaffBirthdayLine(), const PasswordRequestsCard(), const YearEndCard(), SchoolHome(admin: d), const StaffBirthdaysPanel()]),
      ),
    ));
  }

  Future<void> _monthly(BuildContext context) async {
    final now = DateTime.now();
    var month = DateTime(now.year, now.month, 1);
    final hl = TextEditingController();
    final go = await showDialog<bool>(context: context, builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
      title: const Text('Monthly report'),
      content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var k = 0; k < 4; k++) Builder(builder: (_) {
            final m = DateTime(now.year, now.month - k, 1);
            return ChoiceChip(label: Text(DateFormat('MMMM yyyy').format(m)), selected: m == month, onSelected: (_) => set(() => month = m));
          }),
        ]),
        const SizedBox(height: 14),
        TextField(controller: hl, minLines: 2, maxLines: 4, textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Highlights of the month (optional)', hintText: 'e.g. Science expo · Inter-school football winners')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Make the PDF'))],
    )));
    if (go == true && context.mounted) openMonthlyReport(context, month, hl.text);
  }

}


/// Search any student and open exactly what their family sees — read-only; the database refuses every change.
class _ViewAsFamily extends ConsumerStatefulWidget {
  const _ViewAsFamily();
  @override
  ConsumerState<_ViewAsFamily> createState() => _ViewAsFamilyState();
}

class _ViewAsFamilyState extends ConsumerState<_ViewAsFamily> {
  String q = ''; bool busy = false;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final res = ref.watch(studentSearchProvider(q));
    return Panel(title: 'View as family', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Student name or admission number', isDense: true)),
      const SizedBox(height: 6),
      if (q.trim().length >= 2) res.when(
        loading: () => const Padding(padding: EdgeInsets.all(12), child: const GoldLoading()),
        error: (e, _) => Text(friendlyError(e)),
        data: (rows) => rows.isEmpty ? Padding(padding: const EdgeInsets.all(8), child: Text('No student found.', style: TextStyle(color: cs.onSurfaceVariant))) : Column(children: [
          for (final st in rows.take(6)) ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            title: Text('${st['full_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${st['admission_no']}${(st['enrolment'] as List?)?.isNotEmpty == true ? ' · ${st['enrolment'][0]['section']?['grade']?['code']}-${st['enrolment'][0]['section']?['name']}' : ''}'),
            trailing: FilledButton(onPressed: busy ? null : () async {
              setState(() => busy = true);
              try {
                await ref.read(sessionProvider.notifier).viewAsFamily(st['id']);
                if (context.mounted) context.go('/');
              } catch (e) {
                if (context.mounted) toast(context, 'Could not open: ${friendlyError(e)}');
              }
              if (mounted) setState(() => busy = false);
            }, child: const Text('View')),
          ),
        ]),
      ),
      Padding(padding: const EdgeInsets.only(top: 6), child: Text('Opens the parent app for that child, read-only, for 2 hours. Nothing can be sent, changed or paid, and it does not count as the family reading notices. Every use is recorded.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
    ]));
  }
}


