import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'data2.dart' show sendMessage;

/// Works without internet + opens instantly (families).
///
/// The last good answer of a few family screens (today's diary, notices, timetable, profile / ID card, fees) is kept
/// on the phone. When the network fails, that saved copy is shown with a thin bar: "No internet · showing what was
/// saved at 8:42 am". The first time a screen opens after the app starts, the saved copy is shown at once and the
/// fresh answer replaces it a moment later (so the app opens instantly even with internet).
///
/// In provider code:
///   final rows = await offlineRows(ref, 'notices|${s.id}', () => db.from('announcement').select(...));
///   final one  = await offlineRow(ref, 'profile|${s.id}', () => db.from('student').select(...).maybeSingle());
/// Keys must include the student (or section) id, so one child's data never shows for another.

const _prefix = 'rc_off_';
const _outboxKey = 'rc_outbox';

/// When the data on screen was saved (null = online, showing live data). Drives [OfflineBanner].
final offlineSavedAt = ValueNotifier<DateTime?>(null);

/// Goes up by one each time the internet comes back (screens can listen to retry their own work).
final onlineAgain = ValueNotifier<int>(0);

final _mem = <String, (DateTime, Object?)>{};        // answers fetched in this run (a few seconds old at most)
final _inflight = <String, Future<Object?>>{};       // one network call per key at a time
final _openedThisRun = <String>{};                   // the "instant open" happens once per key per run
final _retry = <VoidCallback>[];                     // screens to refresh when the internet is back
Timer? _probe;
bool _pruned = false;

/// True when the error means "could not reach the server" (not "the server said no").
bool isNetworkError(Object e) {
  if (e is TimeoutException) return true;
  final t = e.toString();
  final looksOffline = t.contains('SocketException') || t.contains('ClientException') || t.contains('Failed host lookup') ||
      t.contains('XMLHttpRequest') || t.contains('Failed to fetch') || t.contains('Connection closed') || t.contains('Connection refused') ||
      t.contains('Network is unreachable') || t.contains('HandshakeException') || t.contains('Connection reset');
  return looksOffline;   // a PostgrestException / AuthException without these words means the server answered
}

Future<(DateTime, Object?, String)?> _read(SharedPreferences p, String key) async {
  final Object? got; try { got = p.get('$_prefix$key'); } catch (_) { return null; }
  final raw = got is String ? got : null;
  if (raw == null) return null;
  final i = raw.indexOf('|');
  if (i < 0) return null;
  try {
    final body = raw.substring(i + 1);
    return (DateTime.fromMillisecondsSinceEpoch(int.parse(raw.substring(0, i))), jsonDecode(body), body);
  } catch (_) { return null; }
}

Future<void> _save(String key, String json) async {
  try { (await SharedPreferences.getInstance()).setString('$_prefix$key', '${DateTime.now().millisecondsSinceEpoch}|$json'); } catch (_) {}
}

/// Saved copies older than three weeks are thrown away (once per run).
void _prune(SharedPreferences p) {
  if (_pruned) return;
  _pruned = true;
  final old = DateTime.now().subtract(const Duration(days: 21)).millisecondsSinceEpoch;
  for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
    final got = p.get(k); final v = got is String ? got : '';
    final t = int.tryParse(v.split('|').first) ?? 0;
    if (t < old) p.remove(k);
  }
}

/// Fetches through the network, keeps a copy, and falls back to the copy when there is no internet.
/// [fetch] must return JSON-friendly data (maps, lists, strings, numbers, bools, null) — PostgREST rows are.
Future<Object?> offlineGuard(Ref<Object?> ref, String key, Future<Object?> Function() fetch) async {
  var alive = true;
  ref.onDispose(() => alive = false);
  void refresh() { if (alive) { try { ref.invalidateSelf(); } catch (_) {} } }

  final m = _mem[key];
  if (m != null && DateTime.now().difference(m.$1).inSeconds < 4) return m.$2;   // just fetched by the quiet refresh below

  SharedPreferences? p;
  try { p = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3)); } catch (_) {}
  if (p != null) { try { _prune(p); } catch (_) {} }
  final saved = p == null ? null : await _read(p, key);

  // NB: the clean-up below must not return anything. `() => _inflight.remove(key)` would hand back this very future,
  // and whenComplete would then wait for itself for ever (the "loads for ever" fault of Nov 2026).
  Future<Object?> net() => _inflight[key] ??= fetch().timeout(const Duration(seconds: 20)).then((v) {
        final json = jsonEncode(v);
        _mem[key] = (DateTime.now(), jsonDecode(json));
        _save(key, json);
        _backOnline();
        return _mem[key]!.$2;
      }).whenComplete(() { _inflight.remove(key); });

  // first open in this run with a saved copy: show it at once, refresh quietly behind it
  if (saved != null && _openedThisRun.add(key)) {
    net().then((v) { if (jsonEncode(v) != saved.$3) refresh(); }, onError: (Object e) { if (isNetworkError(e)) _wentOffline(saved.$1, refresh); });
    return saved.$2;
  }
  _openedThisRun.add(key);
  try {
    return await net();
  } catch (e) {
    if (saved != null && isNetworkError(e)) { _wentOffline(saved.$1, refresh); return saved.$2; }
    rethrow;
  }
}

