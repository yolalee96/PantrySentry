import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../models/food_item.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_format.dart';
import 'add_edit_item_screen.dart';
import 'record_discard_screen.dart';

/// AC 2.6.1 plus item actions: consume / discard / donate, edit.
/// The standalone "Delete" action was removed (usability testing found
/// no real use for it once every item must be explicitly resolved via
/// one of these three actions instead).
///
/// Wrapped in a ListenableBuilder and always re-reads the current item
/// from AppState.items by id, rather than displaying the fixed snapshot
/// passed in at navigation time — otherwise editing an item and coming
/// back here showed stale details until you left and reopened the screen.
class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({super.key, required this.appState, required this.item});
  final AppState appState;
  final FoodItem item;

  Future<void> _resolve(
    BuildContext context,
    FoodItem item,
    ItemDisposition disposition, {
    DiscardReason? discardReason,
    ConsumedAmount? consumedAmount,
  }) async {
    // Show immediate visual feedback the moment the action is confirmed
    // — previously the button just sat there with no response while the
    // network request was in flight, then the screen suddenly popped,
    // which read as "nothing happened" from the user's side.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await appState.resolveItem(item, disposition, discardReason: discardReason, consumedAmount: consumedAmount);
      if (context.mounted) {
        Navigator.of(context).pop(); // dismiss the loading indicator
        Navigator.of(context).pop(); // then leave the item detail screen
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // dismiss the loading indicator
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn\'t update this item: $e')));
      }
    }
  }

  Future<void> _consume(BuildContext context, FoodItem item) async {
    final amount = await showModalBottomSheet<ConsumedAmount>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How much did you consume?', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('This helps track how food actually gets used.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              const SizedBox(height: 14),
              ...ConsumedAmount.values.map((a) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.restaurant_outlined),
                    title: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    onTap: () => Navigator.of(context).pop(a),
                  )),
            ],
          ),
        ),
      ),
    );
    if (amount != null && context.mounted) {
      await _resolve(context, item, ItemDisposition.consumed, consumedAmount: amount);
    }
  }

  Future<void> _discard(BuildContext context, FoodItem item) async {
    final reason = await Navigator.of(context).push<DiscardReason>(
      MaterialPageRoute(builder: (_) => RecordDiscardScreen(item: item)),
    );
    if (reason != null && context.mounted) {
      await _resolve(context, item, ItemDisposition.discarded, discardReason: reason);
    }
  }

  Future<void> _donate(BuildContext context, FoodItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as donated?'),
        content: Text('"${item.name}" will be recorded as donated instead of consumed or discarded.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _resolve(context, item, ItemDisposition.donated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        // Always the current version — falls back to the originally
        // passed-in item only if it's ever been removed from the list.
        final liveItem = appState.items.where((i) => i.id == item.id).isEmpty
            ? item
            : appState.items.firstWhere((i) => i.id == item.id);
        return _buildScaffold(context, liveItem);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, FoodItem item) {
    final color = urgencyColor(item.daysLeft);
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AddEditItemScreen(appState: appState, existingItem: item),
            )),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row('Quantity', '${item.quantity} ${item.unit}'),
                    _row('Storage location', item.storageLocation.label),
                    _row('Category', item.category.label),
                    _row('Use-by date', formatLongDate(item.useByDate)),
                    _row(
                      'Status',
                      item.daysLeft < 0 ? '${-item.daysLeft} days overdue' : '${item.daysLeft} days left',
                      valueColor: color,
                    ),
                  ],
                ),
              ),
            ),
            if (item.notes != null && item.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Note', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                      const SizedBox(height: 6),
                      Text(item.notes!, style: const TextStyle(fontSize: 14.5)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (item.isActive) ...[
              if (item.consumedAmount != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.restaurant_outlined, color: Colors.orange.shade700, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${item.consumedAmount!.label} \u2014 still in your inventory',
                          style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text('What happened to this item?',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => _consume(context, item),
                  icon: const Icon(Icons.restaurant_outlined),
                  label: const Text('Consume', style: TextStyle(fontSize: 15.5)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => _discard(context, item),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Discard', style: TextStyle(fontSize: 15.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => _donate(context, item),
                  icon: const Icon(Icons.volunteer_activism_outlined),
                  label: const Text('Donate', style: TextStyle(fontSize: 15.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ] else ...[
              Chip(label: Text('Marked as ${item.disposition!.name}')),
              if (item.discardReason != null) ...[
                const SizedBox(height: 8),
                Text('Reason: ${item.discardReason!.label}', style: TextStyle(color: Colors.grey.shade700)),
              ],
              if (item.consumedAmount != null) ...[
                const SizedBox(height: 8),
                Text(item.consumedAmount!.label, style: TextStyle(color: Colors.grey.shade700)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.w600, color: valueColor)),
        ],
      ),
    );
  }
}
