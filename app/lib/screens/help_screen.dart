import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/session.dart';
import '../core/config.dart';
import '../core/data.dart';
import '../core/help_content.dart';
import '../core/theme.dart';
import '../staff/staff_shell.dart' show StaffPage, Panel;
import '../widgets/common.dart';
import 'family_screens.dart' show callNumber;

/// The round "Help" button at the bottom right of Home (parents) and Overview (staff) — on phones and the website.
class HelpFab extends StatelessWidget {
  final VoidCallback onTap;
  const HelpFab({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
        heroTag: 'help', onPressed: onTap, tooltip: 'Help — how to use the app',
        backgroundColor: Brand.crimson, foregroundColor: Colors.white, elevation: 4,
        icon: const Icon(Icons.help_outline_rounded, size: 24),
        label: const Text('Help', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      );
}

const _tabRoutes = {'/', '/fees', '/diary', '/announcements', '/bus', '/reports'};

/// Help for parents & students ([staff] = false) or for teachers & office ([staff] = true).
class HelpScreen extends ConsumerStatefulWidget {
  final bool staff;
  const HelpScreen({super.key, required this.staff});
  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  final search = TextEditingController();
  String q = '';
  String? topic, openId;
  final voted = <String>{};

  List<HelpItem> get all => widget.staff ? staffHelp : familyHelp;
  List<HelpTopic> get topics => widget.staff ? staffTopics : familyTopics;

  void _vote(HelpItem h, bool yes) {
    setState(() => voted.add(h.id));
    db.from('help_feedback').insert({'item': h.id, 'helpful': yes, 'audience': widget.staff ? 'staff' : 'family'}).then((_) {}, onError: (_) {});
  }

  void _open(String route) {
    if (widget.staff || _tabRoutes.contains(route)) {
      context.go(route);
    } else {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final query = q.trim();
    final List<HelpItem> shown;
    final String heading;
    if (query.isNotEmpty) {
      shown = all.where((h) => h.matches(query)).toList();
      heading = shown.isEmpty ? 'NO ANSWER FOUND FOR “${query.toUpperCase()}”' : '${shown.length} ANSWER${shown.length == 1 ? '' : 'S'} FOR “${query.toUpperCase()}”';
    } else if (topic != null) {
      shown = all.where((h) => h.topic == topic).toList();
      heading = topic!.toUpperCase();
    } else {
      shown = all.where((h) => h.popular).toList();
      heading = 'MOST ASKED';
    }
    // with a search, the best answer is already open
    final autoOpen = query.isNotEmpty && shown.isNotEmpty && openId == null ? shown.first.id : null;

    final searchBox = TextField(
      controller: search,
      onChanged: (v) => setState(() { q = v; openId = null; }),
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: widget.staff ? 'Type a word — marks, diary, notice…' : 'Type a word — fees, bus, password…',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: q.isEmpty ? null : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded), onPressed: () => setState(() { search.clear(); q = ''; openId = null; })),
        filled: true, fillColor: widget.staff ? null : Colors.white,
      ),
    );

    final body = <Widget>[
      if (query.isEmpty) Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in topics) ChoiceChip(
          label: Text('${t.icon}  ${t.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          selected: topic == t.name, showCheckmark: false,
          onSelected: (on) => setState(() { topic = on ? t.name : null; openId = null; }),
        ),
      ]),
      Padding(padding: const EdgeInsets.fromLTRB(2, 18, 2, 8), child: Text(heading, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .6, color: cs.onSurfaceVariant))),
      if (shown.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Try another word, or tap a topic. You can also ask using the buttons below.', style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant))),
      for (final h in shown) _card(h, (openId ?? autoOpen) == h.id, query, cs),
      const SizedBox(height: 8),
      _stillNeedHelp(cs),
      if (widget.staff) const _AdminFeedback(),
    ];

    if (widget.staff) {
      return StaffPage(title: 'Help', subtitle: 'Short answers for teachers and office staff.',
          body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [searchBox, const SizedBox(height: 14), ...body]));
    }
    return Scaffold(body: Column(children: [
      BrandHeader(padding: const EdgeInsets.fromLTRB(8, 4, 20, 20), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconButton(tooltip: 'Back', onPressed: () => context.canPop() ? context.pop() : context.go('/'), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
          Text(AppConfig.appName, style: TextStyle(color: Colors.white.withValues(alpha: .9), fontSize: 13)),
        ]),
        Padding(padding: const EdgeInsets.only(left: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('How can we help?', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontSize: 28)),
          const SizedBox(height: 4),
          Text('Short answers for parents and students.', style: TextStyle(color: Colors.white.withValues(alpha: .92), fontSize: 14)),
          const SizedBox(height: 14),
          searchBox,
        ])),
      ])))),
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body))),
      ])),
    ]));
  }

  /// The question, with the searched words marked.
  Widget _title(String text, String query, {double size = 16}) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    final base = TextStyle(fontWeight: FontWeight.w800, fontSize: size, height: 1.35, color: Theme.of(context).colorScheme.onSurface);
    if (words.isEmpty) return Text(text, style: base);
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    var i = 0;
    while (i < text.length) {
      var hit = -1, len = 0;
      for (final w in words) {
        final at = lower.indexOf(w, i);
        if (at >= 0 && (hit < 0 || at < hit)) { hit = at; len = w.length; }
      }
      if (hit < 0) { spans.add(TextSpan(text: text.substring(i))); break; }
      if (hit > i) spans.add(TextSpan(text: text.substring(i, hit)));
      spans.add(TextSpan(text: text.substring(hit, hit + len), style: TextStyle(backgroundColor: Brand.gold2.withValues(alpha: .45))));
      i = hit + len;
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }

  Widget _card(HelpItem h, bool open, String query, ColorScheme cs) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: open ? Brand.gold : cs.outline.withValues(alpha: .5), width: open ? 1.5 : 1)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => openId = open ? '' : h.id),
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 14, 10, 14), child: Row(children: [
          Expanded(child: _title(h.question, query)),
          Icon(open ? Icons.expand_less_rounded : Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ])),
      ),
      if (open) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, s) in h.steps.indexed) Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 26, height: 26, alignment: Alignment.center, decoration: const BoxDecoration(color: Brand.crimsonTint, shape: BoxShape.circle),
              child: Text('${i + 1}', style: const TextStyle(color: Brand.crimsonDeep, fontWeight: FontWeight.w900, fontSize: 13))),
          const SizedBox(width: 12),
          Expanded(child: Text(s, style: const TextStyle(fontSize: 15, height: 1.5))),
        ])),
        if (h.route != null) Padding(padding: const EdgeInsets.only(top: 4), child: SizedBox(height: 52, child: FilledButton.icon(
          onPressed: () => _open(h.route!),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(h.button ?? 'Open', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ))),
        const SizedBox(height: 10),
        voted.contains(h.id)
            ? Text('Thank you — this helps us improve the answers.', style: TextStyle(color: context.tone(Brand.green), fontWeight: FontWeight.w700))
            : Row(children: [
                Expanded(child: Text('Was this helpful?', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700))),
                TextButton(onPressed: () => _vote(h, true), child: const Text('👍 Yes', style: TextStyle(fontSize: 15))),
                TextButton(onPressed: () => _vote(h, false), child: const Text('👎 No', style: TextStyle(fontSize: 15))),
              ]),
      ])),
    ]),
  );

  Widget _stillNeedHelp(ColorScheme cs) => Container(
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: const Color(0xFF1E1B21), borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Still need help?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
      const SizedBox(height: 4),
      Text(widget.staff ? 'Ask the IT admin or the school office. They can also reset your password.' : 'Call the school office, or send a message to the class teacher in the app.',
          style: TextStyle(color: Colors.white.withValues(alpha: .8), fontSize: 14, height: 1.4)),
      if (!widget.staff) ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _darkButton('📞  Call office', () => callNumber(AppConfig.officePhone))),
          const SizedBox(width: 8),
          Expanded(child: _darkButton('💬  Message teacher', () => context.push('/messages'))),
        ]),
      ],
    ]),
  );

  Widget _darkButton(String label, VoidCallback onTap) => Material(color: const Color(0xFF34313A), borderRadius: BorderRadius.circular(12), child: InkWell(
    borderRadius: BorderRadius.circular(12), onTap: onTap,
    child: Container(height: 48, alignment: Alignment.center, child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
  ));
}

