import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../core/config.dart';
import '../core/data.dart' show setDbToken;

/// A student as returned by the login functions.
class StudentRef {
  final String id, admissionNo, fullName;
  final String? grade, gradeCode, section;
  const StudentRef({required this.id, required this.admissionNo, required this.fullName, this.grade, this.gradeCode, this.section});
  factory StudentRef.fromJson(Map<String, dynamic> j) => StudentRef(
      id: j['id'], admissionNo: j['admission_no'], fullName: j['full_name'],
      grade: j['grade'], gradeCode: j['grade_code'], section: j['section']);
  Map<String, dynamic> toJson() => {'id': id, 'admission_no': admissionNo, 'full_name': fullName, 'grade': grade, 'grade_code': gradeCode, 'section': section};
  String get initials => fullName.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0]).join().toUpperCase();
  String get cls => '${gradeCode ?? ''}-${section ?? ''}';
}

/// Everything the app knows about who is signed in on this phone.
class Session {
  final String token;
  final String kind; // 'student' | 'crew' | 'staff'
  final List<StudentRef> students;
  final String? activeStudentId;
  final bool mustChangePassword;
  final Map<String, dynamic>? crew;
  final Map<String, dynamic>? staff;   // {id, name, email, roles, division} for kind == 'staff'
  const Session({required this.token, required this.kind, this.students = const [], this.activeStudentId, this.mustChangePassword = false, this.crew, this.staff});

  bool get isStaff => kind == 'staff';
  List<String> get roles => List<String>.from(staff?['roles'] ?? const []);
  bool hasRole(String r) => roles.contains(r);
  bool get isOffice => roles.any((r) => const ['office', 'it_admin', 'principal', 'vice_principal'].contains(r));

  StudentRef? get active => students.isEmpty ? null : students.firstWhere((s) => s.id == activeStudentId, orElse: () => students.first);
  Session copyWith({String? activeStudentId, List<StudentRef>? students, bool? mustChangePassword, String? token}) => Session(
      token: token ?? this.token, kind: kind, students: students ?? this.students,
      activeStudentId: activeStudentId ?? this.activeStudentId, mustChangePassword: mustChangePassword ?? this.mustChangePassword, crew: crew, staff: staff);

  Map<String, dynamic> toJson() => {'token': token, 'kind': kind, 'students': students.map((s) => s.toJson()).toList(), 'active': activeStudentId, 'mcp': mustChangePassword, 'crew': crew, 'staff': staff};
  factory Session.fromJson(Map<String, dynamic> j) => Session(
      token: j['token'], kind: j['kind'], students: (j['students'] as List? ?? []).map((e) => StudentRef.fromJson(Map<String, dynamic>.from(e))).toList(),
      activeStudentId: j['active'], mustChangePassword: j['mcp'] ?? false, crew: j['crew'] == null ? null : Map<String, dynamic>.from(j['crew']), staff: j['staff'] == null ? null : Map<String, dynamic>.from(j['staff']));
}

class AuthError implements Exception { final String message; AuthError(this.message); @override String toString() => message; }

/// Talks to the login edge functions and keeps the session on the device (secure storage).
class SessionController extends AsyncNotifier<Session?> {
  static const _store = FlutterSecureStorage();
  static const _key = 'rc_session';

  // On phones the session lives in the OS keychain; on the web the browser's storage is the only option anyway.
  Future<String?> _read() async => kIsWeb ? (await SharedPreferences.getInstance()).getString(_key) : _store.read(key: _key);
  Future<void> _write(String v) async { if (kIsWeb) { await (await SharedPreferences.getInstance()).setString(_key, v); } else { await _store.write(key: _key, value: v); } }
  Future<void> _clear() async { if (kIsWeb) { await (await SharedPreferences.getInstance()).remove(_key); } else { await _store.delete(key: _key); } }

  @override
  Future<Session?> build() async {
    final raw = await _read();
    if (raw == null) return null;
    final s = Session.fromJson(jsonDecode(raw));
    _applyToken(s.token);
    return s;
  }

  // every PostgREST call from now on carries our token → RLS applies the student_ids / staff_id claims
  void _applyToken(String token) => setDbToken(token);

