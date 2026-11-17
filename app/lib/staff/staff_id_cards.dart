import '../widgets/hub_tabs.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../auth/session.dart';
import '../core/brand_images.dart';
import '../core/config.dart';
import '../core/data.dart';
import '../core/data3.dart' show initialsOf;
import '../core/errors.dart';
import '../core/school_docs.dart' show PdfDocScreen;
import '../core/theme.dart';
import '../widgets/royal_extras.dart' show ShimmerPage;
import '../widgets/royal_motion.dart' show FadeRise;
import 'staff_shell.dart';

/// Staff ID cards: photo, name, designation and phone — print-ready on A4 at the real card size (54 × 85.6 mm, nine a sheet).

final staffCardsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async =>
    [for (final x in (await db.rpc('staff_id_rows')) as List? ?? const []) Map<String, dynamic>.from(x as Map)]);

Future<Uint8List?> _photo(String? path) async {
  if (path == null || path.isEmpty) return null;
  try {
    final url = path.startsWith('http') ? path : await db.storage.from('files').createSignedUrl(path, 3600);
    final res = await http.get(Uri.parse(url));
    return res.statusCode == 200 && res.bodyBytes.isNotEmpty ? res.bodyBytes : null;
  } catch (_) { return null; }
}

double _mm(double v) => v * PdfPageFormat.mm;

Future<Uint8List> buildStaffCardsPdf(List<Map<String, dynamic>> rows) async {
  pw.Font base, bold, serif;
  try {
    base = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    serif = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSerif-Bold.ttf'));
  } catch (_) { base = pw.Font.helvetica(); bold = pw.Font.helveticaBold(); serif = pw.Font.timesBold(); }
  final photos = <Uint8List?>[];
  for (var i = 0; i < rows.length; i += 6) { photos.addAll(await Future.wait([for (final r in rows.skip(i).take(6)) _photo(r['photo_path'] as String?)])); }
  final logo = pw.MemoryImage(logoClear);
  const crimson = PdfColor.fromInt(0xFF7E0A10), gold = PdfColor.fromInt(0xFFB8963E), ink = PdfColor.fromInt(0xFF1D1A1F), muted = PdfColor.fromInt(0xFF6B6470);
  pw.Widget card(Map<String, dynamic> r, Uint8List? ph) {
    pw.ImageProvider? img;
    if (ph != null) { try { img = pw.MemoryImage(ph); } catch (_) { img = null; } }
    return pw.Container(width: 300, height: 476, color: PdfColors.white, child: pw.Column(children: [
      pw.Container(height: 96, color: crimson, padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 8), child: pw.Row(children: [
        pw.Container(width: 54, height: 54, padding: const pw.EdgeInsets.all(4), decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(8)), child: pw.Image(logo, fit: pw.BoxFit.contain)),
        pw.SizedBox(width: 10),
        pw.Expanded(child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('ROYALE CONCORDE', style: pw.TextStyle(font: serif, fontSize: 17, color: PdfColors.white, letterSpacing: .6)),
          pw.Text('INTERNATIONAL SCHOOL', style: pw.TextStyle(font: serif, fontSize: 12.5, color: PdfColors.white, letterSpacing: .6)),
          pw.SizedBox(height: 3),
          pw.Text('Kalyan Nagar, Bangalore - 560043', style: pw.TextStyle(font: base, fontSize: 8.5, color: PdfColors.white)),
        ])),
      ])),
      pw.Container(height: 4, color: gold),
      pw.SizedBox(height: 22),
      pw.Container(width: 132, height: 158, decoration: pw.BoxDecoration(borderRadius: pw.BorderRadius.circular(10), border: pw.Border.all(color: gold, width: 2.5), color: const PdfColor.fromInt(0xFFF4EEE2)),
        child: pw.ClipRRect(horizontalRadius: 8, verticalRadius: 8, child: img != null ? pw.Image(img, fit: pw.BoxFit.cover, width: 127, height: 153)
            : pw.Center(child: pw.Text(initialsOf('${r['name']}'), style: pw.TextStyle(font: serif, fontSize: 40, color: crimson))))),
      pw.SizedBox(height: 16),
      pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 14), child: pw.FittedBox(fit: pw.BoxFit.scaleDown, child: pw.Text('${r['name']}'.toUpperCase(), style: pw.TextStyle(font: bold, fontSize: 18, color: crimson, letterSpacing: .4)))),
      pw.SizedBox(height: 6),
      pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 14), child: pw.FittedBox(fit: pw.BoxFit.scaleDown, child: pw.Text('${r['designation'] ?? 'Staff'}', style: pw.TextStyle(font: bold, fontSize: 14, color: ink)))),
      pw.SizedBox(height: 10),
      if ('${r['phone'] ?? ''}'.isNotEmpty) pw.Text('Contact No.: ${r['phone']}', style: pw.TextStyle(font: base, fontSize: 12.5, color: ink)),
      pw.Spacer(),
      pw.Container(height: 1, margin: const pw.EdgeInsets.symmetric(horizontal: 28), color: gold),
      pw.SizedBox(height: 8),
      pw.Text('STAFF', style: pw.TextStyle(font: bold, fontSize: 11, letterSpacing: 4, color: gold)),
      pw.SizedBox(height: 6),
      pw.Text('If found, please return to the school · ${AppConfig.officePhonesShort}', style: pw.TextStyle(font: base, fontSize: 7.5, color: muted)),
      pw.SizedBox(height: 12),
    ]));
  }
  const cw = 54.0, ch = 85.6, gap = 6.0;
  const page = PdfPageFormat(210 * PdfPageFormat.mm, 297 * PdfPageFormat.mm, marginAll: 0);
  final left = (210 - (3 * cw + 2 * gap)) / 2, top = (297 - (3 * ch + 2 * gap)) / 2;
  final doc = pw.Document(title: 'Staff ID cards', author: AppConfig.schoolName);
  for (var s = 0; s < rows.length; s += 9) {
    final batch = [for (var i = s; i < rows.length && i < s + 9; i++) i];
    doc.addPage(pw.Page(pageFormat: page, build: (_) => pw.SizedBox(width: page.width, height: page.height, child: pw.Stack(children: [
      for (final (n, i) in batch.indexed) pw.Positioned(left: _mm(left + (n % 3) * (cw + gap)), top: _mm(top + (n ~/ 3) * (ch + gap)),
        child: pw.Container(decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400, width: .3)),
          child: pw.SizedBox(width: _mm(cw), height: _mm(ch), child: pw.FittedBox(fit: pw.BoxFit.fill, child: pw.ClipRect(child: card(rows[i], photos[i])))))),
      pw.Positioned(left: 0, right: 0, bottom: _mm(4), child: pw.Center(child: pw.Text('Staff ID cards · print at actual size (100%) and cut along the thin lines', style: pw.TextStyle(font: base, fontSize: 7, color: PdfColors.grey600)))),
    ]))));
  }
  return doc.save();
}

