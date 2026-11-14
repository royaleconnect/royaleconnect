import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:intl/intl.dart' show DateFormat;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/session.dart';
import 'data.dart';
import 'cache.dart';
import 'offline.dart';

/// Data for the secondary screens. Everything is read through RLS; the app only shapes it.

String _d(DateTime d) => d.toIso8601String().substring(0, 10);

/// Current enrolment of the active student: section, grade, class teacher, roll no.
final enrolmentProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  ref.cacheFor();
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return null;
  return await offlineRow(ref, 'enrol|${s.id}', () async => await db.from('enrolment')
      .select('roll_no,is_current,section:section_id(id,name,status,placeholder,class_teacher:class_teacher_id(display_name,phone),grade:grade_id(id,code,name,division)),academic_year:academic_year_id(id,label)')
      .eq('student_id', s.id).eq('is_current', true).maybeSingle());
});

/// The section name to show, or null while it is still to be announced (new year, not published yet).
String? shownSection(Map<String, dynamic>? sec) =>
    sec == null || sec['placeholder'] == true || sec['status'] == 'planned' || sec['status'] == 'ready' ? null : sec['name'] as String?;

/// Full profile (no Aadhaar / APAAR / PEN — those columns are never selected).
final profileProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  ref.cacheFor();
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return null;
  return await offlineRow(ref, 'profile|${s.id}', () async => await db.from('student').select('admission_no,full_name,dob,gender,blood_group,house,admission_type,address,father_name,mother_name,guardian_name,photo_path,family_phone(phone,label)').eq('id', s.id).maybeSingle());
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
  ref.cacheFor();
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
  final data = await db.from('message').select('id,sender_kind,body,attachment_path,attachment_name,attachment_mime,created_at,seen_at,edited_at,deleted_at').eq('conversation_id', conversationId).order('created_at', ascending: true);
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
  ref.cacheFor();
  final e = await ref.watch(enrolmentProvider.future);
  if (e == null) return [];
  return offlineRows(ref, 'timetable|${e['section']['id']}', () async => await db.from('timetable_slot').select('weekday,period,starts_at,label,needs_kit,subject:subject_id(name,short),staff:staff_id(display_name)').eq('section_id', e['section']['id']).order('weekday', ascending: true).order('period', ascending: true));
});

final examsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  final e = await ref.watch(enrolmentProvider.future);
  if (e == null) return [];
  final data = await db.from('exam').select('id,name,term,starts_on,ends_on,max_marks,note,exam_paper(on_date,portions,subject:subject_id(name))')
      .eq('grade_id', e['section']['grade']['id']).not('published_at', 'is', null).order('starts_on', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});


final starProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
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
  ref.cacheFor();
  // this year and next year together (from 1 March some classes are already in the new year)
  final from = DateTime.now().subtract(const Duration(days: 300)).toIso8601String().substring(0, 10);
  final data = await db.from('calendar_event').select('title,starts_on,ends_on,kind,grades,note').gte('starts_on', from).order('starts_on', ascending: true);
  return List<Map<String, dynamic>>.from(data);
});

final reportCardsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return [];
  // the earlier admission too (e.g. Grade 10 before re-admission in Grade 11) — one history
  final me = await db.from('student').select('previous_student_id').eq('id', s.id).maybeSingle();
  final ids = [s.id, if (me?['previous_student_id'] != null) me!['previous_student_id'] as String];
  final data = await db.from('report_card').select('id,term,working_days,days_present,remarks,published_at,academic_year:academic_year_id(label)').inFilter('student_id', ids).eq('status', 'published').order('published_at', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

// ---------------------------------------------------------------- leave
final leavesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return [];
  final data = await db.from('leave_request').select('id,from_date,to_date,reason,note,status,decided_at,decided_by_staff:decided_by(display_name)').eq('student_id', s.id).order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

Future<void> applyLeave(String studentId, DateTime from, DateTime to, String reason, String? note) =>
    db.from('leave_request').insert({'student_id': studentId, 'from_date': _d(from), 'to_date': _d(to), 'reason': reason, 'note': note});

// ---------------------------------------------------------------- gallery
final momentsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return [];
  final e = await ref.watch(enrolmentProvider.future);
  if (e == null) return [];
  // only the active child's class (or whole grade) — a family login can cover siblings in other classes
  final data = await db.from('moment').select('id,caption,photo_paths,posted_at,posted_by_staff:posted_by(display_name),moment_like(student_id)')
      .or('section_id.eq.${e['section']['id']},grade_id.eq.${e['section']['grade']['id']}').not('posted_at', 'is', null).order('posted_at', ascending: false).limit(40);
  return List<Map<String, dynamic>>.from(data);
});

