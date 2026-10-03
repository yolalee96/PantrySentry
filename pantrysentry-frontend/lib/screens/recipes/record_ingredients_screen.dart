import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../services/id_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'recipe_formatting.dart';

/// User Story 6.3 — the "Update ingredients used" review. Lists the
/// recipe's ingredients that matched the inventory, each pre-ticked with
/// an editable amount (in the inventory item's own unit). Nothing is
/// deducted until the user confirms. Pops with `true` once saved.
class RecordIngredientsScreen extends StatefulWidget {
  const RecordIngredientsScreen({super.key, required this.appState, required this.recipe});
  final AppState appState;
  final Recipe recipe;

  @override
  State<RecordIngredientsScreen> createState() => _RecordIngredientsScreenState();
}

/// One inventory item in the review. If the recipe lists the same item
/// twice (e.g. "eggs" for batter and for glazing), the amounts are
/// combined, since the server deducts per item.
class _UseRow {
  _UseRow({required this.item, required this.ingredientNames, required double? suggested})
      : controller = TextEditingController(text: suggested == null ? '' : formatQuantity(suggested));

  final MatchedInventoryItem item;
  final List<String> ingredientNames;
  final TextEditingController controller;
  bool selected = true;
  String? error;
}

class _RecordIngredientsScreenState extends State<RecordIngredientsScreen> {
  late final List<_UseRow> _rows;
  // AC 6.3.7 — created once per review and reused for every retry of
  // THIS submission, so a retry after a network error can never deduct
  // twice. A new review (re-opening the screen) gets a new id.
  late final String _submissionId =
      '${IdService.newId('ru')}-${DateTime.now().millisecondsSinceEpoch}';
  bool _saving = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    // Group by inventory item, keeping recipe order.
    final items = <String, MatchedInventoryItem>{};
    final names = <String, List<String>>{};
    final suggestedTotals = <String, double?>{};
    for (final ing in widget.recipe.ingredients) {
      final item = ing.inventoryItem;
      if (item == null) continue;
      items.putIfAbsent(item.id, () => item);
      names.putIfAbsent(item.id, () => []).add(ing.name);
      // Sum the suggestions; if any part couldn't be converted, leave the
      // amount blank for the user rather than pre-filling a partial total.
      if (!suggestedTotals.containsKey(item.id)) {
        suggestedTotals[item.id] = ing.suggestedUseQuantity;
      } else {
        final prev = suggestedTotals[item.id];
        suggestedTotals[item.id] =
            prev == null || ing.suggestedUseQuantity == null ? null : prev + ing.suggestedUseQuantity!;
      }
    }
    _rows = items.values.map((item) {
      final total = suggestedTotals[item.id];
      final capped = total == null ? null : (total > item.quantity ? item.quantity : total);
      return _UseRow(item: item, ingredientNames: names[item.id]!, suggested: capped);
    }).toList();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.controller.dispose();
    }
    super.dispose();
  }

  /// AC 6.3.3 — selected amounts must be more than 0 and no more than
  /// what's in stock. The server checks again, against the latest stock.
  bool _validate() {
    var ok = true;
    for (final r in _rows) {
      r.error = null;
      if (!r.selected) continue;
      final q = double.tryParse(r.controller.text.trim().replaceAll(',', '.'));
      if (q == null) {
        r.error = 'Enter how much you used';
        ok = false;
      } else if (q <= 0) {
        r.error = 'Must be more than 0';
        ok = false;
      } else if (q > r.item.quantity + 1e-9) {
        r.error = 'You only have ${amountText(r.item.quantity, r.item.unit)}';
        ok = false;
      }
    }
    _formError = _rows.any((r) => r.selected) ? null : 'Tick at least one ingredient you used.';
    return ok && _formError == null;
  }

  Future<void> _confirm() async {
    if (!_validate()) {
      setState(() {});
      return;
    }
    // AC 6.3.2 — unticked ingredients are simply not sent.
    final uses = _rows
        .where((r) => r.selected)
        .map((r) => IngredientUse(
              inventoryItemId: r.item.id,
              quantityUsed: double.parse(r.controller.text.trim().replaceAll(',', '.')),
            ))
        .toList();

    setState(() => _saving = true);
    try {
      final result = await widget.appState.recordRecipeUsage(
        submissionId: _submissionId,
        recipe: widget.recipe,
        uses: uses,
      );
      if (!mounted) return;
      final fullyUsed = result.updated.where((u) => u.fullyUsed).map((u) => u.name).toList();
      final summary = result.alreadyRecorded
          ? 'These ingredients were already recorded.'
          : fullyUsed.isEmpty
              ? 'Inventory updated.'
              : 'Inventory updated. Used up: ${fullyUsed.join(', ')}.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(summary)));
      Navigator.of(context).pop(true);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Ingredients used')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(widget.recipe.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 6),
          Text(
            'Untick anything you didn\'t use and adjust the amounts. Items you use up completely will be marked as consumed.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final row in _rows) _buildRow(row),
          if (_formError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_formError!, style: const TextStyle(color: AppTheme.paprika)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _saving ? null : _confirm,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Confirm and update inventory'),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(_UseRow row) {
    final usesFromRecipe = row.ingredientNames.join(', ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: row.selected,
              onChanged: _saving ? null : (v) => setState(() => row.selected = v ?? false),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Text(row.item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    'You have ${amountText(row.item.quantity, row.item.unit)}'
                    '${usesFromRecipe.toLowerCase() == row.item.name.toLowerCase() ? '' : ' · recipe: $usesFromRecipe'}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (row.selected) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: row.controller,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Amount used',
                        suffixText: row.item.unit,
                        errorText: row.error,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (row.error != null) setState(() => row.error = null);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
