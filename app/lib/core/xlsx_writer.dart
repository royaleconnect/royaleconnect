import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'file_save_io.dart' if (dart.library.js_interop) 'file_save_web.dart' as impl;

/// A real Excel file (.xlsx) with one sheet: a bold header row, then the rows.
/// Numbers stay numbers (so Excel can add them up); everything else is text.
Uint8List buildXlsx(String sheetName, List<String> headers, List<List<Object?>> rows, {List<double>? widths}) {
  String col(int i) { var n = i + 1, s = ''; while (n > 0) { final m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = (n - 1) ~/ 26; } return s; }
  final b = XmlBuilder();
  b.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  b.element('worksheet', namespaces: {'http://schemas.openxmlformats.org/spreadsheetml/2006/main': null}, nest: () {
    b.element('sheetViews', nest: () => b.element('sheetView', attributes: {'workbookViewId': '0'}, nest: () =>
        b.element('pane', attributes: {'ySplit': '1', 'topLeftCell': 'A2', 'activePane': 'bottomLeft', 'state': 'frozen'})));
    b.element('cols', nest: () {
      for (var i = 0; i < headers.length; i++) {
        final w = widths != null && i < widths.length ? widths[i] : (headers[i].length + 6).clamp(10, 40).toDouble();
        b.element('col', attributes: {'min': '${i + 1}', 'max': '${i + 1}', 'width': '$w', 'customWidth': '1'});
      }
    });
    b.element('sheetData', nest: () {
      void row(int r, List<Object?> cells, {bool head = false}) => b.element('row', attributes: {'r': '$r'}, nest: () {
        for (var i = 0; i < cells.length; i++) {
          final v = cells[i];
          if (v == null || (v is String && v.isEmpty)) continue;
          final ref = '${col(i)}$r';
          if (v is num && !head) {
            b.element('c', attributes: {'r': ref}, nest: () => b.element('v', nest: v.toString()));
          } else {
            b.element('c', attributes: {'r': ref, 't': 'inlineStr', if (head) 's': '1'}, nest: () =>
                b.element('is', nest: () => b.element('t', attributes: {'xml:space': 'preserve'}, nest: v.toString())));
          }
        }
      });
      row(1, headers, head: true);
      for (var i = 0; i < rows.length; i++) { row(i + 2, rows[i]); }
    });
  });
  final sheet = b.buildDocument().toXmlString();
  final safeName = sheetName.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ').trim();
  final files = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${_esc(safeName.length > 31 ? safeName.substring(0, 31) : safeName)}" sheetId="1" r:id="rId1"/></sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'xl/styles.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
        '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>',
    'xl/worksheets/sheet1.xml': sheet,
  };
  final a = Archive();
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    a.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  final dynamic out = ZipEncoder().encode(a);
  return Uint8List.fromList(List<int>.from(out as List));
}

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

const xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Save / download a file: on the web the browser downloads it; on phones and computers a "Save as" box opens.
Future<void> saveBytes(Uint8List bytes, String fileName, {String mime = xlsxMime}) => impl.saveBytesImpl(bytes, fileName, mime);
