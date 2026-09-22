import 'package:flutter/material.dart';
import 'dart:async';
import '../../state/app_state.dart';
import '../../models/food_item.dart';
import '../../widgets/item_card.dart';
import 'item_detail_screen.dart';
import 'add_edit_item_screen.dart';
import 'receipt_scan_screen.dart';

/// AC 2.5.1 — items grouped under storage-location tabs (All/Fridge/
/// Freezer/Pantry), each showing an item count.
/// Search bar shown on both the home screen and here (AC).
class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

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
      appBar: AppBar(title: const Text('Inventory')),
      body: ListenableBuilder(
        listenable: widget.appState,
        builder: (context, _) {
          final state = widget.appState;
          final searchQuery = _searchController.text;
          final searchResults =
              searchQuery.trim().isEmpty ? null : state.search(searchQuery);

          final all = state.activeItems;
          final byLocation = {
            for (final loc in StorageLocation.values) loc: state.itemsIn(loc),
          };

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _buildSearchBar(),
              ),
              if (searchResults != null)
                Expanded(child: _buildSearchResults(context, searchResults))
              else ...[
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'All (${all.length})'),
                    ...StorageLocation.values
                        .map((loc) => Tab(text: '${loc.label} (${byLocation[loc]!.length})')),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildList(context, all),
                      ...StorageLocation.values.map((loc) => _buildList(context, byLocation[loc]!)),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'scanReceiptFab',
            tooltip: 'Scan receipt',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ReceiptScanScreen(appState: widget.appState),
            )),
            child: const Icon(Icons.receipt_long_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'addItemFab',
            tooltip: 'Add item',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AddEditItemScreen(appState: widget.appState),
            )),
            child: const Icon(Icons.add),
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

  Widget _buildSearchResults(BuildContext context, List<FoodItem> results) {
    if (results.isEmpty) {
      return Center(
        child: Text('No items match your search.', style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    final sorted = [...results]..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => ItemCard(
        item: sorted[i],
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ItemDetailScreen(appState: widget.appState, item: sorted[i]),
        )),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<FoodItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Text('No items here yet.', style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    final sorted = [...items]..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => ItemCard(
        item: sorted[i],
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ItemDetailScreen(appState: widget.appState, item: sorted[i]),
        )),
      ),
    );
  }
}
