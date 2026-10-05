import 'package:flutter/material.dart';

import '../../models/donation.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'donation_centres_screen.dart';
import 'donation_review_screen.dart';
import 'donation_widgets.dart';

/// Epic 7 — step 1: pick one or more items to donate. Opened from the
/// Inventory page's "Donate food" card, from an item's Donate button (with
/// that item ticked), or from a centre's "Prepare donation" ([centre] set,
/// in which case the next step is the review instead of choosing a centre).
class DonateItemsScreen extends StatefulWidget {
  const DonateItemsScreen({super.key, required this.appState, this.preselectedItemId, this.centre});
  final AppState appState;
  final String? preselectedItemId;
  final DonationCentre? centre;

  @override
  State<DonateItemsScreen> createState() => _DonateItemsScreenState();
}

class _DonateItemsScreenState extends State<DonateItemsScreen> {
  List<DonatableItem>? _items;
  String? _error;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await widget.appState.getDonatableItems();
      if (!mounted) return;
      setState(() {
        _items = items;
        final pre = widget.preselectedItemId;
        if (pre != null && items.any((i) => i.id == pre && i.canDonate)) _selected.add(pre);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _continue() async {
    final chosen = _items!.where((i) => _selected.contains(i.id)).toList();
    final centre = widget.centre;
    if (centre == null) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DonationCentresScreen(appState: widget.appState, items: chosen),
      ));
      return;
    }
    // Coming from a centre: re-fetch it with these items so each one is checked.
    final checked = await widget.appState.getDonationCentres(itemIds: chosen.map((i) => i.id).toList());
    if (!mounted) return;
    final withChecks = checked.firstWhere((c) => c.id == centre.id, orElse: () => centre);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DonationReviewScreen(appState: widget.appState, centre: withChecks, items: chosen),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose food to donate')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!, textAlign: TextAlign.center),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ])))
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? const Center(child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('There\'s nothing in your inventory to donate right now.', textAlign: TextAlign.center)))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        if (widget.centre != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text('Donating to ${widget.centre!.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        Text('Tick everything you\'d like to donate. You\'ll set amounts and condition on the next steps.',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                        const SizedBox(height: 8),
                        for (final item in items) _buildRow(item),
                      ],
                    ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _selected.isEmpty ? null : _continue,
            child: Text(_selected.isEmpty
                ? 'Select items to donate'
                : widget.centre == null
                    ? 'Find a centre for ${_selected.length} ${_selected.length == 1 ? 'item' : 'items'}'
                    : 'Continue with ${_selected.length} ${_selected.length == 1 ? 'item' : 'items'}'),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(DonatableItem item) {
    final String? blocked = item.isExpired
        ? 'Expired — can\'t be donated'
        : item.availableToDonate <= 0
            ? 'All of it is already in a pending donation'
            : null;
    final details = [
      '${formatQty(item.availableToDonate)} ${item.unit} available',
      if (item.reservedQuantity > 0) '${formatQty(item.reservedQuantity)} ${item.unit} already in a pending donation',
      if (item.expiryDate != null) 'expires ${formatDate(item.expiryDate!)}',
    ].join(' · ');
    return CheckboxListTile(
      value: _selected.contains(item.id),
      onChanged: blocked != null ? null : (v) => setState(() => v == true ? _selected.add(item.id) : _selected.remove(item.id)),
      title: Text(item.name),
      subtitle: Text(blocked ?? details,
          style: TextStyle(fontSize: 12, color: blocked != null ? AppTheme.paprika : Colors.grey.shade700)),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }
}
