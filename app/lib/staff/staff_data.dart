import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/session.dart';
import '../core/data.dart';

/// Staff-side data. RLS decides what each role may see or change; the app only asks.
String _d(DateTime d) => d.toIso8601String().substring(0, 10);
String nowIso() => DateTime.now().toUtc().toIso8601String();

Map<String, dynamic> _me(dynamic ref) => (ref.read(sessionProvider).value as Session?)?.staff ?? const {};
String myId(dynamic ref) => _me(ref)["id"];

/// Current academic year row.
final yearProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final y = await db.from('academic_year').select('id,label').eq('is_current', true).maybeSingle();
  if (y == null) throw Exception('No current academic year is visible. Ask IT to run the database setup script (0005_reference_reads.sql) or mark a year as current.');
  return y;
});

/// Sections this staff member works with (class teacher / subject teacher / coordinator / office → all).
final mySectionsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final s = ref.watch(sessionProvider).value;
  if (s == null || !s.isStaff) return [];
  final year = await ref.watch(yearProvider.future);
  final all = await db.from('section').select('id,name,class_teacher_id,grade:grade_id(id,code,name,division,sort_order)').eq('academic_year_id', year['id']);
  final rows = List<Map<String, dynamic>>.from(all);
  rows.sort((a, b) { final g = (a['grade']['sort_order'] as int).compareTo(b['grade']['sort_order'] as int); return g != 0 ? g : (a['name'] as String).compareTo(b['name']); });
  if (s.isOffice) return rows;
  final me = s.staff!['id'];
  final ta = await db.from('teaching_assignment').select('section_id,subject:subject_id(id,name)').eq('staff_id', me).eq('academic_year_id', year['id']);
  final taught = {for (final t in ta) t['section_id'] as String};
  final division = s.staff!['division'];
  return rows.where((r) => r['class_teacher_id'] == me || taught.contains(r['id']) || (s.hasRole('coordinator') && r['grade']['division'] == division)).toList();
});

/// Subjects I teach per section (for diary / marks / portions).
final myAssignmentsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final s = ref.watch(sessionProvider).value;
  if (s == null || !s.isStaff) return [];
  final year = await ref.watch(yearProvider.future);
  final data = await db.from('teaching_assignment').select('section_id,subject:subject_id(id,name),section:section_id(name,grade:grade_id(code))').eq('staff_id', s.staff!['id']).eq('academic_year_id', year['id']);
  return List<Map<String, dynamic>>.from(data);
});

final subjectsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async => List<Map<String, dynamic>>.from(await db.from('subject').select('id,name,short').order('name', ascending: true)));
final gradesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async => List<Map<String, dynamic>>.from(await db.from('grade').select('id,code,name,division,sort_order').order('sort_order', ascending: true)));

/// Students of a section (current year), with phones for the office.
final sectionStudentsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, sectionId) async {
  final data = await db.from('enrolment').select('roll_no,student:student_id(id,admission_no,full_name,photo_path,active,family_phone(phone,label))').eq('section_id', sectionId).order('roll_no', ascending: true);
  final rows = List<Map<String, dynamic>>.from(data);
  rows.sort((a, b) => ((a['roll_no'] ?? 999) as int).compareTo((b['roll_no'] ?? 999) as int));
  return rows;
});

/// Student search (office): by name or admission number.
final studentSearchProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, q) async {
  if (q.trim().length < 2) return [];
  final data = await db.from('student').select('id,admission_no,full_name,active,enrolment(section:section_id(name,grade:grade_id(code)),academic_year!inner(is_current))')
      .or('full_name.ilike.%${q.trim()}%,admission_no.ilike.%${q.trim()}%').eq('enrolment.academic_year.is_current', true).limit(30);
  return List<Map<String, dynamic>>.from(data);
});

// ---------------------------------------------------------------- overview numbers
final staffOverviewProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final s = ref.watch(sessionProvider).value!;
  final me = s.staff!['id'];
  final unread = await db.from('conversation').select('staff_unread').eq('staff_id', me).eq('staff_done', false);
  final leaves = await db.from('leave_request').select('id').eq('status', 'pending');
  final today = _d(DateTime.now());
  final diary = await db.from('diary_entry').select('id').eq('author_id', me).eq('for_date', today);
  final fb = s.isOffice ? await db.from('feedback').select('id').eq('status', 'new') : [];
  return {'unread': unread.fold<int>(0, (a, r) => a + ((r['staff_unread'] ?? 0) as int)), 'leaves': leaves.length, 'diary_today': diary.length, 'feedback': fb.length};
});

