import 'food_item.dart';

/// Epic 8 — the server-calculated environmental impact of food wasted in
/// one period. Every number here comes from the backend
/// (GET /households/:id/environmental-impact); Flutter only displays it.
///
/// Total CO2e = Σ (quantity in kg × lifecycle emission factor), using
/// Poore & Nemecek (2018) factors via Our World in Data.
enum EnvironmentalImpactStatus {
  /// Calculated normally.
  ready,

  /// The emission-factor reference data hasn't been loaded into the
  /// database yet — show a "coming soon" state, not an error.
  pendingData,
}

/// Why a single wasted item was or wasn't included in the total.
enum ImpactItemStatus { estimated, noFactor, unknownWeight }

/// How an item's quantity was turned into kilograms.
enum WeightBasis { mass, volume, unitWeight }

class CategoryImpact {
  const CategoryImpact({required this.category, required this.kgCo2e, required this.kgWasted, required this.itemCount});
  final ProductCategory category;
  final double kgCo2e;
  final double kgWasted;
  final int itemCount;

  factory CategoryImpact.fromJson(Map<String, dynamic> json) => CategoryImpact(
        category: _categoryFrom(json['category']),
        kgCo2e: (json['kgCo2e'] as num).toDouble(),
        kgWasted: (json['kgWasted'] as num).toDouble(),
        itemCount: json['itemCount'] as int,
      );
}

/// One bar of the trend chart — the total for one week or month.
/// The last entry is always the selected period itself.
class ImpactPeriodTotal {
  const ImpactPeriodTotal({
    required this.start,
    required this.end,
    required this.kgCo2e,
    required this.hasActivity,
    required this.isComplete,
  });
  final DateTime start;
  final DateTime end;
  final double kgCo2e;
  /// Any item consumed/discarded/donated in this period — false means
  /// "no data", which is different from a real zero-waste period.
  final bool hasActivity;
  /// False for a period that hasn't finished yet (e.g. this week).
  final bool isComplete;

  // These are genuine UTC instants sent with a 'Z' (toISOString on the
  // server), so a plain parse + toLocal is correct here — unlike the
  // zone-less DATETIME strings handled by _parseServerDateTime.
  factory ImpactPeriodTotal.fromJson(Map<String, dynamic> json) => ImpactPeriodTotal(
        start: DateTime.parse(json['start'] as String).toLocal(),
        end: DateTime.parse(json['end'] as String).toLocal(),
        // kgCo2e is null when the period had waste but none of it could be
        // estimated — drawn the same as "no data" ("–"), never as a 0 bar.
        kgCo2e: (json['kgCo2e'] as num?)?.toDouble() ?? 0,
        hasActivity: (json['hasActivity'] as bool) && json['kgCo2e'] != null,
        isComplete: json['isComplete'] as bool,
      );
}

class ImpactItem {
  const ImpactItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.status,
    this.kgWasted,
    this.weightBasis,
    this.weightIsAssumed = false,
    this.factorSource,
    this.weightEnteredByUser = false,
    this.emissionFactor,
    this.factorEntity,
    this.kgCo2e,
  });

  final String id;
  final String name;
  final ProductCategory category;
  final double quantity;
  final String unit;
  final ImpactItemStatus status;
  final double? kgWasted;
  final WeightBasis? weightBasis;
  /// The kg figure came from an assumed conversion (is_assumed = 1, e.g. a
  /// typical piece weight) rather than a measured one.
  final bool weightIsAssumed;
  /// How the factor was chosen: 'food_type' or 'factor_name' (the data
  /// team's name matching — highest factor among matches) or 'reference'.
  final String? factorSource;
  /// The kg figure is the actual weight the user entered for this discard.
  final bool weightEnteredByUser;
  /// kg CO2e per kg of this food.
  final double? emissionFactor;
  /// Which Our World in Data food product the factor came from.
  final String? factorEntity;
  final double? kgCo2e;

  factory ImpactItem.fromJson(Map<String, dynamic> json) => ImpactItem(
        id: json['id'] as String,
        name: json['name'] as String,
        category: _categoryFrom(json['category']),
        quantity: (json['quantity'] as num).toDouble(),
        unit: json['unit'] as String,
        status: ImpactItemStatus.values.byName(json['status'] as String),
        kgWasted: (json['kgWasted'] as num?)?.toDouble(),
        weightBasis: json['weightBasis'] == null ? null : WeightBasis.values.byName(json['weightBasis'] as String),
        weightIsAssumed: json['weightIsAssumed'] as bool? ?? false,
        factorSource: json['factorSource'] as String?,
        weightEnteredByUser: json['weightEnteredByUser'] as bool? ?? false,
        emissionFactor: (json['emissionFactor'] as num?)?.toDouble(),
        factorEntity: json['factorEntity'] as String?,
        kgCo2e: (json['kgCo2e'] as num?)?.toDouble(),
      );
}

