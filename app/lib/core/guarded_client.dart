import 'dart:async';
import 'package:http/http.dart' as http;

/// Database calls that only READ (they change nothing), so it is safe to give them a time limit and to try once more.
/// Calls that save something (a payment, marks, attendance) are never cut short or sent twice.
const readOnlyCalls = <String>{
  'admin_dashboard',
  'admin_overview',
  'admin_student_index',
  'announcement_stats',
  'approvals_inbox',
  'approvals_inbox_leavings',
  'attendance_for_report',
  'attendance_register',
  'attendance_sheet',
  'attendance_summary',
  'bus_family',
  'bus_running',
  'certificate_prefill',
  'certificates_pending',
  'class_logins',
  'concession_list',
  'council_open_election',
  'council_results',
  'cover_sections',
  'crew_check_bus',
  'data_check_list',
  'diary_check',
  'exam_results',
  'fee_day_sheet',
  'fee_dues_matrix',
  'fee_dues_summary',
  'fee_pending',
  'fee_remind_status',
  'fee_report_cancelled',
  'fee_report_concessions',
  'fee_report_dues',
  'fee_report_failed_total',
  'fee_report_months',
  'fee_report_payments',
  'find_students',
  'house_can_add',
  'house_of',
  'house_points_totals',
  'id_card_rows',
  'id_cards_all_ready',
  'leaving_fees',
  'link_list',
  'marks_sheet',
  'marks_status',
  'monthly_report',
  'my_birthday',
  'my_list',
  'my_pickup_time',
  'not_using_app',
  'notice_readers',
  'office_glance',
  'office_leaving_check',
  'office_never_logged_in',
  'office_notice_report',
  'office_strength',
  'office_students',
  'pins_for_route',
  'plan_overview',
  'plan_students',
  'principal_morning',
  'promotion_of',
  'promotion_sheet',
  'report_card_data',
  'report_missing',
  'report_views',
  'school_home',
  'staff_birthdays',
  'staff_directory',
  'staff_holdings',
  'staff_id_rows',
  'staff_morning_brief',
  'staff_quick_search',
  'staff_today',
  'strength_views',
  'student_extra_for_cert',
  'student_marks',
  'student_pending_correction',
  'student_profile',
  'students_counts',
  'system_health',
  'tc_board_classes',
  'tc_board_students',
  'thanks_my_teachers',
  'thanks_wall',
  'today_extras',
  'trip_trail',
  'verify_document',
  'vote_link_open',
  'week_summary',
  'year_end_status',
  'year_for_grade',
  'year_move_plan',
  'year_review',
};

/// The connection every request goes through. A read that gets no answer in [_limit] is tried once more; if that also
/// gets no answer the page shows "taking too long" instead of loading for ever.
class GuardedClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  static const _limit = Duration(seconds: 15);

  bool _isRead(http.BaseRequest r) {
    final p = r.url.path;
    if (!p.contains('/rest/v1/')) return false;                 // files and sign-in keep their own pace
    if (r.method == 'GET' || r.method == 'HEAD') return true;   // reading a table
    final i = p.indexOf('/rpc/');
    return r.method == 'POST' && i >= 0 && readOnlyCalls.contains(p.substring(i + 5));
  }

  http.BaseRequest _copy(http.BaseRequest r) {
    final c = http.Request(r.method, r.url)..headers.addAll(r.headers)..followRedirects = r.followRedirects;
    if (r is http.Request) c.bodyBytes = r.bodyBytes;
    return c;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!_isRead(request) || request is! http.Request) return _inner.send(request);
    final again = _copy(request);
    try {
      return await _inner.send(request).timeout(_limit);
    } on TimeoutException {
      return _inner.send(again).timeout(_limit, onTimeout: () => throw TimeoutException('slow', _limit));
    }
  }

  @override
  void close() => _inner.close();
}
