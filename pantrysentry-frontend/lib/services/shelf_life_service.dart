import '../models/food_item.dart';

/// Suggests a default expiry-reminder lead time based on the item's
/// [ProductCategory] + [StorageLocation] pair — the same key shape as
/// schema.sql's `shelf_life_rules` table (category_id, storage_type_id),
/// so this can be replaced by a real lookup once the shelf-life CSV
/// dataset is ready.
///
/// IMPORTANT: these numbers are placeholder estimates for iteration 1,
/// not sourced from the real dataset. Once the CSV arrives, replace the
/// body of [suggestLeadTime] (and ideally [suggestShelfLifeDays], which
/// mirrors `shelf_life_rules.min_days`/`max_days`) with a lookup against
/// it — keep the method signatures the same so nothing upstream changes.
class ShelfLifeService {
  /// Reminder lead time in days, keyed by "category|storage".
  static const Map<String, int> _defaultLeadTimeDays = {
    'dairy|fridge': 3,
    'dairy|freezer': 10,
    'meat|fridge': 2,
    'meat|freezer': 10,
    'seafood|fridge': 1,
    'seafood|freezer': 10,
    'vegetables|fridge': 3,
    'vegetables|freezer': 14,
    'fruits|fridge': 3,
    'fruits|freezer': 14,
    'snacks|pantry': 21,
    'beverages|pantry': 25,
    'frozenFood|freezer': 14,
    'babyFood|pantry': 21,
    'babyFood|fridge': 2,
    'bakedGoods|pantry': 5,
    'bakedGoods|freezer': 30,
    'condimentsSaucesCannedGoods|pantry': 30,
    'grainsBeansPasta|pantry': 30,
    'shelfStableFoods|pantry': 30,
    'vegetarianProteins|fridge': 5,
    'vegetarianProteins|freezer': 30,
    'deliPreparedFoods|fridge': 3,
    'eggs|fridge': 14,
  };

  /// Suggested shelf-life range in days, mirroring
  /// `shelf_life_rules.min_days`/`max_days`. Used to pre-fill/validate a
  /// use-by date once the item's purchase date is known — not yet wired
  /// into the add-item screen, but ready for when the CSV lands.
  static const Map<String, (int min, int max)> _defaultShelfLifeDaysRange = {
    'dairy|fridge': (5, 7),
    'dairy|freezer': (60, 180),
    'meat|fridge': (2, 4),
    'meat|freezer': (90, 365),
    'seafood|fridge': (1, 2),
    'seafood|freezer': (90, 180),
    'vegetables|fridge': (3, 7),
    'vegetables|freezer': (180, 365),
    'fruits|fridge': (3, 7),
    'fruits|freezer': (180, 365),
    'snacks|pantry': (180, 365),
    'beverages|pantry': (365, 730),
    'frozenFood|freezer': (90, 365),
    'babyFood|pantry': (180, 365),
    'babyFood|fridge': (1, 3),
    'bakedGoods|pantry': (3, 7),
    'bakedGoods|freezer': (60, 180),
    'condimentsSaucesCannedGoods|pantry': (365, 730),
    'grainsBeansPasta|pantry': (365, 730),
    'shelfStableFoods|pantry': (365, 730),
    'vegetarianProteins|fridge': (5, 10),
    'vegetarianProteins|freezer': (60, 180),
    'deliPreparedFoods|fridge': (3, 5),
    'eggs|fridge': (21, 35),
  };

  static String _key(ProductCategory category, StorageLocation location) =>
      '${category.name}|${location.name}';

  static int suggestLeadTime(ProductCategory category, StorageLocation location) {
    return _defaultLeadTimeDays[_key(category, location)] ?? 3;
  }

  static (int min, int max)? suggestShelfLifeDaysRange(
      ProductCategory category, StorageLocation location) {
    return _defaultShelfLifeDaysRange[_key(category, location)];
  }

  static String explanationFor(ProductCategory category, StorageLocation location) {
    final range = suggestShelfLifeDaysRange(category, location);
    final lead = suggestLeadTime(category, location);
    if (range == null) {
      return 'We\'ll suggest a $lead-day reminder — no shelf-life data yet for this combination.';
    }
    return 'Typically lasts ${range.$1}-${range.$2} days here — we\'ll suggest a $lead-day reminder.';
  }
}
