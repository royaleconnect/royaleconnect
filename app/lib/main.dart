import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth/session.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Login is handled by our own server functions; the database client lives in core/data.dart and carries the session token.
  runApp(const ProviderScope(child: RoyaleConnectApp()));
}

class RoyaleConnectApp extends ConsumerWidget {
  const RoyaleConnectApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isStaff = ref.watch(sessionProvider).value?.isStaff ?? false;
    return MaterialApp.router(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        routerConfig: ref.watch(routerProvider),
        // On a laptop or tablet the app is framed at phone width, centred, so every screen keeps its intended proportions.
        builder: (context, child) => LayoutBuilder(builder: (_, c) => (isStaff || c.maxWidth <= 600) ? child! : ColoredBox(
            color: const Color(0xFFE9E4DC),
            child: Center(child: ClipRRect(borderRadius: BorderRadius.circular(c.maxHeight > 900 ? 28 : 0), child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 480, maxHeight: c.maxHeight > 900 ? 860 : c.maxHeight), child: child!))))),
      );
  }
}
