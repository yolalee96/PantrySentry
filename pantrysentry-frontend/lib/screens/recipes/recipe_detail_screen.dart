import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'record_ingredients_screen.dart';
import 'recipe_formatting.dart';

/// User Story 6.2 — a recipe's details and which ingredients the household
/// already has. Viewing never changes the inventory (AC 6.2.5): the only
/// way anything is deducted is the explicit "Update ingredients used"
/// review. Pops with `true` if ingredients were recorded.
class RecipeDetailScreen extends StatelessWidget {
  const RecipeDetailScreen({super.key, required this.appState, required this.recipe});
  final AppState appState;
  final Recipe recipe;

  Future<void> _recordUsage(BuildContext context) async {
    final recorded = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RecordIngredientsScreen(appState: appState, recipe: recipe),
    ));
    if (recorded == true && context.mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final available = recipe.ingredients.where((i) => i.isAvailable).toList();
    final missing = recipe.ingredients.where((i) => !i.isAvailable).toList();
    final times = recipeTimesLine(recipe);
    final details = [
      if (recipe.servings != null) 'Serves ${formatQuantity(recipe.servings!)}${recipe.servingUnit != null ? ' ${recipe.servingUnit}' : ''}',
      if (recipe.difficulty != null) '${recipe.difficulty![0]}${recipe.difficulty!.substring(1).toLowerCase()}',
      if (recipe.cuisine != null) recipe.cuisine!,
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: const Text('Recipe')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
        children: [
          if (!recipe.isAiGenerated) RecipeImage(url: recipe.imageUrl, height: 200),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          if (recipe.isAiGenerated) const Padding(padding: EdgeInsets.only(bottom: 8), child: AiBadge()),
          Text(recipe.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          // AC 6.2.1 — serving size; times shown separately as recorded.
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(details, style: TextStyle(color: Colors.grey.shade700)),
          ],
          if (times.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(times, style: TextStyle(color: Colors.grey.shade700)),
          ],
          if (recipe.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(recipe.description),
          ],
          if (recipe.usesExpiringSoon) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.paprikaLight, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Uses food that needs using soon',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.paprika)),
                  const SizedBox(height: 4),
                  for (final m in recipe.expiringMatches)
                    Text('• ${m.name} — ${expiryPhrase(m.daysLeft, m.expiryDate)}', style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          const Text('Ingredients', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          if (available.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('In your inventory', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
            for (final ing in available) _IngredientRow(ingredient: ing),
          ],
          if (missing.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('You\'ll need', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
            for (final ing in missing) _IngredientRow(ingredient: ing),
          ],
          const SizedBox(height: 22),
          const Text('Method', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          const SizedBox(height: 8),
          for (var i = 0; i < recipe.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppTheme.basilLight,
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.seedColor)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(recipe.steps[i])),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            recipe.isAiGenerated
                ? 'AI-generated by Gemini and not tested. Check ingredients for allergies and always cook food thoroughly.'
                : 'Source: ${recipe.sourceName ?? 'Food.com / RecipeNLG'}. Check ingredients for allergies and always cook food thoroughly.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: available.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Update ingredients used'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => _recordUsage(context),
                ),
              ),
            ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient});
  final RecipeIngredient ingredient;

  @override
  Widget build(BuildContext context) {
    final item = ingredient.inventoryItem;
    final have = item == null ? '' : 'You have ${amountText(item.quantity, item.unit)}';
    final (IconData icon, Color color, String label) = switch (ingredient.status) {
      IngredientStatus.enough => (Icons.check_circle, AppTheme.seedColor, 'In stock'),
      IngredientStatus.notEnough => (Icons.error_outline, AppTheme.honey, 'Not enough · $have'),
      // AC 6.2.4 — can't compare, so ask instead of claiming it's enough.
      IngredientStatus.checkQuantity => (Icons.help_outline, AppTheme.ocean, 'Check quantity · $have'),
      IngredientStatus.missing => (Icons.radio_button_unchecked, Colors.grey, 'Not in inventory'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The recipe's original wording when there is one
                // ("2 tablespoons butter, melted"), else name + amount.
                Text(ingredient.notes != null && !ingredient.notes!.startsWith('AI-linked')
                    ? ingredient.notes!
                    : '${ingredient.name} — ${amountText(ingredient.quantity, ingredient.unit)}'),
                if (ingredient.isOptional || (ingredient.isStaple && !ingredient.isAvailable))
                  Text(ingredient.isOptional ? 'Optional' : 'Basic staple',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (item != null && item.name.toLowerCase() != ingredient.name.toLowerCase())
                  Text('Using: ${item.name}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
