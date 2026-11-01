import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/cache.dart';
import '../core/data.dart';

/// Families' notices: "Keep on top until <date>" and the bus part of the audience ("Bus students only" / "One bus route").
/// Read separately from the notice list so the list still works before the database step of this update is run.
/// (The database already hides bus notices from families who are not on that bus; this keeps a sibling's
///  bus notice out of the other child's list on a shared family login.)

class NoticeExtra {
  final DateTime? pinnedUntil; final bool busOnly; final List<String> routes;
  const NoticeExtra(this.pinnedUntil, this.busOnly, this.routes);
  bool get forBus => busOnly || routes.isNotEmpty;
  /// kept on top until the end of that day
  bool get pinned {
    final p = pinnedUntil;
    if (p == null) return false;
    final t = DateTime.now();
    return !p.isBefore(DateTime(t.year, t.month, t.day));
  }
}

final noticeExtrasProvider = FutureProvider.autoDispose<Map<String, NoticeExtra>>((ref) async {
  ref.cacheFor();
  try {
    final rows = await db.from('announcement').select('id,pinned_until,audience_bus_only,audience_route_ids')
        .not('sent_at', 'is', null).order('sent_at', ascending: false).limit(80);
    return {for (final r in rows) r['id'] as String: NoticeExtra(r['pinned_until'] == null ? null : DateTime.tryParse('${r['pinned_until']}'),
        r['audience_bus_only'] == true, [for (final x in (r['audience_route_ids'] as List? ?? const [])) '$x'])};
  } catch (_) {
    return const {};
  }
});

/// The notices for the active child: bus notices only when the child's route matches; kept-on-top first.
List<Notice> familyNotices(List<Notice> list, Map<String, NoticeExtra> extras, String? myRouteId) {
  final shown = list.where((n) {
    final x = extras[n.id];
    if (x == null || !x.forBus) return true;
    if (myRouteId == null) return false;
    return x.routes.isEmpty || x.routes.contains(myRouteId);
  }).toList();
  return [...shown.where((n) => extras[n.id]?.pinned == true), ...shown.where((n) => extras[n.id]?.pinned != true)];
}

/// "Whole school" / "Your class" … or "Bus families" / "Your bus route".
String noticeAudience(Notice n, NoticeExtra? x) => x == null || !x.forBus ? n.audience : x.routes.isEmpty ? 'Bus families' : 'Your bus route';
