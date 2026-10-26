import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/session.dart';
import '../router.dart';
import 'data.dart' show db;

/// Phone notifications (Firebase Cloud Messaging) and crash reports (Crashlytics).
/// Everything here is best-effort: if Firebase is unavailable the app simply runs without it.
class FirebaseWeb {
  // Web keys only identify the project; they are public by design. Android reads its own from google-services.json.
  static const options = FirebaseOptions(
    apiKey: 'AIzaSyA3VbQjT0bOEXFHTWfFVX_5P5erfSZP9j4',
    authDomain: 'royale-connect.firebaseapp.com',
    projectId: 'royale-connect',
    storageBucket: 'royale-connect.firebasestorage.app',
    messagingSenderId: '93672973250',
    appId: '1:93672973250:web:429ff96e5742a622faac5b',
  );
  static const vapidKey = 'BPqRrMhzusxYlII8rx13ZnRXflNr6XHZtiBZPTmZ_fp19nV4viqpb0cIXIiOI59ej_Yjxu8uZ418FhBrQUdskcU';
}

bool firebaseReady = false;
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Called once in main() before the app starts.
Future<void> initFirebase() async {
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(options: FirebaseWeb.options);
    } else {
      await Firebase.initializeApp();
    }
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase not available: $e');
    return;
  }
  if (kIsWeb) return;   // crash reports are for the phone apps
  try {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      FirebaseCrashlytics.instance.recordFlutterError(details);   // screen/layout problems: reported, app keeps running
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (e) {
    debugPrint('Crash reports not available: $e');
  }
}

String _platform() => kIsWeb ? 'web' : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');

/// The page a notification opens. Same rules as send-notifications on the server.
String routeFor(String? link, {required bool staff}) {
  final l = (link ?? '').replaceFirst(RegExp(r'^/'), '');
  if (l.isEmpty) return staff ? '/staff' : '/';
  if (l.startsWith('fee')) return '/fees';
  if (l.startsWith('chat/')) return staff ? '/staff/messages' : '/$l';
  return '/$l';
}

const _tabs = {'/', '/fees', '/diary', '/announcements', '/bus', '/reports'};

class Push {
  static String? _token;          // this phone's push address
  static String? _registeredFor;  // the session it was last registered for
  static bool _listening = false;

  /// Start listening for notifications. Called once when the app widget is created.
  static void start(WidgetRef ref) {
    if (!firebaseReady || _listening) return;
    _listening = true;
    final m = FirebaseMessaging.instance;
    FirebaseMessaging.onMessage.listen((msg) => _showInApp(ref, msg));          // app open: a banner inside the app
    FirebaseMessaging.onMessageOpenedApp.listen((msg) => _open(ref, msg.data)); // tapped while the app was in the background
    m.getInitialMessage().then((msg) { if (msg != null) _open(ref, msg.data); }).catchError((_) {});   // tapped while the app was closed
    m.onTokenRefresh.listen((t) { _token = t; _send(t); }, onError: (_) {});
    if (!kIsWeb) m.setForegroundNotificationPresentationOptions(alert: false, badge: true, sound: false).catchError((_) {});
  }

  /// Register this phone for whoever is signed in. Safe to call often; only does work when the sign-in changes.
  static Future<void> sync(Session? s) async {
    if (!firebaseReady || s == null || s.kind == 'crew' || s.mustChangePassword || s.viewOnly) return;
    if (_registeredFor == s.token) return;
    _registeredFor = s.token;
    try {
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.setCustomKey('signed_in_as', s.kind).catchError((_) {});
      }
      final perm = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      final t = await FirebaseMessaging.instance.getToken(
          vapidKey: kIsWeb ? FirebaseWeb.vapidKey : null,
          serviceWorkerScriptPath: kIsWeb ? 'firebase-messaging-sw.js' : null);
      if (t == null) return;
      _token = t;
      await _send(t);
    } catch (e) {
      _registeredFor = null;   // try again next time
      debugPrint('Push registration skipped: $e');
    }
  }

  static Future<void> _send(String t) async {
    try {
      await db.rpc('register_push_token', params: {'p_token': t, 'p_platform': _platform(), 'p_label': 'app'});
    } catch (e) {
      debugPrint('Push token not saved: $e');
    }
  }

  /// Called on sign out, while the old sign-in is still active, so this phone stops getting that family's notifications.
  static Future<void> forget() async {
    final t = _token;
    _registeredFor = null;
    if (t == null) return;
    try {
      await db.rpc('unregister_push_token', params: {'p_token': t});
    } catch (_) {}
  }

  static void _showInApp(WidgetRef ref, RemoteMessage msg) {
    final n = msg.notification;
    if (n == null) return;
    final messenger = appMessengerKey.currentState;
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n.title ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
        if ((n.body ?? '').isNotEmpty) Text(n.body!, maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
      action: SnackBarAction(label: 'Open', onPressed: () => _open(ref, msg.data)),
    ));
  }

  static Future<void> _open(WidgetRef ref, Map<String, dynamic> data) async {
    try {
      // wait until the opening screen has finished and the sign-in is loaded (at most ~15 s)
      for (var i = 0; i < 60; i++) {
        if (ref.read(splashDoneProvider) && !ref.read(sessionProvider).isLoading) break;
        await Future.delayed(const Duration(milliseconds: 250));
      }
      final s = ref.read(sessionProvider).value;
      if (s == null) return;
      // a notification about a brother or sister switches the app to that child first
      final sid = data['student_id']?.toString() ?? '';
      if (s.kind == 'student' && sid.isNotEmpty && s.students.any((x) => x.id == sid)) {
        if (s.activeStudentId != sid) await ref.read(sessionProvider.notifier).selectStudent(sid);
        ref.read(childPickedProvider.notifier).done();
      }
      final route = routeFor(data['deep_link']?.toString(), staff: s.isStaff);
      final router = ref.read(routerProvider);
      if (s.isStaff || _tabs.contains(route)) {
        router.go(route);
      } else {
        router.go('/');
        router.push(route);
      }
    } catch (e) {
      debugPrint('Could not open notification: $e');
    }
  }
}
