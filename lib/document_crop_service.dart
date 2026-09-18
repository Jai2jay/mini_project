import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Service responsible for launching the native document scanner and
/// returning the cropped document image.
///
/// Uses [CunningDocumentScanner] which provides:
///   - Native camera UI with real-time edge detection
///   - User-adjustable corner points for manual correction
///   - Automatic perspective correction (flattens skewed documents)
///
/// This service is completely separate from [PreprocessingService] —
/// it handles only the capture-and-crop step.
class DocumentCropService {
  /// Launches the native document scanner and returns the cropped image.
  ///
  /// Opens the platform's native document scanning UI (Google ML Kit on
  /// Android, Apple VisionKit on iOS). The user captures the document
  /// through the scanner's camera, which automatically detects the paper
  /// edges and allows corner adjustment.
  ///
  /// Returns a [File] containing the cropped, perspective-corrected image,
  /// or `null` if the user cancelled the scanner.
  ///
  /// Throws an [Exception] if the scanning process fails.
  static Future<File?> scanAndCropDocument() async {
    try {
      // Launch the native document scanner.
      // noOfPages: 1 limits scanning to a single page.
      // isGalleryImportAllowed: true lets users pick from gallery on Android.
      final List<String>? scannedPages =
          await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        isGalleryImportAllowed: true,
      );

      // User cancelled the scanner — return null.
      if (scannedPages == null || scannedPages.isEmpty) {
        return null;
      }

      // Take the first (and only) scanned page.
      final String scannedPath = scannedPages.first;
      final File scannedFile = File(scannedPath);

      // Verify the scanned file exists.
      if (!await scannedFile.exists()) {
        throw Exception(
          'Scanned document file not found at: $scannedPath',
        );
      }

      // Copy to temp directory with a distinct filename so it doesn't
      // overwrite the raw capture or other intermediate files.
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = p.join(tempDir.path, 'cropped_doc_$timestamp.jpg');
      final outputFile = await scannedFile.copy(outputPath);

      return outputFile;
    } catch (e) {
      // Re-throw with a descriptive message for the UI layer.
      throw Exception(
        'Document scanning failed: $e. '
        'Try better lighting or a higher contrast background.',
      );
    }
  }
}
