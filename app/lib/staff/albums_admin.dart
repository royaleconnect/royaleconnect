import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../auth/session.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/data2.dart' show albumsProvider;
import '../core/errors.dart';
import '../core/theme.dart';
import '../screens/family_screens.dart' show StorageImage, TeamCard;
import '../widgets/common.dart' show Pill;
import '../widgets/royal_extras.dart' show ShimmerPage;
import 'staff_shell.dart';

/// School albums (office, IT, Principal): make an album for an event, add photos (up to 30 at a time), pick the cover,
/// remove a photo. Families see an album as soon as it has photos. The student team card is shown, not edited here (this year
/// the teams were put in once; editing them comes next year).
final staffAlbumsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  final data = await db.from('album').select('id,title,event_date,cover_path,team,created_at,album_photo(id,path,sort_order)').order('event_date', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

List<Map<String, dynamic>> _photos(Map<String, dynamic> al) =>
    List<Map<String, dynamic>>.from(al['album_photo'] ?? [])..sort((x, y) => (x['sort_order'] as int).compareTo(y['sort_order'] as int));

class StaffAlbumsScreen extends ConsumerStatefulWidget {
  final String? albumId;
  const StaffAlbumsScreen({super.key, this.albumId});
  @override
  ConsumerState<StaffAlbumsScreen> createState() => _StaffAlbumsScreenState();
}

class _StaffAlbumsScreenState extends ConsumerState<StaffAlbumsScreen> {
  bool busy = false; int done = 0, total = 0;

  void _refresh() { ref.invalidate(staffAlbumsProvider); ref.invalidate(albumsProvider); }

  Future<void> _newAlbum() async {
    final title = TextEditingController(); DateTime when = DateTime.now();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
      title: const Text('New album'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Event', hintText: 'e.g. Children’s Day')),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: () async {
          final d = await showDatePicker(context: ctx, initialDate: when, firstDate: DateTime(2015), lastDate: DateTime.now().add(const Duration(days: 30)));
          if (d != null) set(() => when = d);
        }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(DateFormat('d MMMM yyyy').format(when))),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Brand.crimson), child: const Text('Make album'))])));
    if (ok != true || title.text.trim().isEmpty || !mounted) return;
    try {
      final me = ref.read(sessionProvider).value?.staff?['id'];
      final r = await db.from('album').insert({'title': title.text.trim(), 'event_date': DateFormat('yyyy-MM-dd').format(when), 'audience_all': true, 'posted_by': me}).select('id').single();
      _refresh();
      if (mounted) context.go('/staff/albums?id=${r['id']}');
    } catch (e) { if (mounted) toast(context, friendlyError(e)); }
  }

  Future<void> _addPhotos(Map<String, dynamic> al) async {
    final xs = await ImagePicker().pickMultiImage(imageQuality: 82, maxWidth: 1800);
    if (xs.isEmpty || !mounted) return;
    final take = xs.take(30).toList();
    var sort = _photos(al).fold<int>(0, (m, p) => (p['sort_order'] as int) > m ? p['sort_order'] as int : m);
    setState(() { busy = true; done = 0; total = take.length; });
    var failed = 0;
    for (final x in take) {
      try {
        final b = await x.readAsBytes();
        final safe = x.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final path = 'albums/${al['id']}/${DateTime.now().millisecondsSinceEpoch}_$safe';
        await db.storage.from('files').uploadBinary(path, b, fileOptions: const FileOptions(contentType: 'image/jpeg'));
        sort++;
        await db.from('album_photo').insert({'album_id': al['id'], 'path': path, 'sort_order': sort});
      } catch (_) { failed++; }
      if (mounted) setState(() => done++);
    }
    _refresh();
    if (mounted) {
      setState(() => busy = false);
      toast(context, failed == 0 ? '${take.length} photo${take.length == 1 ? '' : 's'} added ✓${xs.length > 30 ? ' · add the rest in the next round' : ''}' : '${take.length - failed} added, $failed could not be uploaded — try those again.');
    }
  }

  Future<void> _photoMenu(Map<String, dynamic> al, Map<String, dynamic> p) async {
    final pick = await showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.star_rounded, color: Brand.gold), title: const Text('Make this the cover'), onTap: () => Navigator.pop(ctx, 'cover')),
      ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Brand.crimson), title: const Text('Remove this photo'), onTap: () => Navigator.pop(ctx, 'remove')),
    ])));
    try {
      if (pick == 'cover') { await db.from('album').update({'cover_path': p['path']}).eq('id', al['id']); if (mounted) toast(context, 'Cover changed ✓'); }
      if (pick == 'remove') {
        await db.from('album_photo').delete().eq('id', p['id']);
        if (al['cover_path'] == p['path']) await db.from('album').update({'cover_path': null}).eq('id', al['id']);
        if (mounted) toast(context, 'Photo removed');
      }
      if (pick != null) _refresh();
    } catch (e) { if (mounted) toast(context, friendlyError(e)); }
  }

  Future<void> _edit(Map<String, dynamic> al) async {
    final title = TextEditingController(text: al['title']); DateTime when = DateTime.tryParse('${al['event_date']}') ?? DateTime.now();
    final r = await showDialog<String>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
      title: const Text('Album'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Event')),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: () async {
          final d = await showDatePicker(context: ctx, initialDate: when, firstDate: DateTime(2015), lastDate: DateTime.now().add(const Duration(days: 30)));
          if (d != null) set(() => when = d);
        }, icon: const Icon(Icons.event_rounded, size: 18), label: Text(DateFormat('d MMMM yyyy').format(when))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Delete album', style: TextStyle(color: Brand.crimson))),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), style: FilledButton.styleFrom(backgroundColor: Brand.crimson), child: const Text('Save'))])));
    if (r == null || !mounted) return;
    try {
      if (r == 'save' && title.text.trim().isNotEmpty) await db.from('album').update({'title': title.text.trim(), 'event_date': DateFormat('yyyy-MM-dd').format(when)}).eq('id', al['id']);
      if (r == 'delete') {
        final sure = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text('Delete “${al['title']}”?'),
          content: const Text('Families will no longer see this album. It goes to the Bin, where IT can bring it back.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')), FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Brand.crimson), child: const Text('Delete'))]));
        if (sure != true) return;
        await db.from('album').delete().eq('id', al['id']);
        if (mounted) context.go('/staff/albums');
      }
      _refresh();
    } catch (e) { if (mounted) toast(context, friendlyError(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = ref.watch(staffAlbumsProvider);
    final id = widget.albumId;
    return list.when(loading: () => const StaffPage(title: 'School albums', body: ShimmerPage()),
      error: (e, _) => StaffPage(title: 'School albums', body: Text(friendlyError(e))),
      data: (rows) {
        final al = id == null ? null : rows.where((r) => r['id'] == id).firstOrNull;
        if (al == null) {
          return StaffPage(title: 'School albums', subtitle: 'Photos of school events for every family. Make an album, then add photos — families see it straight away.',
            actions: [FilledButton.icon(onPressed: _newAlbum, style: FilledButton.styleFrom(backgroundColor: Brand.crimson), icon: const Icon(Icons.add_rounded), label: const Text('New album'))],
            body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (rows.isEmpty) Panel(child: Text('No albums yet. Tap New album.', style: TextStyle(color: cs.onSurfaceVariant))),
              for (final r in rows) Panel(padding: const EdgeInsets.all(12), child: InkWell(onTap: () => context.go('/staff/albums?id=${r['id']}'), child: Row(children: [
                () {
                  final ph = _photos(r); final cover = (r['cover_path'] as String?) ?? (ph.isNotEmpty ? ph.first['path'] as String : null);
                  return cover == null
                      ? Container(width: 64, height: 64, decoration: BoxDecoration(color: Brand.crimsonTint, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.photo_library_rounded, color: Brand.crimson))
                      : StorageImage(cover, width: 64, height: 64, radius: BorderRadius.circular(12));
                }(),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r['title'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  Text('${r['event_date'] != null ? DateFormat('d MMM yyyy').format(DateTime.parse(r['event_date'])) : ''} · ${_photos(r).length} photos', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                ])),
                if (r['team'] != null) const Pill('Student team', fg: Color(0xFF6B4A08), bg: Color(0xFFF7E9C6)),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded),
              ]))),
            ]));
        }
        final ph = _photos(al);
        return StaffPage(title: al['title'], subtitle: '${al['event_date'] != null ? DateFormat('d MMMM yyyy').format(DateTime.parse(al['event_date'])) : ''} · ${ph.length} photos · tap a photo to make it the cover or remove it',
          actions: [
            TextButton.icon(onPressed: () => context.go('/staff/albums'), icon: const Icon(Icons.arrow_back_rounded, size: 18), label: const Text('All albums')),
            TextButton.icon(onPressed: () => _edit(al), icon: const Icon(Icons.edit_rounded, size: 18), label: const Text('Edit')),
            FilledButton.icon(onPressed: busy ? null : () => _addPhotos(al), style: FilledButton.styleFrom(backgroundColor: Brand.crimson),
                icon: const Icon(Icons.add_photo_alternate_rounded), label: Text(busy ? 'Adding $done of $total…' : 'Add photos')),
          ],
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (al['team'] is Map) TeamCard(Map<String, dynamic>.from(al['team'])),
            if (ph.isEmpty) Panel(child: Text('No photos yet. Tap Add photos and choose up to 30 at a time.', style: TextStyle(color: cs.onSurfaceVariant)))
            else LayoutBuilder(builder: (_, c) {
              final cols = c.maxWidth >= 900 ? 6 : c.maxWidth >= 600 ? 4 : 3;
              final cell = (c.maxWidth - 8 * (cols - 1)) / cols;
              return Wrap(spacing: 8, runSpacing: 8, children: [for (final p in ph) GestureDetector(onTap: () => _photoMenu(al, p), child: Stack(children: [
                StorageImage(p['path'], width: cell, height: cell, radius: BorderRadius.circular(12)),
                if (al['cover_path'] == p['path']) const Positioned(left: 6, top: 6, child: Pill('Cover', fg: Colors.white, bg: Brand.gold)),
              ]))]);
            }),
          ]));
      });
  }
}
