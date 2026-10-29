import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth/session.dart';
import '../core/data2.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import 'academics_screens.dart' show AppPage;

Widget _loading() => const Center(child: CircularProgressIndicator());
Widget _empty(BuildContext c, String t) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, height: 1.5))));

/// Image from the private bucket via a signed URL.
class StorageImage extends ConsumerWidget {
  final String path; final BoxFit fit; final double? width, height; final BorderRadius? radius;
  const StorageImage(this.path, {super.key, this.fit = BoxFit.cover, this.width, this.height, this.radius});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(signedUrlProvider(path));
    final ph = Container(width: width, height: height, color: Theme.of(context).colorScheme.surfaceContainerHighest);
    return ClipRRect(borderRadius: radius ?? BorderRadius.zero, child: url.when(loading: () => ph, error: (_, __) => ph,
        data: (u) => CachedNetworkImage(imageUrl: u, fit: fit, width: width, height: height, placeholder: (_, __) => ph, errorWidget: (_, __, ___) => ph)));
  }
}

// ---------------------------------------------------------------- gallery
class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});
  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}
class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppPage(title: 'Gallery',
      headerExtra: Row(children: [for (final (i, l) in ['Class moments', 'School albums'].indexed) Expanded(child: GestureDetector(onTap: () => setState(() => tab = i), child: Container(
        margin: const EdgeInsets.only(right: 8), height: 36, alignment: Alignment.center, decoration: BoxDecoration(color: tab == i ? Colors.white : Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
        child: Text(l, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: tab == i ? Brand.crimsonDeep : Colors.white)))))]),
      body: tab == 0 ? _moments(cs) : _albums(cs));
  }

  Widget _moments(ColorScheme cs) {
    final m = ref.watch(momentsProvider);
    final me = ref.watch(sessionProvider).value!.active!;
    return m.when(loading: _loading, error: (e, _) => _empty(context, '$e'), data: (list) => list.isEmpty ? _empty(context, 'Photos the class teacher shares from the classroom appear here.') :
      ListView.separated(padding: const EdgeInsets.all(20), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 14), itemBuilder: (_, i) {
        final mo = list[i]; final paths = List<String>.from(mo['photo_paths'] ?? []);
        final likes = (mo['moment_like'] as List); final liked = likes.any((l) => l['student_id'] == me.id);
        return Container(decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(20)), clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (paths.isNotEmpty) GestureDetector(onTap: () => _view(paths, 0), child: AspectRatio(aspectRatio: 4 / 3, child: StorageImage(paths.first))),
          if (paths.length > 1) SizedBox(height: 64, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), children: [for (final (j, p) in paths.indexed) if (j > 0) Padding(padding: const EdgeInsets.only(right: 6), child: GestureDetector(onTap: () => _view(paths, j), child: StorageImage(p, width: 56, height: 56, radius: BorderRadius.circular(10))))])),
          Padding(padding: const EdgeInsets.fromLTRB(14, 10, 10, 10), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mo['caption'], style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
              Text('${mo['posted_by_staff']?['display_name'] ?? ''} · ${DateFormat('d MMM').format(DateTime.parse(mo['posted_at']).toLocal())}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ])),
            TextButton.icon(onPressed: () async { await toggleLike(mo['id'], me.id, liked); ref.invalidate(momentsProvider); },
              icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: Brand.crimson, size: 20), label: Text('${likes.length}', style: const TextStyle(color: Brand.crimson, fontWeight: FontWeight.w800))),
          ])),
        ]));
      }));
  }

  Widget _albums(ColorScheme cs) {
    final a = ref.watch(albumsProvider);
    return a.when(loading: _loading, error: (e, _) => _empty(context, '$e'), data: (list) => list.isEmpty ? _empty(context, 'School event albums appear here.') :
      ListView(padding: const EdgeInsets.all(20), children: [for (final al in list) ...[
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Expanded(child: Text(al['title'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))), if (al['event_date'] != null) Text(DateFormat('d MMM yyyy').format(DateTime.parse(al['event_date'])), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))])),
        Builder(builder: (_) { final photos = (List<Map<String, dynamic>>.from(al['album_photo'] ?? [])..sort((x, y) => (x['sort_order'] as int).compareTo(y['sort_order'] as int))).map((p) => p['path'] as String).toList();
          return GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 6, crossAxisSpacing: 6, children: [for (final (i, p) in photos.indexed) GestureDetector(onTap: () => _view(photos, i), child: StorageImage(p, radius: BorderRadius.circular(12)))]); }),
        const SizedBox(height: 20),
      ]]));
  }

  void _view(List<String> paths, int start) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _Viewer(paths, start)));
}

