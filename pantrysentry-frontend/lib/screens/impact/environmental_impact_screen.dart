import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/environmental_impact.dart';
import '../../models/food_item.dart';
import '../../models/insights_data.dart';
import '../../services/insights_service.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';

/// Epic 8 — Environmental Impact tab.
///
/// User stories covered:
/// - the estimated carbon footprint of wasted food (headline, shown as
///   litres of petrol — mentor feedback that kg CO2e alone isn't relatable),
/// - comparing impact across categories (pie chart),
/// - tracking changes over time (last 4 weeks/months).
///
/// Every number comes from the backend (GET
/// /households/:id/environmental-impact); this screen only displays it.
/// Uses the same calendar Weekly/Monthly periods as the Progress tab, so
/// "this week" means the same thing in both places.
///
/// Fetches only when the period changes or the household's discarded
/// items change (see [_wasteSignature]) — not on every 8-second poll
/// rebuild — and keeps showing the previous result during a refresh so
/// the screen doesn't flicker.
class EnvironmentalImpactScreen extends StatefulWidget {
  const EnvironmentalImpactScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<EnvironmentalImpactScreen> createState() => _EnvironmentalImpactScreenState();
}

/// How many periods the trend chart shows, including the selected one.
const int _trendLength = 4;

class _EnvironmentalImpactScreenState extends State<EnvironmentalImpactScreen> {
  InsightsPeriod _period = InsightsPeriod.weekly;
  DateTime _anchor = DateTime.now();