  Future<Map<String, dynamic>> _call(String fn, Map<String, dynamic> body, {String? bearer}) async {
    final r = await http.post(Uri.parse('${AppConfig.functionsUrl}/$fn'),
        headers: {'content-type': 'application/json', 'apikey': AppConfig.supabaseAnonKey, if (bearer != null) 'authorization': 'Bearer $bearer'},
        body: jsonEncode(body));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 400) throw AuthError(j['error'] ?? 'Something went wrong.');
    return j;
  }

  Future<void> _save(Session s) async {
    _applyToken(s.token);
    await _write(jsonEncode(s.toJson()));
    state = AsyncData(s);
  }

  /// Admission number + password. `linkToExisting` keeps siblings already on this phone.
  Future<void> loginWithPassword(String admissionNo, String password, {bool linkToExisting = false}) async {
    final existing = linkToExisting ? (state.value?.students.map((s) => s.id).toList() ?? []) : <String>[];
    final j = await _call('login-student', {'admission_no': admissionNo, 'password': password, 'link_to': existing, 'device_label': 'app'});
    final students = (j['students'] as List).map((e) => StudentRef.fromJson(Map<String, dynamic>.from(e))).toList();
    final newId = students.firstWhere((s) => s.admissionNo == admissionNo.trim().toUpperCase(), orElse: () => students.first).id;
    await _save(Session(token: j['token'], kind: 'student', students: students, activeStudentId: linkToExisting ? state.value?.activeStudentId ?? newId : newId, mustChangePassword: j['must_change_password'] == true));
  }

  /// Staff: school email + password.
  Future<void> loginStaff(String email, String password) async {
    final j = await _call('login-staff', {'email': email, 'password': password, 'device_label': 'app'});
    await _save(Session(token: j['token'], kind: 'staff', staff: Map<String, dynamic>.from(j['staff']), mustChangePassword: j['must_change_password'] == true));
  }

  Future<void> changeStaffPassword(String newPassword, {String? current}) async {
    final s = state.value!;
    await _call('password', {'action': 'change_staff', 'new_password': newPassword, if (current != null) 'current_password': current}, bearer: s.token);
    await _save(s.copyWith(mustChangePassword: false));
  }

  Future<String> requestOtp(String phone) async => (await _call('login-otp', {'phone': phone}))['kind'];

  Future<void> loginWithOtp(String phone, String code) async {
    final j = await _call('login-otp', {'phone': phone, 'code': code, 'device_label': 'app'});
    if (j['kind'] == 'crew') {
      await _save(Session(token: j['token'], kind: 'crew', crew: Map<String, dynamic>.from(j['crew'])));
      return;
    }
    final students = (j['students'] as List).map((e) => StudentRef.fromJson(Map<String, dynamic>.from(e))).toList();
    await _save(Session(token: j['token'], kind: 'student', students: students, activeStudentId: students.length == 1 ? students.first.id : null));
  }

  Future<void> changePassword(String newPassword, {String? current}) async {
    final s = state.value!;
    await _call('password', {'action': 'change', 'student_id': s.active!.id, 'new_password': newPassword, if (current != null) 'current_password': current}, bearer: s.token);
    await _save(s.copyWith(mustChangePassword: false));
  }

  Future<void> selectStudent(String id) async => _save(state.value!.copyWith(activeStudentId: id));

  Future<void> signOut() async {
    await _clear();
    setDbToken(null);
    state = const AsyncData(null);
  }
}

final sessionProvider = AsyncNotifierProvider<SessionController, Session?>(SessionController.new);


/// The opening splash stays for 4 seconds every time the app starts.
class SplashDone extends Notifier<bool> {
  @override
  bool build() { Timer(const Duration(seconds: 4), () => state = true); return false; }
}
final splashDoneProvider = NotifierProvider<SplashDone, bool>(SplashDone.new);

/// With two or more children on the phone, the family picks one each time the app opens.
class ChildPicked extends Notifier<bool> {
  @override
  bool build() => false;
  void done() => state = true;
}
final childPickedProvider = NotifierProvider<ChildPicked, bool>(ChildPicked.new);
