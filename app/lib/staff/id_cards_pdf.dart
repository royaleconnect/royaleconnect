import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Print-ready ID cards on A4: real card size (CR80, 54 × 85.6 mm), 9 cards a sheet (3 × 3) with crop marks.
/// Fronts on one page, backs on the next page with the columns swapped left ↔ right,
/// so printing on both sides ("flip on long edge") puts every back behind its own front.
/// The drawing follows the card on screen (screens/idcard_screen.dart): it is laid out on the same 300 × 476 grid and scaled down.
/// This file uses only the pdf package (no Flutter), so it can be checked on its own.

class IdPdfCard {
  final String name, admNo, grade, year, principal;
  final String? blood, father, fatherPhone, mother, motherPhone, address, route;
  final Uint8List? photo;
  const IdPdfCard({required this.name, required this.admNo, required this.grade, required this.year, required this.principal,
    this.blood, this.father, this.fatherPhone, this.mother, this.motherPhone, this.address, this.route, this.photo});
  bool get bus => route != null;
}

class IdPdfFonts {
  final pw.Font base, bold, serif, script;
  const IdPdfFonts(this.base, this.bold, this.serif, this.script);
  factory IdPdfFonts.builtIn() => IdPdfFonts(pw.Font.helvetica(), pw.Font.helveticaBold(), pw.Font.timesBold(), pw.Font.timesBoldItalic());
}

// ---------------------------------------------------------------- sheet layout (millimetres)
const _cardW = 54.0, _cardH = 85.6, _gap = 6.0, _cols = 3, _rows = 3;
const idCardsPerSheet = _cols * _rows;
double _mm(double v) => v * PdfPageFormat.mm;

Future<Uint8List> buildIdCardsPdf(List<IdPdfCard> cards, {required IdPdfFonts fonts, required Uint8List logo, String title = 'ID cards'}) async {
  final doc = pw.Document(title: title, author: 'Royale Concorde International School');
  final logoImg = pw.MemoryImage(logo);
  const page = PdfPageFormat(210 * PdfPageFormat.mm, 297 * PdfPageFormat.mm, marginAll: 0);
  final left = (210 - (_cols * _cardW + (_cols - 1) * _gap)) / 2;
  final top = (297 - (_rows * _cardH + (_rows - 1) * _gap)) / 2;
  final sheets = (cards.length / idCardsPerSheet).ceil();

  for (var s = 0; s < sheets; s++) {
    final batch = cards.skip(s * idCardsPerSheet).take(idCardsPerSheet).toList();
    for (final back in [false, true]) {
      // slot (column, row) of each card on this page; backs swap columns so duplex lines up
      final slots = [for (var i = 0; i < batch.length; i++) (back ? _cols - 1 - i % _cols : i % _cols, i ~/ _cols)];
      doc.addPage(pw.Page(pageFormat: page, build: (_) => pw.SizedBox(width: page.width, height: page.height, child: pw.Stack(children: [
        pw.Positioned.fill(child: pw.CustomPaint(painter: (g, size) => _cropMarks(g, size, slots, left, top))),
        for (var i = 0; i < batch.length; i++)
          pw.Positioned(left: _mm(left + slots[i].$1 * (_cardW + _gap)), top: _mm(top + slots[i].$2 * (_cardH + _gap)),
            child: pw.SizedBox(width: _mm(_cardW), height: _mm(_cardH),
              child: pw.FittedBox(fit: pw.BoxFit.fill, child: pw.SizedBox(width: 300, height: 476,
                child: pw.ClipRect(child: back ? _back(batch[i], fonts, logoImg) : _front(batch[i], fonts, logoImg)))))),
        pw.Positioned(left: 0, right: 0, bottom: _mm(4), child: pw.Center(child: pw.Text(
          '${back ? 'Backs' : 'Fronts'} - sheet ${s + 1} of $sheets  ·  Print both sides, flip on long edge, actual size (100%)',
          style: pw.TextStyle(font: fonts.base, fontSize: 7, color: PdfColors.grey600)))),
      ]))));
    }
  }
  return doc.save();
}

