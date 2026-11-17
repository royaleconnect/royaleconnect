/// The school's marks rules, shared by Marks entry, a student's Marks tab and the report card PDF.
///   • PT 1 / PT 2: out of 30 · I–V: Internal 50 + Written 50 · VI–X: Internal 20 + Written 80
///   • The internal marks are typed in parts (PA, MA, SEA, PF …); PA comes from the periodic test by itself
///   • XI–XII: each subject's own Theory + Practical (70 + 30, 80 + 20, AI 50 + 50)
///   • Grade IX: the 3rd language is school-assessed and not added to the total; VI–VIII: it is in the total
///   • Computers / AI: inside the total in I–VIII, shown apart in IX–X
///   • AB = absent for the written paper only: the internal marks stay and the total shows them alone
library;

const _languages = {'hindi', 'kannada', 'sanskrit', 'french', 'tamil', 'telugu', 'urdu', 'malayalam', 'german', 'marathi'};

/// A student sits a paper when it is their 2nd or 3rd language (I – X), or one of their own subjects in XI – XII
/// (group + elective), or nothing is filled in yet.
bool takesSubject(String? l2, String? l3, String subject, {String? grp, String? el}) {
  final s = subject.trim().toLowerCase();
  final e = electiveOf(subject);
  if (e != null && (grp ?? '').isNotEmpty && (el ?? '').isNotEmpty) {
    return e == el || (grp == 'PCM' && e == 'Maths') || (grp == 'PCB' && e == 'Biology');
  }
  if (!_languages.contains(s)) return true;
  final a = (l2 ?? '').trim().toLowerCase(), b = (l3 ?? '').trim().toLowerCase();
  if (a.isEmpty && b.isEmpty) return true;
  return s == a || s == b;
}

/// XI – XII electives, read from a subject name as the school types it (Mathematics, Physical Education …).
const electives = ['Maths', 'Applied Maths', 'Biology', 'PE', 'AI', 'IP', 'Psychology', 'Home Science', 'Legal Studies'];
String? electiveOf(String subject) {
  final t = subject.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  if (const {'maths', 'math', 'mathematics', 'mat'}.contains(t)) return 'Maths';
  if (const {'appliedmaths', 'appliedmathematics', 'appliedmath', 'am'}.contains(t)) return 'Applied Maths';
  if (const {'biology', 'bio', 'bi'}.contains(t)) return 'Biology';
  if (const {'pe', 'physicaleducation', 'phyed', 'physicaled', 'phed'}.contains(t)) return 'PE';
  if (const {'ai', 'artificialintelligence'}.contains(t)) return 'AI';
  if (const {'ip', 'informaticspractices', 'informaticpractices'}.contains(t)) return 'IP';
  if (const {'psychology', 'psy', 'psych', 'psycho'}.contains(t)) return 'Psychology';
  if (const {'homescience', 'hsc', 'homesc', 'homesci'}.contains(t)) return 'Home Science';
  if (const {'legalstudies', 'legal', 'ls', 'legalstudy'}.contains(t)) return 'Legal Studies';
  for (final l in schoolElectives.values) {
    for (final e in l) { if (t.isNotEmpty && e.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '') == t) return e; }
  }
  return null;
}

/// The groups a XI – XII section teaches, from its stream (fixed rule on the server: _section_stream).
List<String> streamGroups(String? stream) {
  final s = stream ?? '';
  if (s.contains('PCM / PCB')) return const ['PCM', 'PCB'];
  if (s.contains('PCM')) return const ['PCM'];
  if (s.contains('PCB')) return const ['PCB'];
  if (s == 'Commerce') return const ['Commerce'];
  if (s == 'Humanities') return const ['Humanities'];
  return const [];
}
/// The electives a group may take (as in MCB): Science never repeats its own main subject;
/// Commerce takes Applied Maths, Legal Studies, IP, PE, AI or Home Science; Humanities takes Psychology, Home Science or Legal Studies.
/// IT can change these lists in School rules → Subjects ([schoolElectives] is filled from the settings when the app opens).
Map<String, List<String>> schoolElectives = const {};
List<String> listSetting(Map<String, String>? settings, String key, String fallback) =>
    [for (final x in ((settings?[key] ?? '').trim().isEmpty ? fallback : settings![key]!).split(',')) if (x.trim().isNotEmpty) x.trim()];
