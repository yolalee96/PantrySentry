/// Matches schema.sql `shelf_life_rules.rule_status`.
enum ShelfLifeRuleStatus {
  /// A specific day-range recommendation is available.
  available,

  /// No day range — only qualitative handling guidance (see [ShelfLifeSuggestion.sourceText]).
  qualitativeOnly,

  /// This storage method isn't recommended for this item at all (e.g.
  /// seafood in the pantry) — show a warning, not a day countdown.
  notRecommended,
}

/// A real, sourced shelf-life recommendation from the `shelf_life_rules`
/// dataset (FDA/USDA/etc. citations) — see ShelfLifeService for how the
/// app looks this up and falls back when nothing matches yet.
class ShelfLifeSuggestion {
  final ShelfLifeRuleStatus status;
  final int? minDays;
  final int? maxDays;
  final double? recommendedDays;

  /// The real, sourced fact (e.g. "1-2 Days refrigerated" or "Maximum 2
  /// hours at 25-30C; room-temperature storage is not recommended.") —
  /// safe to show directly to users. NEVER use `handling_notes` from the
  /// database for user-facing text; those are internal dev instructions.
  final String? sourceText;
  final String? sourceName;

  /// Set when the typed item name matched a specific product in the
  /// dataset (e.g. "Chicken Breast") rather than falling back to a
  /// generic category-level rule — shown to the user for transparency.
  final String? matchedProductName;

  ShelfLifeSuggestion({
    required this.status,
    this.minDays,
    this.maxDays,
    this.recommendedDays,
    this.sourceText,
    this.sourceName,
    this.matchedProductName,
  });

  factory ShelfLifeSuggestion.fromJson(Map<String, dynamic> json) {
    return ShelfLifeSuggestion(
      status: switch (json['status'] as String) {
        'notRecommended' => ShelfLifeRuleStatus.notRecommended,
        'qualitativeOnly' => ShelfLifeRuleStatus.qualitativeOnly,
        _ => ShelfLifeRuleStatus.available,
      },
      minDays: json['minDays'] as int?,
      maxDays: json['maxDays'] as int?,
      recommendedDays: (json['recommendedDays'] as num?)?.toDouble(),
      sourceText: json['sourceText'] as String?,
      sourceName: json['sourceName'] as String?,
      matchedProductName: json['matchedProductName'] as String?,
    );
  }
}