class StaffIdCardsPage extends ConsumerStatefulWidget {
  const StaffIdCardsPage({super.key});
  @override
  ConsumerState<StaffIdCardsPage> createState() => _StaffIdCardsPageState();
}

class _StaffIdCardsPageState extends ConsumerState<StaffIdCardsPage> {
  String who = 'all'; bool noPhoto = false;

  Future<void> _edit(Map<String, dynamic> r) async {
    final c = TextEditingController(text: '${r['designation'] ?? ''}');
    String? path; var busy = false;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
      title: Text('${r['name']}'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: c, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Designation on the card', hintText: 'e.g. Mathematics Teacher')),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: busy ? null : () async {
          final f = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png'], withData: true);
          final b = f?.files.first.bytes;
          if (b == null) return;
          if (b.length > 3 * 1024 * 1024) { if (ctx.mounted) toast(ctx, 'Please choose a photo under 3 MB.'); return; }
          set(() => busy = true);
          try {
            final ext = (f!.files.first.extension ?? 'jpg').toLowerCase();
            final p = 'photos/staff/${r['id']}_${DateTime.now().millisecondsSinceEpoch}.$ext';
            await db.storage.from('files').uploadBinary(p, Uint8List.fromList(b), fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'));
            set(() { path = p; busy = false; });
          } catch (e) { set(() => busy = false); if (ctx.mounted) toast(ctx, friendlyError(e)); }
        }, icon: const Icon(Icons.photo_camera_rounded, size: 18), label: Text(busy ? 'Uploading…' : path != null ? 'Photo chosen ✓' : r['photo_path'] != null ? 'Replace the photo' : 'Add a photo')),
        const SizedBox(height: 8),
        Text('A passport-style photo works best. Staff photos are seen only by staff.', style: TextStyle(fontSize: 12.5, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: busy ? null : () => Navigator.pop(ctx, true), child: const Text('Save'))])));
    if (ok != true) return;
    try {
      await db.rpc('staff_card_set', params: {'p_staff': r['id'], 'p_designation': c.text.trim(), 'p_photo': path});
      ref.invalidate(staffCardsProvider);
      if (mounted) toast(context, 'Saved ✓');
    } catch (e) { if (mounted) toast(context, friendlyError(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(sessionProvider).value!;
    final can = (s.hasRole('office') || s.hasRole('it_admin') || s.hasRole('principal')) && !s.viewOnly;
    return StaffPage(title: 'Staff ID cards', hub: Hub.staffIds, subtitle: 'Photo, name, designation and phone, in the school’s colours. Print-ready at the real card size.',
      body: ref.watch(staffCardsProvider).when(loading: () => const ShimmerPage(), error: (e, _) => Text(friendlyError(e)), data: (all) {
        final teach = all.where((r) => r['teaching'] == true).length;
        final without = all.where((r) => r['photo_path'] == null).length;
        final rows = [for (final r in all) if ((who == 'all' || (who == 'teaching') == (r['teaching'] == true)) && (!noPhoto || r['photo_path'] == null)) r];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Panel(padding: const EdgeInsets.all(14), child: PickRow(children: [
            Expanded(flex: 3, child: PickField<String>(label: 'Who', value: who, items: [
              DropdownMenuItem(value: 'all', child: Text('All staff (${all.length})')), DropdownMenuItem(value: 'teaching', child: Text('Teaching ($teach)')),
              DropdownMenuItem(value: 'other', child: Text('Non-teaching (${all.length - teach})')),
            ], onChanged: (v) => setState(() => who = v ?? 'all'))),
            const SizedBox(width: 12),
            FilterChip(label: Text('$without without a photo'), selected: noPhoto, onSelected: without == 0 ? null : (v) => setState(() => noPhoto = v)),
            const SizedBox(width: 12),
            FilledButton.icon(onPressed: rows.isEmpty ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
                PdfDocScreen(title: 'Staff ID cards', fileName: 'RCIS-staff-ID-cards.pdf', make: () => buildStaffCardsPdf(rows)))),
                icon: const Icon(Icons.print_rounded, size: 18), label: Text('Print ${rows.length} ${rows.length == 1 ? 'card' : 'cards'}')),
          ])),
          if (rows.isEmpty) Panel(child: Text('Nobody to show.', style: TextStyle(color: cs.onSurfaceVariant)))
          else Wrap(spacing: 14, runSpacing: 14, children: [
            for (final (i, r) in rows.take(60).indexed) FadeRise(delayMs: 25 * (i % 12), dy: 10, child: InkWell(onTap: can ? () => _edit(r) : null, borderRadius: BorderRadius.circular(16),
              child: Container(width: 190, decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Brand.gold.withValues(alpha: .6))), clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  Container(width: double.infinity, color: Brand.crimsonDeep, padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                      child: const Text('ROYALE CONCORDE\nINTERNATIONAL SCHOOL', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10.5, letterSpacing: .8, height: 1.3))),
                  Container(height: 3, color: Brand.gold),
                  const SizedBox(height: 12),
                  r['photo_path'] != null ? Container(width: 76, height: 90, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Brand.gold, width: 2), color: Brand.gold.withValues(alpha: .12)),
                          alignment: Alignment.center, child: Icon(Icons.verified_user_rounded, color: context.tone(Brand.green)))
                      : Container(width: 76, height: 90, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: cs.outlineVariant, width: 2)), alignment: Alignment.center,
                          child: Text(initialsOf('${r['name']}'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: context.tone(Brand.crimsonDeep)))),
                  Padding(padding: const EdgeInsets.fromLTRB(10, 10, 10, 2), child: Text('${r['name']}', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('${r['designation'] ?? ''}', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
                  Padding(padding: const EdgeInsets.fromLTRB(10, 2, 10, 12), child: Text('${r['phone'] ?? 'No phone'}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
                  if (r['photo_path'] == null) Container(width: double.infinity, color: Brand.amberTint, padding: const EdgeInsets.symmetric(vertical: 5), child: Text('No photo yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: context.tone(Brand.amber)))),
                ])))),
          ]),
          const SizedBox(height: 10),
          Text('${rows.length > 60 ? 'Showing the first 60 here; Print makes all ${rows.length}. ' : ''}${can ? 'Tap a card to set the designation or add the photo. ' : ''}A card with a photo shows a green tick here and the photo on the print.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ]);
      }),
    );
  }
}
