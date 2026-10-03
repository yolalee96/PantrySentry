import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/scanned_product.dart';
import '../../services/category_defaults_service.dart';
import '../../state/app_state.dart';

/// A hard, direct safety net for releasing the camera on web, independent
/// of mobile_scanner's own cleanup — which has multiple documented,
/// web-specific issues around not actually releasing the camera hardware
/// (see _exit() below for specifics). Unlike photo capture (image_picker),
/// where the BROWSER owns opening and closing the camera as one atomic,
/// native operation, barcode scanning needs a live embedded video preview
/// that OUR code opens and must close ourselves — so if the package's own
/// bookkeeping is wrong, nothing else stops the stream. This walks every
/// <video> element in the page and force-stops any camera track attached
/// to it, the same guarantee the browser gives Take Photo for free.
///
/// SETUP REQUIRED — add this inside <head> in web/index.html, alongside
/// the tesseract.js <script> tag:
///   <script>
///     window.pantrybuddyStopAllCameraStreams = function() {
///       document.querySelectorAll('video').forEach(function(v) {
///         var s = v.srcObject;
///         if (s && typeof s.getTracks === 'function') {
///           s.getTracks().forEach(function(t) { t.stop(); });
///           v.srcObject = null;
///         }
///       });
///     };
///   </script>
///
/// WEB-ONLY (dart:js_interop) — consistent with BrowserOcrService.
@JS('pantrybuddyStopAllCameraStreams')
external void _stopAllCameraStreamsJS();

void _forceStopAllCameraStreams() {
  try {
    _stopAllCameraStreamsJS();
  } catch (_) {
    // The JS function might not be defined yet (e.g. web/index.html
    // hasn't been updated) — fail quietly rather than crash the exit
    // path; mobile_scanner's own stop()/dispose() still ran regardless.
  }
}

