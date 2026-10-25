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
import 'shell.dart';

/// Makes go_router re-run `redirect` whenever the session changes.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) { ref.listen(sessionProvider, (_, __) => notifyListeners()); }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _SessionListenable(ref);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final s = ref.read(sessionProvider);
      if (s.isLoading) return '/splash';
      final loc = state.matchedLocation;
      final open = loc == '/splash' || loc.startsWith('/login');
      final session = s.value;
      if (session == null) return open ? null : '/login';           // not signed in
      if (session.kind == 'crew') return loc == '/driver' ? null : '/driver';
      if (session.mustChangePassword) return loc == '/set-password' ? null : '/set-password';
      if (session.activeStudentId == null && session.students.length > 1) return loc == '/students' || loc == '/login/add' ? null : '/students';
      if (open) return '/';                                           // signed in, leave the public pages
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen(), routes: [
        GoRoute(path: 'add', builder: (_, __) => const LoginScreen(addSibling: true)),
      ]),
      GoRoute(path: '/set-password', builder: (_, __) => const SetPasswordScreen()),
      GoRoute(path: '/students', builder: (_, __) => const StudentsScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/driver', builder: (_, __) => const DriverScreen()),
      // tiles & secondary pages
      GoRoute(path: '/timetable', builder: (_, __) => const TimetableScreen()),
      GoRoute(path: '/star', builder: (_, __) => const StarScreen()),
      GoRoute(path: '/gallery', builder: (_, __) => const GalleryScreen()),
      GoRoute(path: '/leave', builder: (_, __) => const LeaveScreen()),
      GoRoute(path: '/plan', builder: (_, __) => const MonthlyPlanScreen()),
      GoRoute(path: '/worksheets', builder: (_, __) => const WorksheetsScreen()),
      GoRoute(path: '/exams', builder: (_, __) => const ExamsScreen()),
      GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
      GoRoute(path: '/messages', builder: (_, __) => const MessagesScreen()),
      GoRoute(path: '/chat/:id', builder: (_, st) => ChatScreen(conversationId: st.pathParameters['id']!, title: st.extra as String?)),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(path: '/feedback', builder: (_, __) => const FeedbackScreen()),
      GoRoute(path: '/pay', builder: (_, __) => const PayScreen(), routes: [
        GoRoute(path: 'done', builder: (_, st) => ReceiptScreen(paymentId: st.uri.queryParameters['payment_id'] ?? '')),   // return URL of the web payment link
      ]),
      GoRoute(path: '/receipts', builder: (_, __) => const ReceiptsScreen()),
      GoRoute(path: '/receipt/:id', builder: (_, st) => ReceiptScreen(paymentId: st.pathParameters['id']!)),
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
