import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Runs OCR entirely in the browser via tesseract.js (loaded as a <script>
/// tag in web/index.html — see setup note below), rather than server-side.
///
/// Why client-side: Vercel's serverless bundling is known to break
/// tesseract.js's Node worker-script resolution (several open GitHub
/// issues on exactly this) — running it in the browser instead sidesteps
/// that entirely, needs no new backend hosting, and works independent of
/// the Oracle VM.
///
/// SETUP REQUIRED — add this inside <head> in web/index.html, before the
/// Flutter bootstrap script:
///   <script src="https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/tesseract.min.js"></script>
///
/// WEB-ONLY: this file only compiles for the web target (dart:js_interop).
/// If PantryBuddy ever ships on mobile, this needs a conditional
/// import/platform check — not an issue today since only web is deployed.
@JS('Tesseract.recognize')
external JSPromise<JSAny?> _tesseractRecognize(JSString image, JSString lang);

class BrowserOcrException implements Exception {
  BrowserOcrException(this.message);
  final String message;
  @override
  String toString() => message;
}

class BrowserOcrService {
  /// [imageBytes] — raw image bytes (e.g. from image_picker). Returns the
  /// raw extracted text — never trust this as structured data directly,
  /// it's messy real-world OCR output that still needs parsing.
  static Future<String> recognizeText(List<int> imageBytes) async {
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(imageBytes)}';

    final JSAny? result;
    try {
      result = await _tesseractRecognize(dataUrl.toJS, 'eng'.toJS).toDart;
    } catch (e) {
      throw BrowserOcrException('OCR failed to run: $e. Check that the tesseract.js <script> tag is present in web/index.html.');
    }

    if (result == null) {
      throw BrowserOcrException('OCR returned no result.');
    }
    final data = (result as JSObject).getProperty('data'.toJS);
    if (data == null) {
      throw BrowserOcrException('Unexpected OCR response shape (no "data" field).');
    }
    final text = (data as JSObject).getProperty('text'.toJS);
    if (text == null) {
      throw BrowserOcrException('Unexpected OCR response shape (no "text" field).');
    }
    return (text as JSString).toDart;
  }

}
