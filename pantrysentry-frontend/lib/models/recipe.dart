/// Epic 6 — recipe suggestions. Everything here is calculated by the
/// backend (GET /households/:id/recipe-suggestions): which items are
/// available, ranking, and ingredient availability. Flutter only displays
/// it, then sends back what was actually used (POST .../recipe-usage).

/// Overall result of a suggestions request.
enum RecipeSuggestionsStatus {
  /// At least one recipe matched the inventory.
  ready,

  /// There is inventory, but no recipe matched it (AC 6.1.7).
  noMatches,

  /// Nothing in stock that a recipe could use (everything used up,
  /// removed or past its expiry date).
  noInventory,
}

/// How one recipe ingredient compares with the household inventory
/// (AC 6.2.2–6.2.4).
enum IngredientStatus {
  /// In the inventory, and there's enough of it.
  enough,

  /// In the inventory, but not enough of it.
  notEnough,

  /// In the inventory, but the amounts can't be compared reliably
  /// (e.g. recipe says "300 g", inventory says "2 pcs") — the user is
  /// asked to check rather than told it's sufficient.
  checkQuantity,

  /// Not in the household inventory.
  missing,
}

/// The inventory item a recipe ingredient was matched to, as it stands now.
class MatchedInventoryItem {
  const MatchedInventoryItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    this.expiryDate,
    this.daysLeft,
  });

  final String id;
  final String name;
  final double quantity;
  final String unit;
  /// Calendar date (no time) — null if the item has no expiry recorded.
  final DateTime? expiryDate;
  final int? daysLeft;

  factory MatchedInventoryItem.fromJson(Map<String, dynamic> json) => MatchedInventoryItem(
        id: json['id'] as String,
        name: json['name'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        unit: json['unit'] as String,
        expiryDate: _parseDate(json['expiryDate']),
        daysLeft: json['daysLeft'] as int?,
      );
}

class RecipeIngredient {
  const RecipeIngredient({
    required this.name,
    required this.unit,
    required this.status,
    this.quantity,
    this.inventoryItem,
    this.suggestedUseQuantity,
  });

  final String name;
  /// Null for "to taste" amounts.
  final double? quantity;
  final String unit;
  final IngredientStatus status;
  final MatchedInventoryItem? inventoryItem;
  /// Pre-filled amount for "Update ingredients used", in the INVENTORY
  /// item's unit — null when the units couldn't be converted, so the user
  /// enters it themselves.
  final double? suggestedUseQuantity;

  bool get isAvailable => inventoryItem != null;

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) => RecipeIngredient(
        name: json['name'] as String,
        quantity: (json['quantity'] as num?)?.toDouble(),
        unit: (json['unit'] as String?) ?? '',
        status: IngredientStatus.values.byName(json['status'] as String),
        inventoryItem: json['inventoryItem'] == null
            ? null
            : MatchedInventoryItem.fromJson(json['inventoryItem'] as Map<String, dynamic>),
        suggestedUseQuantity: (json['suggestedUseQuantity'] as num?)?.toDouble(),
      );
}

/// A matched inventory item expiring within 3 days — shown on the recipe
/// card to explain why it's suggested (AC 6.1.3).
class ExpiringMatch {
  const ExpiringMatch({required this.inventoryItemId, required this.name, required this.expiryDate, required this.daysLeft});
  final String inventoryItemId;
  final String name;
  final DateTime expiryDate;
  final int daysLeft;

  factory ExpiringMatch.fromJson(Map<String, dynamic> json) => ExpiringMatch(
        inventoryItemId: json['inventoryItemId'] as String,
        name: json['name'] as String,
        expiryDate: _parseDate(json['expiryDate'])!,
        daysLeft: json['daysLeft'] as int,
      );
}

class Recipe {
  const Recipe({
    required this.id,
    required this.title,
    required this.description,
    required this.steps,
    required this.ingredients,
    required this.expiringMatches,
    required this.matchedCount,
    required this.missingCount,
    this.servings,
    this.prepMinutes,
  });

