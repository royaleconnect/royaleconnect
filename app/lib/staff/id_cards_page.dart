import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import '../widgets/royal_extras.dart' show ShimmerPage;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/widgets.dart' as pw;
import '../core/brand_images.dart';
import '../core/cache.dart';
import '../core/data.dart';
import '../core/school_docs.dart' show PdfDocScreen;
import '../core/sign_font.dart';
import '../core/theme.dart';
import '../core/xlsx_writer.dart';
import '../screens/idcard_screen.dart' show IdCard, IdCardData, IdCardFace;
import 'id_cards_pdf.dart';
import 'school_setup.dart' show setupSectionsProvider;
import 'staff_shell.dart';
import 'students_page.dart' show openStudentRecord;

/// ID cards (office): pick a class (or all), see every card, fix what is missing, then print on A4
/// at the real card size — or download the Excel sheet and photos for the card printer.
/// One fixed rule: only cards that have everything are printed.

class IdCardSet {
  final String year, principal;
  final List<Map<String, dynamic>> rows;
  const IdCardSet(this.year, this.principal, this.rows);
  List<Map<String, dynamic>> get ready => rows.where(idCardReady).toList();
  List<Map<String, dynamic>> get notReady => rows.where((r) => !idCardReady(r)).toList();
  bool get allReady => rows.isNotEmpty && notReady.isEmpty;
}

bool idCardReady(Map<String, dynamic> r) => (r['missing'] as List? ?? const []).isEmpty;

/// The cards of one section (null = the whole school).
final idCardRowsProvider = FutureProvider.autoDispose.family<IdCardSet, String?>((ref, sectionId) async {
  ref.cacheFor();
  final d = Map<String, dynamic>.from((await db.rpc('id_card_rows', params: {'p_section': sectionId})) as Map);
  return IdCardSet((d['year'] ?? '').toString(), (d['principal'] ?? 'Principal').toString(),
      [for (final x in (d['rows'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)]);
});

/// True when every active student's ID card is ready — the "ID cards" menu item glows gold.
/// Never fails (false for anyone outside the office, or when offline).
final idCardsAllReadyProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.cacheFor(const Duration(minutes: 10));
  try {
    return (await db.rpc('id_cards_all_ready')) == true;
  } catch (_) {
    return false;
  }
});

String idCardYearText(String y) {
  final m = RegExp(r'(\d{4})\D+(\d{2,4})').firstMatch(y);
  if (m == null) return y;
  final b = m.group(2)!;
  return '${m.group(1)} - ${b.length == 2 ? '20$b' : b}';
}

String _principalShort(String p) => p.replaceFirst(RegExp(r'^(Mrs?|Ms|Dr)\.?\s+'), '');
String _str(Object? v) => (v ?? '').toString().trim();
String? _opt(Object? v) => _str(v).isEmpty ? null : _str(v);
String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

IdCardData _cardOf(Map<String, dynamic> r, IdCardSet set) => IdCardData(
  name: _str(r['name']), admNo: _str(r['admission_no']), grade: _str(r['grade']), year: idCardYearText(set.year), principal: _principalShort(set.principal),
  blood: _opt(r['blood_group']), father: _opt(r['father_name']), fatherPhone: _opt(r['father_phone']), mother: _opt(r['mother_name']), motherPhone: _opt(r['mother_phone']),
  photoPath: _opt(r['photo_path']), address: _opt(r['address']), route: r['bus'] == true ? _str(r['route_no']) : null,
);

// ---------------------------------------------------------------- photos, fonts, files
/// Photo bytes from the private 'files' bucket (null when there is no photo or it cannot be fetched).
Future<Uint8List?> _photoBytes(String? path) async {
  if (path == null || path.isEmpty) return null;
  try {
    final url = path.startsWith('http') ? path : await db.storage.from('files').createSignedUrl(path, 3600);
    final res = await http.get(Uri.parse(url));
    return res.statusCode == 200 && res.bodyBytes.isNotEmpty ? res.bodyBytes : null;
  } catch (_) {
    return null;
  }
}

/// Fetches photos a few at a time (fast, but gentle on a phone connection).
Future<List<Uint8List?>> _allPhotos(List<Map<String, dynamic>> rows, {void Function(int done)? progress}) async {
  final out = List<Uint8List?>.filled(rows.length, null);
  var done = 0;
  for (var i = 0; i < rows.length; i += 6) {
    final part = rows.sublist(i, (i + 6).clamp(0, rows.length));
    final got = await Future.wait(part.map((r) => _photoBytes(_opt(r['photo_path']))));
    for (var k = 0; k < got.length; k++) { out[i + k] = got[k]; }
    done += got.length;
    progress?.call(done);
  }
  return out;
}