/// User Story 4.1 — scans a product barcode, resolved server-side via
/// Open Food Facts + the product_keyword_mapping table (same recognition
/// pipeline as photo scanning), so a real category comes back whenever
/// one can be resolved. Pops with a [ScannedProduct] on success so the
/// caller (Add Item screen) can pre-fill its form — the user still
/// reviews/edits everything there before it's saved (AC 4.4). Pops with
/// null if the user backs out or chooses to enter the item manually.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key, required this.appState});
  final AppState appState;

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  // Restricted to linear product-barcode formats only — packaging often
  // has a separate marketing QR code (recipes/brand site) right next to
  // the real barcode, and without this the scanner can grab that instead
  // (confirmed happening during testing: it decoded a QR code URL rather
  // than a barcode number).
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      // Deliberately no ITF — deprecated in this mobile_scanner version,
      // and it's mostly used for case/carton-level barcodes rather than
      // retail packaging anyway.
    ],
  );
  final _manualCodeController = TextEditingController();

  bool _busy = false; // true while a detected code is being looked up
  bool _showManualEntry = false;
  String? _statusMessage;
  String? _engineError;
  bool _exited = false; // guards against stopping/popping more than once

  // The barcode that most recently came back "not found", and when. While
  // it's still sitting in frame, the scanner would otherwise re-detect it
  // the instant scanning resumes and immediately re-trigger the same
  // failed lookup — over and over, which is what looked like the screen
  // "glitching"/flashing. Ignoring repeat detections of the SAME code for
  // a short cooldown fixes that, while a genuinely different barcode
  // still triggers a lookup right away.
  String? _lastFailedBarcode;
  DateTime? _lastFailedAt;
  static const _failedCooldown = Duration(seconds: 4);

  @override
  void dispose() {
    // Only a fallback for an unusual teardown path that skipped _exit()
    // (e.g. the widget being removed without a normal pop) — normally
    // _exit() has already disposed the controller by the time this runs,
    // and disposing twice can throw.
    if (!_exited) {
      _controller.dispose();
    }
    _manualCodeController.dispose();
    super.dispose();
  }

  /// The ONLY path that should ever close this screen — guarantees the
  /// camera is actually released first. Handles the system back
  /// gesture/AppBar back button (via PopScope below) as well as every
  /// explicit pop in this file, so there's no route out of this screen
  /// that skips releasing the camera.
  ///
  /// Calls BOTH stop() and dispose(): stop() alone was leaving the
  /// browser's camera hardware indicator light on after leaving this
  /// screen (confirmed via screen recording) — dispose() is what actually
  /// tears down the underlying camera stream on web, not just pausing
  /// frame analysis.
  ///
  /// Also waits for the camera to actually finish starting up first, if
  /// it's still mid-startup — this is a documented mobile_scanner issue
  /// (github.com/juliansteenbakker/mobile_scanner/issues/505): both
  /// stop() and dispose() silently do nothing while the controller's
  /// value.isInitialized is still false, and the in-flight startup can
  /// then finish AFTER dispose(), leaving an orphaned camera stream
  /// nothing can stop anymore. Exiting quickly (e.g. tapping back right
  /// after opening the scanner) is exactly when this happens.
  Future<void> _exit([ScannedProduct? result]) async {
    if (_exited) return;
    _exited = true;

    if (!_controller.value.isInitialized) {
      final completer = Completer<void>();
      late final VoidCallback listener;
      listener = () {
        if (_controller.value.isInitialized || _controller.value.error != null) {
          completer.complete();
        }
      };
      _controller.addListener(listener);
      // Capped wait — if startup is somehow stuck, don't block leaving
      // the screen forever; worst case we're back to the old behaviour.
      await completer.future.timeout(const Duration(seconds: 3), onTimeout: () {});
      _controller.removeListener(listener);
    }

    try {
      await _controller.stop();
    } catch (_) {
      // Already stopped, or never started — fine either way.
    }
    try {
      await _controller.dispose();
    } catch (_) {
      // Already disposed — fine.
    }
    // Belt and braces: force-stop anything still live at the browser
    // level, regardless of whether the above actually worked — this is
    // the same guarantee Take Photo gets from the browser automatically.
    _forceStopAllCameraStreams();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.isEmpty) return;

    if (code == _lastFailedBarcode && _lastFailedAt != null && DateTime.now().difference(_lastFailedAt!) < _failedCooldown) {
      return; // same code that just failed, still in frame — don't re-trigger
    }
    await _lookUp(code);
  }

  Future<void> _lookUp(String barcode) async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    // AC 4.1.6 — pause further detection while looking this one up.
    await _controller.stop();

    try {
      final result = await widget.appState.recognitionRepo.recognizeBarcode(barcode);
      if (!mounted) return;

      if (result.productName == null) {
        setState(() {
          _busy = false;
          _statusMessage = 'No match found for barcode $barcode — try again, or enter the item manually.';
          _lastFailedBarcode = barcode;
          _lastFailedAt = DateTime.now();
        });
        await _controller.start();
        return;
      }

      final category = result.candidates.isNotEmpty ? result.candidates.first.category : null;
      await _exit(ScannedProduct(
        barcode: barcode,
        name: result.productName!,
        category: category,
        suggestedLocation: CategoryDefaultsService.suggestLocation(category),
        brand: result.brand,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusMessage = 'Product lookup failed: $e';
        _lastFailedBarcode = barcode;
        _lastFailedAt = DateTime.now();
      });
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scan barcode'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => _exit()),
          actions: [
            IconButton(
              tooltip: 'Enter barcode manually',
              icon: Icon(_showManualEntry ? Icons.camera_alt_outlined : Icons.keyboard_outlined),
              onPressed: () => setState(() => _showManualEntry = !_showManualEntry),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!_showManualEntry)
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder: (context, error) {
                          // AC 4.1.4 — camera access denied/unavailable.
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _engineError = error.errorCode.name);
                          });
                          return Container(
                            color: Colors.black87,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Camera error (${error.errorCode.name}). Allow camera access or enter the item manually.',
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      )
                    else
                      _buildManualEntry(),
                    if (!_showManualEntry) _buildScanOverlay(),
                    // AC 4.1.5 — guidance while scanning with nothing
                    // detected yet.
                    if (!_showManualEntry && _engineError == null)
                      Positioned(
                        bottom: 12,
                        left: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Position the barcode inside the frame and ensure good lighting.',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    // AC 4.1.6 — loading feedback while a detected code is
                    // being looked up.
                    if (_busy)
                      Container(
                        color: Colors.black54,
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 12),
                              Text('Looking up product...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_statusMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  color: Colors.orange.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade800, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_statusMessage!,
                            style: TextStyle(color: Colors.orange.shade900, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton(
                  onPressed: () => _exit(),
                  child: const Text('Enter item manually instead'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanOverlay() {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 260,
          height: 160,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 2.5),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildManualEntry() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Camera not working? Type the barcode number printed under it instead.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _manualCodeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Barcode number'),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) _lookUp(value.trim());
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () {
                      final value = _manualCodeController.text.trim();
                      if (value.isNotEmpty) _lookUp(value);
                    },
              child: const Text('Look up'),
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
