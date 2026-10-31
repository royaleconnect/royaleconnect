import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth/login_screen.dart';
import 'auth/session.dart';
import 'screens/announcements_screen.dart';
import 'screens/diary_screen.dart';
import 'screens/fees_screen.dart';
import 'screens/home_screen.dart';
import 'screens/academics_screens.dart';
import 'screens/bus_screens.dart';
import 'screens/family_screens.dart';
import 'screens/messages_screen.dart';
import 'screens/pay_screen.dart';
import 'screens/placeholders.dart';
import 'screens/students_screen.dart';
import 'screens/verify_screen.dart';
import 'shell.dart';
import 'staff/staff_screens_1.dart';
import 'staff/staff_screens_2.dart';
import 'staff/staff_calendar.dart';
import 'staff/staff_reports.dart';
import 'staff/school_setup.dart';
import 'screens/help_screen.dart';
import 'screens/toppers_screen.dart';
import 'screens/council_screen.dart';
import 'staff/council_admin.dart';
import 'staff/staff_shell.dart';
import 'staff/today_screen.dart';
import 'staff/students_page.dart';
import 'staff/new_sections.dart';
import 'staff/school_settings.dart';
import 'staff/toppers_admin.dart';
import 'staff/merged_pages.dart';
import 'screens/desk_screen.dart';
import 'staff/desk_admin.dart';