/// A list of rows (e.g. `db.from('x').select(...)`), saved for offline use.
Future<List<Map<String, dynamic>>> offlineRows(Ref<Object?> ref, String key, Future<List<dynamic>> Function() fetch) async {
  final v = await offlineGuard(ref, key, fetch);
  return [for (final r in (v as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
}

/// One row or null (e.g. `...maybeSingle()`), saved for offline use.
Future<Map<String, dynamic>?> offlineRow(Ref<Object?> ref, String key, Future<Map<String, dynamic>?> Function() fetch) async {
  final v = await offlineGuard(ref, key, fetch);
  return v == null ? null : Map<String, dynamic>.from(v as Map);
}

void _wentOffline(DateTime savedAt, VoidCallback retry) {
  final cur = offlineSavedAt.value;
  if (cur == null || savedAt.isBefore(cur)) offlineSavedAt.value = savedAt;
  _retry.add(retry);
  _startProbe();
}

/// Every 15 s while offline: is the school server reachable again?
void _startProbe() {
  _probe ??= Timer.periodic(const Duration(seconds: 15), (_) async {
    try {
      await http.get(Uri.parse('${AppConfig.supabaseUrl}/auth/v1/health'), headers: {'apikey': AppConfig.supabaseAnonKey}).timeout(const Duration(seconds: 6));
      _backOnline();   // any answer at all means the internet is back
    } catch (_) {}
  });
}

void _backOnline() {
  final wasOffline = offlineSavedAt.value != null || _probe != null;
  if (!wasOffline) return;
  _probe?.cancel(); _probe = null;
  offlineSavedAt.value = null;
  final todo = List.of(_retry); _retry.clear();
  for (final f in todo) { f(); }
  onlineAgain.value++;
  flushOutbox();
}

/// Removes every saved copy and unsent message (on sign-out, so the next person on this phone sees nothing).
Future<void> clearOfflineCache() async {
  _mem.clear(); _openedThisRun.clear(); _retry.clear();
  offlineSavedAt.value = null;
  final p = await SharedPreferences.getInstance();
  for (final k in p.getKeys().where((k) => k.startsWith(_prefix) || k == _outboxKey).toList()) { await p.remove(k); }
}

// ---------------------------------------------------------------- messages typed without internet
/// Messages waiting to go (oldest first): {c: conversation id, b: text, at: when typed}.
Future<List<Map<String, dynamic>>> _outbox() async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString(_outboxKey);
    return raw == null ? [] : [for (final x in jsonDecode(raw) as List) Map<String, dynamic>.from(x as Map)];
  } catch (_) { return []; }
}
Future<void> _setOutbox(List<Map<String, dynamic>> list) async {
  final p = await SharedPreferences.getInstance();
  list.isEmpty ? await p.remove(_outboxKey) : await p.setString(_outboxKey, jsonEncode(list));
}

/// Keeps a text message to send when the internet is back.
Future<void> queueMessage(String conversationId, String body) async {
  final list = await _outbox();
  list.add({'c': conversationId, 'b': body, 'at': DateTime.now().toIso8601String()});
  await _setOutbox(list);
  _startProbe();
}

/// Texts still waiting for this conversation.
Future<List<String>> queuedMessages(String conversationId) async => [for (final m in await _outbox()) if (m['c'] == conversationId) '${m['b']}'];

bool _flushing = false;
/// Sends the waiting messages in order; stops at the first one that still cannot go. Returns how many went.
Future<int> flushOutbox() async {
  if (_flushing) return 0;
  _flushing = true;
  var sent = 0;
  try {
    final list = await _outbox();
    while (list.isNotEmpty) {
      final m = list.first;
      try {
        await sendMessage('${m['c']}', body: '${m['b']}');
      } catch (e) {
        if (isNetworkError(e)) { _startProbe(); break; }   // still offline: try again later
        // the server refused it (e.g. the chat was closed): drop it rather than retrying forever
      }
      list.removeAt(0); sent++;
      await _setOutbox(list);
    }
  } finally { _flushing = false; }
  if (sent > 0) onlineAgain.value++;
  return sent;
}

// ---------------------------------------------------------------- the thin bar
/// "No internet · showing what was saved at 8:42 am" — slides in at the top only while saved data is shown.
/// With [child], the bar sits above it (the child keeps its place, so nothing reloads when the bar comes and goes).
class OfflineBanner extends StatelessWidget {
  final Widget? child;
  const OfflineBanner({super.key, this.child});

  static String label(DateTime at) {
    final now = DateTime.now();
    final time = DateFormat('h:mm a').format(at).toLowerCase();
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    return 'No internet · showing what was saved ${sameDay ? 'at $time' : 'on ${DateFormat('d MMM').format(at)}, $time'}';
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DateTime?>(valueListenable: offlineSavedAt, builder: (context, at, _) {
        final bar = AnimatedSize(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic, alignment: Alignment.topCenter,
            child: at == null ? const SizedBox(width: double.infinity) : Material(color: const Color(0xFF33302F), child: SafeArea(bottom: false, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(children: [
                const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFFF3DE9C)),
                const SizedBox(width: 8),
                Expanded(child: Text(label(at), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFF3DE9C), fontSize: 12, fontWeight: FontWeight.w600))),
              ]),
            ))));
        if (child == null) return bar;
        return Column(children: [
          bar,
          Expanded(child: MediaQuery.removePadding(context: context, removeTop: at != null, child: child!)),
        ]);
      });
}
