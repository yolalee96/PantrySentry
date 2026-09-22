import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/recognition_candidate.dart';
import '../../state/app_state.dart';

/// User Story 4.3 — capture or pick a photo of a food item, send it to the
/// backend (Google Vision Label Detection, resolved through
/// product_keyword_mapping — see recognition.js), and let the user pick
/// from the returned candidates. Pops with the chosen [RecognitionCandidate]
/// so the caller (Add Item screen) can pre-fill its form — nothing is
/// saved here, matching the same review-before-commit pattern as barcode
/// scanning (AC 4.4).
class PhotoScanScreen extends StatefulWidget {
  const PhotoScanScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<PhotoScanScreen> createState() => _PhotoScanScreenState();
}

class _PhotoScanScreenState extends State<PhotoScanScreen> {
  Uint8List? _imageBytes;
  bool _busy = false;
  String? _error;
  List<RecognitionCandidate> _candidates = [];

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    XFile? picked;
    try {
      // maxWidth/imageQuality do the compression for us — no separate
      // image library needed, and keeps the upload well under the
      // backend's size limit without the user having to think about it.
      picked = await picker.pickImage(source: source, maxWidth: 768, imageQuality: 85);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _error = _messageForPickerError(source, e));
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = source == ImageSource.camera
          ? 'Camera permission denied. Allow camera access or enter the item manually.'
          : 'Gallery permission denied. Allow gallery access or enter the item manually.');
      return;
    }
    if (picked == null) return; // user cancelled the picker — not an error

    final bytes = await picked.readAsBytes();

    // AC 4.2.11 — validate the file is actually a real, openable image
    // before sending it anywhere, rather than finding out from a
    // confusing backend error later.
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      codec.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _imageBytes = null;
        _candidates = [];
        _error = 'Unable to open this image. Please choose another photo.';
      });
      return;
    }

    setState(() {
      _imageBytes = bytes;
      _candidates = [];
      _error = null;
    });
    await _recognize(bytes);
  }

  /// AC 4.2.4 / 4.2.9 — distinguishes a permission denial from any other
  /// picker failure, with the exact wording specified per source.
  String _messageForPickerError(ImageSource source, PlatformException e) {
    final signal = '${e.code} ${e.message ?? ''}'.toLowerCase();
    final looksLikePermission = signal.contains('denied') || signal.contains('permission') || signal.contains('notallowed');
    if (source == ImageSource.camera) {
      return looksLikePermission
          ? 'Camera permission denied. Allow camera access or enter the item manually.'
          : 'Camera is unavailable right now. Try again, or enter the item manually.';
    }
    return looksLikePermission
        ? 'Gallery permission denied. Allow gallery access or enter the item manually.'
        : 'Gallery is unavailable right now. Try again, or enter the item manually.';
  }

  Future<void> _recognize(Uint8List bytes) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final candidates = await widget.appState.recognitionRepo.recognizeImage(bytes);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _candidates = candidates;
        if (candidates.isEmpty) {
          _error = 'No confident match found — you can still enter the item manually.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Recognition failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Take photo')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_imageBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(_imageBytes!, height: 220, fit: BoxFit.cover),
                )
              else
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.photo_camera_outlined, size: 48, color: Colors.grey.shade400),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      // AC 4.2.12 — disabled while recognition is in
                      // progress, so a second submission can't fire.
                      onPressed: _busy ? null : () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Take photo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose from gallery'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Recognising food', style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: Colors.orange.shade800)),
                ),
              if (_candidates.isNotEmpty) ...[
                const Text('Is this what you photographed?', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_candidates.first.productName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(_candidates.first.categoryName, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _busy ? null : () => setState(() => _candidates = []),
                                child: const Text('Not this'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _busy ? null : () => Navigator.of(context).pop(_candidates.first),
                                child: const Text('Confirm'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(null),
                child: const Text('Enter item manually instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