/// Thin black marks just outside each card corner, for cutting.
void _cropMarks(PdfGraphics g, PdfPoint size, List<(int, int)> slots, double left, double top) {
  const off = .8, len = 2.0;
  g..setStrokeColor(PdfColors.black)..setLineWidth(.25);
  void line(double x1, double y1, double x2, double y2) => g..moveTo(_mm(x1), size.y - _mm(y1))..lineTo(_mm(x2), size.y - _mm(y2));
  for (final (c, r) in slots) {
    final x0 = left + c * (_cardW + _gap), y0 = top + r * (_cardH + _gap), x1 = x0 + _cardW, y1 = y0 + _cardH;
    for (final y in [y0, y1]) { line(x0 - off - len, y, x0 - off, y); line(x1 + off, y, x1 + off + len, y); }
    for (final x in [x0, x1]) { line(x, y0 - off - len, x, y0 - off); line(x, y1 + off, x, y1 + off + len); }
  }
  g.strokePath();
}

// ---------------------------------------------------------------- the card (300 × 476 grid, like the screen)
const _yellow = [PdfColor.fromInt(0xFFF8C537), PdfColor.fromInt(0xFFF2A61C)];
const _purple = [PdfColor.fromInt(0xFF7A4BB8), PdfColor.fromInt(0xFF58308F)];
const _ink = PdfColor.fromInt(0xFF1D1D1D);

// Material icon shapes (24 × 24) — the PDF has no icon font.
const _icPerson = 'M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z';
const _icCall = 'M6.62 10.79c1.44 2.83 3.76 5.14 6.59 6.59l2.2-2.2c.27-.27.67-.36 1.02-.24 1.12.37 2.33.57 3.57.57.55 0 1 .45 1 1V20c0 .55-.45 1-1 1-9.39 0-17-7.61-17-17 0-.55.45-1 1-1h3.5c.55 0 1 .45 1 1 0 1.25.2 2.45.57 3.57.11.35.03.74-.25 1.02l-2.2 2.2z';
const _icDrop = 'M12 2c-5.33 4.55-8 8.48-8 11.8 0 4.98 3.8 8.2 8 8.2s8-3.22 8-8.2c0-3.32-2.67-7.25-8-11.8z';
const _icHome = 'M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z';
const _icBus = 'M4 16c0 .88.39 1.67 1 2.22V20c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1h8v1c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1.78c.61-.55 1-1.34 1-2.22V6c0-3.5-3.58-4-8-4s-8 .5-8 4v10zm3.5 1c-.83 0-1.5-.67-1.5-1.5S6.67 14 7.5 14s1.5.67 1.5 1.5S8.33 17 7.5 17zm9 0c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zm1.5-6H6V6h12v5z';

