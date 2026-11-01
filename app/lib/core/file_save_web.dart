import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

/// Browser download without extra packages: Blob → object URL → a hidden link that is clicked once.
Future<void> saveBytesImpl(Uint8List bytes, String fileName, String mime) async {
  final doc = globalContext['document'] as JSObject;
  final urlApi = globalContext['URL'] as JSObject;
  final opts = JSObject()..['type'] = mime.toJS;
  final blob = (globalContext['Blob'] as JSFunction).callAsConstructor<JSObject>(<JSAny?>[bytes.toJS].toJS, opts);
  final url = urlApi.callMethod<JSString>('createObjectURL'.toJS, blob);
  final a = doc.callMethod<JSObject>('createElement'.toJS, 'a'.toJS);
  a['href'] = url;
  a['download'] = fileName.toJS;
  (doc['body'] as JSObject).callMethod<JSAny?>('appendChild'.toJS, a);
  a.callMethod<JSAny?>('click'.toJS);
  a.callMethod<JSAny?>('remove'.toJS);
  Future.delayed(const Duration(seconds: 2), () => urlApi.callMethod<JSAny?>('revokeObjectURL'.toJS, url));
}
