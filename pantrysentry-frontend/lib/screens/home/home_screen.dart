import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../inventory/inventory_list_screen.dart';
import '../reminders/reminders_screen.dart';
import '../progress/progress_screen.dart';
import '../profile/profile_screen.dart';
import 'home_overview_tab.dart';

/// Bottom-nav shell. "Home" tab satisfies Epic 2's home-screen overview
/// requirements (AC 2.2.1 / AC 2.3.1); "Progress" covers Epic 5's
/// consumption/waste analytics; the remaining tabs give the full
/// inventory browse/search, reminders list, and profile/household views.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeOverviewTab(
        appState: widget.appState,
        onViewInventory: () => setState(() => _index = 1),
      ),
      InventoryListScreen(appState: widget.appState),
      RemindersScreen(appState: widget.appState),
      ProgressScreen(appState: widget.appState),
      ProfileScreen(appState: widget.appState),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.kitchen_outlined), selectedIcon: Icon(Icons.kitchen), label: 'Inventory'),
          NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: 'Reminders'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Progress'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
