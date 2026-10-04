import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'recipe_detail_screen.dart';
import 'recipe_formatting.dart';

/// Epic 6 / User Story 6.1 — recipes matched to the household's inventory,
/// recipes using items expiring within 3 days first. Two sources, shown
/// together: the recipe dataset (fast, loads first) and a few AI ideas
/// from Gemini (slower, loads separately — if it's slow or unavailable,
/// the dataset recipes are still there). Opened from the Home tab.
class RecipeSuggestionsScreen extends StatefulWidget {
  const RecipeSuggestionsScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<RecipeSuggestionsScreen> createState() => _RecipeSuggestionsScreenState();
}

class _RecipeSuggestionsScreenState extends State<RecipeSuggestionsScreen> {
  RecipeSuggestions? _dataset;
  String? _datasetError;
  bool _datasetLoading = true;

  RecipeSuggestions? _ai;
  String? _aiError;
  bool _aiLoading = true;

  int _datasetRequest = 0;
  int _aiRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadDataset();
    _loadAi();
  }

  Future<void> _loadDataset() async {
    final id = ++_datasetRequest;
    setState(() {
      _datasetLoading = true;
      _datasetError = null;
    });
    try {
      final result = await widget.appState.getRecipeSuggestions();
      if (!mounted || id != _datasetRequest) return;
      setState(() {
        _dataset = result;
        _datasetLoading = false;
      });
    } catch (e) {
      if (!mounted || id != _datasetRequest) return;
      setState(() {
        _datasetError = e.toString();
        _datasetLoading = false;
      });
    }
  }

  Future<void> _loadAi({bool refresh = false}) async {
    final id = ++_aiRequest;
    setState(() {
      _aiLoading = true;
      _aiError = null;
    });
    try {
      final result = await widget.appState.getAiRecipeSuggestions(refresh: refresh);
      if (!mounted || id != _aiRequest) return;
      setState(() {
        _ai = result;
        _aiLoading = false;
      });
    } catch (e) {
      if (!mounted || id != _aiRequest) return;
      setState(() {
        _aiError = e.toString();
        _aiLoading = false;
      });
    }
  }

  Future<void> _reloadBoth() => Future.wait([_loadDataset(), _loadAi()]);

  Future<void> _openRecipe(Recipe recipe) async {
    final updated = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RecipeDetailScreen(appState: widget.appState, recipe: recipe),
    ));
    // Ingredients were used — availability and ranking have changed.
    if (updated == true && mounted) _reloadBoth();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipe ideas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'New AI ideas',
            onPressed: _aiLoading ? null : () => _loadAi(refresh: true),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Nothing in stock: both sources say the same thing, so say it once.
    if (_dataset?.status == RecipeSuggestionsStatus.noInventory) {
      return _messageView(
        icon: Icons.kitchen_outlined,
        title: 'Nothing to cook with yet',
        body: 'There are no in-date items in your inventory right now. Add some food and come back for recipe ideas.',
      );
    }
    if (_datasetLoading && _dataset == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final dataset = _dataset;
    final datasetRecipes = dataset?.recipes ?? const <Recipe>[];
    final aiRecipes = _ai?.recipes ?? const <Recipe>[];
    final noneAnywhere = dataset?.status == RecipeSuggestionsStatus.noMatches &&
        !_aiLoading && aiRecipes.isEmpty;

    return RefreshIndicator(
      onRefresh: _reloadBoth,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (dataset != null) _buildIntro(dataset.expiringSoonCount),
          if (noneAnywhere) ...[
            const SizedBox(height: 24),
            // AC 6.1.7 — say so plainly; never imply a match exists.
            _inlineMessage(Icons.search_off, 'No matching recipes found',
                'We couldn\'t find any recipes that use the ingredients you have right now. Try again later, or after adding more items.'),
          ],

          // ---- From the recipe collection ----
          const SizedBox(height: 16),
          _sectionHeader('From our recipe collection', null),
          if (_datasetError != null)
            _inlineError('Couldn\'t load recipes. $_datasetError', _loadDataset)
          else if (datasetRecipes.isEmpty && !noneAnywhere)
            _inlineNote('No recipes in our collection match your ingredients right now.')
          else
            for (final recipe in datasetRecipes) _RecipeCard(recipe: recipe, onTap: () => _openRecipe(recipe)),

          // ---- AI ideas ----
          const SizedBox(height: 20),
          _sectionHeader('AI recipe ideas', 'Created by Gemini for what you have'),
          if (_aiLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Text('Asking Gemini for ideas…', style: TextStyle(color: Colors.grey.shade700)),
                ],
              ),
            )
          else if (_aiError != null)
            _inlineError('AI ideas aren\'t available right now. $_aiError', () => _loadAi())
          else if (aiRecipes.isEmpty)
            _inlineNote('No AI ideas for your ingredients this time.')
          else
            for (final recipe in aiRecipes) _RecipeCard(recipe: recipe, onTap: () => _openRecipe(recipe)),

          const SizedBox(height: 12),
          Text(
            'Collection recipes come from Food.com / RecipeNLG. AI ideas are generated by Gemini and haven\'t been '
            'tested. Always check ingredients for allergies and cook food thoroughly.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro(int expiring) {
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

  Widget _sectionHeader(String title, String? subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      );

  Widget _inlineNote(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
      );

  Widget _inlineError(String text, VoidCallback retry) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(text, style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5))),
            TextButton(onPressed: retry, child: const Text('Retry')),
          ],
        ),
      );

  Widget _inlineMessage(IconData icon, String title, String body) => Column(
        children: [
          Icon(icon, size: 40, color: Colors.grey.shade500),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
        ],
      );

  Widget _messageView({required IconData icon, required String title, required String body}) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [const SizedBox(height: 40), _inlineMessage(icon, title, body)],
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
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!recipe.isAiGenerated) RecipeImage(url: recipe.imageUrl, height: 140),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (recipe.isAiGenerated) const Padding(padding: EdgeInsets.only(bottom: 6), child: AiBadge()),
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
          ],
        ),
      ),
    );
  }
}
