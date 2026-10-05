import 'package:flutter/material.dart';

import '../../models/donation.dart';
import '../../theme/app_theme.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// 2.0 -> "2", 0.25 -> "0.25"
String formatQty(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// How a centre's accepted-food list covers one item, as a small badge.
/// Only our own checks (expired, quantity) ever block a donation; these
/// are guidance, because centres' lists may be incomplete.
class ItemCheckBadge extends StatelessWidget {
  const ItemCheckBadge({super.key, required this.check});
  final ItemCheck? check;

  @override
  Widget build(BuildContext context) {
    final c = check;
    if (c == null) return const SizedBox.shrink();
    final (IconData icon, Color color, String text) = switch (c.result) {
      DonationCheckResult.listed => (Icons.check_circle, AppTheme.seedColor, 'On their list (${c.matchedFood})'),
      DonationCheckResult.similar => (Icons.help_outline, AppTheme.honey, 'Similar food listed (${c.matchedFood}) — check with the centre'),
      DonationCheckResult.notListed => (Icons.warning_amber_rounded, AppTheme.paprika, 'Not on their list — contact them first'),
      DonationCheckResult.noList => (Icons.info_outline, Colors.grey.shade700, 'No food list published — contact them first'),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
      ],
    );
  }
}

/// The centre's own wording, shown as written (never interpreted).
class RequirementsBox extends StatelessWidget {
  const RequirementsBox({super.key, required this.centre});
  final DonationCentre centre;

  @override
  Widget build(BuildContext context) {
    final text = centre.requirements;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.honeyLight, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Centre\'s donation requirements', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            text == null || text.isEmpty
                ? 'This centre hasn\'t published specific requirements. Contact them before dropping food off.'
                : text,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final DonationStatus status;

  @override
  Widget build(BuildContext context) {
    final (String label, Color fg, Color bg) = switch (status) {
      DonationStatus.pending => ('Pending', AppTheme.honey, AppTheme.honeyLight),
      DonationStatus.completed => ('Completed', AppTheme.seedColor, AppTheme.basilLight),
      DonationStatus.cancelled => ('Cancelled', Colors.grey.shade700, Colors.grey.shade200),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}
