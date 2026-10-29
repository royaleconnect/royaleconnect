import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Reads a spreadsheet into plain text cells — no extra package needed for the formats schools get from other software:
///   • Excel .xlsx (and .xlsm)            • CSV / tab-separated text
///   • "Excel" exports that are really an HTML table (many school systems do this)
/// Dates become yyyy-mm-dd and times HH:mm; whole numbers lose their ".0" (so phone numbers stay intact).
class Sheet {
  final String name;
  final List<List<String>> rows;
  const Sheet(this.name, this.rows);
}

class SheetError implements Exception {
  final String message;
  const SheetError(this.message);
  @override
  String toString() => message;
}

List<Sheet> readSpreadsheet(Uint8List bytes, String fileName) {
  if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) return _xlsx(bytes);
  if (bytes.length > 4 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0) {
    throw const SheetError('This is an old-style Excel file (.xls). Open it in Excel → File → Save As → “Excel Workbook (.xlsx)”, then upload the new file.');
  }
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  if (RegExp(r'<table', caseSensitive: false).hasMatch(text)) return [Sheet(_base(fileName), _html(text))];
  return [Sheet(_base(fileName), _csv(text))];
}

String _base(String f) => f.replaceAll(RegExp(r'\.[^.]+$'), '');

// ------------------------------------------------------------------ xlsx
List<Sheet> _xlsx(Uint8List bytes) {
  final Archive arc;
  try {
    arc = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const SheetError('This file could not be opened. Please save it again as .xlsx or .csv and upload it.');
  }
  String? read(String path) {
    final f = arc.findFile(path);
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }
  Iterable<XmlElement> all(XmlNode n, String local) => n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);
  String? attr(XmlElement e, String local) {
    for (final a in e.attributes) {
      if (a.name.local == local) return a.value;
    }
    return null;
  }

  // shared strings
  final shared = <String>[];
  final ss = read('xl/sharedStrings.xml');
  if (ss != null) {
    for (final si in all(XmlDocument.parse(ss), 'si')) {
      shared.add(all(si, 't').map((t) => t.innerText).join());
    }
  }

  // which cell styles are dates / times
  final styleKind = <int, String>{};   // style index → 'date' | 'time'
  final st = read('xl/styles.xml');
  if (st != null) {
    final doc = XmlDocument.parse(st);
    final custom = <int, String>{};
    for (final f in all(doc, 'numFmt')) {
      final id = int.tryParse(attr(f, 'numFmtId') ?? '');
      if (id != null) custom[id] = (attr(f, 'formatCode') ?? '').toLowerCase();
    }
    final xfs = all(doc, 'cellXfs').expand((c) => c.children.whereType<XmlElement>().where((e) => e.name.local == 'xf')).toList();
    for (var i = 0; i < xfs.length; i++) {
      final id = int.tryParse(attr(xfs[i], 'numFmtId') ?? '') ?? 0;
      String? k;
      if ((id >= 14 && id <= 17) || id == 22) k = 'date';
      if ((id >= 18 && id <= 21) || (id >= 45 && id <= 47)) k = 'time';
      final code = custom[id];
      if (code != null) {
        final bare = code.replaceAll(RegExp(r'"[^"]*"|\[[^\]]*\]'), '');
        if (RegExp(r'[dy]').hasMatch(bare)) {
          k = 'date';
        } else if (RegExp(r'h|ss').hasMatch(bare)) {
          k = 'time';
        }
      }
      if (k != null) styleKind[i] = k;
    }
  }

  // sheets in workbook order
  final wb = read('xl/workbook.xml');
  final rels = read('xl/_rels/workbook.xml.rels');
  final targets = <String, String>{};
  if (rels != null) {
    for (final r in all(XmlDocument.parse(rels), 'Relationship')) {
      final t = attr(r, 'Target') ?? '';
      targets[attr(r, 'Id') ?? ''] = t.startsWith('/') ? t.substring(1) : 'xl/$t';
    }
  }
  final sheets = <Sheet>[];
  final list = wb == null ? <XmlElement>[] : all(XmlDocument.parse(wb), 'sheet').toList();
  final paths = <(String, String)>[
    for (final s in list) if (targets[attr(s, 'id')] != null) (attr(s, 'name') ?? 'Sheet', targets[attr(s, 'id')]!),
  ];
  if (paths.isEmpty) {
    for (final f in arc.files) {
      if (f.name.startsWith('xl/worksheets/') && f.name.endsWith('.xml')) paths.add((f.name.split('/').last.replaceAll('.xml', ''), f.name));
    }
  }
  for (final (name, path) in paths) {
    final xml = read(path);
    if (xml == null) continue;
    final rows = <List<String>>[];
    for (final row in all(XmlDocument.parse(xml), 'row')) {
      final cells = <String>[];
      var next = 0;
      for (final c in row.children.whereType<XmlElement>().where((e) => e.name.local == 'c')) {
        final ref = attr(c, 'r');
        final col = ref == null ? next : _colIndex(ref);
        next = col + 1;
        final t = attr(c, 't');
        final v = all(c, 'v').map((e) => e.innerText).join();
        String val;
        if (t == 's') {
          final k = int.tryParse(v);
          val = k != null && k < shared.length ? shared[k] : '';
        } else if (t == 'inlineStr') {
          val = all(c, 't').map((e) => e.innerText).join();
        } else if (t == 'b') {
          val = v == '1' ? 'TRUE' : 'FALSE';
        } else if (t == 'e') {
          val = '';
        } else if (t == 'str' || t == 'd') {
          val = v;
        } else {
          final kind = styleKind[int.tryParse(attr(c, 's') ?? '') ?? -1];
          final n = double.tryParse(v);
          if (n != null && kind == 'date') {
            val = excelDate(n);
          } else if (n != null && kind == 'time') {
            val = excelTime(n);
          } else {
            val = cleanNumber(v);
          }
        }
        while (cells.length < col) {
          cells.add('');
        }
        if (cells.length == col) {
          cells.add(val.trim());
        } else {
          cells[col] = val.trim();
        }
      }
      rows.add(cells);
    }
    sheets.add(Sheet(name, rows));
  }
  if (sheets.isEmpty) throw const SheetError('No sheet with data was found in this file.');
  return sheets;
}

