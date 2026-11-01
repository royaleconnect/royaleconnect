import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/data.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_extras.dart' show PulseRing;

/// The small health dot at the top of the IT / Principal dashboard.
/// Green: all is well · Amber: something to look at · Red: something is not working.
/// Tap it for the details. Comes from the database function system_health().

final systemHealthProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  try {
    return Map<String, dynamic>.from(await db.rpc('system_health') as Map);
  } catch (e) {
    final missing = '$e'.contains('system_health');
    return {'level': missing ? 'amber' : 'red', 'database': missing,   // "function does not exist" still means the database answered
            'notes': [missing ? 'The health check is not set up yet (the database step of this update has not been run).' : 'The app could not reach the database. If this stays red for more than a few minutes, see Help → IT handbook → “If the app is down”.']};
  }
});

Color _colour(String? l) => l == 'green' ? Brand.green : l == 'amber' ? const Color(0xFFE0A100) : Brand.crimson;
String _word(String? l) => l == 'green' ? 'All is well' : l == 'amber' ? 'Something to look at' : 'Something is not working';

class HealthDot extends ConsumerStatefulWidget {
  const HealthDot({super.key});
  @override
  ConsumerState<HealthDot> createState() => _HealthDotState();
}

class _HealthDotState extends ConsumerState<HealthDot> {
  Timer? t;
  @override
  void initState() { super.initState(); t = Timer.periodic(const Duration(minutes: 2), (_) => ref.invalidate(systemHealthProvider)); }
  @override
  void dispose() { t?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final h = ref.watch(systemHealthProvider).value;
    final level = h?['level'] as String?;
    final c = h == null ? Theme.of(context).colorScheme.outline : _colour(level);
    final dot = Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)));
    return Tooltip(message: h == null ? 'Checking…' : 'App health: ${_word(level)}', child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: h == null ? null : () => _details(context, h),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 14, height: 14, child: Center(child: level == 'red' ? PulseRing(color: c, child: dot) : dot)),
        const SizedBox(width: 6),
        Text('Health', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
    ));
  }

  void _details(BuildContext context, Map<String, dynamic> h) {
    final cs = Theme.of(context).colorScheme;
    final notes = List<String>.from(h['notes'] ?? const []);
    String ago(String? iso) {
      if (iso == null) return '—';
      final t = DateTime.parse(iso).toLocal();
      final d = DateTime.now().difference(t);
      if (d.inMinutes < 1) return 'just now';
      if (d.inMinutes < 60) return '${d.inMinutes} min ago';
      if (d.inHours < 24) return '${d.inHours} h ago';
      return DateFormat('d MMM, h:mm a').format(t);
    }
    Widget row(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
      Expanded(child: Text(k, style: TextStyle(color: cs.onSurfaceVariant))),
      Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
    ]));
    final nightly = h['last_nightly'] is Map ? Map<String, dynamic>.from(h['last_nightly']) : null;
    final missing = List<String>.from(h['jobs_missing'] ?? const []);
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Row(children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: _colour(h['level']), shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(_word(h['level']))),
      ]),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (notes.isEmpty) const NoteBox('Everything the app checks is working.', icon: Icons.verified_rounded, iconColor: Brand.green),
        for (final n in notes) Padding(padding: const EdgeInsets.only(bottom: 6), child: NoteBox(n, icon: Icons.warning_amber_rounded, iconColor: _colour(h['level']))),
        const SizedBox(height: 6),
        row('Database', h['database'] == false ? 'Not answering' : 'Answering'),
        if (h.containsKey('last_push_at')) row('Last phone notification sent', ago(h['last_push_at'])),
        if (h.containsKey('queue')) row('Notifications waiting', '${h['queue'] ?? 0}${(h['queue_oldest_min'] ?? 0) > 0 ? ' · oldest ${h['queue_oldest_min']} min' : ''}'),
        if (h['push_failed_24h'] != null) row('Sender failures (24 h)', '${h['push_failed_24h']}'),
        if (h['failed_calls'] != null) row('Failed calls (6 h)', '${h['failed_calls']}'),
        if (h.containsKey('jobs')) row('Scheduled jobs', h['jobs'] == null ? 'could not read' : missing.isEmpty ? 'all present' : 'missing: ${missing.join(', ')}'),
        if (nightly != null) row('Last night job', '${nightly['status'] ?? '—'} · ${ago(nightly['at'])}'),
        if (h['errors_24h'] != null) row('App errors (24 h)', '${h['errors_24h']}'),
        if (h['db_mb'] != null) row('Database used', '${h['db_mb']} MB of 500 MB'),
        const SizedBox(height: 10),
        Text('The website and database are also checked every 30 minutes from outside. If they stop answering, an email goes to the IT address.', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]))),
      actions: [
        TextButton(onPressed: () => launchUrl(Uri.parse('https://github.com/royaleconnect/royaleconnect/actions'), mode: LaunchMode.externalApplication), child: const Text('Backups & checks')),
        TextButton(onPressed: () => launchUrl(Uri.parse('https://console.firebase.google.com/project/royale-connect/crashlytics'), mode: LaunchMode.externalApplication), child: const Text('Crash reports')),
        FilledButton(onPressed: () { ref.invalidate(systemHealthProvider); Navigator.pop(c); }, child: const Text('Close')),
      ],
    ));
  }
}
