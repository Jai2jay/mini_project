import 'dart:typed_data';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Represents a single cropped handwritten row and its spatial metadata.
class RowCropData {
  final int rowIndex;
  final String imagePath;
  final Rect absoluteRect; // Pixel coordinates relative to original image
  final Rect normalizedRect; // Normalized [0.0 .. 1.0] coordinates for UI rendering
  final int originalWidth;
  final int originalHeight;

  RowCropData({
    required this.rowIndex,
    required this.imagePath,
    required this.absoluteRect,
    required this.normalizedRect,
    required this.originalWidth,
    required this.originalHeight,
  });

  Map<String, dynamic> toJson() => {
    'rowIndex': rowIndex,
    'imagePath': imagePath,
    'boundingBox': {
      'left': absoluteRect.left,
      'top': absoluteRect.top,
      'width': absoluteRect.width,
      'height': absoluteRect.height,
    },
    'normalizedBox': {
      'left': normalizedRect.left,
      'top': normalizedRect.top,
      'width': normalizedRect.width,
      'height': normalizedRect.height,
    },
  };
}

/// Robust Row-Level Text Line Segmentation Service.
/// Slices full-size scanned documents into individual row crops with 5-10px padding.
class RowSegmentationService {
  /// Segments an image file into individual row crops.
  /// Saves crops as 'row_1.jpg', 'row_2.jpg' in temporary directory.
  static Future<List<RowCropData>> segmentAndCropRows(
    String imagePath, {
    int paddingMargin = 10,
  }) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      throw Exception('Image not found at $imagePath');
    }

    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Failed to decode image from $imagePath');
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    return segmentAndCropRowsFromImage(
      image,
      outputDir: tempDir.path,
      sessionTimestamp: timestamp,
      paddingMargin: paddingMargin,
    );
  }

  /// Performs row segmentation directly on an [img.Image] and saves crops to [outputDir].
  static List<RowCropData> segmentAndCropRowsFromImage(
    img.Image image, {
    required String outputDir,
    required int sessionTimestamp,
    int paddingMargin = 10,
  }) {
    final int width = image.width;
    final int height = image.height;

    // 1. Convert to grayscale luminance rows and compute horizontal projection profile
    final List<int> projection = List.filled(height, 0);
    final List<Uint8List> grayRows = List.generate(height, (_) => Uint8List(width));

    for (int y = 0; y < height; y++) {
      int inkCount = 0;
      for (int x = 0; x < width; x++) {
        final p = image.getPixel(x, y);
        final int lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
        grayRows[y][x] = lum;
        if (lum < 185) {
          inkCount++;
        }
      }
      projection[y] = inkCount;
    }

    // 2. Identify continuous text row spans
    final int minInkThreshold = max(6, (width * 0.004).round());
    final int minLineHeight = max(24, (height * 0.012).round());

    final List<List<int>> rawSpans = [];
    bool inSpan = false;
    int spanStartY = 0;

    for (int y = 0; y < height; y++) {
      final bool hasInk = projection[y] >= minInkThreshold;
      if (hasInk && !inSpan) {
        inSpan = true;
        spanStartY = y;
      } else if (!hasInk && inSpan) {
        inSpan = false;
        if ((y - spanStartY) >= minLineHeight) {
          rawSpans.add([spanStartY, y]);
        }
      }
    }
    if (inSpan && (height - spanStartY) >= minLineHeight) {
      rawSpans.add([spanStartY, height]);
    }

    // 3. Merge spans separated by small vertical gaps (< 1.8% of height)
    final int mergeGap = max(12, (height * 0.018).round());
    final List<List<int>> mergedSpans = [];

    for (final span in rawSpans) {
      if (mergedSpans.isEmpty) {
        mergedSpans.add(span);
      } else {
        final prev = mergedSpans.last;
        if (span[0] - prev[1] <= mergeGap) {
          prev[1] = span[1];
        } else {
          mergedSpans.add(span);
        }
      }
    }

    // Fallback: if no rows detected, return the entire document as a single row
    if (mergedSpans.isEmpty) {
      mergedSpans.add([0, height]);
    }

    // 4. Crop each row with configurable padding margin and save to disk
    final List<RowCropData> results = [];

    for (int i = 0; i < mergedSpans.length; i++) {
      final int rawY1 = mergedSpans[i][0];
      final int rawY2 = mergedSpans[i][1];
      final int rowH = rawY2 - rawY1;

      // 10-15% dynamic padding margin + fixed padding
      final int vPad = (rowH * 0.12).round() + paddingMargin;
      final int topY = max(0, rawY1 - vPad);
      final int bottomY = min(height, rawY2 + vPad);
      final int cropHeight = bottomY - topY;

      // Find horizontal boundaries within this line
      int minX = width;
      int maxX = 0;
      for (int y = topY; y < bottomY; y++) {
        for (int x = 0; x < width; x++) {
          if (grayRows[y][x] < 185) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
          }
        }
      }

      if (maxX <= minX) {
        minX = 0;
        maxX = width - 1;
      } else {
        final int hPad = max(12, (width * 0.02).round()) + paddingMargin;
        minX = max(0, minX - hPad);
        maxX = min(width - 1, maxX + hPad);
      }

      final int cropWidth = maxX - minX + 1;
      if (cropWidth <= 0 || cropHeight <= 0) continue;

      final img.Image croppedRow = img.copyCrop(
        image,
        x: minX,
        y: topY,
        width: cropWidth,
        height: cropHeight,
      );

      final String cropFileName = 'row_${i + 1}_$sessionTimestamp.jpg';
      final String cropPath = p.join(outputDir, cropFileName);
      final jpgBytes = img.encodeJpg(croppedRow, quality: 92);
      File(cropPath).writeAsBytesSync(jpgBytes);

      final absoluteRect = Rect.fromLTWH(
        minX.toDouble(),
        topY.toDouble(),
        cropWidth.toDouble(),
        cropHeight.toDouble(),
      );

      final normalizedRect = Rect.fromLTWH(
        minX / width,
        topY / height,
        cropWidth / width,
        cropHeight / height,
      );

      results.add(RowCropData(
        rowIndex: i + 1,
        imagePath: cropPath,
        absoluteRect: absoluteRect,
        normalizedRect: normalizedRect,
        originalWidth: width,
        originalHeight: height,
      ));
    }

    return results;
  }
}
