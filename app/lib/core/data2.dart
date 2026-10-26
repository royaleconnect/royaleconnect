import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/session.dart';
import 'data.dart';

/// Data for the secondary screens. Everything is read through RLS; the app only shapes it.

String _d(DateTime d) => d.toIso8601String().substring(0, 10);

/// Current enrolment of the active student: section, grade, class teacher, roll no.
final enrolmentProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return null;
  return await db.from('enrolment')
      .select('roll_no,section:section_id(id,name,class_teacher:class_teacher_id(display_name,phone),grade:grade_id(id,code,name,division)),academic_year!inner(is_current,label)')
      .eq('student_id', s.id).eq('academic_year.is_current', true).maybeSingle();
});

/// Full profile (no Aadhaar / APAAR / PEN — those columns are never selected).
final profileProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return null;
  return await db.from('student').select('admission_no,full_name,dob,gender,blood_group,house,admission_type,address,father_name,mother_name,guardian_name,photo_path,family_phone(phone,label)').eq('id', s.id).maybeSingle();
});

/// Signed URL for a private storage object (valid 1 hour). Cached per path while the screen is alive.
final signedUrlProvider = FutureProvider.autoDispose.family<String, String>((ref, path) async {
  ref.keepAlive();
  if (path.startsWith('http')) return path; // plain web link (sample data, external files)
  return db.storage.from('files').createSignedUrl(path, 3600);
});

// ---------------------------------------------------------------- messages
class Contact { final String staffId, name, kind; final String? subject; Contact(this.staffId, this.name, this.kind, this.subject); }

final contactsProvider = FutureProvider.autoDispose<List<Contact>>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return [];
  // student_contacts is a view, so PostgREST cannot join it to staff / subject; fetch the names separately
  final rows = await db.from('student_contacts').select('staff_id,kind,subject_id').eq('student_id', s.id);
  final staffIds = {for (final r in rows) r['staff_id'] as String}.toList();
  final subjectIds = {for (final r in rows) if (r['subject_id'] != null) r['subject_id'] as String}.toList();
  final staff = staffIds.isEmpty ? <dynamic>[] : await db.from('staff').select('id,display_name,roles').inFilter('id', staffIds);
  final subjects = subjectIds.isEmpty ? <dynamic>[] : await db.from('subject').select('id,name').inFilter('id', subjectIds);
  final staffById = {for (final r in staff) r['id']: r};
  final subjectById = {for (final r in subjects) r['id']: r};
  final data = [for (final r in rows) {...r, 'staff': staffById[r['staff_id']], 'subject': subjectById[r['subject_id']]}];
  final seen = <String>{};
  final out = <Contact>[];
  // order: class teacher, subject teachers, coordinators / VP
  for (final k in ['class', 'subject', 'lead']) {
    for (final r in data.where((r) => r['kind'] == k)) {
      if (!seen.add(r['staff_id'])) continue;
      final roles = List<String>.from(r['staff']?['roles'] ?? []);
      final label = k == 'class' ? 'Class teacher' : k == 'subject' ? (r['subject']?['name'] ?? 'Subject teacher') : roles.contains('vice_principal') ? 'Vice Principal' : 'Coordinator';
      out.add(Contact(r['staff_id'], r['staff']?['display_name'] ?? '', k, label));
    }
  }
  return out;
});

final conversationsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return [];
  final data = await db.from('conversation').select('id,staff_id,last_message_at,student_unread,staff:staff_id(display_name)').eq('student_id', s.id).order('last_message_at', ascending: false, nullsFirst: false);
  return List<Map<String, dynamic>>.from(data);
});

final messagesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, conversationId) async {
  final data = await db.from('message').select('id,sender_kind,body,attachment_path,attachment_name,attachment_mime,created_at,seen_at').eq('conversation_id', conversationId).order('created_at', ascending: true);
  return List<Map<String, dynamic>>.from(data);
});

/// Opens (or finds) the private 1:1 conversation with a staff member.
Future<String> openConversation(String studentId, String staffId) async {
  final ex = await db.from('conversation').select('id').eq('student_id', studentId).eq('staff_id', staffId).maybeSingle();
  if (ex != null) return ex['id'];
  final r = await db.from('conversation').insert({'student_id': studentId, 'staff_id': staffId}).select('id').single();
  return r['id'];
}