/// Makes go_router re-run `redirect` whenever the session changes.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionProvider, (_, __) => notifyListeners());
    ref.listen(splashDoneProvider, (_, __) => notifyListeners());
    ref.listen(childPickedProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionListenable(ref);
  ref.onDispose(refresh.dispose);
  String? pending;   // a link the app was opened with (e.g. the payment return page), kept through the splash
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final s = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      if (s.isLoading || !ref.read(splashDoneProvider)) {
        if (loc != '/splash' && loc != '/') pending ??= state.uri.toString();
        return '/splash';
      }
      // the public "scan to verify" page (QR on receipts and report cards) opens for anyone, signed in or not
      if (pending != null && pending!.startsWith('/verify') && loc == '/splash') { final p = pending; pending = null; return p; }
      if (loc == '/verify') return null;
      if (pending != null && loc == '/splash' && s.value != null && s.value!.kind == 'student' && (s.value!.students.length < 2 || ref.read(childPickedProvider))) { final p = pending; pending = null; return p; }
      final open = loc == '/splash' || loc.startsWith('/login') || loc == '/staff-login';
      final session = s.value;
      if (session == null) return open ? null : (loc.startsWith('/staff') ? '/staff-login' : '/login');   // not signed in
      if (session.kind == 'crew') return loc == '/driver' ? null : '/driver';
      if (session.isStaff) {
        if (session.mustChangePassword) return loc == '/staff/set-password' ? null : '/staff/set-password';
        return loc.startsWith('/staff') ? null : '/staff';                // staff live under /staff
      }
      if (loc.startsWith('/staff')) return '/';                               // a family login never sees the panel
      if (session.mustChangePassword) return loc == '/set-password' ? null : '/set-password';
      if (session.students.length > 1 && (!ref.read(childPickedProvider) || session.activeStudentId == null)) return loc == '/students' || loc == '/login/add' ? null : '/students';
      if (open) return '/';                                           // signed in, leave the public pages
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/verify', builder: (_, st) => VerifyScreen(kind: st.uri.queryParameters.containsKey('p') ? 'p' : 'c', id: st.uri.queryParameters['p'] ?? st.uri.queryParameters['c'] ?? '')),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen(), routes: [
        GoRoute(path: 'add', builder: (_, __) => const LoginScreen(addSibling: true)),
      ]),
      GoRoute(path: '/set-password', builder: (_, __) => const SetPasswordScreen()),
      GoRoute(path: '/staff-login', builder: (_, __) => const StaffLoginScreen()),
      GoRoute(path: '/staff/set-password', builder: (_, __) => const StaffSetPasswordScreen()),
      ShellRoute(builder: (_, __, child) => StaffShell(child: child), routes: [
        GoRoute(path: '/staff', builder: (_, __) => const TodayScreen()),
        GoRoute(path: '/staff/messages', builder: (_, __) => const StaffMessagesScreen()),
        GoRoute(path: '/staff/announcements', builder: (_, __) => const StaffAnnouncementsScreen()),
        GoRoute(path: '/staff/diary', builder: (_, __) => const StaffDiaryScreen()),
        GoRoute(path: '/staff/leave', builder: (_, __) => const StaffLeaveScreen()),
        GoRoute(path: '/staff/exams', builder: (_, __) => const StaffExamsScreen()),
        GoRoute(path: '/staff/marks', builder: (_, __) => const StaffMarksScreen()),
        GoRoute(path: '/staff/plan', builder: (_, __) => const StaffPlanScreen()),
        GoRoute(path: '/staff/worksheets', builder: (_, __) => const StaffWorksheetsScreen()),
        GoRoute(path: '/staff/star', builder: (_, __) => const StaffStarScreen()),
        GoRoute(path: '/staff/moments', builder: (_, __) => const StaffMomentsScreen()),
        GoRoute(path: '/staff/feedback', builder: (_, __) => const StaffFeedbackScreen()),
        GoRoute(path: '/staff/fees', builder: (_, __) => const StaffFeesScreen()),
        GoRoute(path: '/staff/calendar', builder: (_, __) => const StaffCalendarScreen()),
        GoRoute(path: '/staff/reports', builder: (_, __) => const StaffReportsScreen()),
        GoRoute(path: '/staff/transport', builder: (_, __) => const TransportPage()),
        GoRoute(path: '/staff/students', builder: (_, __) => const StudentsPage()),
        GoRoute(path: '/staff/sections', builder: (_, __) => const NewSectionsScreen()),
        GoRoute(path: '/staff/settings', builder: (_, __) => const SchoolSettingsScreen()),
        GoRoute(path: '/staff/toppers', builder: (_, __) => const StaffToppersScreen()),
        GoRoute(path: '/staff/toppers/edit', builder: (_, __) => const ToppersAdminScreen()),
        GoRoute(path: '/staff/council', builder: (_, __) => const StaffCouncilScreen()),
        GoRoute(path: '/staff/council/manage', builder: (_, __) => const CouncilAdminScreen()),
        GoRoute(path: '/staff/users', builder: (_, __) => const StaffPeopleScreen()),
        GoRoute(path: '/staff/setup', builder: (_, __) => const SchoolSetupScreen()),
        GoRoute(path: '/staff/help', builder: (_, __) => const HelpScreen(staff: true)),
        GoRoute(path: '/staff/me', builder: (_, __) => const StaffMeScreen()),
        GoRoute(path: '/staff/desk', builder: (_, __) => const StaffDeskScreen()),
      ]),
      GoRoute(path: '/students', pageBuilder: (_, st) => _grow(st, const StudentsScreen())),
      GoRoute(path: '/settings', pageBuilder: (_, st) => _grow(st, const SettingsScreen())),
      GoRoute(path: '/driver', pageBuilder: (_, st) => _grow(st, const DriverScreen())),
      // tiles & secondary pages
      GoRoute(path: '/timetable', pageBuilder: (_, st) => _grow(st, const TimetableScreen())),
      GoRoute(path: '/star', pageBuilder: (_, st) => _grow(st, const StarScreen())),
      GoRoute(path: '/gallery', pageBuilder: (_, st) => _grow(st, const GalleryScreen())),
      GoRoute(path: '/leave', pageBuilder: (_, st) => _grow(st, const LeaveScreen())),
      GoRoute(path: '/plan', pageBuilder: (_, st) => _grow(st, const MonthlyPlanScreen())),
      GoRoute(path: '/worksheets', pageBuilder: (_, st) => _grow(st, const WorksheetsScreen())),
      GoRoute(path: '/exams', pageBuilder: (_, st) => _grow(st, const ExamsScreen())),
      GoRoute(path: '/calendar', pageBuilder: (_, st) => _grow(st, const CalendarScreen())),
      GoRoute(path: '/messages', pageBuilder: (_, st) => _grow(st, const MessagesScreen())),
      GoRoute(path: '/chat/:id', pageBuilder: (_, st) => _grow(st, ChatScreen(conversationId: st.pathParameters['id']!, title: st.extra as String?))),
      GoRoute(path: '/profile', pageBuilder: (_, st) => _grow(st, const ProfileScreen())),
      GoRoute(path: '/feedback', pageBuilder: (_, st) => _grow(st, const FeedbackScreen())),
      GoRoute(path: '/help', pageBuilder: (_, st) => _grow(st, const HelpScreen(staff: false))),
      GoRoute(path: '/toppers', pageBuilder: (_, st) => _grow(st, const ToppersScreen())),
      GoRoute(path: '/fame', pageBuilder: (_, st) => _grow(st, const ToppersScreen(tab: 2))),
      GoRoute(path: '/council', pageBuilder: (_, st) => _grow(st, const CouncilScreen())),
      GoRoute(path: '/desk', pageBuilder: (_, st) => _grow(st, const DeskListScreen())),
      GoRoute(path: '/pay', pageBuilder: (_, st) => _grow(st, const PayScreen()), routes: [
        GoRoute(path: 'done', pageBuilder: (_, st) => _grow(st, ReceiptScreen(paymentId: st.uri.queryParameters['payment_id'] ?? ''))),   // return URL of the web payment link
      ]),
      GoRoute(path: '/receipts', pageBuilder: (_, st) => _grow(st, const ReceiptsScreen())),
      GoRoute(path: '/notice/:id', pageBuilder: (_, st) => _grow(st, NoticeScreen(id: st.pathParameters['id']!))),
      GoRoute(path: '/receipt/:id', pageBuilder: (_, st) => _grow(st, ReceiptScreen(paymentId: st.pathParameters['id']!))),
      // main shell with bottom tabs
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/fees', builder: (_, __) => const FeesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/diary', builder: (_, __) => const DiaryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/announcements', builder: (_, __) => const AnnouncementsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/bus', builder: (_, __) => const BusScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen())]),
        ],
      ),
    ],
  );
});


/// Secondary pages grow gently into place (and shrink back): a soft zoom with a fade.
Page<void> _grow(GoRouterState st, Widget child) => CustomTransitionPage<void>(
      key: st.pageKey, child: child,
      transitionDuration: const Duration(milliseconds: 420), reverseTransitionDuration: const Duration(milliseconds: 320),
      transitionsBuilder: (context, a, b, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(opacity: c, child: ScaleTransition(scale: Tween(begin: .94, end: 1.0).animate(c),
            child: SlideTransition(position: Tween(begin: const Offset(0, .025), end: Offset.zero).animate(c), child: child)));
      },
    );
