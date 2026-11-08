import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/session.dart';
import '../core/data2.dart';
import '../core/errors.dart';
import '../core/theme.dart';
import 'staff_shell.dart';

/// "Buses running now" for the staff Transport page. Every staff member can see it;
/// the transport in-charge, office and IT (and the Principal / Vice Principal) can end a trip that was left running.
class RunningBusesPanel extends ConsumerWidget {
  const RunningBusesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(sessionProvider).value;
    final canEnd = s != null && !s.viewOnly && ['transport_incharge', 'office', 'it_admin', 'principal', 'vice_principal'].any(s.hasRole);
    final trips = ref.watch(busRunningProvider);
    return Panel(title: 'Buses running now', child: trips.when(
      skipLoadingOnRefresh: true,
      loading: () => const SizedBox(height: 24),
      error: (e, _) => Text(friendlyError(e), style: TextStyle(color: cs.onSurfaceVariant)),
      data: (list) => list.isEmpty
          ? Text('No bus is on a trip right now.', style: TextStyle(color: cs.onSurfaceVariant))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final t in list) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
                const Icon(Icons.gps_fixed_rounded, color: Brand.green, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Bus ${t['bus']} · ${'${t['kind']}'.startsWith('morning') ? 'morning' : 'afternoon'} trip', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text([
                    'started ${time12Iso(t['started_at'] as String?)}',
                    if (t['crew'] != null) '${t['crew']}',
                    t['last_fix_at'] == null ? 'no location yet' : 'last location ${time12Iso(t['last_fix_at'] as String?)}',
                  ].join(' · '), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                ])),
                if (canEnd) OutlinedButton(onPressed: () => _end(context, ref, t), child: const Text('End trip')),
              ])),
              const SizedBox(height: 4),
              Text('A trip also ends by itself 15 minutes after the bus stands at school in the morning, or 3 hours after it started.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ]),
    ));
  }

  Future<void> _end(BuildContext context, WidgetRef ref, Map<String, dynamic> t) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: Text('End the trip of bus ${t['bus']}?'),
      content: const Text('Parents of this bus will stop seeing it on the map.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not yet')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('End trip'))],
    ));
    if (ok != true) return;
    try {
      await endTrip(t['id'] as String);
      ref.invalidate(busRunningProvider);
      if (context.mounted) toast(context, 'Trip of bus ${t['bus']} ended ✓');
    } catch (e) {
      if (context.mounted) toast(context, friendlyError(e));
    }
  }
}