// ---------------------------------------------------------------- messages (staff inbox)
final inboxProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final me = _me(ref)['id'];
  final data = await db.from('conversation').select('id,student_id,last_message_at,staff_unread,staff_done,student:student_id(full_name,admission_no,enrolment(section:section_id(name,grade:grade_id(code)),academic_year!inner(is_current)))')
      .eq('staff_id', me).eq('student.enrolment.academic_year.is_current', true).order('last_message_at', ascending: false, nullsFirst: false);
  return List<Map<String, dynamic>>.from(data);
});

/// Every student this staff member may message (class teacher: own section; subject teacher: sections taught; coordinator/VP/office: all theirs).
final myStudentsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final secs = await ref.watch(mySectionsProvider.future);
  if (secs.isEmpty) return [];
  final data = await db.from('enrolment').select('roll_no,section:section_id(id,name,grade:grade_id(code)),student:student_id(id,admission_no,full_name)')
      .inFilter('section_id', [for (final x in secs) x['id']]);
  final rows = List<Map<String, dynamic>>.from(data);
  rows.sort((a, b) { final c = sectionLabelOf(a['section']).compareTo(sectionLabelOf(b['section'])); return c != 0 ? c : ((a['roll_no'] ?? 999) as int).compareTo((b['roll_no'] ?? 999) as int); });
  return rows;
});
String sectionLabelOf(Map<String, dynamic>? sec) => '${sec?['grade']?['code'] ?? ''}-${sec?['name'] ?? ''}';

/// Staff opens (or finds) the private chat with a student's family.
Future<String> staffOpenConversation(WidgetRef ref, String studentId) async {
  final me = myId(ref);
  final ex = await db.from('conversation').select('id').eq('student_id', studentId).eq('staff_id', me).maybeSingle();
  if (ex != null) return ex['id'];
  final r = await db.from('conversation').insert({'student_id': studentId, 'staff_id': me}).select('id').single();
  return r['id'];
}

Future<void> staffSend(String conversationId, String body) async {
  await db.from('message').insert({'conversation_id': conversationId, 'sender_kind': 'staff', 'body': body});
  // bump the family's unread counter so the parent app shows a badge
  final c = await db.from('conversation').select('student_unread').eq('id', conversationId).single();
  await db.from('conversation').update({'last_message_at': nowIso(), 'staff_unread': 0, 'student_unread': ((c['student_unread'] ?? 0) as int) + 1}).eq('id', conversationId);
}
Future<void> markDone(String conversationId, bool done) => db.from('conversation').update({'staff_done': done, 'staff_unread': 0}).eq('id', conversationId);

// ---------------------------------------------------------------- announcements
final staffAnnouncementsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await db.from('announcement').select('id,category,title,body,sent_at,scheduled_for,audience_all,audience_grade_ids,audience_section_ids,author:author_id(display_name),created_at').order('created_at', ascending: false).limit(100);
  return List<Map<String, dynamic>>.from(data);
});

Future<void> postAnnouncement(WidgetRef ref, {required String category, required String title, required String body, required bool all, List<String> gradeIds = const [], List<String> sectionIds = const [], DateTime? scheduledFor}) async {
  final year = await ref.read(yearProvider.future);
  await db.from('announcement').insert({
    'academic_year_id': year['id'], 'category': category, 'title': title, 'body': body, 'author_id': myId(ref),
    'audience_all': all, 'audience_grade_ids': gradeIds, 'audience_section_ids': sectionIds,
    'scheduled_for': scheduledFor?.toUtc().toIso8601String(), 'sent_at': scheduledFor == null ? nowIso() : null,
  });
}

// ---------------------------------------------------------------- diary
final staffDiaryProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, (String, String)>((ref, key) async {
  final (sectionId, isoDate) = key;
  final data = await db.from('diary_entry').select('id,kind,title,body,for_date,due_on,needs_submission,posted_at,subject:subject_id(name),author:author_id(display_name)').eq('section_id', sectionId).eq('for_date', isoDate).order('created_at', ascending: true);
  return List<Map<String, dynamic>>.from(data);
});

Future<void> postDiary(WidgetRef ref, {required String sectionId, String? subjectId, required String kind, required String title, String? body, required DateTime forDate, DateTime? dueOn, bool needsSubmission = false}) =>
    db.from('diary_entry').insert({'section_id': sectionId, 'subject_id': subjectId, 'author_id': myId(ref), 'kind': kind, 'title': title, 'body': body, 'for_date': _d(forDate), 'due_on': dueOn == null ? null : _d(dueOn), 'needs_submission': needsSubmission, 'submission_due_on': needsSubmission && dueOn != null ? _d(dueOn) : null, 'posted_at': nowIso()});

Future<void> deleteDiary(String id) => db.from('diary_entry').delete().eq('id', id);