  final String id;
  final String title;
  final String description;
  final int? servings;
  final int? prepMinutes;
  final List<String> steps;
  final List<RecipeIngredient> ingredients;
  final List<ExpiringMatch> expiringMatches;
  final int matchedCount;
  final int missingCount;

  bool get usesExpiringSoon => expiringMatches.isNotEmpty;

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
        id: json['id'] as String,
        title: json['title'] as String,
        description: (json['description'] as String?) ?? '',
        servings: json['servings'] as int?,
        prepMinutes: json['prepMinutes'] as int?,
        steps: (json['steps'] as List).cast<String>(),
        ingredients: (json['ingredients'] as List)
            .map((e) => RecipeIngredient.fromJson(e as Map<String, dynamic>))
            .toList(),
        expiringMatches: ((json['expiringMatches'] as List?) ?? const [])
            .map((e) => ExpiringMatch.fromJson(e as Map<String, dynamic>))
            .toList(),
        matchedCount: json['matchedCount'] as int,
        missingCount: json['missingCount'] as int,
      );
}

class RecipeSuggestions {
  const RecipeSuggestions({
    required this.status,
    required this.recipes,
    required this.expiringSoonCount,
    this.source,
    this.generatedAt,
  });

  final RecipeSuggestionsStatus status;
  final List<Recipe> recipes;
  /// How many in-stock items expire within 3 days. 0 = AC 6.1.6 (the
  /// recipes use other available ingredients instead).
  final int expiringSoonCount;
  /// 'llm' for now; 'dataset' once the recipe dataset is added.
  final String? source;
  final DateTime? generatedAt;

  factory RecipeSuggestions.fromJson(Map<String, dynamic> json) => RecipeSuggestions(
        status: RecipeSuggestionsStatus.values.byName(json['status'] as String),
        recipes: ((json['recipes'] as List?) ?? const [])
            .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
            .toList(),
        expiringSoonCount: (json['expiringSoonCount'] as int?) ?? 0,
        source: json['source'] as String?,
        generatedAt: json['generatedAt'] == null ? null : DateTime.parse(json['generatedAt'] as String).toLocal(),
      );
}

/// One ingredient the user confirms they used (User Story 6.3), in the
/// inventory item's own unit.
class IngredientUse {
  const IngredientUse({required this.inventoryItemId, required this.quantityUsed});
  final String inventoryItemId;
  final double quantityUsed;

  Map<String, dynamic> toJson() => {'inventoryItemId': inventoryItemId, 'quantityUsed': quantityUsed};
}

class IngredientUseResult {
  const IngredientUseResult({
    required this.inventoryItemId,
    required this.name,
    required this.quantityUsed,
    required this.remainingQuantity,
    required this.unit,
    required this.fullyUsed,
  });

  final String inventoryItemId;
  final String name;
  final double quantityUsed;
  final double remainingQuantity;
  final String unit;
  final bool fullyUsed;

  factory IngredientUseResult.fromJson(Map<String, dynamic> json) => IngredientUseResult(
        inventoryItemId: json['inventoryItemId'] as String,
        name: json['name'] as String,
        quantityUsed: (json['quantityUsed'] as num).toDouble(),
        remainingQuantity: (json['remainingQuantity'] as num).toDouble(),
        unit: json['unit'] as String,
        fullyUsed: json['fullyUsed'] as bool,
      );
}

class RecipeUsageResult {
  const RecipeUsageResult({required this.alreadyRecorded, required this.updated});
  /// True when this exact submission had already been saved (a retry) —
  /// nothing was deducted a second time (AC 6.3.7).
  final bool alreadyRecorded;
  final List<IngredientUseResult> updated;

  factory RecipeUsageResult.fromJson(Map<String, dynamic> json) => RecipeUsageResult(
        alreadyRecorded: json['alreadyRecorded'] as bool? ?? false,
        updated: ((json['updated'] as List?) ?? const [])
            .map((e) => IngredientUseResult.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 'YYYY-MM-DD' -> a local calendar date (no UTC shift).
DateTime? _parseDate(Object? value) {
  if (value is! String || value.length < 10) return null;
  final parts = value.substring(0, 10).split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}
