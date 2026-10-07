import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/detected_item_draft.dart';
import '../../models/food_item.dart';
import '../../models/shelf_life_suggestion.dart';
import '../../services/category_defaults_service.dart';
import '../../state/app_state.dart';
import '../../utils/date_format.dart';
import '../../utils/unit_options.dart';
import '../../widgets/dropdown_date_picker.dart';

enum _Stage { capture, working, review, submitting }

/// Epic 4 — "Scan several items": one photo of food on a table or in a
/// trolley -> Gemini finds each item -> an editable review list (with
/// numbered boxes on the photo) -> the user confirms -> items are added.
/// Nothing is saved before that confirmation. Works alongside the
/// single-item photo scan and the receipt scan, and follows the receipt
/// review's rules (category, storage and use-by date required; shelf-life
/// suggestions pre-fill the date).
class MultiItemScanScreen extends StatefulWidget {
  const MultiItemScanScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<MultiItemScanScreen> createState() => _MultiItemScanScreenState();
}

class _MultiItemScanScreenState extends State<MultiItemScanScreen> {
  _Stage _stage = _Stage.capture;
  String? _error;
  Uint8List? _photo;
  double _photoAspect = 4 / 3;
  List<DetectedItemDraft> _drafts = [];
  bool _showValidation = false;

  Future<void> _pickImage(ImageSource source) async {
    XFile? picked;
    try {
      // ~1280 px is plenty for recognising groceries, and keeps the upload
      // small and fast (and lighter on the Gemini free tier).
      picked = await ImagePicker().pickImage(source: source, maxWidth: 1280, imageQuality: 85);
    } on PlatformException catch (e) {
      if (!mounted) return;
      final denied = '${e.code} ${e.message ?? ''}'.toLowerCase().contains('denied');
      setState(() => _error = source == ImageSource.camera
          ? (denied ? 'Camera permission denied. Allow camera access or choose from your gallery.' : 'Camera is unavailable right now. Try choosing from your gallery.')
          : (denied ? 'Gallery permission denied. Allow gallery access or take a photo instead.' : 'Gallery is unavailable right now. Try taking a photo instead.'));
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Couldn\'t open the ${source == ImageSource.camera ? 'camera' : 'gallery'}. Try the other option.');
      return;
    }
    if (picked == null) return; // cancelled

