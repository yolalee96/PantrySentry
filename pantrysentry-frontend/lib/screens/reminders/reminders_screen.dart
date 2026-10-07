// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../models/reminder.dart';
import '../inventory/item_detail_screen.dart';
import '../../models/food_item.dart';
// import '../../theme/app_theme.dart';

/// Reminders that are DUE, most urgent first. A reminder only appears here
/// once its date arrives (expiry date minus its lead time); before that it
/// stays hidden, and the empty state says how many are scheduled.
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
          final reminders = appState.dueReminders.where((reminder) {
            final itemKey = '${reminder.householdId}:${reminder.itemId}';
            return seenItemIds.add(itemKey);
          }).toList();
          // Yola

          if (reminders.isEmpty) {
            // Count scheduled (not yet due) reminders, one per item, so the
            // empty screen doesn't suggest that no reminders exist at all.
            final scheduledItems = appState.sortedUpcomingReminders.map((r) => r.itemId).toSet().length;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  scheduledItems == 0
                      ? 'No reminders set yet. Add one from any item\'s page.'
                      : 'Nothing due right now.\n$scheduledItems ${scheduledItems == 1 ? 'reminder is' : 'reminders are'} '
                          'scheduled and will appear here when ${scheduledItems == 1 ? 'it\'s' : 'they\'re'} due.',
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

    // Changed the visual representation of the reminder cards.
    // Added a color coding for the urgency of the reminder based on the
    // number of days left as follows:
    // 1. If item is more than 7 days from expiry date, the color is green. 
    // 2. If item is between 3-7 days from expiry date, the color is yellow. 
    // 3. If item is less than 3 days from expiry date, the color is red.
    // 4. If item is expired, the color is grey.
    final daysLeft = item.daysLeft;
    final Color bellColor;

    if (daysLeft < 0) {
      bellColor = const Color(0xFFE0E0E0);
    } else if (daysLeft < 3) {
      bellColor = const Color(0xFFD50000);
    } else if (daysLeft < 7) {
      bellColor = const Color(0xFFFFEB3B);
    } else {
      bellColor = const Color(0xFF69F0AE);
    }

    final String expiryLabel;

    if (daysLeft < 0) {
      final overdueDays = -daysLeft;
      expiryLabel = 'Expired $overdueDays day${overdueDays == 1 ? '' : 's'} ago';
    } else if (daysLeft == 0) {
      expiryLabel = 'Expires today';
    } else {
      expiryLabel = '$daysLeft day${daysLeft == 1 ? '' : 's'} until expiry';
    }

    return Card(
      color: const Color(0xFFF5F5F5),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side:BorderSide(
          color: Color(0xff00000000),
          width: 1,
          )
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ItemDetailScreen(
              appState: appState,
              item: item,
            ),
          ),
        ),
        leading: CircleAvatar(
          backgroundColor: bellColor,
          child: Icon(
            daysLeft < 0
                ? Icons.delete_outlined
                : Icons.notifications_active_outlined,
            size: 20,
          ),
        ),
        title: Text(
          item.name,
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),

            // White keeps the storage badge readable on every card colour.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: storageColor),
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
              'day${reminder.leadTimeDays == 1 ? '' : 's'} before',
              style: TextStyle(
                color: Colors.black87, 
                fontSize: 12
                ),
            ),
            const SizedBox(height: 4),
            Text(
              expiryLabel,
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (daysLeft < 0) ...[
              const SizedBox(height: 4),
              Text(
                'Open item to record disposal',
                style: TextStyle(
                  color: Colors.black87, 
                  fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
        trailing: reminder.triggered
            ? Icon(
                Icons.notifications,
                color: Colors.black87,
                size: 20,
              )
            : null,
      ),
    );
    // Yola

  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
