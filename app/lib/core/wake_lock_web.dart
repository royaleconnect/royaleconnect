import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSObject? _sentinel;

/// Asks the browser to keep the screen on (released when the page is hidden; call again when the app comes back).
Future<void> keepScreenOn(bool on) async {
  try {
    if (on) {
      final nav = globalContext['navigator'] as JSObject?;
      final wl = nav?['wakeLock'];
      if (wl == null || wl.isUndefinedOrNull) return;
      final p = (wl as JSObject).callMethod<JSPromise<JSObject>>('request'.toJS, 'screen'.toJS);
      _sentinel = await p.toDart;
    } else {
      final s = _sentinel; _sentinel = null;
      s?.callMethod<JSAny?>('release'.toJS);
    }
  } catch (_) {/* not supported or refused: the trip still runs */}
}