Future<void> toggleLike(String momentId, String studentId, bool liked) async {
  if (viewOnlyMode) return;
  liked
      ? await db.from('moment_like').delete().eq('moment_id', momentId).eq('student_id', studentId)
      : await db.from('moment_like').insert({'moment_id': momentId, 'student_id': studentId});
}

final albumsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  // oldest first: a school year reads like a story, July onwards (a new album gets a red “New” for 7 days)
  final data = await db.from('album').select('id,title,event_date,cover_path,team,created_at,album_photo(id,path,sort_order)').order('event_date', ascending: true);
  return List<Map<String, dynamic>>.from(data);
});

// ---------------------------------------------------------------- feedback
Future<void> sendFeedback(String? studentId, String? sectionId, String category, String subject, String body, bool anonymous) =>
    db.from('feedback').insert({'student_id': anonymous ? null : studentId, 'section_id': sectionId, 'category': category, 'subject': subject, 'body': body, 'anonymous': anonymous});

// ---------------------------------------------------------------- transport
final routeDetailProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  ref.cacheFor();
  final t = await ref.watch(transportProvider.future);
  if (t == null) return null;
  final r = await db.from('route').select('id,name,bus_reg_no,morning_start,afternoon_start,driver:driver_staff_id(display_name,phone),conductor:conductor_staff_id(display_name,phone),route_stop(id,seq,name,lat,lng,morning_eta,afternoon_eta)').eq('id', t['route']['id']).single();
  return {...r, 'my_stop': t['stop']};
});

/// '3:52 pm' — 12-hour times everywhere on the bus pages.
String time12(DateTime d) => DateFormat('h:mm a').format(d.toLocal()).toLowerCase();
String time12Iso(String? iso) => iso == null ? '' : time12(DateTime.parse(iso));

/// True while the parent Bus page is on screen (set by the page itself). Fast polling happens only then.
final busPageVisibleProvider = StateProvider<bool>((ref) => false);

/// Everything the parent Bus page shows, from one server call (`bus_family`): the bus, this child's private pickup pin,
/// the running trip with the time to the pin, today's driver and bus assistant, the last trip and the next trip.
/// Refreshes every 3 s ONLY while a trip is running, the Bus page is visible and the app is in front; otherwise every 2 minutes.
/// Stops completely when the Bus page is closed (nothing else watches it).
final busFamilyProvider = StreamProvider.autoDispose<Map<String, dynamic>?>((ref) {
  final s = ref.watch(sessionProvider).value?.active;
  final ctrl = StreamController<Map<String, dynamic>?>();
  if (s == null) { ctrl.add(null); ctrl.close(); return ctrl.stream; }
  var alive = true, busy = false, front = true, again = false;
  Timer? timer; Map<String, dynamic>? last; var got = false;
  Future<void> tick() async {
    if (!alive) return;
    if (busy) { again = true; return; }
    busy = true; timer?.cancel();
    try {
      final r = await db.rpc('bus_family', params: {'p_student': s.id});
      last = r == null ? null : Map<String, dynamic>.from(r as Map); got = true;
      if (alive) ctrl.add(last);
    } catch (e) {
      if (alive && !got) ctrl.addError(e);   // a dropped network moment later on: keep the last picture on screen
    } finally { busy = false; }
    if (!alive) return;
    if (again) { again = false; tick(); return; }
    final fast = last?['trip'] != null && front && ref.read(busPageVisibleProvider);
    timer = Timer(fast ? const Duration(seconds: 3) : const Duration(minutes: 2), tick);
  }
  final life = AppLifecycleListener(
    onResume: () { front = true; tick(); },
    onHide: () => front = false,
    onPause: () => front = false,
  );
  ref.listen<bool>(busPageVisibleProvider, (_, v) { if (v) tick(); });
  ref.onDispose(() { alive = false; timer?.cancel(); life.dispose(); ctrl.close(); });
  tick();
  return ctrl.stream;
});

