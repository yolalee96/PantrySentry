import 'package:flutter/material.dart';

import '../../models/recipe.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "expires today (3 Oct)", "expires tomorrow (4 Oct)", "expires in 3 days (6 Oct)".
String expiryPhrase(int daysLeft, DateTime date) {
  final d = '${date.day} ${_months[date.month - 1]}';
  if (daysLeft <= 0) return 'expires today ($d)';
  if (daysLeft == 1) return 'expires tomorrow ($d)';
  return 'expires in $daysLeft days ($d)';
}

/// 2.0 -> "2", 0.25 -> "0.25", 1.333333 -> "1.33"
String formatQuantity(double q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// "300 g", "2 pcs", "to taste"
String amountText(double? quantity, String unit) {
  if (quantity == null) return unit.isEmpty ? 'to taste' : unit;
  return unit.isEmpty ? formatQuantity(quantity) : '${formatQuantity(quantity)} $unit';
}

/// "Serves 4 · 25 min" for cards. Uses the recorded total time only —
/// never adds up or guesses a total (data team rule).
String recipeMetaLine(Recipe recipe) => [
      if (recipe.servings != null) 'Serves ${formatQuantity(recipe.servings!)}${recipe.servingUnit != null ? ' ${recipe.servingUnit}' : ''}',
      if (recipe.totalMinutes != null) '${recipe.totalMinutes} min',
    ].join(' · ');

/// "Prep 10 min · Cook 15 min · Total 25 min" — each shown only if recorded.
String recipeTimesLine(Recipe recipe) => [
      if (recipe.prepMinutes != null) 'Prep ${recipe.prepMinutes} min',
      if (recipe.cookMinutes != null) 'Cook ${recipe.cookMinutes} min',
      if (recipe.totalMinutes != null) 'Total ${recipe.totalMinutes} min',
    ].join(' · ');

/// Recipe photo with a neutral placeholder while loading or if the link
/// is broken (images are remote and not bundled — availability can change).
class RecipeImage extends StatelessWidget {
  const RecipeImage({super.key, required this.url, required this.height, this.isAi = false});
  final String? url;
  final double height;
  final bool isAi;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      height: height,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Icon(isAi ? Icons.auto_awesome : Icons.restaurant, color: Colors.grey.shade500, size: height * 0.3),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return Image.network(
      url!,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (context, child, progress) => progress == null ? child : placeholder,
    );
  }
}

/// Small "AI-generated" label for Gemini recipes.
class AiBadge extends StatelessWidget {
  const AiBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 12, color: Colors.deepPurple.shade400),
          const SizedBox(width: 4),
          Text('AI-generated', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade400)),
        ],
      ),
    );
  }
}
