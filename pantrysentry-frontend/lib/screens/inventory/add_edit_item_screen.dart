import 'dart:async';
import 'package:flutter/material.dart';
import '../../state/app_state.dart';
import '../../models/food_item.dart';
import '../../models/shelf_life_suggestion.dart';
import '../../models/scanned_product.dart';
import '../../services/shelf_life_service.dart';
import '../../services/reminder_service.dart';
import '../../widgets/validated_text_field.dart';
import '../../utils/date_format.dart';
import '../../utils/unit_options.dart';
import 'barcode_scan_screen.dart';
import 'photo_scan_screen.dart';
import '../../models/recognition_candidate.dart';
import '../../theme/app_theme.dart';
import '../../widgets/dropdown_date_picker.dart';

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// AC 2.1.1 — manual entry: name, quantity, storage location, expiry date.
/// AC 3.1.1 / AC 3.1.2 — optionally set an expiry reminder while adding.
/// [existingItem] != null switches this into edit mode.
class AddEditItemScreen extends StatefulWidget {
  const AddEditItemScreen({super.key, required this.appState, this.existingItem});
  final AppState appState;
  final FoodItem? existingItem;

  @override
  State<AddEditItemScreen> createState() => _AddEditItemScreenState();
}

class _AddEditItemScreenState extends State<AddEditItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  final _priceController = TextEditingController();
  final _customLeadTimeController = TextEditingController();

  /// AC (new) — duplicate detection: the active item this matches by
  /// name, if any (excluding itself when editing). Recomputed live as
  /// the user types, so the warning appears/disappears immediately.
  FoodItem? _duplicateMatch;

  /// Options shown in the unit dropdown — normally just [kUnitOptions],
  /// but gains an extra entry if editing an item whose existing unit
  /// isn't one of the standard options (see initState).
  late List<String> _unitOptions = kUnitOptions;
  String? _unit;

  StorageLocation? _location;
  ProductCategory? _category;
  DateTime? _useByDate;
  bool _dateTouched = false;
  /// Once true, auto-fill never overwrites the date again — set the
  /// moment the user picks a date themselves (or immediately in edit
  /// mode, since an existing item's date is already a deliberate value).
  bool _dateManuallyEdited = false;
  bool _locationTouched = false;
  bool _categoryTouched = false;

  bool _wantsReminder = true; // AC: reminder toggle defaults on
  int? _selectedPresetLeadTime;
  bool _useCustomLeadTime = false;
  String? _reminderError;
  String? _submitError;

  bool _submitting = false;

  // Live shelf-life lookup, across all 3 storage types at once (real,
  // sourced data — see ShelfLifeRepository) — lets us show "here's how
  // this fares in each place" as soon as category+name are set, before
  // the user has picked a storage location.
  Timer? _debounce;
  Map<StorageLocation, ShelfLifeSuggestion?>? _storageSuggestions;
  bool _loadingSuggestions = false;
  int _suggestionRequestId = 0; // guards against a stale response overwriting a newer one

  bool get _isEditing => widget.existingItem != null;

  /// The suggestion for whichever storage location is currently selected
  /// (derived from the all-3 lookup above — no separate fetch needed).
  ShelfLifeSuggestion? get _liveSuggestion =>
      _location == null ? null : _storageSuggestions?[_location];

  @override
  void initState() {
    super.initState();
    final existing = widget.existingItem;
    if (existing != null) {
      _nameController.text = existing.name;
      _quantityController.text = _formatQty(existing.quantity);
      _unit = existing.unit;
      if (!kUnitOptions.contains(existing.unit)) {
        // An existing item can have a unit outside the standard list (it
        // used to be free text) — keep it selectable rather than silently
        // dropping/changing the user's data.
        _unitOptions = [existing.unit, ...kUnitOptions];
      }
      _location = existing.storageLocation;
      _category = existing.category;
      _useByDate = existing.useByDate;
      _dateManuallyEdited = true; // editing an existing item — never auto-overwrite its date
      _notesController.text = existing.notes ?? '';
      _priceController.text = existing.price == null ? '' : _formatPriceForInput(existing.price!);
    } else {
      _unit = kUnitOptions.first; // sensible default for a new item: 'pcs'
    }
    _nameController.addListener(_scheduleSuggestionFetch);
    _nameController.addListener(_checkForDuplicate);
    _scheduleSuggestionFetch();
    _checkForDuplicate();
  }

  /// Live duplicate check — case-insensitive, trimmed, against active
  /// (in-stock) items only in the current household. Doesn't block
  /// typing; just surfaces a warning banner. Submit additionally gates
  /// behind a confirmation dialog if this is still set (see _submit).
  void _checkForDuplicate() {
    final name = _nameController.text.trim().toLowerCase();
    if (name.isEmpty) {
      if (_duplicateMatch != null) setState(() => _duplicateMatch = null);
      return;
    }
    final match = widget.appState.activeItems
        .where((i) => i.id != widget.existingItem?.id && i.name.trim().toLowerCase() == name)
        .firstOrNull;
    if (match?.id != _duplicateMatch?.id) {
      setState(() => _duplicateMatch = match);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.removeListener(_scheduleSuggestionFetch);
    _nameController.removeListener(_checkForDuplicate);
    _nameController.dispose();
    _quantityController.dispose();
    _notesController.dispose();
    _priceController.dispose();
    _customLeadTimeController.dispose();
    super.dispose();
  }

  String _formatQty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  Widget _buildDuplicateWarning(FoodItem match) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.honeyLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppTheme.honey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You already have "${match.name}" — ${_formatQty(match.quantity)} ${match.unit} in ${match.storageLocation.label}.',
              style: const TextStyle(fontSize: 12.5, color: AppTheme.ink),
            ),
          ),
        ],
      ),
    );
  }

  /// Debounced so a real lookup doesn't fire on every single keystroke —
  /// waits half a second after the user stops typing/changing fields.
  /// Only needs a category to be picked (not storage location).
  void _scheduleSuggestionFetch() {
    if (_category == null) {
      setState(() => _storageSuggestions = null);
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _fetchSuggestions);
  }

  Future<void> _fetchSuggestions() async {
    if (_category == null) return;
    final requestId = ++_suggestionRequestId;
    setState(() => _loadingSuggestions = true);
    try {
      final result = await widget.appState.getStorageSuggestions(
        category: _category!,
        itemName: _nameController.text,
      );
      if (!mounted || requestId != _suggestionRequestId) return; // a newer request already superseded this one
      setState(() {
        _storageSuggestions = result;
        _loadingSuggestions = false;
        _refreshSuggestion();
      });
      _maybeAutoFillDate();
    } catch (_) {
      // Network hiccup on a "nice to have" suggestion shouldn't block the
      // form — just silently fall back to the static placeholder estimate.
      if (!mounted || requestId != _suggestionRequestId) return;
      setState(() {
        _storageSuggestions = null;
        _loadingSuggestions = false;
      });
    }
  }

  /// The lead time to suggest right now: prefers the real, sourced value
  /// for the currently-selected storage location when available,
  /// otherwise falls back to ShelfLifeService's static placeholder.
  int? get _suggestedLeadTime {
    if (_category == null || _location == null) return null;
    final live = _liveSuggestion;
    if (live != null && live.status == ShelfLifeRuleStatus.available && live.recommendedDays != null) {
      return live.recommendedDays!.round().clamp(1, 3650);
    }
    return ShelfLifeService.suggestLeadTime(_category!, _location!);
  }

  void _refreshSuggestion() {
    if (!_useCustomLeadTime && _suggestedLeadTime != null) {
      _selectedPresetLeadTime = _suggestedLeadTime;
    }
  }

  /// Auto-calculates the expiry date from the real shelf-life dataset
  /// (using its recommendedDays — already the source's own representative
  /// figure for the range, e.g. the midpoint of "1-2 days") the moment
  /// both a category and storage location are known and a specific rule
  /// is matched. Does nothing for packaged/unmatched foods (no rule, or
  /// notRecommended/qualitativeOnly — neither gives a day count to use),
  /// leaving the date for manual entry as before. Never overwrites a date
  /// the user has already picked themselves.
  void _maybeAutoFillDate() {
    if (_dateManuallyEdited) return;
    final suggestion = _liveSuggestion;
    if (suggestion == null ||
        suggestion.status != ShelfLifeRuleStatus.available ||
        suggestion.recommendedDays == null) {
      // No usable data for the current name/category/storage combo — if
      // there's a leftover auto-filled date from a previous combo, clear
      // it rather than leave a stale value sitting there unexplained.
      if (_useByDate != null) setState(() => _useByDate = null);
      return;
    }
    final days = suggestion.recommendedDays!.round().clamp(0, 3650);
    setState(() {
      _useByDate = DateTime.now().add(Duration(days: days));
      _dateTouched = true;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDropdownDatePicker(
      context: context,
      initialDate: _useByDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        _useByDate = picked;
        _dateTouched = true;
        _dateManuallyEdited = true; // the user's own choice always wins from now on
      });
    }
  }

  /// User Story 4.1 — opens the barcode scanner and, on a match, pre-fills
  /// name/category/storage location. Everything it fills stays fully
  /// editable and nothing is saved until the user submits the form (AC
  /// 4.4) — this only ever sets fields, never calls addItem.
  Future<void> _scanBarcode() async {
    final result = await Navigator.of(context).push<ScannedProduct>(
      MaterialPageRoute(builder: (_) => BarcodeScanScreen(appState: widget.appState)),
    );
    if (result == null || !mounted) return;

    setState(() {
      _nameController.text = result.name;
      if (result.category != null) {
        _category = result.category;
        _categoryTouched = true;
      }
      if (result.suggestedLocation != null) {
        _location = result.suggestedLocation;
        _locationTouched = true;
        _refreshSuggestion();
      }
    });
    _scheduleSuggestionFetch();
    _maybeAutoFillDate();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Filled in from scan: ${result.name} — check the details below before saving.')),
    );
  }

  /// User Story 4.3 — opens the photo scanner and pre-fills name and
  /// category from whatever candidate the user confirms. Storage location
  /// is left for manual entry (recognition doesn't suggest a location).
  Future<void> _scanPhoto() async {
    final result = await Navigator.of(context).push<RecognitionCandidate>(
      MaterialPageRoute(builder: (_) => PhotoScanScreen(appState: widget.appState)),
    );
    if (result == null || !mounted) return;

    setState(() {
      _nameController.text = result.productName;
      if (result.category != null) {
        _category = result.category;
        _categoryTouched = true;
      }
    });
    _scheduleSuggestionFetch();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(
        result.category != null
            ? 'Filled in "${result.productName}" (${result.categoryName}) from photo — check the details below.'
            : 'Filled in "${result.productName}" from photo — please pick a category and check the details.',
      )),
    );
  }

  String _formatPriceForInput(double price) =>
      price == price.roundToDouble() ? price.toStringAsFixed(0) : price.toStringAsFixed(2);

  int? get _effectiveLeadTime {
    if (!_wantsReminder) return null;
    if (_useCustomLeadTime) {
      return int.tryParse(_customLeadTimeController.text.trim());
    }
    return _selectedPresetLeadTime;
  }

  Future<void> _submit() async {
    setState(() {
      _dateTouched = true;
      _locationTouched = true;
      _categoryTouched = true;
    });
    final formValid = _formKey.currentState!.validate();
    if (!formValid || _location == null || _category == null || _useByDate == null || _unit == null) {
      return;
    }

    if (!_isEditing && _duplicateMatch != null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Already in your inventory'),
          content: Text(
            'You already have "${_duplicateMatch!.name}" — ${_formatQty(_duplicateMatch!.quantity)} ${_duplicateMatch!.unit} in ${_duplicateMatch!.storageLocation.label}. Add another anyway?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add anyway')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    if (_wantsReminder) {
      final leadTime = _effectiveLeadTime;
      if (leadTime == null || leadTime <= 0) {
        setState(() => _reminderError = 'Enter a valid number of days');
        return;
      }
      if (!ReminderService.isValidLeadTime(leadTimeDays: leadTime, useByDate: _useByDate!)) {
        setState(() => _reminderError =
            'The reminder date cannot be later than the expiry date.');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _reminderError = null;
      _submitError = null;
    });

    final quantity = double.parse(_quantityController.text.trim());
    final unit = _unit!;
    final notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();
    final priceText = _priceController.text.trim();
    final price = priceText.isEmpty ? null : double.tryParse(priceText);

    try {
      if (_isEditing) {
        final item = widget.existingItem!
          ..name = _nameController.text.trim()
          ..quantity = quantity
          ..unit = unit
          ..storageLocation = _location!
          ..category = _category!
          ..useByDate = _useByDate!
          ..notes = notes
          ..price = price;
        await widget.appState.updateItem(item);
        if (_wantsReminder) {
          await widget.appState.setReminder(item, _effectiveLeadTime!, wasCustom: _useCustomLeadTime);
        } else {
          // Reminder toggle turned off during this edit — cancel any
          // existing untriggered reminder for this item, otherwise the
          // old one just stays active.
          final existing = widget.appState.reminders
              .where((r) => r.itemId == item.id && !r.triggered)
              .toList();
          for (final r in existing) {
            await widget.appState.cancelReminder(r.id);
          }
        }
      } else {
        final newItem = await widget.appState.addItem(
          name: _nameController.text.trim(),
          quantity: quantity,
          unit: unit,
          location: _location!,
          category: _category!,
          useByDate: _useByDate!,
          notes: notes,
          price: price,
        );
        if (_wantsReminder && newItem != null) {
          await widget.appState.setReminder(newItem, _effectiveLeadTime!, wasCustom: _useCustomLeadTime);
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = 'Something went wrong: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit item' : 'Add item')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                if (!_isEditing) ...[
                  _buildScanButtonsRow(),
                  const SizedBox(height: 20),
                ],
                ValidatedTextField(
                  label: 'Item name',
                  controller: _nameController,
                  autofocus: !_isEditing,
                  validator: ValidatedTextField.required('the item name'),
                ),
                if (_duplicateMatch != null) ...[
                  const SizedBox(height: 8),
                  _buildDuplicateWarning(_duplicateMatch!),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ValidatedTextField(
                        label: 'Quantity',
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (value) {
                          final v = double.tryParse((value ?? '').trim());
                          if (v == null || v <= 0) return 'Enter a valid quantity';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _unit,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: _unitOptions
                            .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (value) => setState(() => _unit = value),
                        validator: (value) => value == null ? 'Please select a unit' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildCategoryField(),
                if (_category != null) ...[
                  const SizedBox(height: 12),
                  _buildStorageSuggestionBadges(),
                ],
                const SizedBox(height: 16),
                _buildStorageLocationField(),
                const SizedBox(height: 16),
                _buildDateField(context),
                if (_liveSuggestion?.status == ShelfLifeRuleStatus.notRecommended) ...[
                  const SizedBox(height: 16),
                  _buildNotRecommendedWarning(),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  minLines: 2,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'e.g. "Started this bag, about half left"',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price paid (optional)',
                    hintText: 'e.g. 5.90',
                    prefixText: 'RM ',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null; // optional
                    final parsed = double.tryParse(value.trim());
                    if (parsed == null) return 'Enter a valid amount';
                    if (parsed < 0) return 'Price can\'t be negative';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                _buildReminderSection(),
                if (_submitError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(_submitError!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_isEditing ? 'Save changes' : 'Add to inventory'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// AC 4.1 / 4.3 — two separate entry points, side by side, per the
  /// team's design decision. Photo stays visible but routes to a "coming
  /// soon" message rather than disappearing (see [_scanPhotoComingSoon]).
  Widget _buildScanButtonsRow() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _scanBarcode,
            icon: const Icon(Icons.qr_code_scanner, size: 19),
            label: const Text('Scan barcode'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _scanPhoto,
            icon: const Icon(Icons.camera_alt_outlined, size: 19),
            label: const Text('Take photo'),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryField() {
    final showError = _categoryTouched && _category == null;
    return DropdownButtonFormField<ProductCategory>(
      initialValue: _category,
      decoration: InputDecoration(
        labelText: 'Category',
        helperText: _category == null ? 'Pick a category to see storage guidance' : null,
        errorText: showError ? 'Please select a category' : null,
      ),
      items: ProductCategory.values
          .map((cat) => DropdownMenuItem(value: cat, child: Text(cat.label)))
          .toList(),
      onChanged: (value) => setState(() {
        _category = value;
        _categoryTouched = true;
        _scheduleSuggestionFetch();
      }),
      validator: (value) => value == null ? 'Please select a category' : null,
    );
  }

  /// One badge per storage type (Fridge/Freezer/Pantry) showing at a
  /// glance whether it's a good fit — tap one to select it as the
  /// storage location below. If the category has no shelf-life data at
  /// all (not just for one storage type — for none of them), showing
  /// three "?" badges reads as broken rather than "we don't know yet", so
  /// that case gets a plain-language disclaimer instead of the badges.
  Widget _buildStorageSuggestionBadges() {
    if (_loadingSuggestions) {
      return Row(
        children: [
          const SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('Checking storage guidance...', style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
        ],
      );
    }

    final suggestions = _storageSuggestions;
    if (suggestions == null) return const SizedBox.shrink();

    final hasAnyData = StorageLocation.values.any((loc) => suggestions[loc] != null);
    if (!hasAnyData) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Right now we don\'t have shelf-life data for this category — please key in the expiry date yourself.',
                style: TextStyle(color: Colors.blue.shade900, fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: StorageLocation.values.map((loc) {
        final suggestion = suggestions[loc];
        final selected = _location == loc;
        final (icon, color, label) = _badgeStyleFor(suggestion);
        return ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: selected ? Colors.white : color),
              const SizedBox(width: 5),
              Text('${loc.label}${label != null ? ' · $label' : ''}'),
            ],
          ),
          selected: selected,
          onSelected: (_) {
            setState(() {
              _location = loc;
              _locationTouched = true;
              _refreshSuggestion();
            });
            _maybeAutoFillDate();
          },
        );
      }).toList(),
    );
  }

  (IconData, Color, String?) _badgeStyleFor(ShelfLifeSuggestion? suggestion) {
    if (suggestion == null) return (Icons.help_outline, Colors.grey.shade500, 'no data yet');
    switch (suggestion.status) {
      case ShelfLifeRuleStatus.notRecommended:
        return (Icons.block, Colors.red.shade600, 'not recommended');
      case ShelfLifeRuleStatus.qualitativeOnly:
        return (Icons.info_outline, Colors.orange.shade700, null);
      case ShelfLifeRuleStatus.available:
        final label = suggestion.minDays != null && suggestion.maxDays != null
            ? '${suggestion.minDays}-${suggestion.maxDays}d'
            : null;
        return (Icons.check_circle_outline, Colors.green.shade700, label);
    }
  }

  Widget _buildNotRecommendedWarning() {
    final suggestion = _liveSuggestion;
    final friendlyMessage = 'Storing ${_category!.label} in the ${_location!.label} isn\'t recommended'
        '${_location != StorageLocation.fridge ? ' — use the fridge or freezer instead' : ''}.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(friendlyMessage,
                    style: TextStyle(color: Colors.orange.shade900, fontSize: 13, fontWeight: FontWeight.w600)),
                if (suggestion?.sourceText != null) ...[
                  const SizedBox(height: 4),
                  Text(suggestion!.sourceText!,
                      style: TextStyle(color: Colors.orange.shade800, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageLocationField() {
    final showError = _locationTouched && _location == null;
    return DropdownButtonFormField<StorageLocation>(
      initialValue: _location,
      decoration: InputDecoration(
        labelText: 'Storage location',
        errorText: showError ? 'Please select a storage location' : null,
      ),
      items: StorageLocation.values
          .map((loc) => DropdownMenuItem(value: loc, child: Text(loc.label)))
          .toList(),
      onChanged: (value) {
        setState(() {
          _location = value;
          _locationTouched = true;
          _refreshSuggestion();
        });
        _maybeAutoFillDate();
      },
      validator: (value) => value == null ? 'Please select a storage location' : null,
    );
  }

  Widget _buildDateField(BuildContext context) {
    final showError = _dateTouched && _useByDate == null;
    final wasAutoFilled = _useByDate != null && !_dateManuallyEdited;
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Use-by / expiry date',
          errorText: showError ? 'Please select a date' : null,
          helperText: wasAutoFilled ? 'Auto-filled from shelf-life data — tap to change' : null,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20),
        ),
        child: Text(
          _useByDate == null ? 'Tap to select a date' : formatLongDate(_useByDate!),
          style: TextStyle(color: _useByDate == null ? Colors.grey.shade600 : Colors.black87),
        ),
      ),
    );
  }

  Widget _buildReminderSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Set an expiry reminder'),
              value: _wantsReminder,
              onChanged: (value) => setState(() {
                _wantsReminder = value;
                _reminderError = null;
                if (value && _selectedPresetLeadTime == null) _refreshSuggestion();
              }),
            ),
            if (_wantsReminder) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  ...[7, 3, 1].map((days) => ChoiceChip(
                        label: Text('$days day${days == 1 ? '' : 's'} before'),
                        selected: !_useCustomLeadTime && _selectedPresetLeadTime == days,
                        onSelected: (_) => setState(() {
                          _useCustomLeadTime = false;
                          _selectedPresetLeadTime = days;
                          _reminderError = null;
                        }),
                      )),
                  ChoiceChip(
                    label: const Text('Custom'),
                    selected: _useCustomLeadTime,
                    onSelected: (_) => setState(() {
                      _useCustomLeadTime = true;
                      _reminderError = null;
                    }),
                  ),
                ],
              ),
              if (_suggestedLeadTime != null && !_useCustomLeadTime)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _liveSuggestion?.status == ShelfLifeRuleStatus.available
                        ? 'Suggested: $_suggestedLeadTime days before, based on real shelf-life data'
                        : 'Suggested for ${_category!.label} in ${_location!.label}: '
                            '$_suggestedLeadTime days before',
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                  ),
                ),
              if (_useCustomLeadTime) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customLeadTimeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Days before expiry'),
                  onChanged: (_) => setState(() => _reminderError = null),
                ),
              ],
              if (_reminderError != null) ...[
                const SizedBox(height: 8),
                Text(_reminderError!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
