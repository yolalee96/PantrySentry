import 'package:flutter/material.dart';

import '../../models/donation.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'my_donations_screen.dart';
import 'donation_widgets.dart';

/// Epic 7 / User Story 7.2 — set the amount and condition of each item,
/// read the centre's requirements, confirm, and submit a PENDING donation.
/// Nothing in the inventory changes until the donation is marked completed.
/// With [editing] set, saves changes to that pending donation (AC 7.3.6).
class DonationReviewScreen extends StatefulWidget {
  const DonationReviewScreen({
    super.key,
    required this.appState,
    required this.centre,
    required this.items,
    this.editing,
  });
  final AppState appState;
  final DonationCentre centre;
  final List<DonatableItem> items;
  final Donation? editing;

  @override
  State<DonationReviewScreen> createState() => _DonationReviewScreenState();
}

class _Row {
  _Row(this.item, {double? quantity, this.condition})
      : controller = TextEditingController(text: formatQty(quantity ?? item.availableToDonate));
  final DonatableItem item;
  final TextEditingController controller;
  String? condition;
  String? error;
}

class _DonationReviewScreenState extends State<DonationReviewScreen> {
  late final List<_Row> _rows;
  late final TextEditingController _notes = TextEditingController(text: widget.editing?.notes ?? '');
  bool _declaration = false;
  bool _saving = false;
  String? _formError;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final existing = {for (final i in widget.editing?.items ?? const <DonationItem>[]) i.inventoryItemId: i};
    _rows = widget.items
        .map((item) => _Row(item, quantity: existing[item.id]?.quantity, condition: existing[item.id]?.condition))
        .toList();
    _declaration = _isEdit; // already confirmed when it was created
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.controller.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  /// AC 7.2.4 / 7.2.5 — checked here for instant feedback, and again on
  /// the server against the latest stock.
  bool _validate() {
    var ok = true;
    for (final r in _rows) {
      r.error = null;
      final q = double.tryParse(r.controller.text.trim().replaceAll(',', '.'));
      if (q == null) {
        r.error = 'Enter a number';
      } else if (q <= 0) {
        r.error = 'Must be more than 0';
      } else if (q > r.item.availableToDonate + 1e-9) {
        r.error = 'You can donate at most ${formatQty(r.item.availableToDonate)} ${r.item.unit}';
      } else if (r.condition == null) {
        r.error = 'Choose the condition';
      }
      if (r.error != null) ok = false;
    }
    _formError = !_declaration ? 'Please confirm the declaration below.' : null;
    return ok && _declaration;
  }

  Future<void> _submit() async {
    setState(() {});
    if (!_validate()) {
      setState(() {});
      return;
    }
    final drafts = _rows
        .map((r) => DonationDraftItem(
              inventoryItemId: r.item.id,
              quantity: double.parse(r.controller.text.trim().replaceAll(',', '.')),
              condition: r.condition,
            ))
        .toList();
    setState(() => _saving = true);
    try {
      final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
      if (_isEdit) {
        await widget.appState.updateDonation(donationId: widget.editing!.id, items: drafts, notes: notes);
      } else {
        await widget.appState.createDonation(
          centreId: widget.centre.id,
          items: drafts,
          declarationAgreed: true,
          notes: notes,
        );
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      // Back out of the whole donation flow, then show My donations.
      navigator.popUntil((route) => route.isFirst);
      navigator.push(MaterialPageRoute(builder: (_) => MyDonationsScreen(appState: widget.appState)));
      messenger.showSnackBar(SnackBar(
        content: Text(_isEdit
            ? 'Donation updated.'
            : 'Donation planned. Your inventory will update when you mark it as completed.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final centre = widget.centre;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit donation' : 'Review donation')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // AC 7.2.8 — selected centre and food details together.
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.volunteer_activism_outlined, color: AppTheme.seedColor),
              title: Text(centre.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([centre.fullAddress, if (centre.operatingHours != null) centre.operatingHours!].join('\n')),
              isThreeLine: centre.operatingHours != null,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Food', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          for (final r in _rows) _buildRow(r),
          const SizedBox(height: 8),
          RequirementsBox(centre: centre),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _declaration,
            onChanged: _saving || _isEdit ? null : (v) => setState(() => _declaration = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I\'ve read this centre\'s requirements, and this food meets them and is safe to eat.',
              style: TextStyle(fontSize: 13.5),
            ),
          ),
          TextField(
            controller: _notes,
            enabled: !_saving,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'e.g. planned drop-off day',
              border: OutlineInputBorder(),
            ),
          ),
          if (_formError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_formError!, style: const TextStyle(color: AppTheme.paprika)),
            ),
          const SizedBox(height: 4),
          Text(
            'Nothing is removed from your inventory yet. After you drop the food off, open My donations and '
            'mark it as completed.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_isEdit ? 'Save changes' : 'Plan this donation'),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(_Row r) {
    final item = r.item;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            // AC 7.2.3 — recorded details shown alongside.
            Text(
              [
                '${formatQty(item.availableToDonate)} ${item.unit} available',
                if (item.expiryDate != null) 'expires ${formatDate(item.expiryDate!)}',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            ItemCheckBadge(check: widget.centre.checkFor(item.id)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: r.controller,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      suffixText: item.unit,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: r.condition,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Condition', isDense: true, border: OutlineInputBorder()),
                    items: [for (final c in kDonationConditions) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))],
                    onChanged: _saving ? null : (v) => setState(() => r.condition = v),
                  ),
                ),
              ],
            ),
            if (r.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(r.error!, style: const TextStyle(color: AppTheme.paprika, fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }
}
