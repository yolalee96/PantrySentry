import '../../models/recipe.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "expires today (3 Oct)", "expires tomorrow (4 Oct)", "expires in 3 days (6 Oct)".
String expiryPhrase(int daysLeft, DateTime date) {
  final d = '${date.day} ${_months[date.month - 1]}';
  if (daysLeft <= 0) return 'expires today ($d)';
  if (daysLeft == 1) return 'expires tomorrow ($d)';
  return 'expires in $daysLeft days ($d)';
}

/// "Serves 2 · 20 min"
String recipeMetaLine(Recipe recipe) => [
      if (recipe.servings != null) 'Serves ${recipe.servings}',
      if (recipe.prepMinutes != null) '${recipe.prepMinutes} min',
    ].join(' · ');

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
