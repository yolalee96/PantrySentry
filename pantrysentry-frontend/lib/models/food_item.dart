/// Where an item is physically stored. Matches schema.sql `storage_types`
/// (FRIDGE/FREEZER/PANTRY).
///
/// Epic 2 — AC 2.2.1 / AC 2.5.1
enum StorageLocation { fridge, freezer, pantry }

extension StorageLocationLabel on StorageLocation {
  String get label {
    switch (this) {
      case StorageLocation.fridge:
        return 'Fridge';
      case StorageLocation.freezer:
        return 'Freezer';
      case StorageLocation.pantry:
        return 'Pantry';
    }
  }
}

/// Product category — matches schema.sql `product_categories`. The item
/// name itself stays free text for now (per team decision) rather than
/// picking from the `products` catalog, but the category is kept aligned
/// with the DB's taxonomy so the real shelf-life dataset (keyed by
/// category/product + storage type, same as `shelf_life_rules`) can slot
/// in later without another rename.
///
/// Last synced against insert_static_data.sql's 16 categories — note
/// "Household Items" no longer exists in the real data (replaced by more
/// specific categories like Eggs, Baked Goods, etc.), and category_ids 9
/// and 10 are intentionally skipped in the source data.
enum ProductCategory {
  dairy,
  meat,
  seafood,
  vegetables,
  fruits,
  snacks,
  beverages,
  frozenFood,
  babyFood,
  bakedGoods,
  condimentsSaucesCannedGoods,
  grainsBeansPasta,
  shelfStableFoods,
  vegetarianProteins,
  deliPreparedFoods,
  eggs,
}

extension ProductCategoryLabel on ProductCategory {
  String get label {
    switch (this) {
      case ProductCategory.dairy:
        return 'Dairy';
      case ProductCategory.meat:
        return 'Meat';
      case ProductCategory.seafood:
        return 'Seafood';
      case ProductCategory.vegetables:
        return 'Vegetables';
      case ProductCategory.fruits:
        return 'Fruits';
      case ProductCategory.snacks:
        return 'Snacks';
      case ProductCategory.beverages:
        return 'Beverages';
      case ProductCategory.frozenFood:
        return 'Frozen Food';
      case ProductCategory.babyFood:
        return 'Baby Food';
      case ProductCategory.bakedGoods:
        return 'Baked Goods';
      case ProductCategory.condimentsSaucesCannedGoods:
        return 'Condiments, Sauces & Canned Goods';
      case ProductCategory.grainsBeansPasta:
        return 'Grains, Beans & Pasta';
      case ProductCategory.shelfStableFoods:
        return 'Shelf-Stable Foods';
      case ProductCategory.vegetarianProteins:
        return 'Vegetarian Proteins';
      case ProductCategory.deliPreparedFoods:
        return 'Deli & Prepared Foods';
      case ProductCategory.eggs:
        return 'Eggs';
    }
  }

  /// Matches schema.sql `product_categories.is_fresh_food`.
  bool get isFreshFood => const {
        ProductCategory.dairy,
        ProductCategory.meat,
        ProductCategory.seafood,
        ProductCategory.vegetables,
        ProductCategory.fruits,
        ProductCategory.vegetarianProteins,
        ProductCategory.deliPreparedFoods,
        ProductCategory.eggs,
      }.contains(this);
}

/// What happened to an item once it left the inventory. Matches
/// schema.sql `inventory_items.status` (IN_STOCK maps to isActive==true).
enum ItemDisposition { consumed, discarded, donated }

/// The user's own stated reason for discarding — distinct from the
/// backend's separate auto-computed EXPIRED/USER_DISCARDED timing
/// classification on the transaction row (see backend README).
enum DiscardReason { spoiled, expiredNotSpoiled, qualityDeclined, overbought, forgotAboutIt, other }

extension DiscardReasonLabel on DiscardReason {
  String get label {
    switch (this) {
      case DiscardReason.spoiled:
        return 'Spoiled / unsafe to eat';
      case DiscardReason.expiredNotSpoiled:
        return 'Expired, but not visibly spoiled';
      case DiscardReason.qualityDeclined:
        return 'Quality declined';
      case DiscardReason.overbought:
        return 'Bought too much';
      case DiscardReason.forgotAboutIt:
        return 'Forgot about it';
      case DiscardReason.other:
        return 'Other reason';
    }
  }