/// Same fonts as the receipts and report cards (Noto when bundled, the built-in PDF fonts otherwise).
Future<IdPdfFonts> _fonts() async {
  try {
    return IdPdfFonts(
      pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf')),
      pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf')),
      pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSerif-Bold.ttf')),
      signatureFont(),
    );
  } catch (_) {
    return IdPdfFonts.builtIn();
  }
}

Future<Uint8List> _makePdf(List<Map<String, dynamic>> rows, IdCardSet set) async {
  final photos = await _allPhotos(rows);
  final cards = [
    for (var i = 0; i < rows.length; i++) () {
      final c = _cardOf(rows[i], set);
      return IdPdfCard(name: c.name, admNo: c.admNo, grade: c.grade, year: c.year, principal: c.principal, blood: c.blood,
          father: c.father, fatherPhone: c.fatherPhone, mother: c.mother, motherPhone: c.motherPhone, address: c.address, route: c.route, photo: photos[i]);
    }(),
  ];
  return buildIdCardsPdf(cards, fonts: await _fonts(), logo: logoClear, title: 'ID cards');
}

String _photoExt(Uint8List b, String? path) {
  if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'png';
  if (b.length > 2 && b[0] == 0xFF && b[1] == 0xD8) return 'jpg';
  final m = RegExp(r'\.([A-Za-z0-9]{3,4})$').firstMatch(path ?? '');
  return (m?.group(1) ?? 'jpg').toLowerCase();
}

/// One student's ID card as a print-ready PDF (the same design as the class sheets). Tells what is missing instead.
Future<void> openStudentIdCard(BuildContext context, String studentId, {String? sectionId}) async {
  try {
    final d = Map<String, dynamic>.from((await db.rpc('id_card_rows', params: {'p_section': sectionId})) as Map);
    final set = IdCardSet((d['year'] ?? '').toString(), (d['principal'] ?? 'Principal').toString(),
        [for (final x in (d['rows'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)]);
    final row = set.rows.where((r) => r['id'] == studentId).firstOrNull;
    if (!context.mounted) return;
    if (row == null) { toast(context, 'An ID card needs a class first.'); return; }
    if (!idCardReady(row)) { toast(context, 'Fill in first: ${List<String>.from(row['missing'] ?? const []).join(', ')}.'); return; }
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PdfDocScreen(
      title: 'ID card · ${row['name']}', fileName: 'ID-card-${_safe('${row['name']}')}.pdf', make: () => _makePdf([row], set))));
  } catch (e) {
    if (context.mounted) toast(context, 'Could not make the card. Please try again.');
  }
}

// ---------------------------------------------------------------- the page
class StaffIdCardsScreen extends ConsumerStatefulWidget {
  const StaffIdCardsScreen({super.key});
  @override
  ConsumerState<StaffIdCardsScreen> createState() => _StaffIdCardsScreenState();
}

class _StaffIdCardsScreenState extends ConsumerState<StaffIdCardsScreen> {
  String? sectionId;          // null = all classes
  bool busy = false;
  static const _gridCap = 48;  // "All classes" shows the first cards only; a class shows all of its cards

  String _scopeName(List<Map<String, dynamic>> sections) {
    final s = sections.where((x) => x['id'] == sectionId).firstOrNull;
    return s == null ? 'All classes' : 'Grade ${s['grade']?['code'] ?? ''} ${s['name'] ?? ''}'.trim();
  }

  void _refresh() { ref.invalidate(idCardRowsProvider(sectionId)); ref.invalidate(idCardsAllReadyProvider); }