/// IT / Principal / VP / office: which answers people marked "not helpful" in the last 30 days.
class _AdminFeedback extends ConsumerStatefulWidget {
  const _AdminFeedback();
  @override
  ConsumerState<_AdminFeedback> createState() => _AdminFeedbackState();
}

class _AdminFeedbackState extends ConsumerState<_AdminFeedback> {
  late final Future<List<Map<String, dynamic>>> _votes = db.from('help_feedback').select('item,helpful,audience')
      .gte('at', DateTime.now().subtract(const Duration(days: 30)).toUtc().toIso8601String()).limit(5000)
      .then((r) => List<Map<String, dynamic>>.from(r));

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value;
    if (s == null || !s.isOffice) return const SizedBox.shrink();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _votes,
      builder: (context, snap) {
        final rows = snap.data;
        if (rows == null || rows.isEmpty) return const SizedBox.shrink();
        final questions = {for (final h in [...familyHelp, ...staffHelp]) h.id: h.question};
        final yes = <String, int>{}, no = <String, int>{};
        for (final r in rows) {
          final m = r['helpful'] == true ? yes : no;
          m['${r['item']}'] = (m['${r['item']}'] ?? 0) + 1;
        }
        final worst = no.keys.toList()..sort((a, b) => no[b]!.compareTo(no[a]!));
        return Padding(padding: const EdgeInsets.only(top: 16), child: Panel(
          title: 'Answers people found unclear · last 30 days',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${rows.length} votes. Tell the app team which answers to rewrite.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            if (worst.isEmpty) const Text('Every answer was marked helpful. 👍'),
            for (final id in worst.take(8)) ListTile(contentPadding: EdgeInsets.zero, dense: true,
              title: Text(questions[id] ?? id, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Text('👎 ${no[id]}   👍 ${yes[id] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
        ));
      },
    );
  }
}
