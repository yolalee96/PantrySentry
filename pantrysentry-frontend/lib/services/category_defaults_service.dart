import '../models/food_item.dart';

/// Suggests a default [StorageLocation] for a [ProductCategory] — used to
/// pre-fill the storage location field right after a barcode scan (User
/// Story 4.1) or photo recognition (4.3, later), before the real
/// shelf-life dataset is available.
///
/// IMPORTANT: these are placeholder "most likely" defaults for iteration 2,
/// not sourced from the real dataset — once the CSV/schema data lands,
/// consider deriving this from ShelfLifeRepository.getStorageSuggestions
/// instead (e.g. whichever location has the best-status rule), and keep
/// this as the fallback for categories with no rule data. The suggested
/// location is always shown as a pre-selected, editable field — never
/// submitted without the user seeing it (AC 4.1, 4.4).
class CategoryDefaultsService {
  static const Map<ProductCategory, StorageLocation> _defaultLocation = {
    ProductCategory.dairy: StorageLocation.fridge,
    ProductCategory.meat: StorageLocation.fridge,
    ProductCategory.seafood: StorageLocation.fridge,
    ProductCategory.vegetables: StorageLocation.fridge,
    ProductCategory.fruits: StorageLocation.fridge,
    ProductCategory.snacks: StorageLocation.pantry,
    ProductCategory.beverages: StorageLocation.pantry,
    ProductCategory.frozenFood: StorageLocation.freezer,
    ProductCategory.babyFood: StorageLocation.pantry,
    ProductCategory.bakedGoods: StorageLocation.pantry,
    ProductCategory.condimentsSaucesCannedGoods: StorageLocation.pantry,
    ProductCategory.grainsBeansPasta: StorageLocation.pantry,
    ProductCategory.shelfStableFoods: StorageLocation.pantry,
    ProductCategory.vegetarianProteins: StorageLocation.fridge,
    ProductCategory.deliPreparedFoods: StorageLocation.fridge,
    ProductCategory.eggs: StorageLocation.fridge,
  };

  static StorageLocation? suggestLocation(ProductCategory? category) {
    if (category == null) return null;
    return _defaultLocation[category];
  }
}