class _Viewer extends StatelessWidget {
  final List<String> paths; final int start;
  const _Viewer(this.paths, this.start);
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: PageView(controller: PageController(initialPage: start), children: [for (final p in paths) InteractiveViewer(child: Center(child: StorageImage(p, fit: BoxFit.contain)))]));
}

// ---------------------------------------------------------------- leave
class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});
  static const st = {'pending': (Brand.amber, Brand.amberTint), 'approved': (Brand.green, Brand.greenTint), 'rejected': (Brand.crimsonDeep, Brand.crimsonTint)};
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaves = ref.watch(leavesProvider);
    final cs = Theme.of(context).colorScheme;
    return AppPage(title: 'Leave', actions: [TextButton.icon(onPressed: () => _apply(context, ref), icon: const Icon(Icons.add_rounded, color: Colors.white), label: const Text('Apply', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)))],
      body: leaves.when(loading: _loading, error: (e, _) => _empty(context, '$e'), data: (list) => list.isEmpty ? _empty(context, 'No leave applied yet. Tap Apply to inform the class teacher.') :
        ListView(padding: const EdgeInsets.all(20), children: [for (final l in list) Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Pill(l['status'], fg: (st[l['status']] ?? (Brand.muted, Brand.surface2)).$1, bg: (st[l['status']] ?? (Brand.muted, Brand.surface2)).$2), const Spacer(),
            Text(l['from_date'] == l['to_date'] ? DateFormat('d MMM yyyy').format(DateTime.parse(l['from_date'])) : '${DateFormat('d MMM').format(DateTime.parse(l['from_date']))} – ${DateFormat('d MMM yyyy').format(DateTime.parse(l['to_date']))}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))]),
          const SizedBox(height: 8),
          Text(l['reason'], style: const TextStyle(fontWeight: FontWeight.w700)),
          if (l['note'] != null) Text(l['note'], style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          if (l['decided_at'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${l['status'] == 'approved' ? 'Approved' : 'Declined'} by ${l['decided_by_staff']?['display_name'] ?? 'class teacher'} · ${DateFormat('d MMM').format(DateTime.parse(l['decided_at']).toLocal())}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant))),
        ]))])));
  }

  void _apply(BuildContext context, WidgetRef ref) {
    DateTime from = DateTime.now(), to = DateTime.now(); String reason = 'Sick'; final note = TextEditingController(); bool busy = false;
    showModalBottomSheet(context: context, isScrollControlled: true, showDragHandle: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Apply for leave', style: Theme.of(ctx).textTheme.headlineSmall), const SizedBox(height: 14),
      Row(children: [for (final (i, l) in ['From', 'To'].indexed) Expanded(child: Padding(padding: EdgeInsets.only(right: i == 0 ? 8 : 0), child: OutlinedButton.icon(onPressed: () async {
        final d = await showDatePicker(context: ctx, initialDate: i == 0 ? from : to, firstDate: DateTime.now().subtract(const Duration(days: 7)), lastDate: DateTime.now().add(const Duration(days: 120)));
        if (d != null) set(() { if (i == 0) { from = d; if (to.isBefore(from)) to = from; } else { to = d.isBefore(from) ? from : d; } });
      }, icon: const Icon(Icons.event_rounded, size: 18), label: Text('$l ${DateFormat('d MMM').format(i == 0 ? from : to)}'))))]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [for (final r in ['Sick', 'Family function', 'Travel', 'Medical appointment', 'Other']) ChoiceChip(label: Text(r), selected: reason == r, onSelected: (_) => set(() => reason = r))]),
      const SizedBox(height: 12),
      TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Note for the class teacher (optional)')),
      const SizedBox(height: 16),
      PrimaryButton('Send to class teacher', busy: busy, onPressed: () async {
        set(() => busy = true);
        try { await applyLeave(ref.read(sessionProvider).value!.active!.id, from, to, reason, note.text.trim().isEmpty ? null : note.text.trim()); ref.invalidate(leavesProvider); if (ctx.mounted) Navigator.pop(ctx); }
        catch (e) { set(() => busy = false); if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e'))); }
      }),
    ]))));
  }
}

