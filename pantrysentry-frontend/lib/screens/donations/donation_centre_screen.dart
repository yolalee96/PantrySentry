import 'package:flutter/material.dart';

import '../../models/donation.dart';
import '../../models/food_item.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'donate_items_screen.dart';
import 'donation_review_screen.dart';
import 'donation_widgets.dart';

/// One donation centre: details, contact, opening hours, requirements,
/// accepted foods, and how the chosen items match. "Prepare donation"
/// goes to the review (AC 7.2.1), or to the item picker first if no items
/// were chosen yet.
class DonationCentreScreen extends StatelessWidget {
  const DonationCentreScreen({super.key, required this.appState, required this.centre, this.items = const []});
  final AppState appState;
  final DonationCentre centre;
  final List<DonatableItem> items;

  void _prepare(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => items.isEmpty
          ? DonateItemsScreen(appState: appState, centre: centre)
          : DonationReviewScreen(appState: appState, centre: centre, items: items),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final contact = [
      if (centre.phone != null) ('Phone', centre.phone!),
      if (centre.email != null) ('Email', centre.email!),
      if (centre.websiteUrl != null) ('Website', centre.websiteUrl!),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Donation centre')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(centre.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 21)),
          const SizedBox(height: 2),
          Text(
            [centre.typeLabel, if (centre.distanceKm != null) '${centre.distanceKm!.toStringAsFixed(1)} km away'].join(' · '),
            style: TextStyle(color: Colors.grey.shade700),
          ),
          if (centre.description != null) ...[
            const SizedBox(height: 10),
            Text(centre.description!),
          ],
          const SizedBox(height: 14),
          _infoRow(Icons.place_outlined, centre.fullAddress),
          if (centre.operatingHours != null) _infoRow(Icons.schedule, centre.operatingHours!),
          for (final (label, value) in contact) _infoRow(label == 'Phone' ? Icons.phone_outlined : label == 'Email' ? Icons.email_outlined : Icons.language, value),
          const SizedBox(height: 14),
          RequirementsBox(centre: centre),
          const SizedBox(height: 16),
          const Text('Foods they accept', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          if (centre.acceptedFoods.isEmpty)
            Text('This centre hasn\'t published a verified list of foods. Contact them before dropping food off.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final food in centre.acceptedFoods)
                  Chip(
                    label: Text('${food.itemName} · ${food.category.label}', style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('Your items', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    ItemCheckBadge(check: centre.checkFor(item.id)),
                  ],
                ),
              ),
          ],
          if (centre.sourceUrl != null) ...[
            const SizedBox(height: 18),
            Text('Information verified from: ${centre.sourceUrl}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.volunteer_activism_outlined),
            label: const Text('Prepare donation'),
            onPressed: () => _prepare(context),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppTheme.ocean),
            const SizedBox(width: 10),
            Expanded(child: SelectableText(text, style: const TextStyle(fontSize: 13.5))),
          ],
        ),
      );
}
