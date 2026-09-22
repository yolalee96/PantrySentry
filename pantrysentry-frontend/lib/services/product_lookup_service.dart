import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/food_item.dart';
import '../models/scanned_product.dart';
import 'category_defaults_service.dart';

/// Thrown on a network/server failure (not on "barcode not found" — that's
/// a normal, expected outcome represented by [ProductLookupService.lookup]
/// returning null, since plenty of packaged goods just aren't in the
/// Open Food Facts database).
class ProductLookupException implements Exception {
  ProductLookupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Looks up a scanned barcode against the free, community-run Open Food
/// Facts database (https://world.openfoodfacts.org) — no API key needed.
/// Stands in for a household's own product catalog until the team's
/// database/dataset is ready (see PantryBuddy_Handoff.md); swap the body
/// of [lookup] for a real DB-backed lookup later if desired, keeping the
/// same [ScannedProduct]-returning signature so callers don't change.
class ProductLookupService {
  static const _baseUrl = 'https://world.openfoodfacts.org/api/v2/product';

  /// Returns null if the barcode isn't in Open Food Facts' database (a
  /// normal outcome — the user just falls back to typing the name in
  /// themselves). Throws [ProductLookupException] on a network/server
  /// error, so the caller can distinguish "not found" from "couldn't
  /// check" and word its message accordingly.
  static Future<ScannedProduct?> lookup(String barcode) async {
    final uri = Uri.parse(
      '$_baseUrl/$barcode.json?fields=product_name,product_name_en,categories_tags,brands',
    );

    final http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw ProductLookupException('Couldn\'t reach the product database. Check your connection and try again, or enter the item manually.');
    }

    if (response.statusCode == 404) {
      // Open Food Facts is documented to return 200 + {"status":0} for an
      // unknown barcode, but in practice sometimes returns a plain 404
      // for the same case — treat both the same way: a normal miss, not
      // a failure.
      return null;
    }

    if (response.statusCode != 200) {
      throw ProductLookupException('Product lookup failed (server returned ${response.statusCode}). Try again, or enter the item manually.');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw ProductLookupException('Got an unexpected response from the product database. Try again, or enter the item manually.');
    }

    // v2 API: status == 1 means found, 0 means not in the database.
    if (body['status'] != 1) return null;

    final product = body['product'] as Map<String, dynamic>?;
    if (product == null) return null;

    final name = (product['product_name_en'] as String?)?.trim().isNotEmpty == true
        ? (product['product_name_en'] as String).trim()
        : (product['product_name'] as String?)?.trim();
    if (name == null || name.isEmpty) return null; // no usable name — not worth pre-filling

    final tags = (product['categories_tags'] as List?)?.cast<String>() ?? const [];
    final category = _guessCategory(tags);
    final brand = (product['brands'] as String?)?.split(',').first.trim();

    return ScannedProduct(
      barcode: barcode,
      name: name,
      category: category,
      suggestedLocation: CategoryDefaultsService.suggestLocation(category),
      brand: (brand?.isEmpty ?? true) ? null : brand,
    );
  }

  /// Heuristic keyword match against Open Food Facts' `categories_tags`
  /// (e.g. "en:dairies", "en:frozen-foods") -> our [ProductCategory]
  /// taxonomy. Checked in order, first match wins, most-specific keywords
  /// first (e.g. "cheese" before the more general "dairy") so a product
  /// tagged with several categories lands on the more useful one. Returns
  /// null on no match — the form just leaves category blank for the user
  /// to pick, same as an unmatched item name today.
  static ProductCategory? _guessCategory(List<String> tags) {
    final joined = tags.join(' ').toLowerCase();
    bool has(String kw) => joined.contains(kw);

    const rules = <(String, ProductCategory)>[
      ('frozen', ProductCategory.frozenFood),
      ('baby', ProductCategory.babyFood),
      ('egg', ProductCategory.eggs),
      ('seafood', ProductCategory.seafood),
      ('fish', ProductCategory.seafood),
      ('shellfish', ProductCategory.seafood),
      ('meat', ProductCategory.meat),
      ('poultry', ProductCategory.meat),
      ('sausage', ProductCategory.meat),
      ('charcuterie', ProductCategory.meat),
      ('tofu', ProductCategory.vegetarianProteins),
      ('tempeh', ProductCategory.vegetarianProteins),
      ('plant-based-foods-and-beverages', ProductCategory.vegetarianProteins),
      ('meal', ProductCategory.deliPreparedFoods),
      ('prepared', ProductCategory.deliPreparedFoods),
      ('deli', ProductCategory.deliPreparedFoods),
      ('cheese', ProductCategory.dairy),
      ('yogurt', ProductCategory.dairy),
      ('yoghurt', ProductCategory.dairy),
      ('milk', ProductCategory.dairy),
      ('dair', ProductCategory.dairy),
      ('bread', ProductCategory.bakedGoods),
      ('bakery', ProductCategory.bakedGoods),
      ('pastr', ProductCategory.bakedGoods),
      ('cake', ProductCategory.bakedGoods),
      ('vegetable', ProductCategory.vegetables),
      ('fruit', ProductCategory.fruits),
      ('snack', ProductCategory.snacks),
      ('chip', ProductCategory.snacks),
      ('confectionery', ProductCategory.snacks),
      ('chocolate', ProductCategory.snacks),
      ('beverage', ProductCategory.beverages),
      ('drink', ProductCategory.beverages),
      ('juice', ProductCategory.beverages),
      ('water', ProductCategory.beverages),
      ('sauce', ProductCategory.condimentsSaucesCannedGoods),
      ('condiment', ProductCategory.condimentsSaucesCannedGoods),
      ('canned', ProductCategory.condimentsSaucesCannedGoods),
      ('spread', ProductCategory.condimentsSaucesCannedGoods),
      ('pasta', ProductCategory.grainsBeansPasta),
      ('rice', ProductCategory.grainsBeansPasta),
      ('cereal', ProductCategory.grainsBeansPasta),
      ('legume', ProductCategory.grainsBeansPasta),
      ('bean', ProductCategory.grainsBeansPasta),
      ('grain', ProductCategory.grainsBeansPasta),
    ];

    for (final (keyword, category) in rules) {
      if (has(keyword)) return category;
    }
    return null; // no match — shelf-stable-foods is too broad a default to guess safely
  }
}