// ---------------------------------------------------------------- profile
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}
class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final p = ref.watch(profileProvider); final e = ref.watch(enrolmentProvider); final r = ref.watch(routeDetailProvider);
    final cs = Theme.of(context).colorScheme;
    final tabs = ['Student', 'Academic', if (r.value != null) 'Transport'];
    Widget row(String k, String? v) => v == null || v.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 130, child: Text(k, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))), Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700)))]));
    return AppPage(title: 'Profile',
      headerExtra: Row(children: [for (final (i, l) in tabs.indexed) Expanded(child: GestureDetector(onTap: () => setState(() => tab = i), child: Container(margin: const EdgeInsets.only(right: 8), height: 36, alignment: Alignment.center,
        decoration: BoxDecoration(color: tab == i ? Colors.white : Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)), child: Text(l, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: tab == i ? Brand.crimsonDeep : Colors.white)))))]),
      body: p.when(loading: _loading, error: (err, _) => _empty(context, '$err'), data: (m) {
        if (m == null) return _empty(context, 'Profile not available.');
        final sec = e.value?['section']; final phones = List<Map<String, dynamic>>.from(m['family_phone'] ?? []);
        return ListView(padding: const EdgeInsets.all(20), children: [
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(20)), child: Row(children: [
            m['photo_path'] != null ? StorageImage(m['photo_path'], width: 64, height: 64, radius: BorderRadius.circular(20)) : Avatar(m['full_name'].toString().split(' ').take(2).map((w) => w[0]).join(), size: 64),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m['full_name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)), Text('${sec?['grade']?['name'] ?? ''} ${shownSection(sec) ?? '(section to be announced)'} · ${m['admission_no']}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))])),
          ])),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(20)), child: Column(children: [
            if (tabs[tab] == 'Student') ...[
              row('Date of birth', m['dob'] == null ? null : DateFormat('d MMMM yyyy').format(DateTime.parse(m['dob']))), row('Gender', m['gender']), row('Blood group', m['blood_group']), row('House', m['house']),
              row('Father', m['father_name']), row('Mother', m['mother_name']), row('Guardian', m['guardian_name']),
              for (final ph in phones) row(ph['label'] ?? 'Phone', ph['phone']),
              row('Address', m['address']),
            ] else if (tabs[tab] == 'Academic') ...[
              row('Academic year', e.value?['academic_year']?['label']), row('Class', '${sec?['grade']?['name'] ?? ''} – ${shownSection(sec) ?? 'section to be announced'}'), row('Roll number', e.value?['roll_no']?.toString()),
              row('Class teacher', sec?['class_teacher']?['display_name']), row('Admission type', m['admission_type']), row('Division', sec?['grade']?['division']?.toString()),
            ] else ...[
              row('Route', r.value?['name']), row('Bus', r.value?['bus_reg_no']), row('Stop', r.value?['my_stop']?['name']),
              row('Morning pickup', r.value?['my_stop']?['morning_eta']?.toString().substring(0, 5)), row('Afternoon drop', r.value?['my_stop']?['afternoon_eta']?.toString().substring(0, 5)),
              row('Driver', r.value?['driver']?['display_name']), row('Conductor', r.value?['conductor']?['display_name']),
            ],
          ])),
          const SizedBox(height: 12),
          const NoteBox('To correct any detail, message the class teacher or write to the school office. Changes are made by the office only.'),
        ]);
      }));
  }
}

// ---------------------------------------------------------------- feedback
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});
  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}
class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  String cat = 'Suggestion'; bool anon = false, busy = false; final subj = TextEditingController(), body = TextEditingController();
  @override
  Widget build(BuildContext context) => AppPage(title: 'Feedback', body: ListView(padding: const EdgeInsets.all(20), children: [
    Wrap(spacing: 8, children: [for (final c in ['Suggestion', 'Appreciation', 'Concern', 'Transport', 'Fees', 'App']) ChoiceChip(label: Text(c), selected: cat == c, onSelected: (_) => setState(() => cat = c))]),
    const SizedBox(height: 14),
    TextField(controller: subj, decoration: const InputDecoration(labelText: 'Subject')), const SizedBox(height: 12),
    TextField(controller: body, maxLines: 5, decoration: const InputDecoration(labelText: 'Your message')), const SizedBox(height: 8),
    SwitchListTile(value: anon, onChanged: (v) => setState(() => anon = v), title: const Text('Send anonymously'), subtitle: const Text('The office sees the class, not the name'), contentPadding: EdgeInsets.zero),
    const SizedBox(height: 10),
    PrimaryButton('Send to the school office', busy: busy, onPressed: () async {
      if (subj.text.trim().isEmpty || body.text.trim().isEmpty) return;
      setState(() => busy = true);
      try {
        final s = ref.read(sessionProvider).value!.active!; final e = await ref.read(enrolmentProvider.future);
        await sendFeedback(s.id, e?['section']?['id'], cat, subj.text.trim(), body.text.trim(), anon);
        if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you — sent to the office.'))); Navigator.pop(context); }
      } catch (err) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err'))); }
      if (mounted) setState(() => busy = false);
    }),
  ]));
}

Future<void> callNumber(String? n) async { if (n != null && n.isNotEmpty) await launchUrl(Uri.parse('tel:$n')); }
