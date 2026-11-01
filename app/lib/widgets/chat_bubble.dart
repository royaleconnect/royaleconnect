import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../core/data.dart' show db, openStorageFile, viewOnlyMode;
import '../core/theme.dart';

/// One chat message, used by both the family and the staff chat.
/// Your own message (within 2 days): press and hold (or right-click on a laptop) for "Edit" and "Delete for everyone".
/// A deleted message shows "This message was deleted"; an edited one shows "edited".
class ChatBubble extends StatelessWidget {
  final Map<String, dynamic> m; final bool mine; final double maxWidth; final VoidCallback onChanged;
  final String Function(String iso) time;
  const ChatBubble({super.key, required this.m, required this.mine, required this.onChanged, required this.time, this.maxWidth = 300});

  bool get _deleted => m['deleted_at'] != null;
  bool get _canChange => mine && !_deleted && !viewOnlyMode &&
      DateTime.now().difference(DateTime.parse(m['created_at']).toLocal()).inHours < 48;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = mine ? Colors.white : cs.onSurface;
    final sub = mine ? Colors.white70 : cs.onSurfaceVariant;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth), margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        color: _deleted ? (mine ? Brand.crimson.withValues(alpha: .55) : cs.surfaceContainerHighest.withValues(alpha: .6)) : (mine ? Brand.crimson : cs.surfaceContainerHighest),
        borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4), bottomRight: Radius.circular(mine ? 4 : 16))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (_deleted)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.block_rounded, size: 15, color: sub), const SizedBox(width: 6),
            Text('This message was deleted', style: TextStyle(color: sub, fontStyle: FontStyle.italic)),
          ])
        else ...[
          if (m['attachment_path'] != null) InkWell(onTap: () => openStorageFile(m['attachment_path']), child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon((m['attachment_mime'] ?? '').toString().startsWith('image') ? Icons.image_rounded : Icons.picture_as_pdf_rounded, size: 18, color: mine ? Colors.white : Brand.crimsonDeep),
            const SizedBox(width: 6),
            Flexible(child: Text(m['attachment_name'] ?? 'Attachment', style: TextStyle(color: fg, fontWeight: FontWeight.w700, decoration: TextDecoration.underline))),
          ])),
          if (m['body'] != null) Align(alignment: Alignment.centerLeft, child: Text(m['body'], style: TextStyle(color: fg, height: 1.4))),
        ],
        const SizedBox(height: 3),
        Text([time(m['created_at']), if (m['edited_at'] != null && !_deleted) 'edited', if (mine && m['seen_at'] != null && !_deleted) 'Seen'].join(' · '),
            style: TextStyle(fontSize: 10, color: sub)),
      ]),
    );
    if (!_canChange) return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: bubble);
    return Align(alignment: Alignment.centerRight, child: GestureDetector(
      onLongPress: () => _menu(context), onSecondaryTap: () => _menu(context),
      child: Tooltip(message: 'Press and hold to edit or delete', waitDuration: const Duration(seconds: 1), child: bubble)));
  }

  Future<void> _menu(BuildContext context) async {
    HapticFeedback.selectionClick();
    final pick = await showModalBottomSheet<String>(context: context, showDragHandle: true, builder: (s) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (m['body'] != null) ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Edit'), onTap: () => Navigator.pop(s, 'edit')),
      ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Brand.crimson), title: const Text('Delete for everyone', style: TextStyle(color: Brand.crimson, fontWeight: FontWeight.w700)),
          subtitle: const Text('It disappears from both chats. Allowed for 2 days after sending.'), onTap: () => Navigator.pop(s, 'delete')),
      const SizedBox(height: 8),
    ])));
    if (pick == null || !context.mounted) return;
    try {
      if (pick == 'delete') {
        final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Delete for everyone?'),
            content: const Text('The message will be removed from both chats. This cannot be undone.'),
            actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: Brand.crimson), onPressed: () => Navigator.pop(d, true), child: const Text('Delete'))]));
        if (ok != true) return;
        await db.rpc('message_delete', params: {'p_id': m['id']});
      } else {
        final c = TextEditingController(text: m['body'] ?? '');
        final text = await showDialog<String>(context: context, builder: (d) => AlertDialog(title: const Text('Edit message'),
            content: TextField(controller: c, autofocus: true, minLines: 1, maxLines: 6, textCapitalization: TextCapitalization.sentences),
            actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save'))]));
        if (text == null || text.trim().isEmpty || text.trim() == m['body']) return;
        await db.rpc('message_edit', params: {'p_id': m['id'], 'p_body': text.trim()});
      }
      onChanged();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll(RegExp(r'^.*?message: |, code.*$'), ''))));
    }
  }
}

/// "h:mm a" for today, "d MMM, h:mm a" otherwise.
String chatTime(String iso) {
  final d = DateTime.parse(iso).toLocal(), n = DateTime.now();
  return DateFormat(d.year == n.year && d.month == n.month && d.day == n.day ? 'h:mm a' : 'd MMM, h:mm a').format(d);
}