Future<void> sendMessage(String conversationId, {String? body, String? path, String? name, String? mime}) async {
  await db.from('message').insert({'conversation_id': conversationId, 'sender_kind': 'student', 'body': body, 'attachment_path': path, 'attachment_name': name, 'attachment_mime': mime});
  await db.from('conversation').update({'last_message_at': DateTime.now().toUtc().toIso8601String(), 'staff_done': false}).eq('id', conversationId);
}

Future<void> markConversationRead(String conversationId) => db.from('conversation').update({'student_unread': 0}).eq('id', conversationId);

// ---------------------------------------------------------------- academics
final timetableProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final e = await ref.watch(enrolmentProvider.future);
  if (e == null) return [];
  final data = await db.from('timetable_slot').select('weekday,period,starts_at,label,needs_kit,subject:subject_id(name,short),staff:staff_id(display_name)').eq('section_id', e['section']['id']).order('weekday', ascending: true).order('period', ascending: true);
  return List<Map<String, dynamic>>.from(data);
});

final examsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final e = await ref.watch(enrolmentProvider.future);
  if (e == null) return [];
  final data = await db.from('exam').select('id,name,term,starts_on,ends_on,max_marks,note,exam_paper(on_date,portions,subject:subject_id(name))')
      .eq('grade_id', e['section']['grade']['id']).not('published_at', 'is', null).order('starts_on', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

final monthlyPlanProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, monthIso) async {
  final e = await ref.watch(enrolmentProvider.future);
  if (e == null) return [];
  final data = await db.from('monthly_plan').select('topics,assessment,subject:subject_id(name)').eq('grade_id', e['section']['grade']['id']).eq('month', monthIso).not('published_at', 'is', null);
  return List<Map<String, dynamic>>.from(data);
});

final worksheetsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final e = await ref.watch(enrolmentProvider.future);
  if (e == null) return [];
  final data = await db.from('worksheet').select('id,kind,title,file_path,answer_key_path,answer_key_release_on,created_at,subject:subject_id(name),author:author_id(display_name)')
      .or('section_id.eq.${e['section']['id']},grade_id.eq.${e['section']['grade']['id']}').order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

final starProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final e = await ref.watch(enrolmentProvider.future);
  if (e == null) return [];
  final data = await db.from('star_of_month').select('month,reason,photo_path,student:student_id(full_name,photo_path),posted_by_staff:posted_by(display_name)').eq('section_id', e['section']['id']).order('month', ascending: false).limit(12);
  return List<Map<String, dynamic>>.from(data);
});

/// True when a calendar entry is meant for this grade code ('VIII', 'LKG' …). An empty list means the whole school.
bool eventIsFor(Map<String, dynamic> e, String? grade) {
  final g = List<String>.from(e['grades'] ?? const []);
  return g.isEmpty || grade == null || g.contains(grade.toUpperCase());
}

/// Grades VI–XII have school on the 1st, 3rd and 5th Saturday of every month (unless the calendar marks a holiday).
const seniorGrades = {'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'};
bool isWorkingSaturday(DateTime d, String? grade) =>
    d.weekday == DateTime.saturday && grade != null && seniorGrades.contains(grade.toUpperCase()) && const {1, 3, 5}.contains((d.day - 1) ~/ 7 + 1);
String saturdayOrdinal(DateTime d) => const ['1st', '2nd', '3rd', '4th', '5th'][(d.day - 1) ~/ 7];

final calendarProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await db.from('calendar_event').select('title,starts_on,ends_on,kind,grades,note,academic_year!inner(is_current)').eq('academic_year.is_current', true).order('starts_on', ascending: true);
  return List<Map<String, dynamic>>.from(data);
});

final reportCardsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return [];
  final data = await db.from('report_card').select('id,term,working_days,days_present,remarks,published_at,academic_year:academic_year_id(label)').eq('student_id', s.id).eq('status', 'published').order('published_at', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

// ---------------------------------------------------------------- leave
final leavesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return [];
  final data = await db.from('leave_request').select('id,from_date,to_date,reason,note,status,decided_at,decided_by_staff:decided_by(display_name)').eq('student_id', s.id).order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

Future<void> applyLeave(String studentId, DateTime from, DateTime to, String reason, String? note) =>
    db.from('leave_request').insert({'student_id': studentId, 'from_date': _d(from), 'to_date': _d(to), 'reason': reason, 'note': note});

// ---------------------------------------------------------------- gallery
final momentsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return [];
  final e = await ref.watch(enrolmentProvider.future);
  if (e == null) return [];
  // only the active child's class (or whole grade) — a family login can cover siblings in other classes
  final data = await db.from('moment').select('id,caption,photo_paths,posted_at,posted_by_staff:posted_by(display_name),moment_like(student_id)')
      .or('section_id.eq.${e['section']['id']},grade_id.eq.${e['section']['grade']['id']}').not('posted_at', 'is', null).order('posted_at', ascending: false).limit(40);
  return List<Map<String, dynamic>>.from(data);
});

