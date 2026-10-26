{{flutter_js}}
{{flutter_build_config}}

// Royale Connect: start the app without Flutter's own offline-cache worker, so the notification worker
// (firebase-messaging-sw.js) is the only one on this site.
_flutter.loader.load();
