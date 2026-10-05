// Epic 7 — food donation. Centres, accepted foods and the per-item checks
// all come from the backend (data team's donation tables); Flutter only
// displays them and sends back what the user chose.

import 'food_item.dart';

/// Must match CONDITIONS in the backend (routes/donations.js).
const List<String> kDonationConditions = [
  'Sealed / unopened',
  'Opened, in good condition',
  'Fresh, in good condition',
];

/// How a centre's accepted-food list covers one of the user's items.
enum DonationCheckResult {
  /// A listed food matches the item by name ("Rice" for Rice).
  listed,

  /// Only other foods of the same category are listed — check first.
  similar,

  /// The centre has a list, but nothing in this category.
  notListed,

  /// The centre hasn't published a verified list — contact them.
  noList,
}

class AcceptedFood {
  const AcceptedFood({required this.category, required this.itemName, this.notes});
  final ProductCategory category;
  final String itemName;
  final String? notes;

  factory AcceptedFood.fromJson(Map<String, dynamic> json) => AcceptedFood(
        category: _categoryFrom(json['category']),
        itemName: json['itemName'] as String,
        notes: json['notes'] as String?,
      );
}

class ItemCheck {
  const ItemCheck({required this.inventoryItemId, required this.result, this.matchedFood});
  final String inventoryItemId;
  final DonationCheckResult result;
  /// The listed food that matched ('listed'), or the foods listed in the
  /// same category ('similar').
  final String? matchedFood;

  factory ItemCheck.fromJson(Map<String, dynamic> json) => ItemCheck(
        inventoryItemId: json['inventoryItemId'] as String,
        result: DonationCheckResult.values.byName(json['result'] as String),
        matchedFood: json['matchedFood'] as String?,
      );
}

class DonationCentre {
  const DonationCentre({
    required this.id,
    required this.name,
    required this.type,
    required this.addressLine1,
    required this.acceptedFoods,
    required this.itemChecks,
    this.description,
    this.requirements,
    this.city,
    this.state,
    this.postcode,
    this.latitude,
    this.longitude,
    this.phone,
    this.email,
    this.websiteUrl,
    this.operatingHours,
    this.sourceUrl,
    this.distanceKm,
    this.listedItemCount = 0,
    this.similarItemCount = 0,
  });

  final String id;
  final String name;
  /// careHome, ngo, foodBank, pantryDropOff, ...
  final String type;
  final String? description;
  /// Free text from the centre's own source — shown as written.
  final String? requirements;
  final String addressLine1;
  final String? city;
  final String? state;
  final String? postcode;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String? email;
  final String? websiteUrl;
  final String? operatingHours;
  final String? sourceUrl;
  /// Null unless the user shared their location.
  final double? distanceKm;
  final List<AcceptedFood> acceptedFoods;
  final List<ItemCheck> itemChecks;
  final int listedItemCount;
  final int similarItemCount;

  String get typeLabel => switch (type) {
        'careHome' => 'Care home',
        'ngo' => 'NGO',
        'foodBank' => 'Food bank',
        'communityCentre' => 'Community centre',
        'religiousOrg' => 'Religious organisation',
        'pantryDropOff' => 'Pantry drop-off',
        'communityFridge' => 'Community fridge',
        _ => 'Organisation',
      };

  String get fullAddress => [addressLine1, postcode, city, state]
      .where((p) => p != null && p.trim().isNotEmpty)
      .map((p) => p!.trim())
      .join(', ');

  ItemCheck? checkFor(String inventoryItemId) {
    for (final c in itemChecks) {
      if (c.inventoryItemId == inventoryItemId) return c;
    }
    return null;
  }