Future<void> toggleLike(String momentId, String studentId, bool liked) => liked
    ? db.from('moment_like').delete().eq('moment_id', momentId).eq('student_id', studentId)
    : db.from('moment_like').insert({'moment_id': momentId, 'student_id': studentId});

final albumsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await db.from('album').select('id,title,event_date,cover_path,album_photo(id,path,sort_order)').order('event_date', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

// ---------------------------------------------------------------- feedback
Future<void> sendFeedback(String? studentId, String? sectionId, String category, String subject, String body, bool anonymous) =>
    db.from('feedback').insert({'student_id': anonymous ? null : studentId, 'section_id': sectionId, 'category': category, 'subject': subject, 'body': body, 'anonymous': anonymous});

// ---------------------------------------------------------------- transport
final routeDetailProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final t = await ref.watch(transportProvider.future);
  if (t == null) return null;
  final r = await db.from('route').select('id,name,bus_reg_no,morning_start,afternoon_start,driver:driver_staff_id(display_name,phone),conductor:conductor_staff_id(display_name,phone),route_stop(id,seq,name,lat,lng,morning_eta,afternoon_eta)').eq('id', t['route']['id']).single();
  return {...r, 'my_stop': t['stop']};
});

/// The running trip on the student's route, if any (polled every 10 s by the Bus screen).
final liveTripProvider = StreamProvider.autoDispose<Map<String, dynamic>?>((ref) async* {
  final t = await ref.watch(transportProvider.future);
  if (t == null) { yield null; return; }
  while (true) {
    try {
      yield await db.from('trip').select('id,kind,started_at,status,last_lat,last_lng,last_fix_at,next_stop_seq').eq('route_id', t['route']['id']).eq('status', 'running').maybeSingle();
    } catch (_) {/* a dropped network moment: keep the last position on screen and try again */}
    await Future.delayed(const Duration(seconds: 3));   // the bus phone sends every second; parents refresh every 3 s and the marker glides between
  }
});

final etaPrefProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return {};
  return await db.from('eta_alert_pref').select().eq('student_id', s.id).maybeSingle() ?? {'student_id': s.id, 'trip_started': true, 'ten_min': true, 'two_stops': true, 'at_stop': true, 'trip_ended': false};
});

Future<void> saveEtaPref(Map<String, dynamic> p) => db.from('eta_alert_pref').upsert(p);

// crew side
final crewRouteProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final s = ref.watch(sessionProvider).value;
  if (s == null || s.kind != 'crew') return null;
  final staffId = s.crew?['staff_id'];
  final q = db.from('route').select('id,name,bus_reg_no,route_stop(seq,name)').eq('active', true);
  final r = staffId == null ? await q.limit(1).maybeSingle() : await q.or('driver_staff_id.eq.$staffId,conductor_staff_id.eq.$staffId').maybeSingle();
  return r;
});

final crewTripProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final r = await ref.watch(crewRouteProvider.future);
  if (r == null) return null;
  return await db.from('trip').select('id,kind,started_at,next_stop_seq').eq('route_id', r['id']).eq('status', 'running').maybeSingle();
});

/// Start a trip (kind 'morning' | 'afternoon'). The server tells the families on this route.
Future<String> startTrip(String routeId, String kind, String staffId) async =>
    (await db.rpc('start_trip', params: {'p_route': routeId, 'p_kind': kind})) as String;

Future<void> endTrip(String tripId) => db.rpc('end_trip', params: {'p_trip': tripId});

/// One GPS position. The server updates the live position, keeps history every 10 s, and sends the stop alerts.
/// Returns false when the trip is no longer running (ended from the office, or automatically).
Future<bool> pushFix(String tripId, double lat, double lng, double? speed, double? acc) async {
  final r = await db.rpc('bus_fix', params: {'p_trip': tripId, 'p_lat': lat, 'p_lng': lng, 'p_speed': speed, 'p_acc': acc});
  return (r is Map ? r['running'] : true) != false;
}