String _hex(PdfColor c) => '#${(c.toInt() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
pw.Widget _icon(String path, PdfColor colour, double size) => pw.SvgImage(width: size, height: size,
    svg: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="${_hex(colour)}" d="$path"/></svg>');

pw.Widget _fit(String text, pw.TextStyle style, {double? height, pw.Alignment align = pw.Alignment.centerLeft}) =>
    pw.SizedBox(height: height, child: pw.FittedBox(fit: pw.BoxFit.scaleDown, alignment: align, child: pw.Text(text, style: style)));

String _initials(String name) => name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join().toUpperCase();

pw.Widget _front(IdPdfCard d, IdPdfFonts f, pw.ImageProvider logo) {
  final band = d.bus ? _yellow : _purple;
  final accent = d.bus ? const PdfColor.fromInt(0xFFEE8A22) : const PdfColor.fromInt(0xFF6A3FA8);
  final nameColour = d.bus ? const PdfColor.fromInt(0xFF8E1B1B) : PdfColors.white;
  final serif = pw.TextStyle(font: f.serif, color: nameColour, letterSpacing: .6);
  pw.Widget row(String icon, String? text, {bool phone = false}) => pw.SizedBox(height: 28, child: text == null || text.isEmpty ? null : pw.Row(children: [
    pw.Container(width: 16, height: 16, alignment: pw.Alignment.center, decoration: const pw.BoxDecoration(shape: pw.BoxShape.circle, color: PdfColor.fromInt(0xFFF2A65A)),
        child: _icon(icon, const PdfColor.fromInt(0xFF7A4A1A), 10)),
    pw.SizedBox(width: 12),
    pw.Expanded(child: _fit(text, pw.TextStyle(font: f.bold, fontSize: 12, color: phone ? const PdfColor.fromInt(0xFF6B3FB6) : const PdfColor.fromInt(0xFF333333)), height: 16)),
  ]));
  pw.ImageProvider? photo;
  if (d.photo != null) {
    try { photo = pw.MemoryImage(d.photo!); } catch (_) { photo = null; }   // a file the PDF cannot read → initials
  }
  final blood = (d.blood ?? '').trim();
  return pw.Container(color: PdfColors.white, child: pw.Stack(overflow: pw.Overflow.clip, children: [
    pw.Positioned(left: 0, top: 0, child: pw.Container(width: 300, height: 250,
        decoration: pw.BoxDecoration(gradient: pw.LinearGradient(begin: pw.Alignment.topLeft, end: pw.Alignment.bottomRight, colors: band)))),
    pw.Positioned(left: 150 - 320, top: 150, child: pw.Container(width: 640, height: 640, decoration: const pw.BoxDecoration(color: PdfColors.white, shape: pw.BoxShape.circle))),
    pw.Positioned(left: 10, top: 20, child: pw.SizedBox(width: 48, child: pw.Image(logo, fit: pw.BoxFit.contain))),
    pw.Positioned(left: 60, top: 14, child: pw.SizedBox(width: 232, child: pw.Column(children: [
      _fit('ROYALE CONCORDE', serif.copyWith(fontSize: 17.5), align: pw.Alignment.center),
      _fit('INTERNATIONAL SCHOOL', serif.copyWith(fontSize: 14.5), align: pw.Alignment.center),
      pw.SizedBox(height: 3),
      pw.Text('Kalyan Nagar, Bangalore - 560043', style: pw.TextStyle(font: f.bold, fontSize: 8.5, color: nameColour)),
    ]))),
    pw.Positioned(left: 94, top: 76, child: pw.Container(width: 112, height: 134,
      decoration: pw.BoxDecoration(borderRadius: pw.BorderRadius.circular(10), border: pw.Border.all(color: const PdfColor.fromInt(0xFF2A2A2A), width: 2.5), color: const PdfColor.fromInt(0xFF2F7D6D)),
      child: pw.ClipRRect(horizontalRadius: 8, verticalRadius: 8, child: photo != null
          ? pw.Image(photo, fit: pw.BoxFit.cover, width: 107, height: 129)
          : pw.Center(child: pw.Text(_initials(d.name), style: pw.TextStyle(font: f.serif, fontSize: 34, color: PdfColors.white)))))),
    if (blood.isNotEmpty) pw.Positioned(right: 12, top: 150, child: pw.SizedBox(width: 40, child: pw.Column(children: [
      _icon(_icDrop, const PdfColor.fromInt(0xFFD0242B), 24),
      _fit(blood.contains('ve') ? blood : '${blood}ve', pw.TextStyle(font: f.bold, fontSize: 12, color: const PdfColor.fromInt(0xFFD0242B)), align: pw.Alignment.center),
    ]))),
    pw.Positioned(left: 26, top: 226, child: pw.SizedBox(width: 230,
        child: _fit(d.name.toUpperCase(), pw.TextStyle(font: f.bold, fontSize: 15.5, letterSpacing: .3, color: const PdfColor.fromInt(0xFFC3262E)), height: 22))),
    pw.Positioned(left: 26, top: 258, child: pw.SizedBox(width: 224,
        child: _fit('Adm # : ${d.admNo}', pw.TextStyle(font: f.bold, fontSize: 14, color: _ink), height: 20))),
    pw.Positioned(left: 26, top: 290, child: pw.SizedBox(width: 224, child: pw.Column(children: [
      row(_icPerson, d.father), row(_icCall, d.fatherPhone, phone: true),
      row(_icPerson, d.mother), row(_icCall, d.motherPhone, phone: true),
    ]))),
    pw.Positioned(right: 8, top: 290, child: pw.Transform.rotateBox(angle: math.pi / 2, child: pw.SizedBox(width: 116, height: 36,
        child: pw.Center(child: pw.Text('Grade - ${d.grade}', style: pw.TextStyle(font: f.base, fontSize: d.grade.length > 3 ? 17 : d.grade.length > 2 ? 20 : 23, color: accent)))))),
    pw.Positioned(right: 12, bottom: 12, child: pw.SizedBox(width: 110, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
      _fit(d.principal.split(' ').first, pw.TextStyle(font: f.script, fontSize: 22, color: const PdfColor.fromInt(0xFF2F7A3A)), align: pw.Alignment.center),
      pw.Text('Principal', style: pw.TextStyle(font: f.bold, fontSize: 11, color: const PdfColor.fromInt(0xFF2E6B35))),
    ]))),
  ]));
}

