// Epic 6 — recipe suggestions from the recipe dataset (Food.com /
// RecipeNLG, prepared by the data team). Everything here is calculated by
// the backend (GET /households/:id/recipe-suggestions): which items are
// available, ranking, and ingredient availability. Flutter only displays
// it, then sends back what was actually used
// (POST /households/:id/recipe-cook-sessions).

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
    required this.ingredientId,
    required this.name,
    required this.unit,
    required this.status,
    this.quantity,
    this.notes,
    this.isOptional = false,
    this.isStaple = false,
    this.inventoryItem,
    this.suggestedUseQuantity,
  });

  final String ingredientId;
  final String name;
  /// The original recipe line, e.g. "2 tablespoons butter, melted".
  final String? notes;
  final bool isOptional;
  /// Salt, water, pepper, sugar... Still shown as "not in inventory" (we
  /// never claim the user has them), but not held against the recipe.
  final bool isStaple;
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
        ingredientId: json['ingredientId'] as String,
        name: json['name'] as String,
        notes: json['notes'] as String?,
        isOptional: json['isOptional'] as bool? ?? false,
        isStaple: json['isStaple'] as bool? ?? false,
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
    this.servingUnit,
    this.prepMinutes,
    this.cookMinutes,
    this.totalMinutes,
    this.difficulty,
    this.cuisine,
    this.imageUrl,
    this.sourceName,
    this.sourceUrl,
    this.isAiGenerated = false,
  });

  final String id;
  /// From Gemini rather than the recipe dataset — labelled in the UI.
  final bool isAiGenerated;
  final String title;
  final String description;
  final double? servings;
  final String? servingUnit;
  // Kept separate on purpose (data team rule): never infer total time
  // from prep time, and leave unknown values empty.
  final int? prepMinutes;
  final int? cookMinutes;
  final int? totalMinutes;
  final String? difficulty;
  final String? cuisine;
  /// Remote image — may fail to load; the UI shows a placeholder then.
  final String? imageUrl;
  final String? sourceName;
  final String? sourceUrl;
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
        servings: (json['servings'] as num?)?.toDouble(),
        servingUnit: json['servingUnit'] as String?,
        prepMinutes: json['prepMinutes'] as int?,
        cookMinutes: json['cookMinutes'] as int?,
        totalMinutes: json['totalMinutes'] as int?,
        difficulty: json['difficulty'] as String?,
        cuisine: json['cuisine'] as String?,
        imageUrl: json['imageUrl'] as String?,
        sourceName: json['sourceName'] as String?,
        sourceUrl: json['sourceUrl'] as String?,
        isAiGenerated: json['origin'] == 'ai',
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
  });

  final RecipeSuggestionsStatus status;
  final List<Recipe> recipes;
  /// How many in-stock items expire within 3 days. 0 = AC 6.1.6 (the
  /// recipes use other available ingredients instead).
  final int expiringSoonCount;
  /// 'dataset' (the recipe dataset).
  final String? source;

  factory RecipeSuggestions.fromJson(Map<String, dynamic> json) => RecipeSuggestions(
        status: RecipeSuggestionsStatus.values.byName(json['status'] as String),
        recipes: ((json['recipes'] as List?) ?? const [])
            .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
            .toList(),
        expiringSoonCount: (json['expiringSoonCount'] as int?) ?? 0,
        source: json['source'] as String?,
      );
}

/// One inventory item in the "Update ingredients used" review (User
/// Story 6.3), in the item's own unit. Unticked items are sent too, with
/// [selected] false — recorded in the cooking session, never deducted.
class IngredientUse {
  const IngredientUse({
    required this.inventoryItemId,
    required this.selected,
    this.quantityUsed,
    this.ingredientId,
    this.plannedQuantity,
  });
  final String inventoryItemId;
  final bool selected;
  final double? quantityUsed;
  /// The recipe ingredient line this item was matched to.
  final String? ingredientId;
  /// What the recipe called for, converted to the item's unit, if known.
  final double? plannedQuantity;

  Map<String, dynamic> toJson() => {
        'inventoryItemId': inventoryItemId,
        'selected': selected,
        if (quantityUsed != null) 'quantityUsed': quantityUsed,
        if (ingredientId != null) 'ingredientId': ingredientId,
        if (plannedQuantity != null) 'plannedQuantity': plannedQuantity,
      };
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
  const RecipeUsageResult({required this.alreadyRecorded, required this.updated, this.sessionId});
  final String? sessionId;
  /// True when this exact submission had already been saved (a retry) —
  /// nothing was deducted a second time (AC 6.3.7).
  final bool alreadyRecorded;
  final List<IngredientUseResult> updated;

  factory RecipeUsageResult.fromJson(Map<String, dynamic> json) => RecipeUsageResult(
        sessionId: json['sessionId'] as String?,
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
