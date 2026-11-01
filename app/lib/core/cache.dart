import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/session.dart';

/// Who is signed in (and which child is open). Data kept by [CacheFor] is thrown away the moment this changes,
/// so one person never sees another person's data.
final sessionKeyProvider = Provider<String>((ref) {
  final s = ref.watch(sessionProvider).value;
  if (s == null) return '';
  return '${s.kind}|${s.staff?['id']}|${s.crew?['id']}|${s.activeStudentId}|${s.viewOnly}|${s.students.map((e) => e.id).join(',')}';
});

/// Keeps a screen's data for a few minutes after the screen is closed. Going back to the screen shows that data at once
/// (no loading shimmer) while fresh data is fetched quietly behind it and replaces it a moment later.
extension CacheFor on AutoDisposeRef<Object?> {
  void cacheFor([Duration keep = const Duration(minutes: 3)]) {
    watch(sessionKeyProvider);
    final link = keepAlive();
    Timer? t;
    onCancel(() { t?.cancel(); t = Timer(keep, link.close); });
    onResume(() { t?.cancel(); invalidateSelf(); });
    onDispose(() => t?.cancel());
  }
}