pw.Widget _back(IdPdfCard d, IdPdfFonts f, pw.ImageProvider logo) {
  final band = d.bus ? _yellow : _purple;
  final bandText = d.bus ? const PdfColor.fromInt(0xFF2A1A00) : PdfColors.white;
  const red = PdfColor.fromInt(0xFFE5452F);
  final label = pw.TextStyle(font: f.bold, fontSize: 13, color: _ink);
  return pw.Container(color: PdfColors.white, child: pw.Column(children: [
    pw.Expanded(child: pw.Padding(padding: const pw.EdgeInsets.fromLTRB(20, 16, 20, 6), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      if (d.bus) ...[
        pw.Center(child: pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 5),
            decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFF5B2E9E), borderRadius: pw.BorderRadius.circular(14)),
            child: pw.Text('School Transport', style: pw.TextStyle(font: f.bold, color: PdfColors.white, fontSize: 15)))),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          pw.Container(width: 30, height: 30, alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, color: red, border: pw.Border.all(color: PdfColors.white, width: 2)),
              child: _icon(_icBus, PdfColors.white, 16)),
          pw.Container(padding: const pw.EdgeInsets.fromLTRB(8, 4, 12, 4), color: red,
              child: pw.Text('Route No :', style: pw.TextStyle(font: f.bold, color: PdfColors.white, fontSize: 14))),
          pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 12), decoration: pw.BoxDecoration(border: pw.Border.all(color: red, width: 2)),
              child: pw.Text(d.route ?? '', style: pw.TextStyle(font: f.bold, fontSize: 20, color: _ink))),
        ]),
        pw.SizedBox(height: 8),
      ],
      pw.Row(children: [pw.Text('Name :  ', style: label), pw.Expanded(child: _fit(d.name, label, height: 18))]),
      pw.SizedBox(height: 7),
      pw.Row(children: [
        pw.Container(width: 22, height: 22, alignment: pw.Alignment.center, decoration: const pw.BoxDecoration(shape: pw.BoxShape.circle, color: PdfColor.fromInt(0xFF222222)),
            child: _icon(_icCall, PdfColors.white, 12)),
        pw.Text('  :  ${d.fatherPhone ?? d.motherPhone ?? ''}', style: label),
      ]),
      pw.SizedBox(height: 8),
      pw.Container(width: double.infinity, padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFDCEAF6), borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Column(children: [
          pw.Container(width: 24, height: 24, alignment: pw.Alignment.center, decoration: const pw.BoxDecoration(shape: pw.BoxShape.circle, color: PdfColor.fromInt(0xFF173E86)),
              child: _icon(_icHome, PdfColors.white, 14)),
          pw.SizedBox(height: 4),
          pw.Text(d.address ?? '', maxLines: 4, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: f.bold, fontSize: 11.5, lineSpacing: 2, color: _ink)),
        ])),
      // the logo takes the space that is left, so it never touches the address or the band
      pw.Expanded(child: pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Center(child: pw.ConstrainedBox(constraints: const pw.BoxConstraints(maxWidth: 160, maxHeight: 62), child: pw.Image(logo, fit: pw.BoxFit.contain))))),
    ]))),
    pw.Container(width: double.infinity, padding: const pw.EdgeInsets.fromLTRB(10, 6, 10, 5),
      decoration: pw.BoxDecoration(gradient: pw.LinearGradient(begin: pw.Alignment.topCenter, end: pw.Alignment.bottomCenter, colors: band)),
      child: pw.Text('6th B Main, HRBR Layout, 2nd Block, Kalyan Nagar, Bengaluru - 560043\nPh : 080-25435454/55   Mob : 9535216115', textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: f.bold, fontSize: 9.6, color: bandText, lineSpacing: 2))),
    pw.Container(color: band.last, padding: const pw.EdgeInsets.fromLTRB(12, 0, 12, 10), child: pw.Container(width: double.infinity, color: const PdfColor.fromInt(0xFF1B1B1B),
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Text('Academic Year ${d.year}', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: f.bold, color: PdfColors.white, fontSize: 15)))),
  ]));
}