/// Same provider under the name the Release H brief uses (the parent Bus page's live trip).
final liveTripProvider = busFamilyProvider;

/// One line for the Home "Your day" card: 'Bus 7 · pickup about 7:32 am' (null when the child is not on a bus).
final busHomeLineProvider = FutureProvider.autoDispose<String?>((ref) async {
  ref.cacheFor(const Duration(minutes: 30));
  final t = await ref.watch(transportProvider.future);
  if (t == null) return null;
  final name = '${t['route']?['name'] ?? ''}';
  final bus = RegExp(r'\d+').firstMatch(name)?.group(0) ?? name;
  final at = await ref.watch(myPickupTimeProvider.future);
  return 'Bus $bus${at == null ? '' : ' · pickup about $at'}';
});

/// The child's own pickup time in 12-hour format ('7:32 am'): learned from recent trips passing the pickup pin,
/// else the stop time, else the bus start time. Null when the child is not on a bus. For the Home "Your day" card.
final myPickupTimeProvider = FutureProvider.autoDispose<String?>((ref) async {
  ref.cacheFor(const Duration(minutes: 30));
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return null;
  final t = await ref.watch(transportProvider.future);
  if (t == null) return null;
  try { return (await db.rpc('my_pickup_time', params: {'p_student': s.id})) as String?; } catch (_) { return null; }
});

/// Save this child's pickup point (the family, or the transport office on Check pins). Only that family, transport / office / IT
/// and the crew of that bus can ever read it.
Future<void> savePin(String studentId, double lat, double lng) =>
    db.rpc('pin_set', params: {'p_student': studentId, 'p_lat': lat, 'p_lng': lng});

final etaPrefProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return {};
  return await db.from('eta_alert_pref').select().eq('student_id', s.id).maybeSingle() ?? {'student_id': s.id, 'trip_started': true, 'ten_min': true, 'two_stops': true, 'at_stop': true, 'trip_ended': false};
});

Future<void> saveEtaPref(Map<String, dynamic> p) => db.from('eta_alert_pref').upsert(p);

// ---------------------------------------------------------------- crew side (driver / bus assistant)
/// Me, my usual bus, the running trip (with the children's pins — first names only), the school gate. One server call.
final crewStateProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final s = ref.watch(sessionProvider).value;
  if (s == null || s.kind != 'crew') return null;
  final r = await db.rpc('crew_state');
  return r == null ? null : Map<String, dynamic>.from(r as Map);
});

/// "Which bus today?" → {ok, bus, running, mine, message}
Future<Map<String, dynamic>> checkBus(String bus) async => Map<String, dynamic>.from(await db.rpc('crew_check_bus', params: {'p_bus': bus}) as Map);

/// Start the trip on that bus (morning / afternoon from the clock), or take over the bus that is already running.
Future<String> crewStart(String bus, double? lat, double? lng, {bool takeOver = false}) async {
  final r = await db.rpc('crew_start', params: {'p_bus': bus, 'p_device': await deviceId(), 'p_lat': lat, 'p_lng': lng, 'p_take_over': takeOver});
  return (r as Map)['trip_id'] as String;
}