class EnvironmentalImpact {
  const EnvironmentalImpact({
    required this.status,
    this.totalKgCo2e = 0,
    this.totalKgWasted = 0,
    this.previousTotalKgCo2e,
    this.isPeriodInProgress = false,
    this.petrolLitres = 0,
    this.petrolKgCo2ePerLitre,
    this.petrolSourceName,
    this.wastedItemCount = 0,
    this.estimatedItemCount = 0,
    this.noFactorCount = 0,
    this.unknownWeightCount = 0,
    this.hasApproximateWeights = false,
    this.byCategory = const [],
    this.trend = const [],
    this.items = const [],
  });

  const EnvironmentalImpact.pending() : this(status: EnvironmentalImpactStatus.pendingData);

  final EnvironmentalImpactStatus status;
  final double totalKgCo2e;
  final double totalKgWasted;
  /// Same total for the previous period — null when there isn't enough
  /// activity in one of the two periods to compare meaningfully.
  final double? previousTotalKgCo2e;
  /// The selected period hasn't ended yet — comparisons say "so far".
  final bool isPeriodInProgress;

  /// The headline comparison (mentor feedback: kg CO2e alone isn't
  /// relatable) — litres of petrol with the same emissions.
  final double petrolLitres;
  final double? petrolKgCo2ePerLitre;
  final String? petrolSourceName;
  final int wastedItemCount;
  final int estimatedItemCount;
  final int noFactorCount;
  final int unknownWeightCount;
  /// True if any included item's weight was approximated (volume → kg,
  /// or an average weight per piece/pack) rather than entered in g/kg.
  final bool hasApproximateWeights;
  final List<CategoryImpact> byCategory;
  /// Oldest first; the last entry is the selected period.
  final List<ImpactPeriodTotal> trend;
  final List<ImpactItem> items;

  int get excludedItemCount => noFactorCount + unknownWeightCount;

  /// Positive = more CO2e than the previous period.
  double? get changeVsPrevious => previousTotalKgCo2e == null ? null : totalKgCo2e - previousTotalKgCo2e!;

  factory EnvironmentalImpact.fromJson(Map<String, dynamic> json) {
    if (json['status'] == 'pendingData') return const EnvironmentalImpact.pending();
    final excluded = (json['excludedCounts'] as Map<String, dynamic>?) ?? const {};
    final petrol = (json['petrolEquivalent'] as Map<String, dynamic>?) ?? const {};
    return EnvironmentalImpact(
      status: EnvironmentalImpactStatus.ready,
      totalKgCo2e: (json['totalKgCo2e'] as num).toDouble(),
      totalKgWasted: (json['totalKgWasted'] as num).toDouble(),
      previousTotalKgCo2e: (json['previousTotalKgCo2e'] as num?)?.toDouble(),
      isPeriodInProgress: json['isPeriodInProgress'] as bool? ?? false,
      petrolLitres: (petrol['litres'] as num?)?.toDouble() ?? 0,
      petrolKgCo2ePerLitre: (petrol['kgCo2ePerLitre'] as num?)?.toDouble(),
      petrolSourceName: petrol['sourceName'] as String?,
      wastedItemCount: json['wastedItemCount'] as int,
      estimatedItemCount: json['estimatedItemCount'] as int,
      noFactorCount: (excluded['noFactor'] as int?) ?? 0,
      unknownWeightCount: (excluded['unknownWeight'] as int?) ?? 0,
      hasApproximateWeights: json['hasApproximateWeights'] as bool? ?? false,
      byCategory: ((json['byCategory'] as List?) ?? const [])
          .map((e) => CategoryImpact.fromJson(e as Map<String, dynamic>))
          .toList(),
      trend: ((json['trend'] as List?) ?? const [])
          .map((e) => ImpactPeriodTotal.fromJson(e as Map<String, dynamic>))
          .toList(),
      items: ((json['items'] as List?) ?? const []).map((e) => ImpactItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

ProductCategory _categoryFrom(Object? name) {
  if (name is String) {
    for (final c in ProductCategory.values) {
      if (c.name == name) return c;
    }
  }
  return ProductCategory.shelfStableFoods; // same fallback the backend uses
}
