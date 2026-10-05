import 'food_item.dart';

/// Confidence Gemini gave a detected item. Low/medium are flagged on the
/// review screen as "check this".
enum DetectionConfidence { high, medium, low }

/// One item found by "Scan several items" (Epic 4) — mutable so the review
/// screen can edit everything before saving. Nothing here is written to
/// the inventory until the user confirms.
class DetectedItemDraft {
  DetectedItemDraft({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.confidence,
    required this.matched,
    this.category,
    this.referenceName,
    this.boxes = const [],
    this.addedManually = false,
  });

  /// "+ Add something it missed" — an empty row the user fills in.
  factory DetectedItemDraft.manual() => DetectedItemDraft(
        name: '',
        quantity: 1,
        unit: 'pcs',
        confidence: DetectionConfidence.high,
        matched: false,
        addedManually: true,
      );

  String name;
  double quantity;
  String unit;
  ProductCategory? category;
  StorageLocation? storageLocation;
  DateTime? useByDate;
  /// True once the user picked a date — shelf-life auto-fill never overwrites it.
  bool dateManuallyEdited = false;
  bool included = true;

  final DetectionConfidence confidence;
  /// Linked to the reference data (gives the Impact tab and recipes a match).
  final bool matched;
  final String? referenceName;
  /// [ymin, xmin, ymax, xmax] on a 0–1000 scale of the photo.
  final List<List<int>> boxes;
  final bool addedManually;

  bool get needsCheck => !addedManually && confidence != DetectionConfidence.high;

  factory DetectedItemDraft.fromJson(Map<String, dynamic> json) {
    final categoryName = json['categoryDartName'] as String?;
    ProductCategory? category;
    for (final c in ProductCategory.values) {
      if (c.name == categoryName) category = c;
    }
    return DetectedItemDraft(
      name: json['name'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      unit: json['unit'] as String,
      category: category,
      matched: json['matched'] as bool? ?? false,
      referenceName: json['referenceName'] as String?,
      confidence: DetectionConfidence.values.byName(json['confidence'] as String? ?? 'low'),
      boxes: ((json['boxes'] as List?) ?? const [])
          .map((b) => (b as List).map((n) => (n as num).toInt()).toList())
          .where((b) => b.length == 4)
          .toList(),
    );
  }
}