int _colIndex(String ref) {
  var n = 0;
  for (final ch in ref.toUpperCase().codeUnits) {
    if (ch < 65 || ch > 90) break;
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}

/// Excel day number → yyyy-mm-dd (1900 date system).
String excelDate(double n) {
  final d = DateTime.utc(1899, 12, 30).add(Duration(days: n.floor()));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Excel fraction of a day → HH:mm.
String excelTime(double n) {
  final mins = ((n - n.floor()) * 24 * 60).round() % (24 * 60);
  return '${(mins ~/ 60).toString().padLeft(2, '0')}:${(mins % 60).toString().padLeft(2, '0')}';
}

/// "9845012345.0" / "9.845012345E9" → "9845012345"; other numbers unchanged.
String cleanNumber(String v) {
  final n = double.tryParse(v);
  if (n == null) return v;
  if (n == n.roundToDouble() && n.abs() < 1e15) return n.toInt().toString();
  return v;
}

// ------------------------------------------------------------------ html table
List<List<String>> _html(String text) {
  final rows = <List<String>>[];
  final tr = RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true);
  final td = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', caseSensitive: false, dotAll: true);
  for (final m in tr.allMatches(text)) {
    rows.add([for (final c in td.allMatches(m.group(1)!)) _htmlText(c.group(1)!)]);
  }
  return rows;
}

String _htmlText(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

// ------------------------------------------------------------------ csv / tsv
List<List<String>> _csv(String text) {
  final firstLine = text.split('\n').first;
  final sep = [',', ';', '\t'].reduce((a, b) => firstLine.split(a).length >= firstLine.split(b).length ? a : b);
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == sep) {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString().trim());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString().trim());
    rows.add(row);
  }
  return rows;
}
