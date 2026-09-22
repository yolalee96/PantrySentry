import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../models/food_item.dart';
import '../../models/insights_data.dart';
import '../../services/insights_service.dart';
import '../../services/price_estimate_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/trend_chart.dart';

const _categoryEmoji = <ProductCategory, String>{
  ProductCategory.dairy: '🥛',
  ProductCategory.meat: '🥩',
  ProductCategory.seafood: '🐟',
  ProductCategory.vegetables: '🥦',
  ProductCategory.fruits: '🍎',
  ProductCategory.snacks: '🍪',
  ProductCategory.beverages: '🥤',
  ProductCategory.frozenFood: '🧊',
  ProductCategory.babyFood: '🍼',
  ProductCategory.bakedGoods: '🍞',
  ProductCategory.condimentsSaucesCannedGoods: '🥫',
  ProductCategory.grainsBeansPasta: '🍚',
  ProductCategory.shelfStableFoods: '📦',
  ProductCategory.vegetarianProteins: '🌱',
  ProductCategory.deliPreparedFoods: '🍱',
  ProductCategory.eggs: '🥚',
};

/// Epic 5 — Progress tab. Household-wide insights only (the personal
/// "My Stats" view was removed per mentor feedback — not necessary).
///
/// 5.2 — Household view.
/// 5.3 — the trend chart.
/// 5.4 — the suggestion cards (forward-looking action tips +
/// reason-based recommended changes).
/// 5.5 — estimated value card.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  InsightsPeriod _period = InsightsPeriod.weekly;
  DateTime _anchor = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.appState,
          builder: (context, _) {
            final state = widget.appState;
            final range = InsightsService.rangeFor(_period, _anchor);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildPeriodToggle(),
                const SizedBox(height: 12),
                _buildRangeNav(range),
                const SizedBox(height: 16),
                ..._buildStatsSection(state, range),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My Progress', style: Theme.of(context).textTheme.headlineSmall),
              Text('Track your household\'s food journey', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.seedColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.eco_outlined, color: AppTheme.seedColor),
        ),
      ],
    );
  }

  Widget _buildPeriodToggle() {
    return SegmentedButton<InsightsPeriod>(
      segments: const [
        ButtonSegment(value: InsightsPeriod.weekly, label: Text('Weekly')),
        ButtonSegment(value: InsightsPeriod.monthly, label: Text('Monthly')),
      ],
      selected: {_period},
      onSelectionChanged: (s) => setState(() {
        _period = s.first;
        _anchor = DateTime.now();
      }),
    );
  }

  Widget _buildRangeNav(DateRange range) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() {
                _anchor = InsightsService.shift(range, _period, forward: false).start;
              }),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 16),
                  const SizedBox(width: 8),
                  Text(InsightsService.label(range, _period), style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() {
                _anchor = InsightsService.shift(range, _period, forward: true).start;
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Household stats section ====================

  List<Widget> _buildStatsSection(AppState state, DateRange range) {
    final items = state.items;
    final summary = InsightsService.summarize(items, range);
    final trend = InsightsService.trend(items, range);
    final breakdown = InsightsService.categoryBreakdown(items, range);
    final reasonBreakdown = InsightsService.discardReasonBreakdown(items, range);
    final recommendedChanges = InsightsService.generateRecommendedChanges(
      breakdown.isEmpty ? [const CategoryWasteCount(ProductCategory.shelfStableFoods, 0)] : breakdown,
      summary,
      reasonBreakdown: reasonBreakdown,
    );
    final actionTips = InsightsService.generateActionTips(items);
    final wastedItems = items.where((i) =>
        i.disposition == ItemDisposition.discarded && i.resolvedAt != null && range.contains(i.resolvedAt!)).toList();
    final estimatedValue = PriceEstimateService.estimateValue(wastedItems);

    return [
      _buildStatCardsRow(summary),
      const SizedBox(height: 16),
      _buildComparisonCard(summary),
      const SizedBox(height: 16),
      _buildTrendCard(trend),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildCategoryBreakdownCard(breakdown)),
          const SizedBox(width: 12),
          Expanded(child: _buildEstimatedValueCard(estimatedValue)),
        ],
      ),
      const SizedBox(height: 16),
      _buildDiscardReasonCard(reasonBreakdown),
      const SizedBox(height: 16),
      _buildActionTipsCard(actionTips),
      const SizedBox(height: 16),
      _buildRecommendedChangesCard(recommendedChanges),
    ];
  }

  Widget _buildStatCardsRow(PeriodSummary summary) {
    Widget statCard(String label, int value, Color color, Color fill) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(18)),
          child: Column(
            children: [
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
              const SizedBox(height: 4),
              Text('$value', style: AppTheme.statNumberStyle.copyWith(fontSize: 24, color: color)),
              Text('items', style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 11)),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        statCard('Consumed', summary.consumed, AppTheme.seedColor, AppTheme.basilLight),
        const SizedBox(width: 10),
        statCard('Stored', summary.stored, AppTheme.ocean, AppTheme.oceanLight),
        const SizedBox(width: 10),
        statCard('Wasted', summary.wasted, AppTheme.paprika, AppTheme.paprikaLight),
      ],
    );
  }

  /// The "X% less/more waste" comparison card — kept from the original
  /// design even though the score ring next to it was removed. Compares
  /// this period's reduction score to the immediately preceding period's.
  Widget _buildComparisonCard(PeriodSummary summary) {
    final change = summary.percentChangeVsPrevious;
    final improved = change <= 0; // score dropping = less waste = good

    if (summary.previousScore == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Not enough history yet to compare with the previous period.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
        ),
      );
    }

    return Card(
      color: improved ? AppTheme.basilLight : AppTheme.paprikaLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(improved ? Icons.trending_up : Icons.trending_down,
                color: improved ? AppTheme.seedColor : AppTheme.paprika),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style,
                      children: [
                        TextSpan(
                          text: '${change.abs()}% ',
                          style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 17,
                            color: improved ? AppTheme.seedColor : AppTheme.paprika,
                          ),
                        ),
                        TextSpan(text: improved ? 'less waste' : 'more waste', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    improved ? 'Great job! You wasted less food this period.' : 'A bit more waste than last period — check the tip below.',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendCard(List<TrendPoint> trend) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Trends (items)', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Wrap(
              spacing: 14,
              children: [
                _LegendDot(color: AppTheme.seedColor, label: 'Consumed'),
                _LegendDot(color: AppTheme.paprika, label: 'Wasted'),
              ],
            ),
            const SizedBox(height: 12),
            TrendChart(points: trend),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdownCard(List<CategoryWasteCount> breakdown) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Category breakdown\n(wasted items)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 12),
            if (breakdown.isEmpty)
              Text('No wasted items this period 🎉', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5))
            else
              ...breakdown.take(4).map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(_categoryEmoji[c.category] ?? '🍽️', style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(c.category.label, style: const TextStyle(fontSize: 12.5))),
                        Text('${c.count} item${c.count == 1 ? '' : 's'}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildEstimatedValueCard(double estimatedValue) {
    return Card(
      color: AppTheme.honeyLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Estimated value\nwasted', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                Icon(Icons.info_outline, size: 15, color: Colors.grey.shade600),
              ],
            ),
            const SizedBox(height: 10),
            Text('RM ${estimatedValue.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.paprika)),
            const Text('Estimated', style: TextStyle(fontSize: 11, color: AppTheme.paprika, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              'This is an estimate based on current market prices and input from users.',
              style: TextStyle(fontSize: 10.5, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /// Household-only. Uses the real DiscardReason data (spoiled / expired
  /// not spoiled / quality declined / other) rather than inventing a
  /// richer "root cause" taxonomy that isn't actually captured anywhere.
  Widget _buildDiscardReasonCard(List<DiscardReasonCount> reasons) {
    final total = reasons.fold<int>(0, (sum, r) => sum + r.count);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Why food was wasted', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Based on the reason picked when discarding an item.', style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
            const SizedBox(height: 14),
            if (reasons.isEmpty)
              Text('No discarded items with a reason recorded this period.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5))
            else
              ...reasons.map((r) {
                final pct = total == 0 ? 0.0 : r.count / total;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(r.reason.label, style: const TextStyle(fontSize: 12.5))),
                          Text('${r.count} · ${(pct * 100).round()}%',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 6,
                          backgroundColor: Colors.grey.shade200,
                          color: AppTheme.paprika,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  /// Forward-looking, numbered — items currently in stock about to
  /// expire, with a specific action per item (matches the "Ways to
  /// reduce food waste" mockup).
  Widget _buildActionTipsCard(List<WasteSuggestion> tips) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ways to reduce food waste', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            for (var i = 0; i < tips.length; i++)
              Container(
                margin: EdgeInsets.only(bottom: i == tips.length - 1 ? 0 : 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppTheme.basilLight, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: AppTheme.seedColor,
                      child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tips[i].headline, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          const SizedBox(height: 2),
                          Text(tips[i].detail, style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text('Based on what\'s currently in your inventory and approaching its use-by date.',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  /// Root-cause based, checkmarked — up to a few discard reasons at once,
  /// not just the single dominant one (matches the "Recommended changes"
  /// mockup).
  Widget _buildRecommendedChangesCard(List<WasteSuggestion> changes) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recommended changes', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            for (var i = 0; i < changes.length; i++)
              Container(
                margin: EdgeInsets.only(bottom: i == changes.length - 1 ? 0 : 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppTheme.basilLight, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      radius: 12,
                      backgroundColor: AppTheme.seedColor,
                      child: Icon(Icons.check, color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(changes[i].headline, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          const SizedBox(height: 2),
                          Text(changes[i].detail, style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text('Based on discard reasons recorded by household members.',
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ],
    );
  }
}
