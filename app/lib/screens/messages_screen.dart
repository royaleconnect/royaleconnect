import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../auth/session.dart';
import '../core/data.dart';
import '../core/data2.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/royal_extras.dart' show GoldLoading;

/// Private 1:1 messages with the teachers who teach this student (+ coordinator / VP). Student side can only start
/// a chat with those contacts; nothing can be deleted; files are PDF or images.
class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convs = ref.watch(conversationsProvider);
    final contacts = ref.watch(contactsProvider);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(8, 4, 20, 16), child: Row(children: [
        IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
        const Text('Messages', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      ])),
      Expanded(child: RefreshIndicator(onRefresh: () async { ref.invalidate(conversationsProvider); ref.invalidate(contactsProvider); }, child: ListView(padding: const EdgeInsets.all(20), children: [
        if ((convs.value ?? []).isNotEmpty) ...[
          Eyebrow('Recent', color: cs.onSurfaceVariant), const SizedBox(height: 8),
          for (final c in convs.value!) _tile(context, cs, name: c['staff']?['display_name'] ?? '', sub: c['last_message_at'] == null ? 'No messages yet' : DateFormat('d MMM, h:mm a').format(DateTime.parse(c['last_message_at']).toLocal()),
              unread: (c['student_unread'] ?? 0) as int, onTap: () => context.push('/chat/${c['id']}', extra: c['staff']?['display_name'])),
          const SizedBox(height: 18),
        ],
        Eyebrow('Your teachers', color: cs.onSurfaceVariant), const SizedBox(height: 8),
        contacts.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: const GoldLoading()),
          error: (e, _) => Text('$e'),
          data: (list) => Column(children: [for (final k in list) _tile(context, cs, name: k.name, sub: k.subject ?? '', onTap: () async {
            final s = ref.read(sessionProvider).value!.active!;
            final id = await openConversation(s.id, k.staffId);
            if (context.mounted) context.push('/chat/$id', extra: k.name);
          })])),
        const SizedBox(height: 18),
        const NoteBox('Teachers are notified straight away, except between 12 am and 5 am — those wait until morning. Only you and the teacher can see this chat.'),
      ]))),
    ]));
  }

  Widget _tile(BuildContext context, ColorScheme cs, {required String name, required String sub, int unread = 0, required VoidCallback onTap}) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Material(
      color: cs.surface, borderRadius: BorderRadius.circular(16), child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), onTap: onTap,
        leading: Avatar(name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase(), size: 42),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: unread > 0 ? CircleAvatar(radius: 11, backgroundColor: Brand.crimson, child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))) : const Icon(Icons.chevron_right_rounded),
      )));
}

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId; final String? title;
  const ChatScreen({super.key, required this.conversationId, this.title});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final text = TextEditingController(); final scroll = ScrollController();
  bool sending = false;

  @override
  void initState() { super.initState(); markConversationRead(widget.conversationId).then((_) => ref.invalidate(unreadMessagesProvider)); }

  Future<void> _send({String? path, String? name, String? mime}) async {
    final body = text.text.trim();
    if (body.isEmpty && path == null) return;
    setState(() => sending = true);
    try {
      await sendMessage(widget.conversationId, body: body.isEmpty ? null : body, path: path, name: name, mime: mime);
      text.clear(); ref.invalidate(messagesProvider(widget.conversationId)); ref.invalidate(conversationsProvider);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e'))); }
    if (mounted) setState(() => sending = false);
  }

  Future<void> _attach({bool camera = false}) async {
    List<int>? bytes; String? name, mime;
    if (camera) {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80, maxWidth: 1600);
      if (x == null) return; bytes = await x.readAsBytes(); name = x.name; mime = 'image/jpeg';
    } else {
      final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], withData: true);
      if (r == null || r.files.isEmpty) return; final f = r.files.first; bytes = f.bytes; name = f.name; mime = f.extension == 'pdf' ? 'application/pdf' : 'image/${f.extension == 'jpg' ? 'jpeg' : f.extension}';
    }
    if (bytes == null) return;
    if (bytes.length > 10 * 1024 * 1024) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Files up to 10 MB only.'))); return; }
    final path = 'chat/${widget.conversationId}/${DateTime.now().millisecondsSinceEpoch}_$name';
    setState(() => sending = true);
    try {
      await db.storage.from('files').uploadBinary(path, Uint8List.fromList(bytes), fileOptions: FileOptions(contentType: mime));
      await _send(path: path, name: name, mime: mime);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'))); setState(() => sending = false); }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = ref.watch(messagesProvider(widget.conversationId));
    final cs = Theme.of(context).colorScheme;
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(8, 4, 20, 14), hairline: false, child: Row(children: [
        IconButton(onPressed: () => context.pop(), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
        Expanded(child: Text(widget.title ?? 'Chat', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
      ])),
      Expanded(child: msgs.when(
        loading: () => const GoldLoading(),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          WidgetsBinding.instance.addPostFrameCallback((_) { if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent); });
          return ListView.builder(controller: scroll, padding: const EdgeInsets.all(16), itemCount: list.length, itemBuilder: (_, i) {
            final m = list[i]; final mine = m['sender_kind'] == 'student';
            return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(
              constraints: const BoxConstraints(maxWidth: 300), margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(color: mine ? Brand.crimson : cs.surface, borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16), bottomLeft: Radius.circular(mine ? 16 : 4), bottomRight: Radius.circular(mine ? 4 : 16))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (m['attachment_path'] != null) InkWell(onTap: () => openStorageFile(m['attachment_path']), child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon((m['attachment_mime'] ?? '').toString().startsWith('image') ? Icons.image_rounded : Icons.picture_as_pdf_rounded, size: 18, color: mine ? Colors.white : Brand.crimsonDeep), const SizedBox(width: 6),
                  Flexible(child: Text(m['attachment_name'] ?? 'Attachment', style: TextStyle(color: mine ? Colors.white : cs.onSurface, fontWeight: FontWeight.w700, decoration: TextDecoration.underline))),
                ])),
                if (m['body'] != null) Align(alignment: Alignment.centerLeft, child: SelectableText(m['body'], style: TextStyle(color: mine ? Colors.white : cs.onSurface, height: 1.4))),
                const SizedBox(height: 3),
                Text('${DateFormat('h:mm a').format(DateTime.parse(m['created_at']).toLocal())}${mine ? (m['seen_at'] != null ? ' · Seen' : '') : ''}', style: TextStyle(fontSize: 10, color: mine ? Colors.white70 : cs.onSurfaceVariant)),
              ])));
          });
        })),
      Container(padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + MediaQuery.of(context).padding.bottom), decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outline))), child: Row(children: [
        IconButton(onPressed: sending ? null : () => _attach(), icon: const Icon(Icons.attach_file_rounded), tooltip: 'PDF or photo'),
        IconButton(onPressed: sending ? null : () => _attach(camera: true), icon: const Icon(Icons.photo_camera_outlined), tooltip: 'Camera'),
        Expanded(child: TextField(controller: text, minLines: 1, maxLines: 4, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Message…', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)))),
        const SizedBox(width: 6),
        IconButton.filled(onPressed: sending ? null : () => _send(), icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded), style: IconButton.styleFrom(backgroundColor: Brand.crimson)),
      ])),
    ]));
  }
}
