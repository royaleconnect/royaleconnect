import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/data3.dart' show appSettingsProvider, featureOn;
import '../screens/thanks_screen.dart' show thanksWeekNow;
import '../widgets/common.dart';
import '../widgets/royal_extras.dart' show GoldLoading;
import '../widgets/royal_motion.dart';
import 'staff_shell.dart';

/// Teachers' Day thank-you wall (teacher side): the notes families sent to this teacher, as gold cards.
/// The notes stay with the teacher after the week (and in later years).

final staffThanksProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  final s = ref.watch(sessionProvider).value;
  if (s == null || !s.isStaff) return const [];
  return List<Map<String, dynamic>>.from(await db.rpc('thanks_wall') as List);
});

const _paper = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFFBEF), Color(0xFFFBEFD0)]);
const _paperLine = Color(0xFFEBD39A), _ink = Color(0xFF3A2A08), _goldInk = Color(0xFF8A6A1E);

/// Compact card for the staff Today page: how many notes and the newest one. Shown in Teachers' Day week and for a year
/// after the teacher receives notes; hidden otherwise.
class ThanksWallCard extends ConsumerWidget {
  const ThanksWallCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!featureOn(ref.watch(appSettingsProvider).value, 'thanks')) return const SizedBox.shrink();
    final notes = ref.watch(staffThanksProvider).value;
    if (notes == null) return const SizedBox.shrink();
    final week = thanksWeekNow();
    // the notes of the last 12 months (so the card stays all year after Teachers' Day, then makes room)
    final cutoff = DateTime.now().subtract(const Duration(days: 365));
    final thisYear = notes.where((n) => (DateTime.tryParse('${n['created_at']}') ?? DateTime(2000)).isAfter(cutoff)).toList();
    if (!week && thisYear.isEmpty) return const SizedBox.shrink();
    final newest = thisYear.isEmpty ? null : thisYear.first;
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Material(color: Colors.transparent, child: InkWell(
      onTap: () => context.push('/staff/thanks'), borderRadius: BorderRadius.circular(18),
      child: Ink(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: _paper, borderRadius: BorderRadius.circular(18), border: Border.all(color: _paperLine, width: 1.5),
          boxShadow: [BoxShadow(color: const Color(0xFF785000).withValues(alpha: .18), blurRadius: 16, offset: const Offset(0, 6))]),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.favorite_rounded, color: Color(0xFFB5121A)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(thisYear.isEmpty ? 'Your thank-you wall' : 'Your thank-you wall · ${thisYear.length} ${thisYear.length == 1 ? 'note' : 'notes'}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, color: _ink)),
            const SizedBox(height: 4),
            if (newest == null)
              const Text('It is Teachers’ Day week. Thank-you notes from families will appear here.', style: TextStyle(color: _goldInk, fontSize: 13, height: 1.4))
            else ...[
              Text('“${newest['body']}”', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cormorantGaramond(fontSize: 17, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, color: _ink, height: 1.25)),
              Text('— ${_from(newest)}', style: const TextStyle(color: _goldInk, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ])),
          const Padding(padding: EdgeInsets.only(left: 8, top: 2), child: Text('Open ›', style: TextStyle(color: _goldInk, fontWeight: FontWeight.w900))),
        ]),
      ),
    )));
  }
}

String _from(Map<String, dynamic> n) => [n['from'], n['cls']].where((x) => x != null && '$x'.isNotEmpty).join(', ');

class StaffThanksScreen extends ConsumerWidget {
  const StaffThanksScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(staffThanksProvider);
    final n = notes.value?.length ?? 0;
    return StaffPage(
      title: 'Your thank-you wall',
      subtitle: n == 0 ? 'Notes families send you in Teachers’ Day week (2–8 September). They stay with you.' : '$n ${n == 1 ? 'note' : 'notes'} from families · they stay with you',
      body: notes.when(
        loading: () => const GoldLoading(),
        error: (e, _) => NoteBox('Could not load your notes. $e'),
        data: (list) {
          if (list.isEmpty) return const NoteBox('No notes yet. During Teachers’ Day week families can send you a short thank-you, and it will appear here.', icon: Icons.favorite_border_rounded);
          final years = <int, List<Map<String, dynamic>>>{};
          for (final x in list) { years.putIfAbsent((x['yr'] as num?)?.toInt() ?? 0, () => []).add(x); }
          var shown = 0;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final y in years.keys) ...[
              if (years.length > 1) Padding(padding: const EdgeInsets.fromLTRB(2, 6, 0, 10), child: Text("Teachers' Day $y",
                  style: GoogleFonts.cinzel(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Theme.of(context).colorScheme.onSurface))),
              LayoutBuilder(builder: (_, c) {
                final cols = c.maxWidth >= 900 ? 3 : c.maxWidth >= 520 ? 2 : 1;
                final w = (c.maxWidth - (cols - 1) * 12) / cols;
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final note in years[y]!) SizedBox(width: w, child: FadeRise(
                      // the first dozen appear one by one, the rest quickly
                      delayMs: 200 + math.min(shown++, 12) * 320 + math.max(0, shown - 12) * 40, dy: 16,
                      child: _Note(note, tilt: ((note['id'] as String).hashCode % 5 - 2) * .012))),
                ]);
              }),
              const SizedBox(height: 18),
            ],
          ]);
        },
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final Map<String, dynamic> n; final double tilt;
  const _Note(this.n, {required this.tilt});
  @override
  Widget build(BuildContext context) => Transform.rotate(angle: tilt, child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(gradient: _paper, borderRadius: BorderRadius.circular(16), border: Border.all(color: _paperLine),
            boxShadow: [BoxShadow(color: const Color(0xFF785000).withValues(alpha: .22), blurRadius: 16, offset: const Offset(0, 8), spreadRadius: -6)]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('“${n['body']}”', style: GoogleFonts.cormorantGaramond(fontSize: 18.5, fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, color: _ink, height: 1.3)),
          const SizedBox(height: 10),
          Text('— ${_from(n)}', style: const TextStyle(color: _goldInk, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ]),
      ));
}
