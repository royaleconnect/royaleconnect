/// Import from Excel — the rules (no screens here): what can be imported, how columns are recognised,
/// how each cell is read (dates, phones, classes…), and the row-by-row check before anything is saved.

class ImpField {
  final String key, label, type;   // type: text | date | time | phone | number | class | section | roles | division | feekind | bool | maplink
  final List<String> names;        // column headings this field is recognised by (lower case, no punctuation)
  final bool required;
  const ImpField(this.key, this.label, this.names, {this.type = 'text', this.required = false});
}

class ImpKind {
  final String key, label, help, template, rpc;
  final List<String> roles;
  final List<ImpField> fields;
  const ImpKind(this.key, this.label, this.help, this.template, this.rpc, this.roles, this.fields);
}

const _office = ['office', 'it_admin', 'principal', 'vice_principal'];
const _transport = ['transport_incharge', 'office', 'it_admin', 'principal', 'vice_principal'];
const _accounts = ['accounts', 'it_admin', 'principal'];

const importKinds = <ImpKind>[
  ImpKind('students', 'Students & parents', 'One row per student. New admission numbers are added; existing ones are updated (only the filled-in cells change, phones are added).',
      'students.csv', 'admin_import_students', _office, [
    ImpField('admission_no', 'Admission number', ['admission no', 'admission number', 'adm no', 'admn no', 'admission', 'adm number', 'enrollment no', 'enrolment no', 'enrolment number', 'enrollment number', 'admission id', 'student id'], required: true),
    ImpField('full_name', 'Student name', ['student name', 'name', 'full name', 'name of the student', 'student', 'students name', 'student full name'], required: true),
    ImpField('dob', 'Date of birth', ['dob', 'date of birth', 'birth date', 'birthdate', 'd o b'], type: 'date', required: true),
    ImpField('class', 'Class (or class & section)', ['class', 'grade', 'std', 'standard', 'class section', 'class and section', 'class sec', 'classsection', 'class name', 'current class'], type: 'class', required: true),
    ImpField('section', 'Section', ['section', 'sec', 'div', 'division', 'section name'], type: 'section'),
    ImpField('roll_no', 'Roll number', ['roll no', 'roll number', 'roll', 'rollno'], type: 'number'),
    ImpField('father_phone', 'Father’s mobile', ['father mobile', 'father phone', 'father mobile no', 'father contact', 'fathers mobile', 'father mobile number', 'father contact no', 'father cell'], type: 'phone'),
    ImpField('mother_phone', 'Mother’s mobile', ['mother mobile', 'mother phone', 'mother mobile no', 'mother contact', 'mothers mobile', 'mother mobile number', 'mother contact no', 'mother cell'], type: 'phone'),
    ImpField('phone', 'Other mobile', ['mobile', 'phone', 'mobile no', 'contact', 'contact no', 'phone number', 'mobile number', 'sms mobile', 'sms number', 'primary mobile', 'parent mobile', 'guardian mobile', 'contact number', 'emergency contact'], type: 'phone'),
    ImpField('father_name', 'Father’s name', ['father name', 'fathers name', 'father', 'name of father']),
    ImpField('mother_name', 'Mother’s name', ['mother name', 'mothers name', 'mother', 'name of mother']),
    ImpField('guardian_name', 'Guardian', ['guardian', 'guardian name', 'guardians name']),
    ImpField('gender', 'Gender', ['gender', 'sex'], type: 'gender'),
    ImpField('address', 'Address', ['address', 'residential address', 'permanent address', 'present address', 'communication address', 'home address']),
    ImpField('blood_group', 'Blood group', ['blood group', 'blood', 'bloodgroup']),
    ImpField('house', 'House', ['house', 'house name']),
    ImpField('admission_type', 'Admission type', ['admission type', 'student type', 'boarding type', 'day scholar boarder']),
  ]),
  ImpKind('staff', 'Staff', 'One row per staff member. Matched by email: new emails are added, existing ones updated. Drivers and bus assistants are set up in Transport instead.',
      'staff.csv', 'admin_import_staff', ['it_admin', 'principal'], [
    ImpField('email', 'School email', ['email', 'email id', 'e mail', 'mail', 'official email', 'school email', 'email address', 'mail id'], required: true),
    ImpField('full_name', 'Full name', ['name', 'full name', 'staff name', 'employee name', 'teacher name', 'name of the staff'], required: true),
    ImpField('display_name', 'Name parents see', ['display name', 'name for parents', 'short name', 'called as']),
    ImpField('phone', 'Mobile', ['mobile', 'phone', 'contact', 'mobile no', 'mobile number', 'contact no', 'phone number'], type: 'phone'),
    ImpField('roles', 'Role / designation', ['role', 'roles', 'designation', 'post', 'position', 'department'], type: 'roles'),
    ImpField('division', 'Coordinator for (wing)', ['wing', 'division', 'coordinator for', 'section head of'], type: 'division'),
  ]),
  ImpKind('sections', 'Classes & class teachers', 'One row per section: grade, section and the class teacher’s school email. New sections are made; the teacher must already be in Staff.',
      'classes.csv', 'admin_import_sections', _office, [
    ImpField('grade', 'Grade', ['grade', 'class', 'std', 'standard'], type: 'grade', required: true),
    ImpField('section', 'Section', ['section', 'sec', 'div', 'division', 'section name'], required: true),
    ImpField('teacher_email', 'Class teacher’s email', ['class teacher email', 'class teacher email id', 'teacher email', 'email', 'email id', 'class teacher', 'confirmed email id', 'class teacher mail']),
  ]),
  ImpKind('fee_plan', 'Fee plan', 'One row per fee per grade (e.g. Grade VIII · Term 1 tuition · 25,000 · due 10 Jun). After importing, use Fees → “Give to all students”.',
      'fee_plan.csv', 'admin_import_fee_plan', _accounts, [
    ImpField('grade', 'Grade', ['grade', 'class', 'std', 'standard', 'class name'], type: 'grade', required: true),
    ImpField('head', 'Fee name', ['fee name', 'fee head', 'fee', 'head', 'particulars', 'fee type', 'description', 'fee particulars', 'term'], required: true),
    ImpField('amount', 'Amount', ['amount', 'fee amount', 'amount rs', 'rs', 'total', 'amount inr'], type: 'number', required: true),
    ImpField('due_on', 'Due date', ['due date', 'due on', 'due', 'last date', 'last date to pay'], type: 'date', required: true),
    ImpField('kind', 'Type', ['kind', 'category', 'fee category'], type: 'feekind'),
    ImpField('optional', 'Optional?', ['optional', 'is optional'], type: 'bool'),
  ]),
  ImpKind('stops', 'Bus routes & stops', 'One row per stop, in the order the bus reaches them in the morning. Stops without a map location can be pinned later in Bus routes → Stops on the map.',
      'bus_stops.csv', 'admin_import_stops', _transport, [
    ImpField('route', 'Route', ['route', 'route name', 'route no', 'route number', 'bus route', 'route code'], required: true),
    ImpField('bus', 'Bus number', ['bus', 'bus no', 'bus number', 'vehicle', 'vehicle no', 'vehicle number', 'registration', 'reg no', 'registration no']),
    ImpField('stop', 'Stop', ['stop', 'stop name', 'pickup point', 'pick up point', 'boarding point', 'point', 'stage', 'bus stop', 'stop point', 'pickup stop']),
    ImpField('morning_eta', 'Morning pick-up time', ['pickup time', 'pick up time', 'morning time', 'morning', 'am time', 'pickup', 'morning pickup'], type: 'time'),
    ImpField('afternoon_eta', 'Afternoon drop time', ['drop time', 'afternoon time', 'evening time', 'pm time', 'drop', 'afternoon drop'], type: 'time'),
    ImpField('morning_start', 'Bus leaves (morning)', ['morning start', 'route start', 'start time', 'departure'], type: 'time'),
    ImpField('afternoon_start', 'Bus leaves school (afternoon)', ['afternoon start', 'return start', 'school leaving', 'leaves school'], type: 'time'),
    ImpField('lat', 'Latitude', ['latitude', 'lat'], type: 'number'),
    ImpField('lng', 'Longitude', ['longitude', 'lng', 'long', 'lon'], type: 'number'),
    ImpField('map', 'Google Maps link', ['map', 'map link', 'google map', 'google maps', 'location', 'location link', 'maps link'], type: 'maplink'),
  ]),
  ImpKind('riders', 'Students on each bus', 'One row per student who takes the school bus: admission number, route and stop. Import the bus routes first.',
      'bus_students.csv', 'admin_import_riders', _transport, [
    ImpField('admission_no', 'Admission number', ['admission no', 'admission number', 'adm no', 'admn no', 'admission', 'enrollment no', 'enrolment no', 'student id'], required: true),
    ImpField('route', 'Route', ['route', 'route name', 'route no', 'route number', 'bus route'], required: true),
    ImpField('stop', 'Stop', ['stop', 'stop name', 'pickup point', 'pick up point', 'boarding point', 'point', 'stage', 'bus stop'], required: true),
    ImpField('name', 'Student name (only to help you read the check list)', ['student name', 'name', 'student']),
  ]),
  ImpKind('paid', 'Fees already paid', 'Payments made before Royale Connect (e.g. Term 1 paid in MyClassBoard). With a fee name, that fee is settled; without one, the amount settles the oldest fees first. Give fees to the class first.',
      'fees_paid.csv', 'admin_import_paid', _accounts, [
    ImpField('admission_no', 'Admission number', ['admission no', 'admission number', 'adm no', 'admn no', 'admission', 'enrollment no', 'enrolment no', 'student id'], required: true),
    ImpField('amount', 'Amount paid', ['amount', 'paid amount', 'amount paid', 'paid', 'total paid', 'fee paid', 'collected', 'amount rs', 'receipt amount'], type: 'number', required: true),
    ImpField('head', 'Fee name', ['fee name', 'fee head', 'head', 'particulars', 'fee', 'fee type', 'term']),
    ImpField('paid_on', 'Date paid', ['date', 'date paid', 'paid on', 'paid date', 'payment date', 'receipt date', 'date of payment'], type: 'date'),
    ImpField('ref', 'Receipt number', ['receipt no', 'receipt number', 'receipt', 'bill no', 'ref', 'reference', 'transaction id']),
    ImpField('name', 'Student name (only to help you read the check list)', ['student name', 'name', 'student']),
  ]),
];

