/// The school's marks rules, shared by Marks entry, a student's Marks tab and the report card PDF.
///   • PT 1 / PT 2: out of 30 · I–V term exams: 50 written · VI–X: Internals 20 + Written 80
///   • XI–XII: each subject's own Theory + Practical (70 + 30, 80 + 20, AI 50 + 50)
///   • Grade IX: the 3rd language is school-assessed and not added to the total; VI–VIII: it is in the total (600)
///   • Computers / AI in I–X: shown separately, not in the total
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
const electives = ['Maths', 'Biology', 'PE', 'AI', 'IP', 'Psychology', 'Home Science'];
String? electiveOf(String subject) {
  final t = subject.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  if (const {'maths', 'math', 'mathematics', 'appliedmathematics', 'appliedmaths', 'mat'}.contains(t)) return 'Maths';
  if (const {'biology', 'bio', 'bi'}.contains(t)) return 'Biology';
  if (const {'pe', 'physicaleducation', 'phyed', 'physicaled', 'phed'}.contains(t)) return 'PE';
  if (const {'ai', 'artificialintelligence'}.contains(t)) return 'AI';
  if (const {'ip', 'informaticspractices', 'informaticpractices'}.contains(t)) return 'IP';
  if (const {'psychology', 'psy', 'psych', 'psycho'}.contains(t)) return 'Psychology';
  if (const {'homescience', 'hsc', 'homesc', 'homesci'}.contains(t)) return 'Home Science';
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
/// The electives a group may take: Commerce and Humanities never Maths or Biology; PCM not Maths again; PCB not Biology again.
List<String> electivesFor(String? grp) => [
  for (final e in electives)
    if (!(grp == 'PCM' && e == 'Maths') && !(grp == 'PCB' && e == 'Biology') && !((grp == 'Commerce' || grp == 'Humanities') && (e == 'Maths' || e == 'Biology'))) e,
];
/// Short name on the student's line: PCM + Biology and PCB + Maths are both "PCMB".
String? subjectCode(String? grp, String? el) {
  if ((grp ?? '').isEmpty || (el ?? '').isEmpty) return null;
  if ((grp == 'PCM' || grp == 'PCB') && (el == 'Maths' || el == 'Biology')) return 'PCMB';
  return '$grp + $el';
}
/// Main subjects of each group (English is common to all).
const groupCore = {
  'PCM': ['Physics', 'Chemistry', 'Maths'], 'PCB': ['Physics', 'Chemistry', 'Biology'],
  'Commerce': ['Accountancy', 'Business Studies', 'Economics'], 'Humanities': ['History', 'Political Science', 'Economics'],
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

/// CBSE scale used by the school: 91–100 A1 · 81–90 A2 · 71–80 B1 · 61–70 B2 · 51–60 C1 · 41–50 C2 · 33–40 D · below 33 E
String cbseGrade(num pct) => pct >= 90.5 ? 'A1' : pct >= 80.5 ? 'A2' : pct >= 70.5 ? 'B1' : pct >= 60.5 ? 'B2' : pct >= 50.5 ? 'C1' : pct >= 40.5 ? 'C2' : pct >= 32.5 ? 'D' : 'E';

const coGrades = {'A': 'Outstanding', 'B': 'Very good', 'C': 'Good', 'D': 'Fair', 'E': 'Needs improvement'};

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
