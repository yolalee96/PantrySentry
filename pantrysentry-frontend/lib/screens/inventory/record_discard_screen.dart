import 'package:flutter/material.dart';
import '../../models/food_item.dart';
import '../../theme/app_theme.dart';

/// AC (from usability testing): discarding an item asks WHY, so the
/// household can see real waste patterns instead of just a raw count.
/// Deliberately excludes the "was it visibly spoiled?" toggle and a
/// notes field — team decision to keep this quick to fill in.
class RecordDiscardScreen extends StatefulWidget {
  const RecordDiscardScreen({super.key, required this.item});
  final FoodItem item;

  @override
  State<RecordDiscardScreen> createState() => _RecordDiscardScreenState();
}

class _RecordDiscardScreenState extends State<RecordDiscardScreen> {
  DiscardReason? _reason;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final color = urgencyColor(item.daysLeft);
    final statusLabel = item.daysLeft < 0 ? 'Expired' : '${item.daysLeft} days left';

    return Scaffold(
      appBar: AppBar(title: const Text('Record discard')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Why are you discarding this?', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'This helps your household understand food waste patterns.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.fastfood_outlined, color: Colors.grey),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(
                            '${_formatQty(item.quantity)} ${item.unit} \u2022 $statusLabel \u2022 ${item.storageLocation.label}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                      child: Text(statusLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text('REASON FOR DISCARDING',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Card(
              child: RadioGroup<DiscardReason>(
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v),
                child: Column(
                  children: DiscardReason.values.map((r) {
                    return RadioListTile<DiscardReason>(
                      value: r,
                      title: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _reason == null ? null : () => Navigator.of(context).pop(_reason),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
                    child: const Text('Confirm discard'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatQty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}
