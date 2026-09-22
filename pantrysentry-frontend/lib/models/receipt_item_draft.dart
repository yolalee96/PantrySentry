import 'food_item.dart';

/// One line item parsed from a receipt — mutable so the review screen can
/// let the user edit every field before anything is saved (nothing here
/// is ever written to inventory directly).
class ReceiptItemDraft {
  ReceiptItemDraft({
    required this.rawName,
    required this.barcode,
    required this.quantity,
    required this.unit,
    required this.totalPrice,
    required this.matched,
    this.category,
    this.storageLocation,
    this.included = true,
  }) : name = rawName;

  /// The name as originally parsed — kept for reference even after [name]
  /// is edited by the user.
  final String rawName;
  final String barcode;
  /// User-editable from here on.
  String name;
  double quantity;
  String unit;
  double totalPrice;
  ProductCategory? category;
  StorageLocation? storageLocation;
  DateTime? useByDate;
  /// True once the user has picked a date themselves via the date
  /// picker — shelf-life auto-fill must never overwrite that.
  bool dateManuallyEdited = false;
  /// Whether this line resolved to any candidate at all when parsed —
  /// false means "not recognized as a known food item", shown to the
  /// user as a flag rather than silently dropped (they paid for it).
  final bool matched;
  /// Whether this row should be included when "Add N items" is pressed —
  /// lets the user deselect a line without deleting it outright.
  bool included;

  factory ReceiptItemDraft.fromJson(Map<String, dynamic> json) {
    final candidates = (json['candidates'] as List?) ?? const [];
    final first = candidates.isNotEmpty ? candidates.first as Map<String, dynamic> : null;
    final categoryDartName = first?['categoryDartName'] as String?;
    final category = categoryDartName == null ? null : ProductCategory.values.byName(categoryDartName);
    return ReceiptItemDraft(
      rawName: json['rawName'] as String,
      barcode: json['barcode'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unit: json['unit'] as String,
      totalPrice: (json['totalPrice'] as num).toDouble(),
      matched: json['matched'] as bool,
      category: category,
    );
  }
}