// ------------------------------------------------------------------ column matching
String normHeader(String s) => s.toLowerCase().replaceAll(RegExp(r"[’'`.]"), '').replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// The heading row: the first of the top 15 rows that matches the most known headings.
int findHeaderRow(List<List<String>> rows, ImpKind kind) {
  var best = 0, bestScore = -1;
  final known = {for (final f in kind.fields) ...f.names};
  for (var i = 0; i < rows.length && i < 15; i++) {
    final score = rows[i].where((c) => known.contains(normHeader(c))).length * 10 + rows[i].where((c) => c.trim().isNotEmpty).length;
    if (score > bestScore && rows[i].where((c) => c.trim().isNotEmpty).length >= 2) { best = i; bestScore = score; }
  }
  return best;
}

/// field key → column index. Exact heading matches first, then headings that contain a known name.
Map<String, int> autoMatch(List<String> headers, ImpKind kind) {
  final h = [for (final x in headers) normHeader(x)];
  final used = <int>{};
  final out = <String, int>{};
  for (final f in kind.fields) {
    for (final n in f.names) {
      final i = h.indexOf(n);
      if (i >= 0 && !used.contains(i)) { out[f.key] = i; used.add(i); break; }
    }
  }
  for (final f in kind.fields) {
    if (out.containsKey(f.key)) continue;
    final names = [...f.names.where((n) => n.length >= 5)]..sort((a, b) => b.length.compareTo(a.length));
    outer:
    for (final n in names) {
      for (var i = 0; i < h.length; i++) {
        if (!used.contains(i) && h[i].contains(n)) { out[f.key] = i; used.add(i); break outer; }
      }
    }
  }
  return out;
}

