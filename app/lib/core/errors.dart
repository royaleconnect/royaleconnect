/// Turns any error into one short, kind sentence for parents and staff — never raw technical text.
String friendlyError(Object? e) {
  final t = '$e'.toLowerCase();
  if (t.contains('socketexception') || t.contains('failed host lookup') || t.contains('network') || t.contains('clientexception') ||
      t.contains('xmlhttprequest') || t.contains('connection') || t.contains('timeout')) {
    return 'No internet right now. Please check your connection and try again.';
  }
  if (t.contains('jwt') || t.contains('expired') || t.contains('401') || t.contains('session') && t.contains('revoked')) {
    return 'Please sign in again.';
  }
  if (t.contains('not allowed') || t.contains('permission') || t.contains('42501') || t.contains('403')) {
    return 'You don’t have access to this. Please ask the school office.';
  }
  // messages our own database functions raise on purpose are already written in plain English
  final m = RegExp(r'message:\s*([^,}]+)').firstMatch('$e')?.group(1)?.trim();
  if (m != null && m.isNotEmpty && !m.contains('_') && m.length < 160) return m;
  return 'Something went wrong. Please try again in a minute.';
}
