import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../widgets/item_card.dart';
import 'item_detail_screen.dart';

/// AC 2.4.1 — full (not just preview) list of expiring items.
class ExpiringSoonScreen extends StatelessWidget {
  const ExpiringSoonScreen({
    // Added parameters expiredOnly and windowDays to allow for filtering
    // of items based on expiration status and time window.
    super.key, 
    required this.appState,
    this.expiredOnly = false,
    this.windowDays = 7,
    // Yola
    });
  final AppState appState;
  // Declared the expiredOnly and windowDays parameters to
  // allow for filtering of items based on expiration status
  // and time window.
  final bool expiredOnly;
  final int windowDays;
  // Yola

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Added a conditional title to the AppBar based on the
      // expiredOnly parameter.
      appBar: AppBar(
        title: Text(expiredOnly ? 'Expired' : 'Eat First'),
      ),
      // Yola
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          // Filter items based on the expiredOnly parameter and the windowDays parameter.
          final items = appState.activeItems.where((item) {
            final days = item.daysLeft;

            return expiredOnly
                ? days < 0
                : days >= 0 && days <= windowDays;
          }).toList()
            ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
            // Yola

          if (items.isEmpty) {
            return Center(
              // Replaced Text to Padding with a message that
              // reflects the expiredOnly parameter and the windowDays parameter.
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  expiredOnly
                      ? 'No expired items in your inventory.'
                      : 'Nothing expiring in the next $windowDays days.',
                  textAlign: TextAlign.center,
                ),
              ),
              // Yola
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => ItemCard(
              item: items[i],
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ItemDetailScreen(appState: appState, item: items[i]),
              )),
            ),
          );
        },
      ),
    );
  }
}
