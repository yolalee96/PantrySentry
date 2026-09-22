// Dart's ProductCategory enum name -> product_categories.category_name
// IMPORTANT: this must exactly match category_id order/labels in
// insert_static_data.sql. Last synced against the 16-category version
// (category_id 9 and 10 are intentionally absent in the source data).
const CATEGORY_DB_NAMES = {
  dairy: 'Dairy',
  meat: 'Meat',
  seafood: 'Seafood',
  vegetables: 'Vegetables',
  fruits: 'Fruits',
  snacks: 'Snacks',
  beverages: 'Beverages',
  frozenFood: 'Frozen Food',
  babyFood: 'Baby Food',
  bakedGoods: 'Baked Goods',
  condimentsSaucesCannedGoods: 'Condiments, Sauces & Canned Goods',
  grainsBeansPasta: 'Grains, Beans & Pasta',
  shelfStableFoods: 'Shelf-Stable Foods',
  vegetarianProteins: 'Vegetarian Proteins',
  deliPreparedFoods: 'Deli & Prepared Foods',
  eggs: 'Eggs',
};
const CATEGORY_DART_NAMES = Object.fromEntries(
  Object.entries(CATEGORY_DB_NAMES).map(([dart, db]) => [db, dart])
);

// Dart's StorageLocation enum name -> storage_types.storage_name
const STORAGE_DB_NAMES = { fridge: 'FRIDGE', freezer: 'FREEZER', pantry: 'PANTRY' };
const STORAGE_DART_NAMES = Object.fromEntries(
  Object.entries(STORAGE_DB_NAMES).map(([dart, db]) => [db, dart])
);

module.exports = { CATEGORY_DB_NAMES, CATEGORY_DART_NAMES, STORAGE_DB_NAMES, STORAGE_DART_NAMES };