/// This phone's own id (made once, kept on the phone). The trip remembers which phone sends its location.
String? _deviceId;
Future<String> deviceId() async {
  if (_deviceId != null) return _deviceId!;
  final p = await SharedPreferences.getInstance();
  var id = p.getString('rc_device_id');
  if (id == null) {
    final r = math.Random.secure();
    id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await p.setString('rc_device_id', id);
  }
  return _deviceId = id;
}

/// End a trip. Crew: the morning trip only at school (the server checks). Transport / office / IT: any trip, anywhere.
Future<void> endTrip(String tripId) => db.rpc('end_trip', params: {'p_trip': tripId});

/// This phone takes over sending the location (the other crew phone stops).
Future<void> takeOverTrip(String tripId) async { await db.rpc('take_over_trip', params: {'p_trip': tripId, 'p_device': await deviceId()}); }

/// One GPS position. The server updates the live position, keeps history every 10 s, and sends the alerts.
/// Returns {running: false} when the trip has ended, {elsewhere: true} when another phone is sending.
Future<Map<String, dynamic>> pushFix(String tripId, double lat, double lng, double? speed, double? acc) async {
  final r = await db.rpc('bus_fix', params: {'p_trip': tripId, 'p_lat': lat, 'p_lng': lng, 'p_speed': speed, 'p_acc': acc, 'p_device': await deviceId()});
  return r is Map ? Map<String, dynamic>.from(r) : {'running': true};
}

/// Where the bus has been on this trip: [[lat, lng], …] every 10 s.
Future<List<List<double>>> tripTrail(String tripId) async {
  final r = await db.rpc('trip_trail', params: {'p_trip': tripId});
  return [for (final p in (r as List)) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]];
}

// ---------------------------------------------------------------- staff side (transport in-charge / office / IT)
/// Trips running now (Transport page). Refreshed every 15 s while the page is open.
final busRunningProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
  var alive = true; ref.onDispose(() => alive = false);
  while (alive) {
    try { yield List<Map<String, dynamic>>.from(await db.rpc('bus_running') as List); } catch (_) {}
    await Future.delayed(const Duration(seconds: 15));
  }
});

final busRoutesProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  ref.cacheFor();
  return List<Map<String, dynamic>>.from(await db.from('route').select('id,name,bus_reg_no').eq('active', true).order('name', ascending: true));
});

/// Check pins: the children of one bus with their pins.
final pinsForRouteProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, routeId) async =>
    List<Map<String, dynamic>>.from(await db.rpc('pins_for_route', params: {'p_route': routeId}) as List));

// ---------------------------------------------------------------- map maths
/// Straight-line distance in metres.
double metresBetween(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final a = math.pow(math.sin(rad(lat2 - lat1) / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(rad(lng2 - lng1) / 2), 2);
  return 6371000 * 2 * math.asin(math.min(1, math.sqrt(a)));
}

/// '600 m' / '2.4 km'
String distText(num m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${(m / 10).round() * 10} m';

/// Stops in the order the bus visits them (morning: stop order; afternoon: reverse).
List<Map<String, dynamic>> travelOrder(List<Map<String, dynamic>> stops, bool morning) {
  final s = List<Map<String, dynamic>>.from(stops)..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
  return morning ? s : s.reversed.toList();
}

/// Road distance and minutes from the bus to a stop, going through the stops in between.
/// Roads are ~35% longer than a straight line; city school-bus speed ~18 km/h including stops.
(double metres, int minutes) etaTo(double busLat, double busLng, List<Map<String, dynamic>> order, int fromIdx, int toIdx) {
  if (fromIdx < 0 || toIdx < fromIdx || toIdx >= order.length) return (0.0, 0);
  var m = 0.0;
  var lat = busLat, lng = busLng;
  for (var i = fromIdx; i <= toIdx; i++) {
    final a = order[i]['lat'], b = order[i]['lng'];
    if (a == null || b == null) continue;
    final la = (a as num).toDouble(), lo = (b as num).toDouble();
    m += metresBetween(lat, lng, la, lo);
    lat = la; lng = lo;
  }
  m *= 1.35;
  return (m, math.max(1, (m / 1000 / 18 * 60).round()));
}
