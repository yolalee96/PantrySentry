import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../widgets/item_card.dart';
import 'item_detail_screen.dart';

/// AC 2.4.1 — full (not just preview) list of expiring items.
class ExpiringSoonScreen extends StatelessWidget {
  const ExpiringSoonScreen({super.key, required this.appState});
  final AppState appState;

  static const _windowDays = 7; // slightly wider window for the full view

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expiring Soon')),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final items = appState.expiringWithin(_windowDays);
          if (items.isEmpty) {
            return Center(
              child: Text('Nothing expiring in the next $_windowDays days 🎉',
                  style: TextStyle(color: Colors.grey.shade600)),
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
