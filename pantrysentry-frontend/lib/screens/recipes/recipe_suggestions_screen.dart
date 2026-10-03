import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'recipe_detail_screen.dart';
import 'recipe_formatting.dart';

/// Epic 6 / User Story 6.1 — recipes matched to the household's inventory,
/// with recipes using items expiring within 3 days first. Opened from the
/// Home tab's "Recipe ideas" card.
class RecipeSuggestionsScreen extends StatefulWidget {
  const RecipeSuggestionsScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<RecipeSuggestionsScreen> createState() => _RecipeSuggestionsScreenState();
}

class _RecipeSuggestionsScreenState extends State<RecipeSuggestionsScreen> {
  RecipeSuggestions? _data;
  String? _error;
  bool _loading = true;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.appState.getRecipeSuggestions(refresh: refresh);
      if (!mounted || id != _requestId) return;
      setState(() {
        _data = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openRecipe(Recipe recipe) async {
    final updated = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RecipeDetailScreen(appState: widget.appState, recipe: recipe),
    ));
    // Ingredients were used — availability and ranking have changed.
    if (updated == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipe ideas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Get new ideas',
            onPressed: _loading ? null : () => _load(refresh: true),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Finding recipes for what you have…\nThis can take a few seconds.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
            ],
          ),
        ),
      );
    }
    if (_error != null && _data == null) {
      return _messageView(
        icon: Icons.cloud_off_outlined,
        title: 'Couldn\'t load recipe ideas',
        body: _error!,
        action: FilledButton(onPressed: () => _load(), child: const Text('Try again')),
      );
    }

    final data = _data!;
    if (data.status == RecipeSuggestionsStatus.noInventory) {
      return _messageView(
        icon: Icons.kitchen_outlined,
        title: 'Nothing to cook with yet',
        body: 'There are no in-date items in your inventory right now. Add some food and come back for recipe ideas.',
      );
    }
    if (data.status == RecipeSuggestionsStatus.noMatches) {
      // AC 6.1.7 — say so plainly; never imply a match exists.
      return _messageView(
        icon: Icons.search_off,
        title: 'No matching recipes found',
        body: 'We couldn\'t find any recipes that use the ingredients you have right now. '
            'Try again later, or after adding more items.',
        action: OutlinedButton(onPressed: () => _load(refresh: true), child: const Text('Try different ideas')),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: AppTheme.paprika, fontSize: 12.5)),
            ),
          _buildIntro(data),
          const SizedBox(height: 12),
          for (final recipe in data.recipes) ...[
            _RecipeCard(recipe: recipe, onTap: () => _openRecipe(recipe)),
            const SizedBox(height: 12),
          ],
          Text(
            'Recipes are AI-generated. Check ingredients for allergies and always cook food thoroughly.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro(RecipeSuggestions data) {
    final expiring = data.expiringSoonCount;
    // AC 6.1.6 — when nothing is expiring soon, say the recipes use the
    // rest of the inventory instead.
    final text = expiring > 0
        ? 'Recipes using your $expiring ${expiring == 1 ? 'item' : 'items'} expiring in the next 3 days come first.'
        : 'Nothing is expiring in the next 3 days, so these recipes use other food you have.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: expiring > 0 ? AppTheme.honeyLight : AppTheme.basilLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(expiring > 0 ? Icons.schedule : Icons.eco_outlined,
              size: 20, color: expiring > 0 ? AppTheme.honey : AppTheme.seedColor),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _messageView({required IconData icon, required String title, required String body, Widget? action}) {
    return ListView(
      // Scrollable so pull-to-refresh-style layouts and small screens behave.
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        Icon(icon, size: 48, color: Colors.grey.shade500),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
        if (action != null) ...[const SizedBox(height: 20), Center(child: action)],
      ],
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe, required this.onTap});
  final Recipe recipe;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = recipeMetaLine(recipe);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(recipe.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(meta, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
              if (recipe.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(recipe.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              ],
              // AC 6.1.3 — which expiring item this uses, and its date.
              for (final match in recipe.expiringMatches)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 15, color: AppTheme.paprika),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Uses ${match.name} · ${expiryPhrase(match.daysLeft, match.expiryDate)}',
                          style: const TextStyle(fontSize: 12.5, color: AppTheme.paprika, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                recipe.missingCount == 0
                    ? 'All ${recipe.matchedCount} ingredients in your inventory'
                    : '${recipe.matchedCount} of ${recipe.matchedCount + recipe.missingCount} ingredients in your inventory',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
