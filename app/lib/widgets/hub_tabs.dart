import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/session.dart';
import '../core/data3.dart';
import '../staff/staff_shell.dart' show staffCanOpen;

/// Pages that belong together sit behind one menu item, with tabs at the top
/// (e.g. Calendar · Timetable · Exams). Tabs whose section IT has switched off are not shown.
enum Hub { calendar, honours, attendance, staffExams, staffHonours, schoolSetup, staffAttendance, staffFees, staffIds, staffStudents }

const _hubs = <Hub, List<(String, String, String?)>>{   // path, label, feature switch
  Hub.calendar: [('/calendar', 'Calendar', null), ('/timetable', 'Timetable', 'timetable'), ('/exams', 'Exams', null)],
  Hub.honours: [('/star', 'Star of the month', 'star'), ('/toppers', 'Toppers', 'toppers'), ('/council', 'Council', 'council'), ('/houses', 'Houses', 'houses'), ('/fame', 'Hall of Fame', 'fame')],   // Hall of Fame last (used least)
  Hub.attendance: [('/attendance', 'Attendance', null), ('/leave', 'Leave', 'leave')],
  // Marks entered is inside Reports; Promotion shows from February to May, when it is needed
  Hub.staffExams: [('/staff/exams', 'Exams', null), ('/staff/marks', 'Marks entry', null), ('/staff/reports', 'Report cards', null), ('/staff/exam-reports', 'Reports', null), ('/staff/promotion', 'Promotion', null)],
  Hub.staffStudents: [('/staff/students', 'Students', null), ('/staff/strength', 'Strength', null), ('/staff/leaving', 'Leaving check', null)],
  Hub.staffIds: [('/staff/id-cards', 'Students', null), ('/staff/staff-ids', 'Staff', null)],
  Hub.staffAttendance: [('/staff/attendance', 'Mark attendance', null), ('/staff/attendance/register', 'Register', null)],
  Hub.staffFees: [('/staff/fees', 'Receipts', null), ('/staff/fees/record', 'Record a payment', null), ('/staff/fees/dues', 'Dues', null), ('/staff/fees/reports', 'Reports', null), ('/staff/fees/concessions', 'Concessions', null)],
  Hub.staffHonours: [('/staff/toppers', 'Toppers & Hall of Fame', null), ('/staff/council', 'Council', 'council'), ('/staff/houses', 'Houses', 'houses')],
  Hub.schoolSetup: [('/staff/setup', 'Classes & fees', null), ('/staff/users', 'Staff', null), ('/staff/settings', 'Settings', null), ('/staff/bin', 'Bin', null)],
};

/// The first page of a hub that is switched on (where the menu item leads).
String hubStart(Hub h, Map<String, String>? settings) =>
    _hubs[h]!.firstWhere((t) => t.$3 == null || featureOn(settings, t.$3!), orElse: () => _hubs[h]!.first).$1;

class HubTabs extends ConsumerWidget {
  final Hub hub; final bool onDark; final List<String> hide;
  const HubTabs(this.hub, {super.key, this.onDark = true, this.hide = const []});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).value;
    final here = GoRouterState.of(context).uri.path;
    final s = ref.watch(sessionProvider).value;
    final tabs = [for (final t in _hubs[hub]!) if ((t.$3 == null || featureOn(settings, t.$3!)) && !hide.contains(t.$1)
        && (!t.$1.startsWith('/staff') || s == null || staffCanOpen(s, settings, t.$1))) t];
    // a page that lives inside a tab keeps that tab lit; of two tabs that fit, the longer address wins (Fees vs Fees → Dues)
    final at = const {'/staff/fees/day': '/staff/fees/reports', '/staff/rules': '/staff/settings', '/staff/sections': '/staff/settings', '/staff/marks-status': '/staff/exam-reports'}[here] ?? here;
    final season = const [2, 3, 4, 5].contains(DateTime.now().month);
    tabs.removeWhere((t) => t.$1 == '/staff/promotion' && !season && at != t.$1);
    String? lit;
    for (final t in tabs) { if ((at == t.$1 || at.startsWith('${t.$1}/')) && (lit == null || t.$1.length > lit.length)) lit = t.$1; }
    if (tabs.length < 2) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      for (final t in tabs) Padding(padding: const EdgeInsets.only(right: 6), child: Builder(builder: (_) {
        final on = lit == t.$1;
        final fg = onDark ? (on ? const Color(0xFF7E0A10) : Colors.white) : (on ? Colors.white : cs.onSurface);
        final bg = onDark ? (on ? Colors.white : Colors.white.withValues(alpha: .14)) : (on ? cs.onSurface : cs.surface);
        return Material(color: bg, borderRadius: BorderRadius.circular(99), child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: on ? null : () => context.pushReplacement(t.$1),
          child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: onDark || on ? null : Border.all(color: cs.outline)),
            child: Text(t.$2, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12.5)))));
      })),
    ]));
  }
}
