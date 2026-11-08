/// Keep the screen on while a bus trip is being shared from this phone.
/// Website / installed web app: the browser's Screen Wake Lock (Chrome, Edge, Safari 16.4+). Android / iPhone app: nothing here
/// (no extra package); the "Bus trip running" notification keeps the location going with the screen off.
export 'wake_lock_stub.dart' if (dart.library.js_interop) 'wake_lock_web.dart';
