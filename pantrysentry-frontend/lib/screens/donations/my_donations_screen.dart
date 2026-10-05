import 'package:flutter/material.dart';

import '../../models/donation.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'donation_review_screen.dart';
import 'donation_widgets.dart';

/// Epic 7 / User Story 7.3 — the donations this user created, filterable
/// by All / Pending / Completed (AC 7.3.1, 7.3.2, 7.3.4).
class MyDonationsScreen extends StatefulWidget {
  const MyDonationsScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<MyDonationsScreen> createState() => _MyDonationsScreenState();
}

class _MyDonationsScreenState extends State<MyDonationsScreen> {
  String? _filter; // null = all
  List<Donation>? _donations;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = ++_request;
    setState(() => _error = null);
    try {
      final list = await widget.appState.getMyDonations(status: _filter);
      if (mounted && id == _request) setState(() => _donations = list);
    } catch (e) {
      if (mounted && id == _request) setState(() => _error = e.toString());
    }
  }

  Future<void> _open(Donation d) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => DonationDetailScreen(appState: widget.appState, donation: d),
    ));
    // Status or items may have changed (completed, cancelled, edited).
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final donations = _donations;
    return Scaffold(
      appBar: AppBar(title: const Text('My donations')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final (label, value) in [('All', null), ('Pending', 'pending'), ('Completed', 'completed')])
                  ChoiceChip(
                    label: Text(label),
                    selected: _filter == value,
                    onSelected: (_) {
                      setState(() {
                        _filter = value;
                        _donations = null;
                      });
                      _load();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
            if (donations == null && _error == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            if (donations != null && donations.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  _filter == null ? 'You haven\'t planned any donations yet.' : 'No $_filter donations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            for (final d in donations ?? const <Donation>[]) _buildCard(d),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Donation d) {
    final summary = d.items.map((i) => '${i.name} (${formatQty(i.quantity)} ${i.unit})').join(', ');
    return Card(
      margin: const EdgeInsets.only(top: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(d),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(d.centreName, style: const TextStyle(fontWeight: FontWeight.w700))),
                  StatusChip(status: d.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(summary, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                d.status == DonationStatus.completed && d.completedAt != null
                    ? 'Donated ${formatDate(d.completedAt!)}'
                    // AC 7.3.3 — pending means the user hasn't confirmed
                    // delivery, not that the centre is reviewing it.
                    : 'Not delivered yet · planned ${formatDate(d.createdAt)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// AC 7.3.5–7.3.9 — details, and for a pending donation: edit, cancel,
/// or mark as completed.
class DonationDetailScreen extends StatefulWidget {
  const DonationDetailScreen({super.key, required this.appState, required this.donation});
  final AppState appState;
  final Donation donation;

  @override
  State<DonationDetailScreen> createState() => _DonationDetailScreenState();
}

class _DonationDetailScreenState extends State<DonationDetailScreen> {
  late Donation _donation = widget.donation;
  bool _busy = false;

  bool get _pending => _donation.status == DonationStatus.pending;

  void _showError(Object e) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
  }

  Future<void> _edit() async {
    setState(() => _busy = true);
    try {
      final available = await widget.appState.getDonatableItems(excludeDonationId: _donation.id);
      final ids = _donation.items.map((i) => i.inventoryItemId).toSet();
      final items = available.where((i) => ids.contains(i.id)).toList();
      final centres = await widget.appState.getDonationCentres(itemIds: items.map((i) => i.id).toList());
      DonationCentre? centre;
      for (final c in centres) {
        if (c.id == _donation.centreId) centre = c;
      }
      if (!mounted) return;
      setState(() => _busy = false);
      if (centre == null || items.isEmpty) {
        _showError('This donation can\'t be edited any more — its centre or items are no longer available. You can cancel it instead.');
        return;
      }
      if (items.length < ids.length) {
        _showError('Some items are no longer in your inventory and have been left out.');
      }
      // A non-nullable copy: `centre` is assigned in a loop, so Dart
      // can't promote it inside the builder closure below.
      final DonationCentre found = centre;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DonationReviewScreen(appState: widget.appState, centre: found, items: items, editing: _donation),
      ));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _showError(e);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this donation?'),
        content: const Text('It will be removed from your donations. Your inventory won\'t change.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel donation')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.appState.cancelDonation(_donation.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _showError(e);
    }
  }

  /// AC 7.3.8 — confirm what was actually handed over (0 = not delivered).
  Future<void> _complete() async {
    final controllers = {
      for (final i in _donation.items)
        i.id: TextEditingController(text: formatQty(i.quantity < i.currentQuantity ? i.quantity : i.currentQuantity)),
    };
    final delivered = await showDialog<Map<String, double>>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Mark as completed'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('How much did you hand over? Enter 0 for anything you didn\'t deliver.',
                      style: TextStyle(fontSize: 13)),
                  for (final i in _donation.items)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextField(
                        controller: controllers[i.id],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: i.name,
                          suffixText: i.unit,
                          helperText: 'In stock: ${formatQty(i.currentQuantity)} ${i.unit}',
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  if (error != null)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: const TextStyle(color: AppTheme.paprika))),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
              FilledButton(
                onPressed: () {
                  final values = <String, double>{};
                  for (final i in _donation.items) {
                    final q = double.tryParse(controllers[i.id]!.text.trim().replaceAll(',', '.'));
                    if (q == null || q < 0) {
                      setDialogState(() => error = 'Enter 0 or more for ${i.name}.');
                      return;
                    }
                    if (q > i.currentQuantity + 1e-9) {
                      setDialogState(() => error = 'Only ${formatQty(i.currentQuantity)} ${i.unit} of ${i.name} is in stock.');
                      return;
                    }
                    values[i.id] = q;
                  }
                  if (values.values.every((v) => v == 0)) {
                    setDialogState(() => error = 'Nothing delivered? Cancel the donation instead.');
                    return;
                  }
                  Navigator.pop(context, values);
                },
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
      },
    );
    for (final c in controllers.values) {
      c.dispose();
    }
    if (delivered == null) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.appState.completeDonation(donationId: _donation.id, deliveredByItemId: delivered);
      if (!mounted) return;
      setState(() {
        _donation = updated;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Donation completed — thank you! Your inventory has been updated.')),
      );
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _donation;
    return Scaffold(
        appBar: AppBar(title: const Text('Donation')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              children: [
                Expanded(child: Text(d.centreName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19))),
                StatusChip(status: d.status),
              ],
            ),
            if (d.centreAddress != null && d.centreAddress!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(d.centreAddress!, style: TextStyle(color: Colors.grey.shade700)),
            ],
            if (d.centreHours != null) Text(d.centreHours!, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
            if (d.centrePhone != null) SelectableText('Phone: ${d.centrePhone}', style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _pending ? AppTheme.honeyLight : AppTheme.basilLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _pending
                    // AC 7.3.3
                    ? 'Pending: you haven\'t confirmed delivery yet. Once you\'ve dropped the food off, tap "Mark as completed" '
                        'so your inventory is updated.'
                    : 'Completed on ${formatDate(d.completedAt ?? d.createdAt)}. The donated amounts were removed from your '
                        'inventory and counted as donated, not consumed or wasted.',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Food', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            for (final i in d.items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${i.name} — ${formatQty(i.quantity)} ${i.unit}'),
                subtitle: Text([
                  if (i.condition != null) i.condition!,
                  if (i.expiryDate != null) 'expires ${formatDate(i.expiryDate!)}',
                ].join(' · ')),
              ),
            if (d.notes != null) ...[
              const SizedBox(height: 8),
              Text('Notes: ${d.notes}', style: TextStyle(color: Colors.grey.shade800)),
            ],
            Text('Planned ${formatDate(d.createdAt)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        bottomNavigationBar: !_pending
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Mark as completed'),
                        onPressed: _busy ? null : _complete,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: OutlinedButton(onPressed: _busy ? null : _edit, child: const Text('Edit'))),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy ? null : _cancel,
                              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.paprika),
                              child: const Text('Cancel donation'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}
