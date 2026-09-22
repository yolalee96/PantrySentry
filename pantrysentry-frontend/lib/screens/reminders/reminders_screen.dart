import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../models/reminder.dart';
import '../../theme/app_theme.dart';
import '../inventory/item_detail_screen.dart';
import '../../models/food_item.dart';

/// AC 3.3.1 — all upcoming reminders in one place, sorted by urgency.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key, required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          // Only show one reminder per item, even if multiple reminders exist for that item.
          final seenItemIds = <String>{};
          final reminders = appState.sortedUpcomingReminders.where((reminder) {
            final itemKey = '${reminder.householdId}:${reminder.itemId}';
            return seenItemIds.add(itemKey);
          }).toList();
          // Yola

          if (reminders.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No reminders set yet. Add one from any item\'s page.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reminders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _ReminderTile(appState: appState, reminder: reminders[i]),
          );
        },
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.appState, required this.reminder});
  final AppState appState;
  final Reminder reminder;

  @override
  Widget build(BuildContext context) {
    final item = appState.items.where((i) => i.id == reminder.itemId).firstOrNull;
    if (item == null) return const SizedBox.shrink();
    // Added a storage location color label to the reminder card for better 
    // visibility of where the item is stored.
    final Color storageColor;
    final IconData storageIcon;

    switch (item.storageLocation) {
      case StorageLocation.fridge:
        storageColor = const Color(0xFF1565C0);
        storageIcon = Icons.kitchen_outlined;
        break;
      case StorageLocation.freezer:
        storageColor = const Color(0xFF00695C);
        storageIcon = Icons.ac_unit_outlined;
        break;
      case StorageLocation.pantry:
        storageColor = const Color(0xFF795548);
        storageIcon = Icons.inventory_2_outlined;
        break;
    }
    // Yola

    final color = urgencyColor(item.daysLeft);

    return Card(
      // Added a border to the reminder card for better visibility.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(
          color: Colors.black,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      // Yola

      child: ListTile(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ItemDetailScreen(appState: appState, item: item),
        )),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(Icons.notifications_active_outlined, color: color, size: 20),
        ),
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        
        // Modified subtitle to include the storage location of item (with it's label).
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: storageColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: storageColor.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    storageIcon,
                    size: 14,
                    color: storageColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    item.storageLocation.label,
                    style: TextStyle(
                      color: storageColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Reminds ${reminder.leadTimeDays} '
              'day${reminder.leadTimeDays == 1 ? '' : 's'} before • '
            ),

            // Separately make remaining number of days bold for better visibility.
            RichText(
              text: TextSpan(
                text: '${item.daysLeft} days left',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          ],
        ),
        // Yola

        trailing: reminder.triggered
            ? const Icon(Icons.notifications, color: Colors.orange, size: 20)
            : null,
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