// ------------------------------------------------------------------ reading cells
const _months = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10, 'nov': 11, 'dec': 12};

/// Dates as written in Indian school sheets → yyyy-mm-dd (day first when it is ambiguous). null = not understood.
String? parseDate(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  DateTime? d;
  var m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s);
  if (m != null) d = _ymd(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  if (d == null) {
    m = RegExp(r'^(\d{1,2})[-/. ](\d{1,2})[-/. ](\d{2,4})\b').firstMatch(s);
    if (m != null) {
      var a = int.parse(m[1]!), b = int.parse(m[2]!);
      if (b > 12 && a <= 12) { final t = a; a = b; b = t; }   // written month-first
      d = _ymd(_year(m[3]!), b, a);
    }
  }
  if (d == null) {
    m = RegExp(r'^(\d{1,2})(?:st|nd|rd|th)?[-/. ]+([a-z]{3,9})[-/., ]+(\d{2,4})').firstMatch(s);
    if (m != null && _months[m[2]!.substring(0, 3)] != null) d = _ymd(_year(m[3]!), _months[m[2]!.substring(0, 3)]!, int.parse(m[1]!));
  }
  if (d == null) {
    m = RegExp(r'^([a-z]{3,9})[-/. ]+(\d{1,2})(?:st|nd|rd|th)?[-/., ]+(\d{2,4})').firstMatch(s);
    if (m != null && _months[m[1]!.substring(0, 3)] != null) d = _ymd(_year(m[3]!), _months[m[1]!.substring(0, 3)]!, int.parse(m[2]!));
  }
  if (d == null) {
    final n = double.tryParse(s);   // an Excel day number that came through as plain text
    if (n != null && n > 3000 && n < 80000) d = DateTime.utc(1899, 12, 30).add(Duration(days: n.floor()));
  }
  if (d == null) return null;
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

int _year(String y) {
  var n = int.parse(y);
  if (y.length == 2) n += n > (DateTime.now().year % 100) + 1 ? 1900 : 2000;
  return n;
}

DateTime? _ymd(int y, int m, int d) {
  if (y < 1950 || y > 2100 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final x = DateTime.utc(y, m, d);
  return x.month == m ? x : null;   // 31 Feb etc.
}

/// "7:10", "07.10 am", "3:45 PM", "7:10:00", "0.2986" (Excel) → HH:mm.
String? parseTime(String raw) {
  final s = raw.trim().toLowerCase().replaceAll(' ', '');
  if (s.isEmpty) return null;
  final n = double.tryParse(s);
  if (n != null && n > 0 && n < 1) {
    final mins = (n * 24 * 60).round();
    return '${(mins ~/ 60).toString().padLeft(2, '0')}:${(mins % 60).toString().padLeft(2, '0')}';
  }
  final m = RegExp(r'^(\d{1,2})[:.](\d{2})(?::\d{2})?(am|pm|a\.m\.|p\.m\.)?$').firstMatch(s);
  if (m == null) return null;
  var h = int.parse(m[1]!);
  final min = int.parse(m[2]!);
  final ap = m[3];
  if (ap != null && ap.startsWith('p') && h < 12) h += 12;
  if (ap != null && ap.startsWith('a') && h == 12) h = 0;
  if (h > 23 || min > 59) return null;
  return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
}

/// Indian mobile → 10 digits, or null. "+91 98450 12345", "098450-12345", "9845012345.0" all work.
String? parsePhone(String raw) {
  var d = raw.replaceAll(RegExp(r'\.0+$'), '').replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
  if (d.length != 10 || !RegExp(r'^[6-9]').hasMatch(d)) return null;
  return d;
}

/// One cell may hold two numbers ("9845012345 / 9845067890").
List<String> splitPhones(String raw) => raw.split(RegExp(r'[/,;&]|\s{2,}|\bor\b')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

num? parseNumber(String raw) {
  final s = raw.replaceAll(RegExp(r'(rs\.?|inr|₹|,|\s)', caseSensitive: false), '');
  return num.tryParse(s);
}

bool? parseBool(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  if (['y', 'yes', 'true', '1', 'optional'].contains(s)) return true;
  if (['n', 'no', 'false', '0', 'compulsory', 'mandatory'].contains(s)) return false;
  return null;
}

String? parseGender(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  if (s.startsWith('m') || s == 'boy') return 'Male';
  if (s.startsWith('f') || s == 'girl') return 'Female';
  return null;
}

/// Designation text → app roles. Anything not recognised is a teacher.
List<String> parseRoles(String raw) {
  final out = <String>{};
  for (final part in raw.toLowerCase().split(RegExp(r'[,/;&+]|\band\b'))) {
    final s = part.trim();
    if (s.isEmpty) continue;
    if (s.contains('vice') && s.contains('principal') || s == 'vp') {
      out.add('vice_principal');
    } else if (s.contains('principal')) {
      out.add('principal');
    } else if (s.contains('coordinator') || s.contains('co ordinator') || s.contains('co-ordinator') || s.contains('hod')) {
      out.add('coordinator');
    } else if (s.contains('class teacher')) {
      out.addAll(['teacher', 'class_teacher']);
    } else if (s.contains('account') || s.contains('cashier') || s.contains('finance')) {
      out.add('accounts');
    } else if (s == 'it' || s.contains('it admin') || s.contains('system admin') || s.contains('it head')) {
      out.add('it_admin');
    } else if (s.contains('transport')) {
      out.add('transport_incharge');
    } else if (s.contains('office') || s.contains('admin') || s.contains('reception') || s.contains('clerk') || s.contains('front desk')) {
      out.add('office');
    } else {
      out.add('teacher');
    }
  }
  return out.isEmpty ? ['teacher'] : out.toList();
}

String? parseDivision(String raw) {
  final s = raw.toLowerCase();
  if (s.trim().isEmpty) return null;
  if (s.contains('pre') || s.contains('kg') || s.contains('nursery') || s.contains('kinder')) return 'pre_primary';
  if (s.contains('primary')) return 'primary';
  if (s.contains('middle')) return 'middle';
  if (s.contains('high') || s.contains('senior') || s.contains('secondary')) return 'high_senior';
  return null;
}

String parseFeeKind(String raw, String head) {
  final s = '${raw.toLowerCase()} ${head.toLowerCase()}';
  if (s.contains('bus') || s.contains('transport') || s.contains('van')) return 'transport';
  if (s.contains('tuition') || s.contains('term') || s.contains('annual') || s.contains('admission')) return 'tuition';
  if (s.contains('book') || s.contains('uniform') || s.contains('activity') || s.contains('exam') || s.contains('lab')) return 'misc';
  return raw.trim().isEmpty ? 'tuition' : 'other';
}

/// Google Maps link or "13.02, 77.64" → (lat, lng).
(double, double)? parseMapLink(String raw) {
  final m = RegExp(r'(-?\d{1,2}\.\d{3,})\s*,\s*(-?\d{1,3}\.\d{3,})').firstMatch(raw);
  if (m == null) return null;
  final lat = double.parse(m[1]!), lng = double.parse(m[2]!);
  if (lat.abs() > 90 || lng.abs() > 180) return null;
  return (lat, lng);
}

// ------------------------------------------------------------------ classes & grades
const _roman = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'];

String _compact(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

class SchoolClasses {
  final List<Map<String, dynamic>> grades;     // {id, code, name}
  final List<Map<String, dynamic>> sections;   // {id, name, grade:{id, code, name}}
  late final Map<String, String> _gradeByAlias = _buildAliases();

  SchoolClasses(this.grades, this.sections);

  Map<String, String> _buildAliases() {
    final m = <String, String>{};
    for (final g in grades) {
      final id = g['id'] as String;
      final code = _compact('${g['code']}');
      final aliases = <String>{code, _compact('${g['name'] ?? ''}')};
      final r = _roman.indexOf(code);
      if (r > 0) aliases.addAll(['$r', 'GRADE$r', 'CLASS$r', 'STD$r', 'GRADE$code', 'CLASS$code', 'STD$code']);
      if (code == 'LKG') aliases.addAll(['LOWERKG', 'KG1', 'JRKG', 'JUNIORKG', 'PP2']);
      if (code == 'UKG') aliases.addAll(['UPPERKG', 'KG2', 'SRKG', 'SENIORKG', 'PP3']);
      if (code.contains('NUR') || code.contains('PREKG') || code == 'PKG') aliases.addAll(['NURSERY', 'NUR', 'PREKG', 'PKG', 'PLAYGROUP', 'PP1']);
      for (final a in aliases) {
        if (a.isNotEmpty) m.putIfAbsent(a, () => id);
      }
    }
    return m;
  }

  /// Grade text ("8", "VIII", "Grade 8", "LKG") → grade id.
  String? grade(String raw) {
    final c = _compact(raw);
    if (c.isEmpty) return null;
    return _gradeByAlias[c];
  }

  /// Class text, with or without a separate section column → section id.
  /// "VIII-B", "8 B", "8B", "Grade 8 - B", "Class VIII (B)", "XI Sci", "LKG A" all work.
  String? section(String cls, [String sec = '']) {
    final c = _compact(cls.replaceAll(RegExp(r'\b(grade|class|std|standard)\b', caseSensitive: false), ''));
    final s = _compact(sec);
    if (c.isEmpty) return null;
    // try the longest grade name at the start, the rest is the section
    final aliases = _gradeByAlias.keys.where(c.startsWith).toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final a in aliases) {
      final gid = _gradeByAlias[a]!;
      final rest = s.isNotEmpty ? s : c.substring(a.length);
      final inGrade = sections.where((x) => x['grade']?['id'] == gid).toList();
      if (inGrade.isEmpty) continue;
      if (rest.isEmpty) {
        if (inGrade.length == 1) return inGrade.first['id'];
        continue;
      }
      for (final x in inGrade) {
        final n = _compact('${x['name']}');
        if (n == rest || (rest.length >= 3 && n.startsWith(rest)) || (n.length >= 3 && rest.startsWith(n))) return x['id'];
      }
    }
    return null;
  }

  String label(String sectionId) {
    final x = sections.where((s) => s['id'] == sectionId).firstOrNull;
    return x == null ? '' : '${x['grade']?['code']}-${x['name']}';
  }
}

// ------------------------------------------------------------------ the check
class CheckedRow {
  final int line;                // row number as Excel shows it
  final String who;              // name / admission number, for people reading the list
  final Map<String, dynamic> rec;
  final bool isNew;
  final List<String> notes;      // imported, but something was left out (e.g. a 9-digit phone)
  CheckedRow(this.line, this.who, this.rec, this.isNew, this.notes);
}

class Problem {
  final int line; final String who; final String text; final bool blocking;
  const Problem(this.line, this.who, this.text, {this.blocking = true});
}

class CheckResult {
  final List<CheckedRow> ready;
  final List<Problem> problems;     // blocking ones are skipped; others are notes on imported rows
  final int skippedEmpty;
  CheckResult(this.ready, this.problems, this.skippedEmpty);
  int get newCount => ready.where((r) => r.isNew).length;
  int get updateCount => ready.where((r) => !r.isNew).length;
  int get blocked => problems.where((p) => p.blocking).length;
}

/// [students]: UPPER-CASE admission number → student id (whole school).
CheckResult checkRows({
  required ImpKind kind,
  required List<List<String>> rows,
  required int headerRow,
  required Map<String, int> mapping,
  required Map<String, String> students,
  required SchoolClasses classes,
  Set<String> existingEmails = const {},
  Set<String> existingRoutes = const {},
}) {
  final ready = <CheckedRow>[];
  final problems = <Problem>[];
  var empty = 0;
  final seen = <String, int>{};

  for (var r = headerRow + 1; r < rows.length; r++) {
    final row = rows[r];
    final line = r + 1;
    String cell(String key) {
      final i = mapping[key];
      return i == null || i >= row.length ? '' : row[i].trim();
    }
    if (row.every((c) => c.trim().isEmpty)) { empty++; continue; }
    final errs = <String>[];
    final notes = <String>[];
    final rec = <String, dynamic>{'i': line};
    String who = '';
    var isNew = true;

    switch (kind.key) {
      case 'students':
        final adm = cell('admission_no').toUpperCase();
        final name = cell('full_name');
        who = name.isEmpty ? adm : '$name · $adm';
        if (adm.isEmpty) { errs.add('Admission number missing'); break; }
        if (seen.containsKey(adm)) { errs.add('Same admission number as row ${seen[adm]}'); break; }
        seen[adm] = line;
        isNew = !students.containsKey(adm);
        rec['admission_no'] = adm;
        if (name.isNotEmpty) rec['full_name'] = _title(name);
        final dobRaw = cell('dob');
        final dob = parseDate(dobRaw);
        if (dob != null) {
          rec['dob'] = dob;
        } else if (dobRaw.isNotEmpty) {
          errs.add('Date of birth “$dobRaw” not understood');
        }
        if (isNew && name.isEmpty) errs.add('Student name missing');
        if (isNew && dobRaw.isEmpty) errs.add('Date of birth missing');
        final cls = cell('class'), sec = cell('section');
        if (cls.isNotEmpty) {
          final sid = classes.section(cls, sec);
          if (sid == null) {
            errs.add('Class “${[cls, sec].where((x) => x.isNotEmpty).join(' ')}” — no such section in the app (add it in Classes first)');
          } else {
            rec['section_id'] = sid;
          }
        } else if (isNew) {
          errs.add('Class missing');
        }
        final roll = int.tryParse(cell('roll_no').replaceAll(RegExp(r'\.0+$'), ''));
        if (roll != null) rec['roll_no'] = roll;
        final phones = <Map<String, String>>[];
        for (final (k, label) in const [('father_phone', 'Father'), ('mother_phone', 'Mother'), ('phone', 'Other')]) {
          final raw = cell(k);
          if (raw.isEmpty) continue;
          for (final p in splitPhones(raw)) {
            final d = parsePhone(p);
            if (d == null) {
              notes.add('$label mobile “$p” is not a 10-digit mobile — left out');
            } else if (!phones.any((x) => x['phone'] == d)) {
              phones.add({'phone': d, 'label': label});
            }
          }
        }
        if (phones.isNotEmpty) rec['phones'] = phones;
        if (isNew && phones.isEmpty) notes.add('No parent mobile — the family will not get notifications until one is added');
        for (final k in const ['father_name', 'mother_name', 'guardian_name', 'address', 'blood_group', 'house', 'admission_type']) {
          final v = cell(k);
          if (v.isNotEmpty) rec[k] = k.endsWith('_name') ? _title(v) : (k == 'blood_group' ? v.toUpperCase().replaceAll(' ', '') : v);
        }
        final g = parseGender(cell('gender'));
        if (g != null) rec['gender'] = g;

      case 'staff':
        final email = cell('email').toLowerCase();
        final name = cell('full_name');
        who = name.isEmpty ? email : '$name · $email';
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) { errs.add(email.isEmpty ? 'Email missing' : 'Email “$email” not valid'); break; }
        if (seen.containsKey(email)) { errs.add('Same email as row ${seen[email]}'); break; }
        seen[email] = line;
        isNew = !existingEmails.contains(email);
        rec['email'] = email;
        if (name.isNotEmpty) rec['full_name'] = _title(name);
        if (isNew && name.isEmpty) errs.add('Name missing');
        if (cell('display_name').isNotEmpty) rec['display_name'] = cell('display_name');
        final ph = cell('phone');
        if (ph.isNotEmpty) {
          final d = parsePhone(ph);
          if (d == null) { notes.add('Mobile “$ph” is not a 10-digit mobile — left out'); } else { rec['phone'] = d; }
        }
        if (cell('roles').isNotEmpty) rec['roles'] = parseRoles(cell('roles'));
        final div = parseDivision(cell('division'));
        if (div != null) rec['division'] = div;

      case 'sections':
        final g = cell('grade'), sec = cell('section').toUpperCase();
        final email = cell('teacher_email').toLowerCase();
        who = '$g-$sec';
        final gid = classes.grade(g);
        if (gid == null) { errs.add(g.isEmpty ? 'Grade missing' : 'Grade “$g” not found'); break; }
        if (sec.isEmpty) { errs.add('Section missing'); break; }
        if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
          notes.add('“${cell('teacher_email')}” is not an email — class teacher left as it is');
        } else if (email.isNotEmpty) {
          rec['teacher_email'] = email;
          if (existingEmails.isNotEmpty && !existingEmails.contains(email)) { errs.add('No staff member with the email $email — add or import the staff first'); break; }
        }
        final key = '$gid|$sec';
        if (seen.containsKey(key)) { errs.add('Same section as row ${seen[key]}'); break; }
        seen[key] = line;
        isNew = classes.section(g, sec) == null;
        rec.addAll({'grade_id': gid, 'section': sec});

      case 'fee_plan':
        final g = cell('grade'), head = cell('head');
        who = '$g · $head';
        final gid = classes.grade(g);
        if (gid == null) errs.add(g.isEmpty ? 'Grade missing' : 'Grade “$g” not found');
        if (head.isEmpty) errs.add('Fee name missing');
        final amt = parseNumber(cell('amount'));
        if (amt == null || amt <= 0) errs.add('Amount “${cell('amount')}” not understood');
        final due = parseDate(cell('due_on'));
        if (due == null) errs.add(cell('due_on').isEmpty ? 'Due date missing' : 'Due date “${cell('due_on')}” not understood');
        final key = '$gid|${head.toLowerCase()}';
        if (seen.containsKey(key)) errs.add('Same fee for this grade as row ${seen[key]}');
        seen[key] = line;
        rec.addAll({'grade_id': gid, 'head': head, 'amount': amt, 'due_on': due, 'kind': parseFeeKind(cell('kind'), head), 'optional': parseBool(cell('optional')) ?? false});

      case 'stops':
        final route = cell('route'), stop = cell('stop');
        who = stop.isEmpty ? route : '$route · $stop';
        if (route.isEmpty) { errs.add('Route missing'); break; }
        isNew = !existingRoutes.contains(route.toLowerCase());
        rec['route'] = route;
        if (cell('bus').isNotEmpty) rec['bus'] = cell('bus').toUpperCase();
        if (stop.isNotEmpty) rec['stop'] = stop;
        for (final k in const ['morning_eta', 'afternoon_eta', 'morning_start', 'afternoon_start']) {
          final raw = cell(k);
          if (raw.isEmpty) continue;
          final t = parseTime(raw);
          if (t == null) { notes.add('Time “$raw” not understood — left out'); } else { rec[k] = t; }
        }
        var lat = double.tryParse(cell('lat')), lng = double.tryParse(cell('lng'));
        final link = parseMapLink(cell('map'));
        if ((lat == null || lng == null) && link != null) { lat = link.$1; lng = link.$2; }
        if (lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180) {
          rec['lat'] = lat; rec['lng'] = lng;
        } else if (stop.isNotEmpty) {
          notes.add('No map location — pin it later in Bus routes → Stops on the map');
        }

      case 'riders':
        final adm = cell('admission_no').toUpperCase();
        who = cell('name').isEmpty ? adm : '${cell('name')} · $adm';
        final sid = students[adm];
        if (adm.isEmpty) { errs.add('Admission number missing'); break; }
        if (sid == null) { errs.add('No student with admission number $adm — import the students first'); break; }
        if (cell('route').isEmpty) errs.add('Route missing');
        if (cell('stop').isEmpty) errs.add('Stop missing');
        if (cell('route').isNotEmpty && existingRoutes.isNotEmpty && !existingRoutes.contains(cell('route').toLowerCase())) errs.add('No route called “${cell('route')}” — import the bus routes first');
        isNew = true;
        rec.addAll({'student_id': sid, 'route': cell('route'), 'stop': cell('stop')});

      case 'paid':
        final adm = cell('admission_no').toUpperCase();
        who = cell('name').isEmpty ? adm : '${cell('name')} · $adm';
        final sid = students[adm];
        if (adm.isEmpty) { errs.add('Admission number missing'); break; }
        if (sid == null) { errs.add('No student with admission number $adm'); break; }
        final amt = parseNumber(cell('amount'));
        if (amt == null) { errs.add('Amount “${cell('amount')}” not understood'); break; }
        if (amt <= 0) { empty++; continue; }   // nothing paid: not a problem, just nothing to do
        isNew = false;
        rec.addAll({'student_id': sid, 'amount': amt, 'head': cell('head'), 'ref': cell('ref')});
        final pd = parseDate(cell('paid_on'));
        if (pd != null) rec['paid_on'] = pd;
    }

    if (errs.isNotEmpty) {
      problems.add(Problem(line, who, errs.join(' · ')));
    } else {
      for (final n in notes) {
        problems.add(Problem(line, who, n, blocking: false));
      }
      ready.add(CheckedRow(line, who, rec, isNew, notes));
    }
  }
  return CheckResult(ready, problems, empty);
}

/// "AYAAN KHAN" → "Ayaan Khan"; names already in mixed case are left alone.
String _title(String s) {
  if (s != s.toUpperCase() && s != s.toLowerCase()) return s.trim();
  return s.trim().split(RegExp(r'\s+')).map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase()).join(' ');
}