/// The grades where French is offered as a 2nd language (Grade IX today), and the school's own category list.
Set<int> frenchGrades = const {9};
List<String> schoolCategories = const ['General', 'OBC', 'SC', 'ST'];
void readSchoolRules(Map<String, String>? settings) {
  frenchGrades = {for (final c in listSetting(settings, 'french_grades', 'IX')) gradeNoOf(c)}..remove(0);
  schoolCategories = listSetting(settings, 'categories', 'General,OBC,SC,ST');
  schoolElectives = {
    'Science': listSetting(settings, 'electives_science', 'Maths,Biology,AI,IP,PE,Psychology,Home Science'),
    'Commerce': listSetting(settings, 'electives_commerce', 'Applied Maths,Legal Studies,IP,PE,AI,Home Science'),
    'Humanities': listSetting(settings, 'electives_humanities', 'Psychology,Home Science,Legal Studies'),
  };
}
List<String> electivesFor(String? grp) {
  final sci = schoolElectives['Science'] ?? const ['Maths', 'Biology', 'AI', 'IP', 'PE', 'Psychology', 'Home Science'];
  return switch (grp) {
    'PCM' => [for (final e in sci) if (e != 'Maths') e],
    'PCB' => [for (final e in sci) if (e != 'Biology') e],
    'Commerce' => [for (final e in schoolElectives['Commerce'] ?? const ['Applied Maths', 'Legal Studies', 'IP', 'PE', 'AI', 'Home Science']) if (e != 'Maths' && e != 'Biology') e],
    'Humanities' => [for (final e in schoolElectives['Humanities'] ?? const ['Psychology', 'Home Science', 'Legal Studies']) if (e != 'Maths' && e != 'Biology') e],
    _ => {...electives, for (final l in schoolElectives.values) ...l}.toList(),
  };
}
/// Short name on the student's line: PCM + Biology and PCB + Maths are both "PCMB".
String? subjectCode(String? grp, String? el) {
  if ((grp ?? '').isEmpty || (el ?? '').isEmpty) return null;
  if ((grp == 'PCM' || grp == 'PCB') && (el == 'Maths' || el == 'Biology')) return 'PCMB';
  return '$grp + $el';
}
/// Main subjects of each group (English is common to all).
const groupCore = {
  'PCM': ['Physics', 'Chemistry', 'Maths'], 'PCB': ['Physics', 'Chemistry', 'Biology'],
  'Commerce': ['Accountancy', 'Business Studies', 'Economics'], 'Humanities': ['History', 'Sociology'],
};

/// Where a subject goes on the card: 'main' (in the total), 'r3' (Grade IX 3rd language) or 'skill' (computers / AI).
String cardPart(int gradeNo, String part, String subject, String? l3) {
  if (part == 'skill') return 'skill';
  if (gradeNo == 9 && (l3 ?? '').trim().isNotEmpty && subject.trim().toLowerCase() == l3!.trim().toLowerCase()) return 'r3';
  return 'main';
}

/// Column names: (internal, external). XI–XII and skill subjects: Practical / Theory; others: Internals / Written.
(String, String) markLabels(int gradeNo, String part) =>
    gradeNo >= 11 || part == 'skill' ? ('Practical', 'Theory') : ('Internals', 'Written');