    final bytes = await picked.readAsBytes();
    try {
      final image = await _decode(bytes);
      _photoAspect = image.width / image.height;
    } catch (_) {
      _photoAspect = 4 / 3;
    }
    setState(() {
      _photo = bytes;
      _error = null;
      _stage = _Stage.working;
    });
    await _detect(bytes);
  }

  Future<ui.Image> _decode(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }

  Future<void> _detect(Uint8List bytes) async {
    try {
      final drafts = await widget.appState.recognitionRepo.recognizeMultipleItems(bytes);
      if (!mounted) return;
      if (drafts.isEmpty) {
        setState(() {
          _stage = _Stage.capture;
          _error = 'No food items found in that photo. Try again with the items spread out and well lit.';
        });
        return;
      }
      for (final d in drafts) {
        d.storageLocation = CategoryDefaultsService.suggestLocation(d.category);
      }
      setState(() {
        _drafts = drafts;
        _stage = _Stage.review;
        _showValidation = false;
      });
      unawaited(Future.wait(_drafts.map(_fetchShelfLifeSuggestion)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.capture;
        _error = e.toString();
      });
    }
  }

  /// Same shelf-life auto-fill as the receipt scan and Add screen; never
  /// overwrites a date the user picked.
  Future<void> _fetchShelfLifeSuggestion(DetectedItemDraft draft) async {
    if (draft.category == null || draft.dateManuallyEdited || draft.name.trim().isEmpty) return;
    try {
      final suggestions = await widget.appState.getStorageSuggestions(category: draft.category!, itemName: draft.name);
      if (!mounted || draft.dateManuallyEdited) return;
      final live = draft.storageLocation == null ? null : suggestions[draft.storageLocation];
      if (live != null && live.status == ShelfLifeRuleStatus.available && live.recommendedDays != null) {
        final days = live.recommendedDays!.round().clamp(0, 3650);
        setState(() => draft.useByDate = DateTime.now().add(Duration(days: days)));
      }
    } catch (_) {
      // Lookup hiccup — the date just stays for manual entry.
    }
  }

  Future<void> _submit() async {
    final toAdd = _drafts.where((d) => d.included).toList();
    if (toAdd.isEmpty) return;
    final missing = toAdd.where((d) =>
        d.name.trim().isEmpty || d.quantity <= 0 || d.category == null || d.storageLocation == null || d.useByDate == null);
    if (missing.isNotEmpty) {
      setState(() => _showValidation = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${missing.length} item(s) need a name, quantity, category, storage location or use-by date.'),
      ));
      return;
    }

    setState(() => _stage = _Stage.submitting);
    final added = <DetectedItemDraft>[];
    for (final d in toAdd) {
      try {
        final result = await widget.appState.addItem(
          name: d.name.trim(),
          quantity: d.quantity,
          unit: d.unit,
          location: d.storageLocation!,
          category: d.category!,
          useByDate: d.useByDate!,
        );
        if (result != null) added.add(d);
      } catch (_) {
        // Left in the list below so it can be retried.
      }
    }
    if (!mounted) return;
    final failed = toAdd.length - added.length;
    if (failed == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${added.length} item${added.length == 1 ? '' : 's'} to your inventory.')),
      );
      Navigator.of(context).pop();
      return;
    }
    // Keep only what still needs adding, so retrying can't add anything twice.
    setState(() {
      _drafts = _drafts.where((d) => !added.contains(d)).toList();
      _stage = _Stage.review;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Added ${added.length}; $failed couldn\'t be added. They\'re still listed — tap Add to try again.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan several items')),
      body: SafeArea(
        child: switch (_stage) {
          _Stage.capture => _buildCaptureView(),
          _Stage.working => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Finding the items in your photo…'),
                ]),
              ),
            ),
          _Stage.review => _buildReviewView(),
          _Stage.submitting => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }

  Widget _buildCaptureView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          height: 180,
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
          alignment: Alignment.center,
          child: Icon(Icons.shopping_basket_outlined, size: 48, color: Colors.grey.shade400),
        ),
        const SizedBox(height: 12),
        Text(
          'Spread your groceries out on a table (or snap your trolley) so each item is visible. '
          'You\'ll check everything before it\'s added.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Take photo'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose from gallery'),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
            child: Text(_error!, style: TextStyle(color: Colors.orange.shade900, fontSize: 13)),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Photos are sent to Google Gemini to recognise the items. On the free tier, Google may use them to improve '
          'its products, so avoid including people or personal documents.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _buildReviewView() {
    final includedCount = _drafts.where((d) => d.included).length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            children: [
              if (_photo != null) _buildPhotoWithBoxes(),
              const SizedBox(height: 10),
              const Text('Check each item — edit anything that\'s wrong, untick anything to skip.',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              for (var i = 0; i < _drafts.length; i++) _buildDraftCard(_drafts[i], i + 1),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _drafts.add(DetectedItemDraft.manual())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add something it missed'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: ElevatedButton(
            onPressed: includedCount == 0 ? null : _submit,
            child: Text(includedCount == 0
                ? 'Select items to add'
                : 'Add $includedCount item${includedCount == 1 ? '' : 's'} to inventory'),
          ),
        ),
      ],
    );
  }

  /// The photo with a numbered box for each detected item, matching the
  /// numbers on the cards below.
  Widget _buildPhotoWithBoxes() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: _photoAspect,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            return Stack(
              children: [
                Positioned.fill(child: Image.memory(_photo!, fit: BoxFit.fill)),
                for (var i = 0; i < _drafts.length; i++)
                  for (final box in _drafts[i].boxes)
                    Positioned(
                      top: box[0] / 1000 * h,
                      left: box[1] / 1000 * w,
                      height: (box[2] - box[0]) / 1000 * h,
                      width: (box[3] - box[1]) / 1000 * w,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _drafts[i].included ? Colors.amberAccent : Colors.white54,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.topLeft,
                          child: Container(
                            color: _drafts[i].included ? Colors.amberAccent : Colors.white54,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black)),
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDraftCard(DetectedItemDraft draft, int number) {
    final showErrors = _showValidation && draft.included;
    return Card(
      key: ObjectKey(draft),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(value: draft.included, onChanged: (v) => setState(() => draft.included = v ?? true)),
                CircleAvatar(
                  radius: 11,
                  backgroundColor: Colors.amber.shade200,
                  child: Text('$number', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: draft.name,
                    decoration: InputDecoration(
                      labelText: 'Item name',
                      isDense: true,
                      errorText: showErrors && draft.name.trim().isEmpty ? 'Required' : null,
                    ),
                    onChanged: (v) => draft.name = v,
                  ),
                ),
              ],
            ),
            if (draft.needsCheck)
              Padding(
                padding: const EdgeInsets.only(left: 48, bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.help_outline, size: 14, color: Colors.orange.shade800),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        draft.confidence == DetectionConfidence.low
                            ? 'Not sure about this one — please check it'
                            : 'Check the name and amount',
                        style: TextStyle(color: Colors.orange.shade800, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: _formatQty(draft.quantity),
                          decoration: InputDecoration(
                            labelText: 'Qty',
                            isDense: true,
                            errorText: showErrors && draft.quantity <= 0 ? 'Required' : null,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (v) => draft.quantity = double.tryParse(v.replaceAll(',', '.')) ?? 0,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: kUnitOptions.contains(draft.unit) ? draft.unit : 'pcs',
                          decoration: const InputDecoration(labelText: 'Unit', isDense: true),
                          items: kUnitOptions.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                          onChanged: (v) => setState(() => draft.unit = v ?? draft.unit),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<ProductCategory>(
                          initialValue: draft.category,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Category',
                            isDense: true,
                            errorText: showErrors && draft.category == null ? 'Required' : null,
                          ),
                          hint: const Text('Select'),
                          items: ProductCategory.values
                              .map((c) => DropdownMenuItem(value: c, child: Text(c.label, overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              draft.category = v;
                              draft.storageLocation ??= CategoryDefaultsService.suggestLocation(v);
                            });
                            _fetchShelfLifeSuggestion(draft);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<StorageLocation>(
                          initialValue: draft.storageLocation,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Storage',
                            isDense: true,
                            errorText: showErrors && draft.storageLocation == null ? 'Required' : null,
                          ),
                          hint: const Text('Select'),
                          items: StorageLocation.values.map((s) => DropdownMenuItem(value: s, child: Text(s.label))).toList(),
                          onChanged: (v) {
                            setState(() => draft.storageLocation = v);
                            _fetchShelfLifeSuggestion(draft);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDropdownDatePicker(
                        context: context,
                        initialDate: draft.useByDate ?? DateTime.now().add(const Duration(days: 5)),
                        firstDate: DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                      );
                      if (picked != null) {
                        setState(() {
                          draft.useByDate = picked;
                          draft.dateManuallyEdited = true;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Use-by date',
                        isDense: true,
                        errorText: showErrors && draft.useByDate == null ? 'Required' : null,
                      ),
                      child: Text(draft.useByDate == null ? 'Tap to set' : formatLongDate(draft.useByDate!)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatQty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}
