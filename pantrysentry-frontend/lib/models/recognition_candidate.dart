import 'food_item.dart';

/// One suggested match from the backend's product_keyword_mapping table —
/// always shown for the user to confirm, never auto-applied (per the
/// recognition handover's acceptance checks).
class RecognitionCandidate {
  const RecognitionCandidate({
    required this.referenceId,
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.category,
    required this.matchedKeyword,
    required this.sourceName,
    this.sourceUrl,
  });

  final int referenceId;
  /// Null means this is a category-level reference, not one of the
  /// original catalogue products — the backend deliberately never
  /// upgrades this to a specific product automatically.
  final int? productId;
  final String productName;
  /// Display name straight from the database, e.g. "Condiments, Sauces &
  /// Canned Goods" — always safe to show even if [category] is null.
  final String categoryName;
  /// Parsed into this app's ProductCategory enum server-side (via the
  /// same mapping table used everywhere else in the app) — null only for
  /// the couple of category IDs intentionally absent from the 16-category
  /// set, in which case the form leaves category for manual entry.
  final ProductCategory? category;
  final String matchedKeyword;
  final String sourceName;
  final String? sourceUrl;

  factory RecognitionCandidate.fromJson(Map<String, dynamic> json) => RecognitionCandidate(
        referenceId: json['referenceId'] as int,
        productId: json['productId'] as int?,
        productName: json['productName'] as String,
        categoryName: json['categoryName'] as String,
        category: json['categoryDartName'] == null
            ? null
            : ProductCategory.values.byName(json['categoryDartName'] as String),
        matchedKeyword: json['matchedKeyword'] as String,
        sourceName: json['sourceName'] as String,
        sourceUrl: json['sourceUrl'] as String?,
      );
}

/// Result of a barcode recognition call — the raw Open Food Facts product
/// info (if any) plus whatever candidates the mapping table produced from
/// its category tags.
class BarcodeRecognitionResult {
  const BarcodeRecognitionResult({required this.productName, required this.brand, required this.candidates});
  final String? productName;
  final String? brand;
  final List<RecognitionCandidate> candidates;
}

/// Result of an OCR recognition call — the raw extracted text (shown to
/// the user, never trusted silently — see the handover's OCR caveats)
/// plus whatever candidates matched from it.
class OcrRecognitionResult {
  const OcrRecognitionResult({required this.rawText, required this.candidates});
  final String rawText;
  final List<RecognitionCandidate> candidates;
}
