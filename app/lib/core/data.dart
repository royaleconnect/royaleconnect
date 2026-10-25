import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../auth/session.dart';
import 'config.dart';

/// Opens a file stored in the private `files` bucket through a short-lived signed URL.
Future<void> openStorageFile(String path) async {
  final url = await db.storage.from('files').createSignedUrl(path, 600);
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Thin data layer over PostgREST. Every query is already filtered by RLS; the app only shapes it.
/// The client is rebuilt whenever the session token changes, so every request carries it.
SupabaseClient db = SupabaseClient(AppConfig.supabaseUrl, AppConfig.supabaseAnonKey);
void setDbToken(String? token) {
  db = SupabaseClient(AppConfig.supabaseUrl, AppConfig.supabaseAnonKey, headers: token == null ? const {} : {'Authorization': 'Bearer $token'});
}

String _today() => DateTime.now().toIso8601String().substring(0, 10);

class FeeRow {
  final String id, title, status, dueOn, kind; final num amount; final String? paidOn, parentId, note;
  FeeRow(this.id, this.title, this.amount, this.dueOn, this.status, this.kind, this.paidOn, this.parentId, this.note);
  bool get paid => status == 'paid';
  bool get pending => status == 'pending';
  bool get isLate => kind == 'late_fee';
  int daysUntil([DateTime? from]) => DateTime.parse(dueOn).difference(from ?? DateTime.parse(_today())).inDays;
  bool get overdue => pending && daysUntil() < 0;
}

class FeeSummary {
  final List<FeeRow> rows;
  FeeSummary(this.rows);
  List<FeeRow> get unpaid => rows.where((r) => r.pending).toList();
  List<FeeRow> get overdue => unpaid.where((r) => r.overdue).toList();
  List<FeeRow> get dueSoon => unpaid.where((r) => !r.overdue && r.daysUntil() <= 30).toList();
  List<FeeRow> get upcoming => unpaid.where((r) => !r.overdue && r.daysUntil() > 30).toList();
  List<FeeRow> get paidRows => rows.where((r) => r.paid).toList();
  num get total => rows.where((r) => r.status != 'cancelled' && r.status != 'waived').fold(0, (a, r) => a + r.amount);
  num get paidAmount => paidRows.fold(0, (a, r) => a + r.amount);
  num get balance => unpaid.fold(0, (a, r) => a + r.amount);
  int get pct => total == 0 ? 0 : (paidAmount / total * 100).round();
}

/// Fees for the active student (the nightly job keeps late-fee rows current).
final feesProvider = FutureProvider.autoDispose<FeeSummary>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return FeeSummary([]);
  final data = await db.from('fee_ledger')
      .select('id,title,amount,due_on,status,paid_on,parent_ledger_id,note,fee_head:fee_head_id(kind),academic_year!inner(is_current)')
      .eq('student_id', s.id).eq('academic_year.is_current', true).order('due_on', ascending: true);
  return FeeSummary([for (final r in data) FeeRow(r['id'], r['title'], r['amount'] as num, r['due_on'], r['status'], r['fee_head']?['kind'] ?? 'other', r['paid_on'], r['parent_ledger_id'], r['note'])]);
});

class Notice { final String id, category, title, body, by, when, audience; final bool urgent, read; final String? file;
  Notice(this.id, this.category, this.title, this.body, this.by, this.when, this.audience, this.urgent, this.read, this.file); }

final noticesProvider = FutureProvider.autoDispose<List<Notice>>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return [];
  final data = await db.from('announcement')
      .select('id,category,title,body,attachment_path,sent_at,audience_all,audience_grade_ids,audience_section_ids,author:author_id(display_name),announcement_read(student_id)')
      .not('sent_at', 'is', null).order('sent_at', ascending: false).limit(50);
  return [for (final r in data) Notice(r['id'], r['category'], r['title'], r['body'], r['author']?['display_name'] ?? 'School office',
      r['sent_at'], r['audience_all'] == true ? 'Whole school' : 'Your grade', r['category'] == 'urgent',
      (r['announcement_read'] as List).any((x) => x['student_id'] == s.id), r['attachment_path'])];
});

Future<void> markNoticeRead(String noticeId, String studentId) =>
    db.from('announcement_read').upsert({'announcement_id': noticeId, 'student_id': studentId});

class DiaryEntry { final String id, kind, title, forDate, by; final String? body, subject, dueOn; final bool needsSubmission;
  DiaryEntry(this.id, this.kind, this.title, this.body, this.forDate, this.subject, this.by, this.dueOn, this.needsSubmission); }

final diaryProvider = FutureProvider.autoDispose.family<List<DiaryEntry>, String>((ref, isoDate) async {
  final data = await db.from('diary_entry')
      .select('id,kind,title,body,for_date,due_on,needs_submission,subject:subject_id(name),author:author_id(display_name)')
      .eq('for_date', isoDate).not('posted_at', 'is', null).order('created_at', ascending: true);
  return [for (final r in data) DiaryEntry(r['id'], r['kind'], r['title'], r['body'], r['for_date'], r['subject']?['name'], r['author']?['display_name'] ?? '', r['due_on'], r['needs_submission'] == true)];
});

/// Unread message count across the active student's conversations.
final unreadMessagesProvider = FutureProvider.autoDispose<int>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return 0;
  final data = await db.from('conversation').select('student_unread').eq('student_id', s.id);
  return data.fold<int>(0, (a, r) => a + ((r['student_unread'] ?? 0) as int));
});

/// Transport enrolment (null when the student is not on a bus) — decides whether the Bus tab shows.
final transportProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return null;
  final r = await db.from('transport_enrolment').select('route:route_id(id,name,bus_reg_no,morning_start,afternoon_start),stop:stop_id(name,seq,morning_eta,afternoon_eta)').eq('student_id', s.id).maybeSingle();
  return r;
});

/// One payment with its lines (receipt screen).
final paymentProvider = FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, id) async =>
    await db.from('payment').select('id,amount,mode,status,receipt_no,gateway_payment_id,paid_at,payment_line(amount,fee_ledger:fee_ledger_id(title))').eq('id', id).maybeSingle());

/// Payment history for the active student, newest first.
final paymentsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final s = ref.watch(sessionProvider).value?.active;
  if (s == null) return [];
  final data = await db.from('payment').select('id,amount,status,receipt_no,paid_at').eq('student_id', s.id).neq('status', 'created').order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});