  /// The string sent to/received from the backend (see
  /// VALID_DISCARD_REASONS in routes/inventory.js).
  String get apiValue {
    switch (this) {
      case DiscardReason.spoiled:
        return 'spoiled';
      case DiscardReason.expiredNotSpoiled:
        return 'expired_not_spoiled';
      case DiscardReason.qualityDeclined:
        return 'quality_declined';
      case DiscardReason.overbought:
        return 'overbought';
      case DiscardReason.forgotAboutIt:
        return 'forgot_about_it';
      case DiscardReason.other:
        return 'other';
    }
  }

  static DiscardReason? fromApiValue(String? value) {
    for (final r in DiscardReason.values) {
      if (r.apiValue == value) return r;
    }
    return null;
  }
}

/// How much of a consumed item was actually used.
enum ConsumedAmount { partial, half, full }

extension ConsumedAmountLabel on ConsumedAmount {
  String get label {
    switch (this) {
      case ConsumedAmount.partial:
        return 'Partially consumed';
      case ConsumedAmount.half:
        return 'Half consumed';
      case ConsumedAmount.full:
        return 'Fully consumed';
    }
  }

  String get apiValue {
    switch (this) {
      case ConsumedAmount.partial:
        return 'partial';
      case ConsumedAmount.half:
        return 'half';
      case ConsumedAmount.full:
        return 'full';
    }
  }

  static ConsumedAmount? fromApiValue(String? value) {
    for (final a in ConsumedAmount.values) {
      if (a.apiValue == value) return a;
    }
    return null;
  }
}

/// A single inventory item. Matches schema.sql `inventory_items`
/// (simplified: `name` stays free text here instead of a `product_id`
/// FK into a `products` catalog, per team decision).
///
/// Epic 2 — AC 2.1.1 / AC 2.6.1
class FoodItem {
  final String id;
  final String householdId;
  String name;
  double quantity;
  String unit;
  StorageLocation storageLocation;
  ProductCategory category;
  DateTime useByDate;
  final DateTime addedAt;
  final String addedByUserId;
  ItemDisposition? disposition; // null while still active in the inventory (IN_STOCK)
  DateTime? resolvedAt;
  /// Who actually performed the consume/discard/donate action — distinct
  /// from [addedByUserId] (whoever originally added it). Null until
  /// resolved. Personal ("My Stats") consumed/wasted counts must filter
  /// on this, not addedByUserId — otherwise a housemate eating something
  /// you added would count as your consumption, not theirs.
  String? resolvedByUserId;
  /// Optional free-text note — e.g. "half a bag left" for a large packet
  /// bought once but used gradually. Shown on the item card and detail
  /// screen; editable any time via the Edit Item screen.
  String? notes;
  /// Set only when [disposition] is discarded.
  DiscardReason? discardReason;
  /// Set only when [disposition] is consumed.
  ConsumedAmount? consumedAmount;
  /// Optional — what the user actually paid for this item (a total
  /// purchase price, not a per-unit figure). Null until they enter one;
  /// feeds the Progress tab's estimated-waste-value card when present,
  /// ahead of any placeholder/public-data estimate (User Story 5.5).
  double? price;
  /// Server-computed fallback estimate from public PriceCatcher data, for
  /// items whose product has a mapped price reference — only used when
  /// [price] hasn't been entered by the user. Never editable directly.
  final double? publicEstimatedPrice;

  FoodItem({
    required this.id,
    required this.householdId,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.storageLocation,
    required this.category,
    required this.useByDate,
    required this.addedByUserId,
    DateTime? addedAt,
    this.disposition,
    this.resolvedAt,
    this.resolvedByUserId,
    this.notes,
    this.discardReason,
    this.consumedAmount,
    this.price,
    this.publicEstimatedPrice,
  }) : addedAt = addedAt ?? DateTime.now();

  bool get isActive => disposition == null;

  int get daysLeft {
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final useByDateOnly =
        DateTime(useByDate.year, useByDate.month, useByDate.day);
    return useByDateOnly.difference(todayDateOnly).inDays;
  }

  /// Whether this item falls within its reminder window (Epic 2/3 — used
  /// for the "Expiring Soon" section, AC 2.3.1).
  bool isExpiringWithin(int days) => isActive && daysLeft <= days;
}