  factory DonationCentre.fromJson(Map<String, dynamic> json) => DonationCentre(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        description: json['description'] as String?,
        requirements: json['requirements'] as String?,
        addressLine1: json['addressLine1'] as String,
        city: json['city'] as String?,
        state: json['state'] as String?,
        postcode: json['postcode'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        websiteUrl: json['websiteUrl'] as String?,
        operatingHours: json['operatingHours'] as String?,
        sourceUrl: json['sourceUrl'] as String?,
        distanceKm: (json['distanceKm'] as num?)?.toDouble(),
        acceptedFoods: ((json['acceptedFoods'] as List?) ?? const [])
            .map((e) => AcceptedFood.fromJson(e as Map<String, dynamic>))
            .toList(),
        itemChecks: ((json['itemChecks'] as List?) ?? const [])
            .map((e) => ItemCheck.fromJson(e as Map<String, dynamic>))
            .toList(),
        listedItemCount: (json['listedItemCount'] as int?) ?? 0,
        similarItemCount: (json['similarItemCount'] as int?) ?? 0,
      );
}

/// An inventory item as offered in the donation item picker.
class DonatableItem {
  const DonatableItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.reservedQuantity,
    required this.availableToDonate,
    required this.isExpired,
    this.expiryDate,
  });

  final String id;
  final String name;
  final ProductCategory category;
  final double quantity;
  final String unit;
  final DateTime? expiryDate;
  /// Already promised to the household's other pending donations.
  final double reservedQuantity;
  final double availableToDonate;
  final bool isExpired;

  bool get canDonate => !isExpired && availableToDonate > 0;

  factory DonatableItem.fromJson(Map<String, dynamic> json) => DonatableItem(
        id: json['id'] as String,
        name: json['name'] as String,
        category: _categoryFrom(json['category']),
        quantity: (json['quantity'] as num).toDouble(),
        unit: json['unit'] as String,
        expiryDate: _parseDate(json['expiryDate']),
        reservedQuantity: (json['reservedQuantity'] as num).toDouble(),
        availableToDonate: (json['availableToDonate'] as num).toDouble(),
        isExpired: json['isExpired'] as bool? ?? false,
      );
}

/// One item the user is putting into a donation.
class DonationDraftItem {
  DonationDraftItem({required this.inventoryItemId, required this.quantity, required this.condition});
  final String inventoryItemId;
  double quantity;
  String? condition;

  Map<String, dynamic> toJson() => {'inventoryItemId': inventoryItemId, 'quantity': quantity, 'condition': condition};
}

enum DonationStatus { pending, completed, cancelled }

class DonationItem {
  const DonationItem({
    required this.id,
    required this.inventoryItemId,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.delivered,
    required this.itemStillInStock,
    required this.currentQuantity,
    this.condition,
    this.expiryDate,
  });

  final String id;
  final String inventoryItemId;
  final String name;
  final double quantity;
  final String unit;
  final String? condition;
  final DateTime? expiryDate;
  final bool delivered;
  final bool itemStillInStock;
  final double currentQuantity;

  factory DonationItem.fromJson(Map<String, dynamic> json) => DonationItem(
        id: json['id'] as String,
        inventoryItemId: json['inventoryItemId'] as String,
        name: json['name'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        unit: json['unit'] as String,
        condition: json['condition'] as String?,
        expiryDate: _parseDate(json['expiryDate']),
        delivered: json['delivered'] as bool? ?? false,
        itemStillInStock: json['itemStillInStock'] as bool? ?? true,
        currentQuantity: (json['currentQuantity'] as num?)?.toDouble() ?? 0,
      );
}

class Donation {
  const Donation({
    required this.id,
    required this.status,
    required this.centreId,
    required this.centreName,
    required this.items,
    required this.createdAt,
    this.centreAddress,
    this.centrePhone,
    this.centreHours,
    this.notes,
    this.completedAt,
  });

  final String id;
  final DonationStatus status;
  final String centreId;
  final String centreName;
  final String? centreAddress;
  final String? centrePhone;
  final String? centreHours;
  final String? notes;
  final DateTime createdAt;
  final DateTime? completedAt;
  final List<DonationItem> items;

  factory Donation.fromJson(Map<String, dynamic> json) {
    final centre = json['centre'] as Map<String, dynamic>;
    return Donation(
      id: json['id'] as String,
      status: DonationStatus.values.byName(json['status'] as String),
      centreId: centre['id'] as String,
      centreName: centre['name'] as String,
      centreAddress: [centre['addressLine1'], centre['city']].whereType<String>().join(', '),
      centrePhone: centre['phone'] as String?,
      centreHours: centre['operatingHours'] as String?,
      notes: json['notes'] as String?,
      createdAt: _parseUtc(json['createdAt'])!,
      completedAt: _parseUtc(json['completedAt']),
      items: ((json['items'] as List?) ?? const [])
          .map((e) => DonationItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

ProductCategory _categoryFrom(Object? name) {
  for (final c in ProductCategory.values) {
    if (c.name == name) return c;
  }
  return ProductCategory.shelfStableFoods;
}

/// 'YYYY-MM-DD' -> local calendar date.
DateTime? _parseDate(Object? value) {
  if (value is! String || value.length < 10) return null;
  final p = value.substring(0, 10).split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// DATETIME from the server ('YYYY-MM-DD HH:MM:SS', UTC) -> local time.
DateTime? _parseUtc(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final s = value.replaceFirst(' ', 'T');
  return DateTime.parse(s.endsWith('Z') || s.contains('+') ? s : '${s}Z').toLocal();
}
