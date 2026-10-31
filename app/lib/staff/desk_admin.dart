import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../screens/desk_screen.dart';
import 'staff_screens_2.dart' show pickAndUpload;

/// Staff panel → Principal's Desk. Everyone sees the messages; IT and the Principal also write new ones,
/// change the welcome messages, and set her name and photo.
class StaffDeskScreen extends StatelessWidget {
  const StaffDeskScreen({super.key});
  @override
  Widget build(BuildContext context) => DeskListScreen(staff: true, editor: _openEditor, pickPhoto: _pickPhoto);
}

const _photoExt = ['jpg', 'jpeg', 'png', 'webp'];
Future<String?> _pickPhoto(BuildContext context) => pickAndUpload(context, 'photos/desk', ext: _photoExt, maxMb: 8);

Future<void> _openEditor(BuildContext context, WidgetRef ref, DeskMessage? existing) async {
  final saved = await Navigator.of(context, rootNavigator: true).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _DeskEditor(existing: existing)));
  if (saved == true) ref.invalidate(deskMessagesProvider);
}

class _DeskEditor extends ConsumerStatefulWidget {
  final DeskMessage? existing;
  const _DeskEditor({this.existing});
  @override
  ConsumerState<_DeskEditor> createState() => _DeskEditorState();
}

class _DeskEditorState extends ConsumerState<_DeskEditor> {
  late final title = TextEditingController(text: widget.existing?.title ?? '');
  late final body = TextEditingController(text: widget.existing?.body ?? '');
  late final link = TextEditingController(text: widget.existing?.linkUrl ?? '');
  late final linkLabel = TextEditingController(text: widget.existing?.linkLabel ?? '');
  late String audience = widget.existing?.audience ?? 'everyone';
  late String? picture = widget.existing?.picturePath;
  bool busy = false; String? error;
  bool get welcome => widget.existing?.isWelcome ?? false;

  Map<String, dynamic> _row() => {
        'title': title.text.trim(), 'body': body.text.trim(),
        if (!welcome) ...{'audience': audience, 'picture_path': picture, 'link_url': link.text.trim().isEmpty ? null : _url(link.text.trim()), 'link_label': linkLabel.text.trim().isEmpty ? null : linkLabel.text.trim()},
      };
  static String _url(String u) => u.startsWith('http') ? u : 'https://$u';

  DeskMessage _preview() => DeskMessage.fromRow({
        'id': widget.existing?.id ?? 'preview', 'kind': welcome ? 'welcome' : 'event', 'audience': audience,
        'created_at': DateTime.now().toUtc().toIso8601String(), ..._row(), 'title': title.text.trim().isEmpty ? 'Your title' : title.text.trim(),
      });

  Future<void> _save() async {
    if (title.text.trim().isEmpty || body.text.trim().isEmpty) { setState(() => error = 'Please write a title and the message.'); return; }
    setState(() { busy = true; error = null; });
    try {
      if (widget.existing == null) {
        await db.from('principal_message').insert({..._row(), 'kind': 'event', 'created_by': ref.read(sessionProvider).value?.staff?['id']});
      } else {
        await db.from('principal_message').update({..._row(), 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', widget.existing!.id);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() { busy = false; error = 'Could not save: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final th = DeskTheme.forTitle(title.text);
    final isNew = widget.existing == null;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'New message' : welcome ? 'Welcome message' : 'Change message')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: ListView(padding: const EdgeInsets.all(20), children: [
        if (isNew) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text('It opens full screen for everyone the next time they open the app, with a notification, and then stays in "From the Principal\'s Desk".', style: TextStyle(color: cs.onSurfaceVariant))),
        TextField(controller: title, onChanged: (_) => setState(() {}), textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. RoMUN 2026 — be a delegate!')),
        if (!welcome) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Design: ${th.label} — chosen from the title (Annual Day, Sports Day, Hackathon, MUN … get their own).', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
        const SizedBox(height: 16),
        TextField(controller: body, minLines: 8, maxLines: 20, textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true, hintText: 'Leave an empty line between paragraphs. "Dear …," and her signature are added automatically.')),
        if (!welcome) ...[
          const SizedBox(height: 18),
          Text('WHO SEES IT', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          SegmentedButton<String>(segments: const [ButtonSegment(value: 'everyone', label: Text('Everyone')), ButtonSegment(value: 'families', label: Text('Families')), ButtonSegment(value: 'staff', label: Text('Staff'))],
              selected: {audience}, showSelectedIcon: false, onSelectionChanged: (v) => setState(() => audience = v.first)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Text(picture == null ? 'Picture or poster (optional)' : 'Picture added ✓', style: const TextStyle(fontWeight: FontWeight.w700))),
            if (picture != null) TextButton(onPressed: () => setState(() => picture = null), child: const Text('Remove')),
            OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)), icon: const Icon(Icons.image_outlined, size: 18), label: Text(picture == null ? 'Add' : 'Change'),
                onPressed: () async { final p = await _pickPhoto(context); if (p != null) setState(() => picture = p); }),
          ]),
          const SizedBox(height: 14),
          TextField(controller: link, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Link (optional)', hintText: 'e.g. a registration form')),
          const SizedBox(height: 10),
          TextField(controller: linkLabel, decoration: const InputDecoration(labelText: 'Button text (optional)', hintText: 'Know more')),
        ],
        if (error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(error!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700))),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.play_circle_outline_rounded), label: const Text('Preview'),
              onPressed: () => Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => DeskShowScreen(message: _preview()))))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: busy ? null : _save, child: Text(busy ? 'Saving…' : isNew ? 'Send' : 'Save'))),
        ]),
      ]))),
    );
  }
}
