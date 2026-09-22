import '../models/food_item.dart';

/// Which calendar granularity is being viewed — drives both the date-range
/// math and the toggle UI on the Progress tab.
enum InsightsPeriod { weekly, monthly }

/// A concrete date range for one period, plus the label/navigation the UI
/// needs (AC 5.1/5.2 — "May 12 – May 18" style header with prev/next).
class DateRange {
  const DateRange(this.start, this.end);
  /// Inclusive start of day.
  final DateTime start;
  /// Inclusive end of day (23:59:59.999) — kept end-inclusive throughout
  /// rather than exclusive, so "was this item active at the end of the
  /// period" checks don't need a separate off-by-one convention.
  final DateTime end;

  bool contains(DateTime t) => !t.isBefore(start) && !t.isAfter(end);
}

/// One period's headline counts (User Story 5.1 / 5.2) — "Consumed / Stored
/// / Wasted" cards plus the reduction score and week-over-week comparison.
class PeriodSummary {
  const PeriodSummary({
    required this.consumed,
    required this.wasted,
    required this.donated,
    required this.stored,
    required this.score,
    this.previousScore,
  });

  final int consumed;
  final int wasted;
  final int donated;
  /// Items still active (in stock) as of the end of the period — a
  /// snapshot, not a flow count like the other three.
  final int stored;
  /// 0-100 — see [InsightsService.calculateScore] for the formula.
  final int score;
  /// The same score for the immediately preceding period, if there's
  /// enough history to compute one — powers the "X% less waste" line.
  final int? previousScore;

  int get percentChangeVsPrevious {
    if (previousScore == null || previousScore == 0) return 0;
    final raw = (((score - previousScore!) / previousScore!) * 100).round();
    // A period compared against a very low previous score (or a default
    // "no activity" score — see calculateScore) can otherwise produce a
    // mathematically huge but meaningless percentage (e.g. 400%+) —
    // clamp to a sane, always-readable range.
    return raw.clamp(-100, 100);
  }
}

/// One point on the trend chart (User Story 5.3) — a single day's (or
/// month's, when zoomed out) consumed/wasted/stored counts.
class TrendPoint {
  const TrendPoint({required this.date, required this.consumed, required this.wasted, required this.stored});
  final DateTime date;
  final int consumed;
  final int wasted;
  final int stored;
}

/// Wasted-item count for one category, within the selected period — feeds
/// the "Category breakdown" list and (indirectly) the 5.4 suggestion.
class CategoryWasteCount {
  const CategoryWasteCount(this.category, this.count);
  final ProductCategory category;
  final int count;
}

/// Household-only breakdown of *why* items were discarded (uses the real
/// DiscardReason the user picks in the discard flow — spoiled / expired
/// not spoiled / quality declined / other — not a bigger "root cause"
/// taxonomy like "forgot about it" or "overbought", since that data isn't
/// captured anywhere yet).
class DiscardReasonCount {
  const DiscardReasonCount(this.reason, this.count);
  final DiscardReason reason;
  final int count;
}

/// User Story 5.4 — a single actionable tip derived from the period's
/// waste pattern. See InsightsService.generateSuggestion for the rules.
class WasteSuggestion {
  const WasteSuggestion({required this.headline, required this.detail});
  final String headline;
  final String detail;
}

/// User Story 5.2 — how often the household tends to re-buy a given item,
/// derived purely from the gaps between its past `addedAt` timestamps.
class PurchaseRhythm {
  const PurchaseRhythm({required this.itemName, required this.category, required this.averageDaysBetween, required this.purchaseCount});
  final String itemName;
  final ProductCategory category;
  final double averageDaysBetween;
  /// How many times this item has been bought — rhythm is only shown once
  /// this is >= 2 (need at least one gap to measure), so a single one-off
  /// purchase never gets a misleading "every 0 days" style stat.
  final int purchaseCount;
}
