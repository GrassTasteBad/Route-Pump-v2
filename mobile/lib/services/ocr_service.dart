import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Result from an OCR scan of a price board image.
class OcrScanResult {
  /// All prices detected (pesos), e.g. [75.00, 80.00, 72.00]
  final List<double> detectedPrices;

  /// The primary/first price detected (most prominent)
  final double? primaryPrice;

  /// Raw text blocks extracted from the image
  final String rawText;

  /// Whether any prices were successfully extracted
  bool get hasPrice => detectedPrices.isNotEmpty;

  const OcrScanResult({
    required this.detectedPrices,
    required this.primaryPrice,
    required this.rawText,
  });
}

class OcrService {
  static final OcrService _instance = OcrService._internal();
  factory OcrService() => _instance;
  OcrService._internal();

  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Scans an image file and extracts all fuel prices found on the board.
  Future<OcrScanResult> scanPriceBoard(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final RecognizedText recognizedText =
        await _textRecognizer.processImage(inputImage);

    final rawText = recognizedText.text;
    final prices = _extractPrices(rawText);

    return OcrScanResult(
      detectedPrices: prices,
      primaryPrice: prices.isNotEmpty ? prices.first : null,
      rawText: rawText,
    );
  }

  /// Parses a raw OCR text block and extracts numbers that look like fuel prices.
  /// Fuel prices in the Philippines typically range from ₱50 to ₱150 per litre.
  List<double> _extractPrices(String text) {
    final List<double> prices = [];

    // Match patterns like:
    //  75.00  |  75  |  ₱75.00  |  P75.00  |  Php 75  |  75.5
    final pricePattern = RegExp(
      r'(?:₱|P|Php\.?\s*)?(\d{2,3}(?:\.\d{1,2})?)',
      caseSensitive: false,
    );

    final matches = pricePattern.allMatches(text);
    for (final match in matches) {
      final raw = match.group(1);
      if (raw == null) continue;
      final value = double.tryParse(raw);
      if (value == null) continue;
      // Only accept values in a realistic fuel price range (₱30–₱200)
      if (value >= 30.0 && value <= 200.0) {
        if (!prices.contains(value)) prices.add(value);
      }
    }

    // Sort ascending so the cheapest (likely regular unleaded) is first
    prices.sort();
    return prices;
  }

  void dispose() {
    _textRecognizer.close();
  }
}
