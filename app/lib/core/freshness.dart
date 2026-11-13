import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/session.dart';
import '../screens/desk_screen.dart' show deskMessagesProvider;
import '../screens/my_list.dart' show myListProvider;
import '../screens/notice_extras.dart' show noticeExtrasProvider;
import 'data.dart';
import 'data2.dart';
import 'data3.dart';

/// Keeps what the family sees up to date: when the app comes back to the front, and when a notification arrives or is
/// tapped, the family's screens fetch their data again quietly (the old data stays on screen until the new arrives).
/// So a new notice opened from a notification is always there — never "no longer available".
DateTime _last = DateTime(2000);

void refreshFamilyData(WidgetRef ref, {bool force = false}) {
  final s = ref.read(sessionProvider).value;
  if (s == null || s.kind != 'student') return;
  final now = DateTime.now();
  if (!force && now.difference(_last).inSeconds < 20) return;   // coming back twice in a few seconds: once is enough
  _last = now;
  for (final p in <ProviderOrFamily>[
    noticesProvider, noticeExtrasProvider, feesProvider, paymentsProvider, unreadMessagesProvider, conversationsProvider,
    myListProvider, homeworkDueProvider, diaryProvider, latestDiaryProvider, reportCardsProvider, calendarProvider,
    deskMessagesProvider, appSettingsProvider, timetableProvider, homeworkForProvider, transportProvider, examsProvider,
  ]) {
    ref.invalidate(p);
  }
  if (force) { for (final p in <ProviderOrFamily>[enrolmentProvider, profileProvider, starProvider, momentsProvider, albumsProvider]) { ref.invalidate(p); } }
}
