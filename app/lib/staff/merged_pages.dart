import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/session.dart';
import '../core/theme.dart';
import 'school_setup.dart' show StaffTab, TransportTab;
import 'staff_screens_2.dart' show StaffTransportScreen;
import 'staff_shell.dart';

/// Pages that used to exist twice (once in "School setup") — now one page each.

/// Staff: add, change, roles, one-time passwords.
class StaffPeopleScreen extends StatelessWidget {
  const StaffPeopleScreen({super.key});
  @override
  Widget build(BuildContext context) => const StaffPage(
    title: 'Staff',
    subtitle: 'Add teachers and office staff, choose their roles, and give a one-time password when someone forgets theirs.',
    body: StaffTab(),
  );
}

/// Transport: today's buses and crew logins · routes, stops on the map and who takes which bus.
class TransportPage extends ConsumerStatefulWidget {
  const TransportPage({super.key});
  @override
  ConsumerState<TransportPage> createState() => _TransportPageState();
}

class _TransportPageState extends ConsumerState<TransportPage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider).value!;
    final canEdit = ['transport_incharge', 'office', 'it_admin', 'principal', 'vice_principal'].any(s.hasRole);
    return StaffPage(
      title: 'Transport',
      subtitle: 'Live buses, driver and bus-assistant logins, routes and stops on the map, and which student takes which bus.',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (canEdit) Padding(padding: const EdgeInsets.only(bottom: 16), child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (i, l, ic) in const [(0, 'Today’s buses & crew', Icons.gps_fixed_rounded), (1, 'Routes, stops & students', Icons.alt_route_rounded)])
            ChoiceChip(avatar: Icon(ic, size: 18, color: tab == i ? Colors.white : Brand.crimsonDeep), label: Text(l), selected: tab == i, showCheckmark: false,
                selectedColor: Brand.crimson, labelStyle: TextStyle(fontWeight: FontWeight.w800, color: tab == i ? Colors.white : null), onSelected: (_) => setState(() => tab = i)),
        ])),
        if (tab == 1 && canEdit) const TransportTab() else const StaffTransportScreen(bodyOnly: true),
      ]),
    );
  }
}