  EnvironmentalImpact? _data;
  Object? _error;
  bool _loading = false;
  int _requestId = 0;
  // What the last fetch was for — a new fetch happens only when one of
  // these changes.
  DateTime? _loadedStart;
  String? _loadedHouseholdId;
  int? _loadedSignature;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onAppStateChanged);
    _maybeLoad();
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    if (_maybeLoad()) setState(() {});
  }

  DateRange get _range => InsightsService.rangeFor(_period, _anchor);

  /// Starts of the earlier periods in the trend chart, oldest first.
  List<DateTime> _trendStarts(DateRange range) {
    final starts = <DateTime>[];
    var r = range;
    for (var i = 1; i < _trendLength; i++) {
      r = InsightsService.shift(r, _period, forward: false);
      starts.insert(0, r.start);
    }
    return starts;
  }

  /// Changes whenever a discarded item is added, removed or edited.
  int _wasteSignature() => Object.hashAll(widget.appState.items
      .where((i) => i.disposition == ItemDisposition.discarded)
      .map((i) => Object.hash(i.id, i.resolvedAt, i.quantity, i.unit, i.category)));

  /// Fetches if the period, household or waste data changed since the
  /// last fetch. Returns whether it started one. Never calls setState
  /// itself, so it's safe from initState and listeners alike.
  bool _maybeLoad({bool force = false}) {
    final range = _range;
    final householdId = widget.appState.currentHousehold?.id;
    final signature = _wasteSignature();
    if (!force && range.start == _loadedStart && householdId == _loadedHouseholdId && signature == _loadedSignature) {
      return false;
    }
    if (range.start != _loadedStart || householdId != _loadedHouseholdId) {
      _data = null; // never show last week's numbers under this week's label
    }
    _loadedStart = range.start;
    _loadedHouseholdId = householdId;
    _loadedSignature = signature;
    _load(range);
    return true;
  }

  Future<void> _load(DateRange range) async {
    final id = ++_requestId;
    _loading = true;
    _error = null;
    try {
      final result = await widget.appState.getEnvironmentalImpact(range: range, trendStarts: _trendStarts(range));
      if (!mounted || id != _requestId) return; // superseded by a newer request
      setState(() {
        _data = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _changePeriod(VoidCallback change) {
    setState(() {
      change();
      _maybeLoad();
    });
  }

  String get _periodWord => _period == InsightsPeriod.weekly ? 'week' : 'month';

  @override
  Widget build(BuildContext context) {
    final range = _range;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            _maybeLoad(force: true);
            setState(() {});
          },
          child: ListView(
            // Lets pull-to-refresh work even when the content is shorter
            // than the screen (e.g. the "Coming soon" state).
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildPeriodToggle(),
              const SizedBox(height: 12),
              _buildRangeNav(range),
              const SizedBox(height: 16),
              ..._buildBody(),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== Header & period controls ====================

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Environmental impact', style: Theme.of(context).textTheme.headlineSmall),
              Text('Carbon footprint of food your household wasted', style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.info_outline, color: Colors.grey.shade700),
          tooltip: 'How this is calculated',
          onPressed: _showMethodDialog,
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
      onSelectionChanged: (s) => _changePeriod(() {
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
              onPressed: () => _changePeriod(() => _anchor = InsightsService.shift(range, _period, forward: false).start),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 16),
                  const SizedBox(width: 8),
                  Text(InsightsService.label(range, _period), style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (_loading && _data != null) ...[
                    const SizedBox(width: 8),
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _changePeriod(() => _anchor = InsightsService.shift(range, _period, forward: true).start),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Body ====================

  List<Widget> _buildBody() {
    final data = _data;
    if (data == null && _error != null) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Couldn\'t load the environmental impact estimate.', style: TextStyle(color: Colors.grey.shade700)),
                TextButton(
                  onPressed: () => setState(() => _maybeLoad(force: true)),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    if (data == null) {
      return const [Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator()))];
    }
    if (data.status == EnvironmentalImpactStatus.pendingData) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.hourglass_empty, color: AppTheme.ocean, size: 32),
                const SizedBox(height: 10),
                const Text('Coming soon', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 6),
                Text(
                  'We\'re still preparing the emission data used to estimate the carbon footprint of wasted food.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      _buildHeadlineCard(data),
      // No comparison when this period's waste couldn't be estimated at all.
      if (data.changeVsPrevious != null && !(data.wastedItemCount > 0 && data.estimatedItemCount == 0)) ...[
        const SizedBox(height: 12),
        _buildComparison(data),
      ],
      const SizedBox(height: 20),
      _sectionTitle('Impact by category'),
      const SizedBox(height: 8),
      _buildCategoryCard(data),
      const SizedBox(height: 20),
      _sectionTitle('Household impact trend'),
      const SizedBox(height: 8),
      _buildTrendCard(data),
      if (data.items.isNotEmpty) ...[
        const SizedBox(height: 20),
        _buildItemBreakdown(data),
      ],
      const SizedBox(height: 14),
      _buildFootnote(data),
    ];
  }

  Widget _sectionTitle(String text) =>
      Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16));

  /// Headline, prototype's peach card. Petrol is the big number; kg CO2e
  /// stays visible underneath for anyone who wants the actual unit.
  Widget _buildHeadlineCard(EnvironmentalImpact data) {
    final noWaste = data.wastedItemCount == 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: noWaste ? AppTheme.basilLight : AppTheme.honeyLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ESTIMATED CARBON FOOTPRINT OF WASTED FOOD',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: Colors.brown.shade700),
          ),
          const SizedBox(height: 10),
          if (noWaste) ...[
            Text('No food wasted', style: AppTheme.statNumberStyle.copyWith(fontSize: 28, color: AppTheme.seedColor)),
            const SizedBox(height: 4),
            Text(
              data.isPeriodInProgress ? 'Nothing thrown out this $_periodWord so far 🌱' : 'Nothing thrown out this $_periodWord 🌱',
              style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
            ),
          ] else if (data.estimatedItemCount == 0) ...[
            // Food was wasted, but none of it could be converted to CO2e.
            // Showing "0.0 L / 0 kg" here would claim zero impact — the
            // data team's rule is that missing data is never shown as 0.
            Text('Not available yet', style: AppTheme.statNumberStyle.copyWith(fontSize: 26, color: Colors.grey.shade800)),
            const SizedBox(height: 4),
            Text(
              '${data.wastedItemCount} wasted item${data.wastedItemCount == 1 ? '' : 's'} this $_periodWord, but we don\'t have '
              'the data to estimate ${data.wastedItemCount == 1 ? 'its' : 'their'} carbon footprint. '
              'See "How each item was counted" below for why.',
              style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Icon(Icons.local_gas_station_outlined, color: AppTheme.paprika, size: 30),
                const SizedBox(width: 6),
                Text(_formatLitres(data.petrolLitres),
                    style: AppTheme.statNumberStyle.copyWith(fontSize: 34, color: AppTheme.paprika)),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('of petrol', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.paprika)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Wasting this food had about the same carbon footprint as burning ${_formatLitres(data.petrolLitres)} of petrol.',
              style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
              child: Text(
                '${_formatKg(data.totalKgCo2e)} kg CO₂e · from ${_formatKg(data.totalKgWasted)} kg of wasted food',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.brown.shade800),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// vs. the previous period, as an absolute amount (litres + kg), never
  /// a percentage — see the Iteration 2 "400% more waste" bug.
  Widget _buildComparison(EnvironmentalImpact data) {
    final change = data.changeVsPrevious!;
    final same = change.abs() < 0.05;
    final better = change < 0;
    final color = same ? Colors.grey.shade700 : (better ? AppTheme.seedColor : AppTheme.paprika);
    final soFar = data.isPeriodInProgress ? ' so far' : '';
    final litres = _formatLitres(change.abs() / (data.petrolKgCo2ePerLitre ?? 2.34502));
    final text = same
        ? 'About the same as last $_periodWord$soFar'
        : '$litres of petrol ${better ? 'less' : 'more'} than last $_periodWord$soFar';
    final detail = same ? null : '${better ? '−' : '+'}${_formatKg(change.abs())} kg CO₂e';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: same ? Colors.grey.shade100 : (better ? AppTheme.basilLight : AppTheme.paprikaLight),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(same ? Icons.trending_flat : (better ? Icons.trending_down : Icons.trending_up), color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13.5)),
                if (detail != null) Text(detail, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Category pie ====================

  static const _sliceColors = [AppTheme.honey, AppTheme.paprika, Color(0xFF5E9E6E), Color(0xFFC9A23A), AppTheme.ocean];
  static const _otherColor = Color(0xFFB8C0BB);

  Widget _buildCategoryCard(EnvironmentalImpact data) {
    if (data.byCategory.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            data.wastedItemCount == 0 ? 'No wasted items this $_periodWord 🎉' : 'None of this $_periodWord\'s wasted items could be estimated yet.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
          ),
        ),
      );
    }

    // Up to 5 slices: the top 4 categories, plus "Other" for the rest
    // (16 slices would be unreadable). Exactly 5 categories are all shown.
    final total = data.totalKgCo2e;
    final slices = <_Slice>[];
    final cats = data.byCategory;
    final shown = cats.length <= 5 ? cats : cats.take(4).toList();
    for (var i = 0; i < shown.length; i++) {
      slices.add(_Slice(shown[i].category.label, shown[i].kgCo2e, _sliceColors[i % _sliceColors.length]));
    }
    if (cats.length > 5) {
      final rest = cats.skip(4).fold<double>(0, (s, c) => s + c.kgCo2e);
      slices.add(_Slice('Other (${cats.length - 4})', rest, _otherColor));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share of ${_formatKg(total)} kg CO₂e from wasted food',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final narrow = constraints.maxWidth < 330;
              final pie = SizedBox(
                width: narrow ? 140 : 150,
                height: narrow ? 140 : 150,
                child: CustomPaint(painter: _PiePainter(slices)),
              );
              final legend = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final s in slices) _legendRow(s, total)],
              );
              return narrow
                  ? Column(children: [pie, const SizedBox(height: 16), legend])
                  : Row(children: [pie, const SizedBox(width: 20), Expanded(child: legend)]);
            }),
          ],
        ),
      ),
    );
  }

  Widget _legendRow(_Slice s, double total) {
    final pct = total <= 0 ? 0 : (s.value / total * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text('${_formatKg(s.value)} kg CO₂e', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Text('$pct%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
        ],
      ),
    );
  }

  // ==================== Trend bars ====================

  Widget _buildTrendCard(EnvironmentalImpact data) {
    final trend = data.trend;
    if (trend.isEmpty) return const SizedBox.shrink();
    final max = trend.fold<double>(0, (m, p) => p.kgCo2e > m ? p.kgCo2e : m);
    const chartHeight = 120.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('kg CO₂e from wasted food, last ${trend.length} ${_periodWord}s',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
            const SizedBox(height: 14),
            SizedBox(
              height: chartHeight + 20,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < trend.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              trend[i].hasActivity ? _formatKg(trend[i].kgCo2e) : '–',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              // A real zero keeps a thin stub so it reads
                              // as data; "–" above marks no activity at all.
                              height: max <= 0 ? 3.0 : math.max(3.0, trend[i].kgCo2e / max * chartHeight),
                              decoration: BoxDecoration(
                                color: i == trend.length - 1 ? const Color(0xFF5E9E6E) : const Color(0xFFA9CDB2),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < trend.length; i++)
                  Expanded(
                    child: Text(
                      _trendLabel(trend[i], isSelected: i == trend.length - 1),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontWeight: i == trend.length - 1 ? FontWeight.w700 : FontWeight.normal,
                      ),
                    ),
                  ),
              ],
            ),
            if (!trend.last.isComplete) ...[
              const SizedBox(height: 8),
              Text('This $_periodWord isn\'t over yet, so its bar will keep changing.',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
            ],
          ],
        ),
      ),
    );
  }

  String _trendLabel(ImpactPeriodTotal p, {required bool isSelected}) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (isSelected && !p.isComplete) return _period == InsightsPeriod.weekly ? 'This week' : 'This month';
    return _period == InsightsPeriod.weekly
        ? '${p.start.day} ${months[p.start.month - 1]}'
        : months[p.start.month - 1];
  }

  // ==================== Per-item breakdown ====================

  /// Shows exactly how each wasted item was counted (or why it wasn't) —
  /// keeps the estimate transparent, and useful when demoing.
  Widget _buildItemBreakdown(EnvironmentalImpact data) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: const Text('How each item was counted', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text('${data.estimatedItemCount} of ${data.wastedItemCount} wasted items estimated',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [for (final item in data.items) _itemRow(item)],
      ),
    );
  }

  Widget _itemRow(ImpactItem item) {
    final qty = item.quantity == item.quantity.roundToDouble() ? item.quantity.toInt().toString() : item.quantity.toString();
    String detail;
    switch (item.status) {
      case ImpactItemStatus.estimated:
        final approx = item.weightIsAssumed ? '≈' : '';
        detail = '$qty ${item.unit} → $approx${_formatKg(item.kgWasted!)} kg × ${item.emissionFactor} (${item.factorEntity})';
        break;
      case ImpactItemStatus.noFactor:
        // Wording from the data team's Epic 8 README for excluded items.
        detail = '$qty ${item.unit} · environmental impact data is currently unavailable for this item';
        break;
      case ImpactItemStatus.unknownWeight:
        // Usually "pcs"/"pack": there's no reliable weight for one piece of
        // most foods, so the hint tells people how to get it counted.
        detail = '$qty ${item.unit} · can\'t convert "${item.unit}" to kg for this item yet (entering it in g or kg lets it be counted)';
        break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(detail, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.kgCo2e == null ? 'Not counted' : '${_formatKg(item.kgCo2e!)} kg',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              color: item.kgCo2e == null ? Colors.grey.shade500 : AppTheme.ink,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Footnote & method ====================

  Widget _buildFootnote(EnvironmentalImpact data) {
    final lines = <String>[];
    if (data.excludedItemCount > 0) {
      lines.add('${data.excludedItemCount} wasted item${data.excludedItemCount == 1 ? '' : 's'} couldn\'t be estimated yet and '
          '${data.excludedItemCount == 1 ? 'isn\'t' : 'aren\'t'} included.');
    }
    if (data.hasApproximateWeights) {
      lines.add('Some figures are based on assumed values (a typical piece weight or density for that food).');
    }
    lines.add('Estimates use each item\'s product, quantity and discard record, and cover the food\'s whole lifecycle, not just landfill.');
    return Text(lines.join(' '), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600));
  }

  void _showMethodDialog() {
    final petrolFactor = _data?.petrolKgCo2ePerLitre ?? 2.34502;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How this is estimated'),
        content: SingleChildScrollView(
          child: Text(
            'For each wasted item, we convert the amount to kilograms and multiply it by a lifecycle emission '
            'factor for that type of food (kg CO₂e per kg). The total is the sum across all wasted items:\n\n'
            'Total CO₂e = Σ (quantity in kg × emission factor)\n\n'
            'The factors cover the food\'s whole lifecycle (farming, processing, transport and retail), so they '
            'show the impact of producing food that was never eaten, not only what happens in landfill.\n\n'
            'To make the number easier to picture, we compare it with burning petrol: 1 litre of petrol produces '
            'about $petrolFactor kg CO₂e.\n\n'
            'Amounts in g or kg are converted exactly. Litres, millilitres, pieces and dozens are converted with a '
            'conversion for that specific food: a measured value where one exists, otherwise an assumed typical density '
            'or piece weight. Figures that use an assumed value are marked ≈. If an item can\'t be matched to our food '
            'data, it is left out rather than guessed, and never counted as zero.\n\n'
            'Sources: Poore, J. & Nemecek, T. (2018), Science 360(6392), 987–992, via Our World in Data. '
            'Petrol factor: ${_data?.petrolSourceName ?? 'DEFRA 2023, as used by MGTC Malaysia'}. '
            'Calculation method adapted from the GHG Protocol.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }
}

String _formatKg(double kg) => kg >= 10 ? kg.toStringAsFixed(1) : kg.toStringAsFixed(2);

String _formatLitres(double litres) {
  if (litres > 0 && litres < 0.1) return '<0.1 L';
  return litres >= 10 ? '${litres.toStringAsFixed(0)} L' : '${litres.toStringAsFixed(1)} L';
}

class _Slice {
  const _Slice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.slices);
  final List<_Slice> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (s, x) => s + x.value);
    if (total <= 0) return;
    final rect = Offset.zero & size;
    final gap = slices.length > 1 ? 0.03 : 0.0; // small white gap between slices, as in the prototype
    var angle = -math.pi / 2;
    for (final s in slices) {
      final sweep = s.value / total * 2 * math.pi;
      if (sweep > gap) {
        canvas.drawArc(rect, angle + gap / 2, sweep - gap, true, Paint()..color = s.color);
      }
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) => old.slices != slices;
}