// ---------------------------------------------------------------- leave
final staffLeavesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await db.from('leave_request').select('id,from_date,to_date,reason,note,status,created_at,student:student_id(full_name,admission_no,enrolment(section:section_id(name,grade:grade_id(code)),academic_year!inner(is_current)))')
      .eq('student.enrolment.academic_year.is_current', true).order('created_at', ascending: false).limit(100);
  return List<Map<String, dynamic>>.from(data);
});
Future<void> decideLeave(WidgetRef ref, String id, bool approve) => db.from('leave_request').update({'status': approve ? 'approved' : 'declined', 'decided_by': myId(ref), 'decided_at': nowIso()}).eq('id', id);

// ---------------------------------------------------------------- star & moments
Future<void> postStar(WidgetRef ref, {required String sectionId, required String studentId, required DateTime month, required String reason}) =>
    db.from('star_of_month').upsert({'section_id': sectionId, 'month': _d(DateTime(month.year, month.month, 1)), 'student_id': studentId, 'reason': reason, 'posted_by': myId(ref)}, onConflict: 'section_id,month');

final staffStarHistoryProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, sectionId) async {
  final data = await db.from('star_of_month').select('month,reason,photo_path,student:student_id(full_name,photo_path)').eq('section_id', sectionId).order('month', ascending: false).limit(12);
  return List<Map<String, dynamic>>.from(data);
});

Future<void> postMoment(WidgetRef ref, {required String sectionId, required String caption, required List<String> paths}) =>
    db.from('moment').insert({'section_id': sectionId, 'caption': caption, 'photo_paths': paths, 'posted_by': myId(ref), 'posted_at': nowIso()});

final staffMomentsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await db.from('moment').select('id,caption,photo_paths,posted_at,section:section_id(name,grade:grade_id(code)),posted_by_staff:posted_by(display_name)').order('created_at', ascending: false).limit(50);
  return List<Map<String, dynamic>>.from(data);
});

// ---------------------------------------------------------------- exams, plan, worksheets
final staffExamsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final year = await ref.watch(yearProvider.future);
  final data = await db.from('exam').select('id,name,term,starts_on,ends_on,max_marks,note,published_at,grade:grade_id(id,code,name),exam_paper(id,on_date,portions,confirmed_at,subject:subject_id(id,name))').eq('academic_year_id', year['id']).order('starts_on', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

Future<String> createExam(WidgetRef ref, {required String gradeId, required String name, required String term, DateTime? starts, DateTime? ends, int maxMarks = 100, String? note, required List<String> subjectIds}) async {
  final year = await ref.read(yearProvider.future);
  final e = await db.from('exam').insert({'academic_year_id': year['id'], 'grade_id': gradeId, 'name': name, 'term': term, 'starts_on': starts == null ? null : _d(starts), 'ends_on': ends == null ? null : _d(ends), 'max_marks': maxMarks, 'note': note, 'created_by': myId(ref)}).select('id').single();
  if (subjectIds.isNotEmpty) await db.from('exam_paper').insert([for (final s in subjectIds) {'exam_id': e['id'], 'subject_id': s}]);
  return e['id'];
}
Future<void> publishExam(String id, bool publish) => db.from('exam').update({'published_at': publish ? nowIso() : null}).eq('id', id);
Future<void> savePortions(WidgetRef ref, String paperId, {DateTime? onDate, String? portions}) =>
    db.from('exam_paper').update({'on_date': onDate == null ? null : _d(onDate), 'portions': portions, 'confirmed_by': myId(ref), 'confirmed_at': nowIso()}).eq('id', paperId);

final staffPlanProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, (String, String)>((ref, key) async {
  final (gradeId, monthIso) = key;
  final data = await db.from('monthly_plan').select('id,topics,assessment,published_at,subject:subject_id(id,name)').eq('grade_id', gradeId).eq('month', monthIso);
  return List<Map<String, dynamic>>.from(data);
});
Future<void> savePlan(WidgetRef ref, {required String gradeId, required String monthIso, required String subjectId, required String topics, String? assessment, bool publish = true}) async {
  final year = await ref.read(yearProvider.future);
  await db.from('monthly_plan').upsert({'academic_year_id': year['id'], 'grade_id': gradeId, 'month': monthIso, 'subject_id': subjectId, 'topics': topics, 'assessment': assessment, 'published_at': publish ? nowIso() : null}, onConflict: 'academic_year_id,grade_id,month,subject_id');
}

final staffWorksheetsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await db.from('worksheet').select('id,kind,title,file_path,answer_key_path,answer_key_release_on,created_at,subject:subject_id(name),section:section_id(name,grade:grade_id(code)),grade:grade_id(code),author:author_id(display_name)').order('created_at', ascending: false).limit(100);
  return List<Map<String, dynamic>>.from(data);
});
Future<void> addWorksheet(WidgetRef ref, {String? sectionId, String? gradeId, required String subjectId, required String kind, required String title, required String filePath, String? keyPath, DateTime? keyRelease}) =>
    db.from('worksheet').insert({'section_id': sectionId, 'grade_id': gradeId, 'subject_id': subjectId, 'kind': kind, 'title': title, 'file_path': filePath, 'answer_key_path': keyPath, 'answer_key_release_on': keyRelease == null ? null : _d(keyRelease), 'author_id': myId(ref)});

