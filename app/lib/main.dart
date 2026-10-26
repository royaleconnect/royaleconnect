import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth/session.dart';
import 'core/config.dart';
import 'core/push.dart';
import 'core/theme.dart';
import 'parent_layout.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // notifications + crash reports; the app still opens if this is slow or unavailable
  await initFirebase().timeout(const Duration(seconds: 8), onTimeout: () {});
  // Login is handled by our own server functions; the database client lives in core/data.dart and carries the session token.
  runApp(const ProviderScope(child: RoyaleConnectApp()));
}

class RoyaleConnectApp extends ConsumerStatefulWidget {
  const RoyaleConnectApp({super.key});
  @override
  ConsumerState<RoyaleConnectApp> createState() => _RoyaleConnectAppState();
}

class _RoyaleConnectAppState extends ConsumerState<RoyaleConnectApp> {
  @override
  void initState() {
    super.initState();
    Push.start(ref);
    WidgetsBinding.instance.addPostFrameCallback((_) => Push.sync(ref.read(sessionProvider).value));
  }

  @override
  Widget build(BuildContext context) {
    // register this phone for notifications whenever someone signs in (or a sibling is added)
    ref.listen(sessionProvider, (_, next) => Push.sync(next.value));
    final isStaff = ref.watch(sessionProvider).value?.isStaff ?? false;
    return MaterialApp.router(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ref.watch(themeModeProvider),
        routerConfig: ref.watch(routerProvider),
        scaffoldMessengerKey: appMessengerKey,
        // Staff: full-width panel. Parents on a laptop (960 px and wider): side menu + full page.
        // Everything else on a big screen (sign-in pages, small tablets) is framed at phone width, centred.
        builder: (context, child) => AnimatedBuilder(animation: ref.watch(routerProvider).routerDelegate, builder: (context, _) => LayoutBuilder(builder: (_, c) {
          final sess = ref.watch(sessionProvider).value;
          final loc = ref.read(routerProvider).routerDelegate.currentConfiguration.uri.path;
          final family = sess != null && sess.kind == 'student' && !sess.mustChangePassword && sess.active != null && ref.watch(splashDoneProvider) && (sess.students.length == 1 || (sess.activeStudentId != null && ref.watch(childPickedProvider)));
          if (isStaff || c.maxWidth <= 600 || loc == '/splash') return child!;      // the opening screen fills any screen
          if (family && c.maxWidth >= 960) return ParentFrame(child: child!);
          final dark = Theme.of(context).brightness == Brightness.dark;
          return DecoratedBox(
            decoration: BoxDecoration(gradient: RadialGradient(radius: 1.2, colors: dark ? const [Color(0xFF1E1A20), Color(0xFF0E0C10)] : const [Color(0xFFFFFDF8), Color(0xFFF1E9DB)])),
            child: Center(child: ClipRRect(borderRadius: BorderRadius.circular(c.maxHeight > 900 ? 28 : 0), child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 480, maxHeight: c.maxHeight > 900 ? 860 : c.maxHeight), child: child!))));
        })),
      );
  }
}