/// The school's grading scale, highest first: (grade, from %). 91–100 A1 · 81–90 A2 … 33–40 D · below 33 E, where a
/// mark is rounded to the whole percent first (so 90.5 is A1). IT can change it in School rules → Grading scale.
List<(String, num)> gradeScale = const [('A1', 90.5), ('A2', 80.5), ('B1', 70.5), ('B2', 60.5), ('C1', 50.5), ('C2', 40.5), ('D', 32.5), ('E', 0)];
void setGradeScale(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return;
  final l = [for (final r in rows) ('${r['grade_label']}', (r['min_pct'] as num))]..sort((a, b) => b.$2.compareTo(a.$2));
  gradeScale = l;
}
String cbseGrade(num pct) {
  for (final (g, from) in gradeScale) { if (pct >= from) return g; }
  return gradeScale.last.$1;
}

const coGrades = {'A': 'Outstanding', 'B': 'Very good', 'C': 'Good', 'D': 'Fair', 'E': 'Needs improvement'};
/// XI – XII use a 3-point scale for the co-scholastic areas.
const coGrades3 = {'A': 'Excellent', 'B': 'Good', 'C': 'Fair'};

/// The internal assessment columns of a paper: [(name, maximum)] — empty when the paper has one internal box (or none).
List<(String, num)> partsOf(Map p) => [
  for (final d in (p['parts'] as List? ?? const [])) ('${(d as Map)['k']}', (d['m'] as num)),
];

/// What one mark adds up to. AB (absent for the written paper): the internal marks alone, no grade.
({num? internal, num? written, bool absent, bool has, num total, num max}) markOf(Map? m, Map p) {
  final i = (m?['i'] ?? m?['internal']) as num?, e = (m?['e'] ?? m?['external']) as num?;
  final ab = (m?['ab'] ?? m?['absent']) == true;
  final mi = ((p['mi'] ?? p['max_internal'] ?? 0) as num), me = ((p['me'] ?? p['max_external'] ?? 0) as num);
  return (internal: i, written: ab ? null : e, absent: ab, has: i != null || e != null || ab, total: (i ?? 0) + (ab ? 0 : (e ?? 0)), max: mi + me);
}

String fmtMark(num? v) => v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1));

/// Reads a typed box: '' → null, 'AB' → absent, a number → the number, anything else → NaN (shown in red).
({num? value, bool absent, bool bad}) readMark(String t) {
  final s = t.trim();
  if (s.isEmpty) return (value: null, absent: false, bad: false);
  if (s.toUpperCase() == 'AB' || s.toUpperCase() == 'A') return (value: null, absent: true, bad: false);
  final n = num.tryParse(s);
  if (n == null || n < 0) return (value: null, absent: false, bad: true);
  return (value: n, absent: false, bad: false);
}

/// 'VI' → 6 (0 for pre-primary).
int gradeNoOf(String? code) => const {'I': 1, 'II': 2, 'III': 3, 'IV': 4, 'V': 5, 'VI': 6, 'VII': 7, 'VIII': 8, 'IX': 9, 'X': 10, 'XI': 11, 'XII': 12}[(code ?? '').toUpperCase()] ?? 0;

/// The co-scholastic areas of a class (School rules → Co-scholastic), and the ten life skills of VI – VIII (Part 2B).
List<String> coAreasFor(Map<String, String>? settings, int gno) => gno >= 11 ? listSetting(settings, 'co_11_12', 'Work Experience,Physical Education,General Studies,Discipline')
    : gno >= 9 ? listSetting(settings, 'co_9_10', 'Art Education,Health & Physical Education,Discipline,Music')
    : gno >= 6 ? listSetting(settings, 'co_6_8', 'Art,Music,Physical Education,GK')
    : listSetting(settings, 'co_1_5', 'Art & Craft,GK,Music,Dance,Games & Sports');
List<String> lifeSkillsFor(Map<String, String>? settings, int gno) => gno < 6 || gno > 8 ? const []
    : [for (final x in (settings?['life_skills'] ?? '').split('|')) if (x.trim().isNotEmpty) x.trim()];
