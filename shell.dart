import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/data.dart';
import 'core/data3.dart';
import 'screens/help_screen.dart' show HelpFab;
import 'screens/consent_screen.dart';

/// Bottom navigation. The Bus tab appears only for students with a transport enrolment.
class AppShell extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const AppShell({super.key, required this.shell});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // first sign-in: the family agrees to the privacy notice once (DPDP)
    if (ref.watch(consentGivenProvider).value == false) return const ConsentScreen();
    final onBus = ref.watch(transportProvider).value != null && featureOn(ref.watch(appSettingsProvider).value, 'bus');
    final unread = ref.watch(unreadMessagesProvider).value ?? 0;
    const items = [
      (Icons.home_rounded, Icons.home_outlined, 'Home'),
      (Icons.account_balance_wallet_rounded, Icons.account_balance_wallet_outlined, 'Fees'),
      (Icons.menu_book_rounded, Icons.menu_book_outlined, 'Diary'),
      (Icons.campaign_rounded, Icons.campaign_outlined, 'Notices'),
      (Icons.directions_bus_rounded, Icons.directions_bus_outlined, 'Bus'),
      (Icons.school_rounded, Icons.school_outlined, 'Reports'),
    ];
    // branch index 4 is Bus; hide it (and remap) when the student is not on a bus
    final visible = [for (var i = 0; i < items.length; i++) if (i != 4 || onBus) i];
    final selected = visible.indexOf(shell.currentIndex).clamp(0, visible.length - 1);
    return Scaffold(
      body: shell,
      // Help: bottom right of Home, on phones and on the website
      floatingActionButton: shell.currentIndex == 0 ? HelpFab(onTap: () => context.push('/help')) : null,
      // On a laptop the side menu (parent_layout.dart) replaces the bottom tabs.
      bottomNavigationBar: MediaQuery.sizeOf(context).width >= 960 ? null : NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (i) => shell.goBranch(visible[i], initialLocation: visible[i] == shell.currentIndex),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [for (final i in visible) NavigationDestination(
          icon: i == 0 && unread > 0 ? Badge(label: Text('$unread'), child: Icon(items[i].$2)) : Icon(items[i].$2),
          selectedIcon: Icon(items[i].$1), label: items[i].$3)],
      ),
    );
  }
}