  void _print(IdCardSet set, String scope) {
    final rows = set.ready;
    if (rows.isEmpty) { toast(context, 'No card is ready yet. Fill in the missing details first.'); return; }
    final left = set.rows.length - rows.length;
    if (left > 0) toast(context, '$left card${left == 1 ? ' is' : 's are'} left out until the missing details are filled in.');
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => PdfDocScreen(
      title: 'ID cards · $scope', fileName: 'RCIS-ID-cards-${_safe(scope)}.pdf', make: () => _makePdf(rows, set))));
  }

  Future<void> _pack(IdCardSet set, String scope) async {
    if (set.rows.isEmpty) return;
    setState(() => busy = true);
    final progress = ValueNotifier<int>(0);
    var dialogOpen = true;
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
      content: ValueListenableBuilder<int>(valueListenable: progress, builder: (_, n, __) => Row(children: [
        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)), const SizedBox(width: 16),
        Expanded(child: Text('Getting photos… $n of ${set.rows.length}')),
      ]))));
    try {
      final photos = await _allPhotos(set.rows, progress: (n) => progress.value = n);
      final zip = Archive();
      final names = <String?>[];
      for (var i = 0; i < set.rows.length; i++) {
        final b = photos[i];
        if (b == null) { names.add(null); continue; }
        final name = '${_safe(_str(set.rows[i]['admission_no']))}.${_photoExt(b, _opt(set.rows[i]['photo_path']))}';
        names.add(name);
        zip.addFile(ArchiveFile(name, b.length, b));
      }
      final xlsx = buildXlsx('ID cards', const ['Admission No', 'Name', 'Grade', 'Section', 'Blood group', 'Father', 'Father phone', 'Mother', 'Mother phone',
          'Address', 'Bus', 'Route No', 'Photo file', 'Card colour', 'Still missing'], [
        for (var i = 0; i < set.rows.length; i++) () {
          final r = set.rows[i];
          return <Object?>[_str(r['admission_no']), _str(r['name']), _str(r['grade']), _str(r['section']), _str(r['blood_group']),
            _str(r['father_name']), _str(r['father_phone']), _str(r['mother_name']), _str(r['mother_phone']), _str(r['address']),
            r['bus'] == true ? 'Yes' : 'No', r['bus'] == true ? _str(r['route_no']) : '', names[i] ?? '', r['bus'] == true ? 'Yellow' : 'Purple',
            (r['missing'] as List? ?? const []).join(', ')];
        }(),
      ], widths: const [16, 28, 8, 9, 11, 24, 14, 24, 14, 48, 6, 9, 20, 11, 28]);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      dialogOpen = false;
      final tag = '${_safe(scope)}-${idCardYearText(set.year).replaceAll(' ', '')}';
      await saveBytes(xlsx, 'RCIS-ID-cards-$tag.xlsx');
      final photoCount = names.whereType<String>().length;
      if (photoCount > 0) {
        final dynamic out = ZipEncoder().encode(zip);
        await saveBytes(Uint8List.fromList(List<int>.from(out as List)), 'RCIS-ID-photos-$tag.zip', mime: 'application/zip');
      }
      if (mounted) toast(context, photoCount > 0 ? 'Excel sheet and $photoCount photos saved. Photos are named by admission number.' : 'Excel sheet saved. No photos yet.');
    } catch (_) {
      if (mounted) {
        if (dialogOpen) Navigator.of(context, rootNavigator: true).pop();
        toast(context, 'Could not make the files. Please try again.');
      }
    } finally {
      progress.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  void _preview(Map<String, dynamic> r, IdCardSet set) => showDialog<void>(context: context, builder: (ctx) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    child: Padding(padding: const EdgeInsets.all(18), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_str(r['name']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 12),
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260), child: IdCard(data: _cardOf(r, set))),
      const SizedBox(height: 10),
      Text('Tap the card to turn it over.', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant, fontSize: 12.5)),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(onPressed: () { Navigator.pop(ctx); openStudentRecord(context, r['id']).then((_) => _refresh()); }, child: const Text('Open student')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ]),
    ]))));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sections = ref.watch(setupSectionsProvider).value ?? const <Map<String, dynamic>>[];
    final scope = _scopeName(sections);
    final async = ref.watch(idCardRowsProvider(sectionId));
    final set = async.value;

    final picker = DropdownButtonHideUnderline(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outline, width: 1.5)),
      child: DropdownButton<String?>(value: sections.any((s) => s['id'] == sectionId) ? sectionId : null, borderRadius: BorderRadius.circular(12),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('All classes', style: TextStyle(fontWeight: FontWeight.w700))),
          for (final s in sections) DropdownMenuItem<String?>(value: s['id'] as String, child: Text('Grade ${s['grade']?['code'] ?? ''} ${s['name'] ?? ''}')),
        ],
        onChanged: (v) => setState(() => sectionId = v)),
    ));

    return StaffPage(
      title: 'ID cards',
      subtitle: 'Yellow cards for bus students, purple for the others. Only cards with every detail are printed.',
      actions: [
        if (set != null && set.rows.isNotEmpty) OutlinedButton.icon(onPressed: busy ? null : () => _pack(set, scope), icon: const Icon(Icons.folder_zip_rounded, size: 18), label: const Text('Excel / photos pack')),
        if (set != null && set.rows.isNotEmpty) FilledButton.icon(onPressed: busy ? null : () => _print(set, scope), icon: const Icon(Icons.print_rounded, size: 18), label: const Text('Print')),
      ],
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          picker,
          if (set != null) Text('${set.ready.length} of ${set.rows.length} cards ready', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
        ]),
        const SizedBox(height: 14),
        if (async.isLoading && set == null) const ShimmerPage()
        else if (async.hasError && set == null) Panel(child: Text('Could not load the ID cards. Please check the internet and try again.', style: TextStyle(color: cs.onSurfaceVariant)))
        else if (set != null && set.rows.isEmpty) Panel(child: Text('No students in $scope yet.', style: TextStyle(color: cs.onSurfaceVariant)))
        else if (set != null) ...[
          if (set.allReady) _AllReadyBanner(scope: scope, count: set.rows.length),
          if (set.notReady.isNotEmpty) Panel(
            title: 'Not ready (${set.notReady.length})',
            child: Column(children: [
              for (final r in set.notReady.take(sectionId == null ? 60 : 1000)) ListTile(
                dense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const CircleAvatar(radius: 14, backgroundColor: Brand.amberTint, child: Icon(Icons.priority_high_rounded, size: 16, color: Brand.amber)),
                title: Text(_str(r['name']), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('Grade ${_str(r['grade'])} ${_str(r['section'])} · ${_str(r['admission_no'])}  —  Missing: ${(r['missing'] as List).join(', ')}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => openStudentRecord(context, r['id']).then((_) => _refresh()),
              ),
              if (sectionId == null && set.notReady.length > 60)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text('Showing the first 60. Pick a class to see the rest.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
            ]),
          ),
          Panel(
            title: sectionId == null && set.rows.length > _gridCap ? 'Cards (first $_gridCap — pick a class to see all)' : 'Cards',
            child: LayoutBuilder(builder: (_, c) {
              final cols = (c.maxWidth / 132).floor().clamp(2, 8);
              final shown = sectionId == null ? set.rows.take(_gridCap).toList() : set.rows;
              return GridView.builder(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: shown.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 12, mainAxisSpacing: 14, childAspectRatio: 300 / 476 * .86),
                itemBuilder: (_, i) => _MiniCard(row: shown[i], data: _cardOf(shown[i], set), onTap: () => _preview(shown[i], set)),
              );
            }),
          ),
        ],
      ]),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final Map<String, dynamic> row; final IdCardData data; final VoidCallback onTap;
  const _MiniCard({required this.row, required this.data, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final ok = idCardReady(row);
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: Stack(children: [
        Positioned.fill(child: DecoratedBox(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 3))]),
          child: IdCardFace(data))),
        Positioned(top: 4, right: 4, child: Tooltip(message: ok ? 'Ready' : 'Missing: ${(row['missing'] as List).join(', ')}',
          child: Container(width: 22, height: 22, decoration: BoxDecoration(shape: BoxShape.circle, color: ok ? Brand.green : Brand.amber, border: Border.all(color: Colors.white, width: 2)),
            child: Icon(ok ? Icons.check_rounded : Icons.priority_high_rounded, size: 13, color: Colors.white)))),
      ])),
      const SizedBox(height: 4),
      Text(data.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
    ]));
  }
}

/// Soft gold glow when every card in the chosen class (or the whole school) is ready.
class _AllReadyBanner extends StatelessWidget {
  final String scope; final int count;
  const _AllReadyBanner({required this.scope, required this.count});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(colors: dark ? [const Color(0xFF3A2E14), const Color(0xFF2A2210)] : [const Color(0xFFFFF8E6), const Color(0xFFFBEFD0)]),
        border: Border.all(color: Brand.gold.withValues(alpha: .7), width: 1.2),
        boxShadow: [BoxShadow(color: Brand.gold.withValues(alpha: .35), blurRadius: 22, spreadRadius: 1)],
      ),
      child: Row(children: [
        const Icon(Icons.verified_rounded, color: Brand.gold, size: 26),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('All ID cards ready ✓', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: dark ? Brand.gold2 : const Color(0xFF7A5A12))),
          Text('$scope · $count card${count == 1 ? '' : 's'} with photo, blood group, phone and address.', style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ])),
      ]),
    );
  }
}
