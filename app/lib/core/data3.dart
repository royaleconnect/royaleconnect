import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/session.dart';
import 'data.dart';
import 'data2.dart';

/// Release A data: school settings (feature switches, who can use what), homework for tomorrow,
/// Board Toppers and Hall of Fame.

// ---------------------------------------------------------------- school settings
/// Every school_setting row as key → value (readable by everyone signed in; changed only by IT / Principal).
final appSettingsProvider = FutureProvider<Map<String, String>>((ref) async {
  ref.watch(sessionProvider);
  final rows = await db.from('school_setting').select('key,value');
  return {for (final r in rows) r['key'] as String: (r['value'] ?? '').toString()};
});

Map<String, dynamic> _json(String? v) {
  try { final x = jsonDecode(v ?? '{}'); return x is Map<String, dynamic> ? x : {}; } catch (_) { return {}; }
}

/// Feature switches. A missing switch means "on".
Map<String, dynamic> featuresOf(Map<String, String>? settings) => _json(settings?['features']);
bool featureOn(Map<String, String>? settings, String key) => featuresOf(settings)[key] != false;

/// The features IT can switch on and off (key, label, what it does).
const featureList = [
  ('toppers', 'Board Toppers', 'Class X and XII toppers with photos, and subject centums.'),
  ('fame', 'Hall of Fame', 'Former students and where they are today.'),
  ('bus', 'School bus tracking', 'Live bus on the map and “bus is near” alerts.'),
  ('messages', 'Messages to teachers', 'Private chat between families and teachers.'),
  ('gallery', 'Gallery & class moments', 'School albums and class photos.'),
  ('star', 'Star of the month', 'One student per class each month.'),
  ('worksheets', 'Worksheets', 'PDF worksheets and answer keys.'),
  ('plan', 'Monthly plan', 'What each subject covers this month.'),
  ('leave', 'Leave requests', 'Families ask for leave; the class teacher approves.'),
];

/// Who can use which staff page: page path → roles. Missing = the normal choice.
Map<String, List<String>> staffAccessOf(Map<String, String>? settings) =>
    {for (final e in _json(settings?['staff_access']).entries) if (e.value is List) e.key: List<String>.from(e.value as List)};

/// The current school year's label ('2026-27'); it changes by itself on the second move-up day.
final yearLabelProvider = FutureProvider<String?>((ref) async {
  ref.watch(sessionProvider);
  final r = await db.from('academic_year').select('label').eq('is_current', true).maybeSingle();
  return r?['label'] as String?;
});

// ---------------------------------------------------------------- homework for the next school day
/// How many homework / project entries of the active student's class are due on [isoDate].
final homeworkDueProvider = FutureProvider.autoDispose.family<int, String>((ref, isoDate) async {
  final e = await ref.watch(enrolmentProvider.future);
  final sec = e?['section'];
  if (sec == null || shownSection(sec) == null) return 0;
  final rows = await db.from('diary_entry').select('id').eq('section_id', sec['id']).eq('due_on', isoDate)
      .inFilter('kind', ['homework', 'project']).not('posted_at', 'is', null);
  return rows.length;
});

// ---------------------------------------------------------------- Board Toppers & Hall of Fame
/// All toppers of a board class ('X' or 'XII'), newest year first.
final toppersProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, cls) async {
  final rows = await db.from('board_topper').select('id,year,board_class,kind,rank,full_name,section,percent,subject,photo_path')
      .eq('board_class', cls).order('year', ascending: false).order('rank', ascending: true).order('full_name', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});

/// Yearly summary (students, pass %, 90%+) keyed by year.
final boardResultsProvider = FutureProvider.autoDispose.family<Map<int, Map<String, dynamic>>, String>((ref, cls) async {
  final rows = await db.from('board_result').select('year,board_class,students,pass_percent,distinctions,note').eq('board_class', cls);
  return {for (final r in rows) (r['year'] as num).toInt(): Map<String, dynamic>.from(r)};
});

final hallOfFameProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await db.from('hall_of_fame').select('id,full_name,batch,achievement,category,photo_path,spotlight,sort')
      .order('spotlight', ascending: false).order('sort', ascending: true).order('batch', ascending: false);
  return List<Map<String, dynamic>>.from(rows);
});

const fameCategories = ['Academics', 'Medicine', 'Engineering', 'Commerce', 'Abroad', 'Business', 'Sports', 'Arts', 'Service'];
const fameIcons = {'Academics': '🎓', 'Medicine': '🩺', 'Engineering': '⚙️', 'Commerce': '💼', 'Abroad': '✈️', 'Business': '🚀', 'Sports': '🏅', 'Arts': '🎨', 'Service': '🤝'};

String initialsOf(String name) => name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
