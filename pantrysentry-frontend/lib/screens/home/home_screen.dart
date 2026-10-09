import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../inventory/inventory_list_screen.dart';
import '../reminders/reminders_screen.dart';
import '../progress/progress_screen.dart';
import '../profile/profile_screen.dart';
import '../impact/environmental_impact_screen.dart';
import 'home_overview_tab.dart';
import '../../models/food_item.dart';

/// Bottom-nav shell. "Home" tab satisfies Epic 2's home-screen overview
/// requirements (AC 2.2.1 / AC 2.3.1); "Progress" covers Epic 5's
/// consumption/waste analytics; "Impact" covers Epic 8's environmental
/// impact insights; the remaining tabs give the full
/// inventory browse/search, reminders list, and profile/household views.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  // Added fields to track the inventory location and request count for the inventory screen.
  StorageLocation? _inventoryLocation;
  int _inventoryRequest = 0;

  void _openInventory([StorageLocation? location]) {
    setState(() {
      _inventoryLocation = location;
      _inventoryRequest++;
      _index = 1;
    });
  }
  // Yola

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeOverviewTab(
        appState: widget.appState,
        onViewInventory: () => _openInventory(),
        // Added an onViewStorage callback to the HomeOverviewTab.
        onViewStorage: (location) => _openInventory(location),
        // Yola
      ),
      InventoryListScreen(
        appState: widget.appState,
        // Pass the inventory location and request count to the InventoryListScreen.
        requestedLocation: _inventoryLocation,
        navigationRequest: _inventoryRequest,
        // Yola
      ),
      RemindersScreen(appState: widget.appState),
      ProgressScreen(appState: widget.appState),
      EnvironmentalImpactScreen(appState: widget.appState),
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
          NavigationDestination(icon: Icon(Icons.eco_outlined), selectedIcon: Icon(Icons.eco), label: 'Impact'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
