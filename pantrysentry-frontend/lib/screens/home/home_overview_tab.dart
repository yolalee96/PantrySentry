import 'package:flutter/material.dart';
import 'dart:async';
import '../../state/app_state.dart';
import '../../models/app_user.dart';
import '../../models/food_item.dart';
import '../../theme/app_theme.dart';
import '../../widgets/item_card.dart';
import '../../widgets/app_logo.dart';
import '../inventory/expiring_soon_screen.dart';
import '../inventory/item_detail_screen.dart';
import '../household/switch_household_screen.dart';

const _expiringSoonWindowDays = 3;

/// AC 1.2.2 — household name + user avatar in the header.
/// AC 2.2.1 — total count + per-category breakdown.
/// AC 2.3.1 / AC 2.4.1 — expiring soon preview + "View All".
/// AC 2.7.1 — search across all locations.
class HomeOverviewTab extends StatefulWidget {
  const HomeOverviewTab({
    super.key,
    required this.appState,
    required this.onViewInventory,
  });

  final AppState appState;
  final VoidCallback onViewInventory;

  @override
  State<HomeOverviewTab> createState() => _HomeOverviewTabState();
}

class _HomeOverviewTabState extends State<HomeOverviewTab> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Debounced so the list only re-filters/rebuilds ~300ms after typing
  /// pauses, instead of on every single keystroke — typing fast in
  /// search was a real, noticeable source of lag.
  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.appState,
          builder: (context, _) {
            final state = widget.appState;
            final searchQuery = _searchController.text;
            final searchResults =
                searchQuery.trim().isEmpty ? null : state.search(searchQuery);

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildHeader(context, state)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildSearchBar(),
                  ),
                ),
                if (searchResults != null)
                  _buildSearchResults(context, searchResults)
                else ...[
                  SliverToBoxAdapter(child: _buildSummary(context, state)),
                  SliverToBoxAdapter(child: _buildExpiringSoon(context, state)),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Tappable — opens the household switcher. Uses the same hero-fill
  /// green as the rest of the app's primary cards (see Progress tab's
  /// "Your contribution"), rather than a separate one-off bright green.
  Widget _buildHeader(BuildContext context, AppState state) {
    final user = state.currentUser;
    final household = state.currentHousehold;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppLogo(markSize: 150, direction: Axis.horizontal),
          const SizedBox(height: 16),
          Material(
            color: AppTheme.seedColor,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SwitchHouseholdScreen(appState: state),
              )),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.white,
                      child: Text(
                        user != null ? AvatarCatalog.emojiFor(user.avatarKey) : '🥕',
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            household?.name ?? 'Your household',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17,
                                ),
                          ),
                          Text(
                            'Tap to switch households',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => _onSearchChanged(),
      decoration: InputDecoration(
        hintText: 'Search your inventory...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _searchController.clear()),
              ),
      ),
    );
  }

  /// Small illustrations for the three storage locations — kept exactly
  /// as designed, only the surrounding hero card's background color
  /// changed (not these).
  Widget _buildStorageIllustration(StorageLocation location) {
    final isPantry = location == StorageLocation.pantry;
    final isFreezer = location == StorageLocation.freezer;

    final outline = isPantry ? const Color(0xFF795548) : const Color(0xFF356477);
    final fill = isPantry ? const Color(0xFFFFE0B2) : const Color(0xFFDCEFF5);

    Widget handle() {
      return Container(
        width: 4,
        height: 12,
        decoration: BoxDecoration(color: outline, borderRadius: BorderRadius.circular(2)),
      );
    }

    Widget jar(Color color) {
      return Container(
        width: 12,
        height: 17,
        decoration: BoxDecoration(
          color: color,
          border: Border(top: BorderSide(color: outline, width: 4)),
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }

    return SizedBox(
      height: 80,
      child: Center(
        child: Container(
          width: isFreezer ? 76 : 56,
          height: isFreezer ? 52 : 76,
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: outline, width: 2),
            borderRadius: BorderRadius.circular(7),
          ),
          child: isPantry
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [jar(const Color(0xFF81A969)), jar(const Color(0xFFD99562))],
                    ),
                    Divider(color: outline, thickness: 2, height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [jar(const Color(0xFFD6AD52)), jar(const Color(0xFF81A969))],
                    ),
                  ],
                )
              : isFreezer
                  ? Column(
                      children: [
                        Container(
                          height: 12,
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: outline, width: 2))),
                          alignment: Alignment.center,
                          child: Container(width: 18, height: 3, color: outline),
                        ),
                        Expanded(child: Icon(Icons.ac_unit, color: outline, size: 24)),
                      ],
                    )
                  : Column(
                      children: [
                        SizedBox(
                          height: 25,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(padding: const EdgeInsets.only(left: 7), child: handle()),
                          ),
                        ),
                        Divider(color: outline, thickness: 2, height: 2),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(padding: const EdgeInsets.only(left: 7), child: handle()),
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  /// Changed from brown/gold to ocean blue — same hero-fill pattern used
  /// elsewhere, just a different one of the app's real palette colors
  /// (see AppTheme) instead of an off-palette brown.
  Widget _buildSummary(BuildContext context, AppState state) {
    final active = state.activeItems;
    final byLocation = {
      for (final loc in StorageLocation.values)
        loc: active.where((i) => i.storageLocation == loc).length,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.heroFill(AppTheme.ocean),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${active.length}',
                    style: AppTheme.statNumberStyle.copyWith(fontSize: 40, color: Colors.white)),
                const SizedBox(width: 8),
                Text('items in your inventory',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < StorageLocation.values.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        children: [
                          _buildStorageIllustration(StorageLocation.values[i]),
                          const SizedBox(height: 8),
                          Text(
                            StorageLocation.values[i].label,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.ink),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${byLocation[StorageLocation.values[i]]}',
                            style: AppTheme.statNumberStyle.copyWith(fontSize: 24, color: AppTheme.ocean),
                          ),
                          Text(
                            byLocation[StorageLocation.values[i]] == 1 ? 'item' : 'items',
                            style: TextStyle(fontSize: 11, color: AppTheme.ink.withValues(alpha: 0.65)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onViewInventory,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('View Inventory'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpiringSoon(BuildContext context, AppState state) {
    final expiring = state.expiringWithin(_expiringSoonWindowDays);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Expiring Soon', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ExpiringSoonScreen(appState: widget.appState),
                )),
                child: const Text('View All'),
              ),
            ],
          ),
          if (expiring.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Nothing expiring in the next $_expiringSoonWindowDays days 🎉',
                  style: TextStyle(color: Colors.grey.shade600)),
            )
          else
            ...expiring.take(4).map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ItemCard(
                    item: item,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ItemDetailScreen(appState: widget.appState, item: item),
                    )),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context, List<FoodItem> results) {
    if (results.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text('No items match your search.', style: TextStyle(color: Colors.grey.shade600)),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ItemCard(
              item: results[i],
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ItemDetailScreen(appState: widget.appState, item: results[i]),
              )),
            ),
          ),
          childCount: results.length,
        ),
      ),
    );
  }
}
