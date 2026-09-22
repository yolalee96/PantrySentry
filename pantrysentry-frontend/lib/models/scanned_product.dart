import 'food_item.dart';

/// Result of a barcode lookup (User Story 4.1) — feeds the Add Item form's
/// pre-fill step (4.4: user still reviews/edits everything before saving).
///
/// [category] and [suggestedLocation] are best-effort guesses. Either can
/// be null (product found but uncategorised, or category has no sensible
/// default storage location) — the form just leaves that field blank for
/// the user to pick themselves rather than guessing wrong.
class ScannedProduct {
  const ScannedProduct({
    required this.barcode,
    required this.name,
    this.category,
    this.suggestedLocation,
    this.brand,
  });

  final String barcode;
  final String name;
  final ProductCategory? category;
  final StorageLocation? suggestedLocation;
  final String? brand;
}
