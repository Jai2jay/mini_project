import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Holds a segmented line crop with its raw RGB pixel data for ONNX inference.
class LineCropData {
  final int lineIndex;
  final int topY;
  final int bottomY;
  final int leftX;
  final int rightX;

  /// Raw RGB bytes of the line crop resized to rawHeight x rawWidth x 3.
  /// Used by OfflineCRNNService to build ONNX input tensors.
  final Uint8List rawRgbBytes;
  final int rawWidth;
  final int rawHeight;

  LineCropData({
    required this.lineIndex,
    required this.topY,
    required this.bottomY,
    required this.leftX,
    required this.rightX,
    required this.rawRgbBytes,
    required this.rawWidth,
    required this.rawHeight,
  });
}

/// Segments a document image into horizontal text line crops with
/// 15% ascender/descender padding.  Each crop is stored as a raw
/// 32-pixel-tall RGB byte buffer ready for ONNX [1, 32, W, 3] inference.
class LineSegmentationService {
  static Future<List<LineCropData>> segmentDocumentLines(
      String imagePath) async {
    final file = File(imagePath);
    if (!file.existsSync()) {
      throw Exception('Image file not found at: $imagePath');
    }
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Failed to decode image from: $imagePath');
    }
    return segmentLinesFromImage(image);
  }

  static List<LineCropData> segmentLinesFromImage(img.Image image) {
    final int width = image.width;
    final int height = image.height;

    // ── 1. Build horizontal ink projection profile ──────────────────────────
    final List<int> hProj = List.filled(height, 0);
    // We only need grayscale per row for the projection, so keep it simple
    for (int y = 0; y < height; y++) {
      int ink = 0;
      for (int x = 0; x < width; x++) {
        final pixel = image.getPixel(x, y);
        final int lum =
            (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
        if (lum < 185) ink++;
      }
      hProj[y] = ink;
    }

    // ── 2. Detect raw line bands ──────────────────────────────────────────
    final int minInk = max(5, (width * 0.004).round());
    final int minLineH = max(20, (height * 0.012).round());

    final List<List<int>> rawLines = [];
    bool inLine = false;
    int startY = 0;
    for (int y = 0; y < height; y++) {
      if (hProj[y] >= minInk && !inLine) {
        inLine = true;
        startY = y;
      } else if (hProj[y] < minInk && inLine) {
        inLine = false;
        if (y - startY >= minLineH) rawLines.add([startY, y]);
      }
    }
    if (inLine && height - startY >= minLineH) rawLines.add([startY, height]);

    // ── 3. Merge close lines ─────────────────────────────────────────────
    final int mergeGap = max(10, (height * 0.015).round());
    final List<List<int>> merged = [];
    for (final l in rawLines) {
      if (merged.isEmpty || l[0] - merged.last[1] > mergeGap) {
        merged.add(l);
      } else {
        merged.last[1] = l[1];
      }
    }
    if (merged.isEmpty) merged.add([0, height]);

    // ── 4. Crop, pad, resize and build raw RGB buffers ───────────────────
    final List<LineCropData> result = [];
    for (int i = 0; i < merged.length; i++) {
      final int rawY1 = merged[i][0];
      final int rawY2 = merged[i][1];
      final int lineH = rawY2 - rawY1;

      // 15% vertical padding for ascenders / descenders
      final int vPad = (lineH * 0.15).round();
      final int y1 = max(0, rawY1 - vPad);
      final int y2 = min(height, rawY2 + vPad);

      // Find horizontal ink extent
      int minX = width, maxX = 0;
      for (int y = y1; y < y2; y++) {
        for (int x = 0; x < width; x++) {
          final pixel = image.getPixel(x, y);
          final int lum =
              (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
          if (lum < 185) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
          }
        }
      }
      if (maxX <= minX) {
        minX = 0;
        maxX = width - 1;
      } else {
        final int hPad = max(8, (width * 0.02).round());
        minX = max(0, minX - hPad);
        maxX = min(width - 1, maxX + hPad);
      }

      final int cropW = maxX - minX + 1;
      final int cropH = y2 - y1;
      if (cropW <= 0 || cropH <= 0) continue;

      // Crop the line from the original image
      final img.Image lineCrop = img.copyCrop(
        image,
        x: minX,
        y: y1,
        width: cropW,
        height: cropH,
      );

      // Resize to 32 px tall, preserving aspect ratio (cap width at 512)
      final double scale = 32.0 / lineCrop.height;
      final int newW = min((lineCrop.width * scale).round(), 512);
      final img.Image resized = img.copyResize(
        lineCrop,
        width: newW,
        height: 32,
        interpolation: img.Interpolation.linear,
      );

      // Store as compact RGB byte buffer [32 x newW x 3]
      final Uint8List rgb = Uint8List(32 * newW * 3);
      for (int y = 0; y < 32; y++) {
        for (int x = 0; x < newW; x++) {
          final pixel = resized.getPixel(x, y);
          final int off = (y * newW + x) * 3;
          rgb[off] = pixel.r.round();
          rgb[off + 1] = pixel.g.round();
          rgb[off + 2] = pixel.b.round();
        }
      }

      result.add(LineCropData(
        lineIndex: i,
        topY: y1,
        bottomY: y2,
        leftX: minX,
        rightX: maxX,
        rawRgbBytes: rgb,
        rawWidth: newW,
        rawHeight: 32,
      ));
    }

    return result;
  }
}