// ---------------------------------------------------------------- marks
final marksProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, (String, String, String)>((ref, key) async {
  final (examId, subjectId, sectionId) = key;
  final students = await ref.watch(sectionStudentsProvider(sectionId).future);
  final marks = await db.from('mark').select('student_id,internal,external,absent').eq('exam_id', examId).eq('subject_id', subjectId);
  final byStudent = {for (final m in marks) m['student_id']: m};
  return [for (final s in students) {'student': s['student'], 'roll_no': s['roll_no'], 'mark': byStudent[s['student']['id']]}];
});
Future<void> saveMarks(WidgetRef ref, String examId, String subjectId, List<Map<String, dynamic>> rows) =>
    db.from('mark').upsert([for (final r in rows) {'exam_id': examId, 'subject_id': subjectId, 'student_id': r['student_id'], 'internal': r['internal'], 'external': r['external'], 'absent': r['absent'] ?? false, 'entered_by': myId(ref), 'updated_at': nowIso()}], onConflict: 'exam_id,subject_id,student_id');

// ---------------------------------------------------------------- feedback (office)
final staffFeedbackProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await db.from('feedback').select('id,category,subject,body,anonymous,status,reply,created_at,student:student_id(full_name,admission_no),section:section_id(name,grade:grade_id(code))').order('created_at', ascending: false).limit(100);
  return List<Map<String, dynamic>>.from(data);
});
Future<void> replyFeedback(WidgetRef ref, String id, String reply, String status) => db.from('feedback').update({'reply': reply, 'status': status, 'replied_by': myId(ref), 'replied_at': nowIso()}).eq('id', id);

// ---------------------------------------------------------------- fees desk (office / accounts)
final studentLedgerProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, studentId) async {
  final data = await db.from('fee_ledger').select('id,title,amount,due_on,status,paid_on,parent_ledger_id,note,academic_year!inner(is_current)').eq('student_id', studentId).eq('academic_year.is_current', true).order('due_on', ascending: true);
  return List<Map<String, dynamic>>.from(data);
});
final overdueReportProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final today = _d(DateTime.now());
  final data = await db.from('fee_ledger').select('id,title,amount,due_on,student:student_id(id,full_name,admission_no,enrolment(section:section_id(name,grade:grade_id(code)),academic_year!inner(is_current)))')
      .eq('status', 'pending').lt('due_on', today).eq('student.enrolment.academic_year.is_current', true).order('due_on', ascending: true).limit(500);
  return List<Map<String, dynamic>>.from(data);
});
final recentPaymentsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await db.from('payment').select('id,amount,mode,status,receipt_no,paid_at,student:student_id(full_name,admission_no)').eq('status', 'success').order('paid_at', ascending: false).limit(100);
  return List<Map<String, dynamic>>.from(data);
});

// ---------------------------------------------------------------- transport (in-charge / office)
final routesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await db.from('route').select('id,name,bus_reg_no,active,morning_start,afternoon_start,driver:driver_staff_id(display_name,phone),conductor:conductor_staff_id(display_name,phone),route_stop(id,seq,name),transport_enrolment(student_id)').order('name', ascending: true);
  return List<Map<String, dynamic>>.from(data);
});
final runningTripsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
  while (true) {
    yield List<Map<String, dynamic>>.from(await db.from('trip').select('id,kind,started_at,last_fix_at,next_stop_seq,route:route_id(name,bus_reg_no)').eq('status', 'running'));
    await Future.delayed(const Duration(seconds: 15));
  }
});

// ---------------------------------------------------------------- staff directory (IT)
final staffListProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async =>
    List<Map<String, dynamic>>.from(await db.from('staff').select('id,email,full_name,display_name,roles,division,phone,active').order('full_name', ascending: true)));

/// Call a server function with the staff token (password resets etc.). Throws with the server's message on failure.
Future<Map<String, dynamic>> callFunction(WidgetRef ref, String fn, Map<String, dynamic> body) async {
  final s = ref.read(sessionProvider).value!;
  final r = await http.post(Uri.parse('${AppConfig.functionsUrl}/$fn'), headers: {'content-type': 'application/json', 'apikey': AppConfig.supabaseAnonKey, 'authorization': 'Bearer ${s.token}'}, body: jsonEncode(body));
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  if (r.statusCode >= 400) throw Exception(j['error'] ?? 'Request failed');
  return j;
}
