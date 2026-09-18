import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Service responsible for preprocessing captured images before OCR.
///
/// Runs a 4-step pipeline:
///   1. Grayscale conversion
///   2. Gaussian blur (noise reduction)
///   3. Adaptive thresholding (shadow/lighting normalization)
///   4. Mild dilation (thickens handwritten strokes)
///
/// All processing is done in pure Dart using the `image` package.
/// No processing logic should live in UI files — this service is the
/// single source of truth for image preprocessing.
class PreprocessingService {
  /// Processes the raw camera image and returns a cleaned File.
  ///
  /// [rawImagePath] is the absolute path to the captured image from the camera.
  /// Returns a [File] pointing to the processed image saved in the temp directory.
  /// Throws an [Exception] if any step in the pipeline fails.
  ///
  /// When [forOCR] is true, a lighter preprocessing pass is used:
  /// grayscale + mild contrast boost only, skipping adaptive threshold and
  /// dilation. This preserves thin handwriting strokes that ML Kit needs
  /// to detect character shapes. Set [forOCR] to false (default) for the
  /// full high-contrast "scanned" look used in the UI preview.
  static Future<File> processImage(
    String rawImagePath, {
    bool forOCR = false,
  }) async {
    // Load the raw image from disk.
    final rawBytes = await File(rawImagePath).readAsBytes();
    final decoded = img.decodeImage(rawBytes);

    if (decoded == null) {
      throw Exception('Failed to decode image at: $rawImagePath');
    }

    // Step 1: Convert to grayscale.
    // This simplifies the image to a single luminance channel,
    // which is required for thresholding and improves OCR accuracy.
    img.Image grayscaled = img.grayscale(decoded);

    // Step 2: Apply Gaussian blur (5x5 kernel) for noise reduction.
    // This smooths out camera noise and minor artifacts that could
    // interfere with the thresholding step.
    img.Image blurred = img.gaussianBlur(grayscaled, radius: 2);

    // The final image to save — depends on the forOCR flag.
    img.Image finalImage;

    if (forOCR) {
      // Lighter pass for OCR: skip threshold and dilation.
      // Apply a mild contrast boost instead to help ML Kit detect edges
      // without destroying thin handwriting strokes.
      finalImage = img.adjustColor(blurred, contrast: 1.3);
    } else {
      // Full pipeline for visual display (high-contrast scanned look).

      // Step 3: Apply adaptive thresholding.
      // Unlike global thresholding, adaptive thresholding calculates a
      // threshold for each pixel based on its local neighborhood, which
      // handles uneven lighting and shadows on the paper.
      img.Image thresholded = _adaptiveThreshold(
        blurred,
        blockSize: 11,
        c: 2,
      );

      // Step 4: Apply mild dilation (3x3 kernel).
      // This thickens thin handwritten strokes that may have been
      // thinned by the thresholding step, improving OCR readability.
      finalImage = _dilate(thresholded, kernelSize: 3);
    }

    // Save the processed image to the app's temporary directory.
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final suffix = forOCR ? 'ocr' : 'display';
    final outputPath = p.join(tempDir.path, 'processed_${suffix}_$timestamp.png');
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(img.encodePng(finalImage));

    return outputFile;
  }

  /// Applies adaptive Gaussian thresholding to a grayscale image.
  ///
  /// For each pixel, computes the mean luminance in a [blockSize] x [blockSize]
  /// neighborhood, then sets the pixel to white if its value is above
  /// (mean - [c]), or black otherwise.
  ///
  /// This is equivalent to OpenCV's ADAPTIVE_THRESH_GAUSSIAN_C method.
  static img.Image _adaptiveThreshold(
    img.Image src, {
    required int blockSize,
    required int c,
  }) {
    final width = src.width;
    final height = src.height;
    final halfBlock = blockSize ~/ 2;

    // Create an output image with the same dimensions.
    final output = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Compute the mean luminance of the local neighborhood.
        double sum = 0;
        int count = 0;

        for (int dy = -halfBlock; dy <= halfBlock; dy++) {
          for (int dx = -halfBlock; dx <= halfBlock; dx++) {
            final nx = (x + dx).clamp(0, width - 1);
            final ny = (y + dy).clamp(0, height - 1);
            final pixel = src.getPixel(nx, ny);
            // In a grayscale image, r == g == b, so just use r.
            sum += pixel.r.toDouble();
            count++;
          }
        }

        final mean = sum / count;
        final currentPixel = src.getPixel(x, y);
        final value = currentPixel.r.toDouble();

        // Threshold: if pixel value > (local mean - C), it's foreground (white).
        // For dark text on light paper, text pixels will be below the threshold.
        final outputPixel = output.getPixel(x, y);
        if (value > mean - c) {
          // Background — set to white.
          outputPixel.r = 255;
          outputPixel.g = 255;
          outputPixel.b = 255;
        } else {
          // Foreground (text) — set to black.
          outputPixel.r = 0;
          outputPixel.g = 0;
          outputPixel.b = 0;
        }
      }
    }

    return output;
  }

  /// Applies morphological dilation with a square kernel.
  ///
  /// For each pixel, if ANY neighbor within the [kernelSize] x [kernelSize]
  /// window is black (foreground/text), the output pixel is set to black.
  /// This thickens dark strokes, making handwriting more readable for OCR.
  static img.Image _dilate(img.Image src, {required int kernelSize}) {
    final width = src.width;
    final height = src.height;
    final halfKernel = kernelSize ~/ 2;

    final output = img.Image(width: width, height: height);

    // Initialize output to white.
    for (final pixel in output) {
      pixel.r = 255;
      pixel.g = 255;
      pixel.b = 255;
    }

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        bool hasBlackNeighbor = false;

        // Check the neighborhood for any black (foreground) pixel.
        for (int dy = -halfKernel; dy <= halfKernel && !hasBlackNeighbor; dy++) {
          for (int dx = -halfKernel; dx <= halfKernel && !hasBlackNeighbor; dx++) {
            final nx = (x + dx).clamp(0, width - 1);
            final ny = (y + dy).clamp(0, height - 1);
            final pixel = src.getPixel(nx, ny);

            // Black pixel = foreground (text stroke).
            if (pixel.r.toInt() == 0) {
              hasBlackNeighbor = true;
            }
          }
        }

        if (hasBlackNeighbor) {
          final outputPixel = output.getPixel(x, y);
          outputPixel.r = 0;
          outputPixel.g = 0;
          outputPixel.b = 0;
        }
      }
    }

    return output;
  }
}
