import 'dart:typed_data';
import 'dart:math';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'line_segmentation_service.dart';

/// Offline Handwriting Recognition Service using the Ruth ONNX model.
///
/// Model:  ruth_model.onnx
///   Input:  [batch, 32, 128, 3]  Float32 RGB (pixel values 0–255)
///   Output: [batch, T, 75]       CTC logits  (74 vocab chars + blank@74)
///   Vocab:  74 characters from IAM handwriting dataset (letters, digits, punct.)
///
/// Pipeline per scanned page:
///   1. Segment full page into horizontal text rows (15% ascender/descender padding).
///   2. Feed left ~45% NAME sub-crop through ONNX CRNN → CTC decode → name string.
///   3. Feed right ~55% PHONE sub-crop through ONNX → digit regex → phone string.
///   4. Return structured List<{name, phone}>.
class OfflineCRNNService {
  static OrtSession? _session;
  static bool _isInitialized = false;

  // Vocabulary from ruth configs.yaml (74 chars; CTC blank = index 74)
  static const String _vocab =
      "z9k5ijq.E0TPr,LcfDyumotYKO-QJ;d:Bn?b8lNWHI4s6'g7U!1A3)pweV#MRF\"GZvax&h(S2C";
  static const int _blankIdx = 74;

  // ─── Initialisation ────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_isInitialized && _session != null) return;
    final ort = OnnxRuntime();
    _session = await ort.createSessionFromAsset(
      'assets/models/ruth_model.onnx',
      options: OrtSessionOptions(intraOpNumThreads: 4),
    );
    _isInitialized = true;
  }

  // ─── Main entry point ──────────────────────────────────────────────────────

  /// Extracts contacts from a full-page document image path.
  static Future<List<Map<String, String>>> extractAndParseContacts(
      String imagePath) async {
    await initialize();
    final lines = await LineSegmentationService.segmentDocumentLines(imagePath);
    if (lines.isEmpty) return [];
    return processPageLines(lines);
  }

  /// Processes pre-segmented line crops into contact entries.
  static Future<List<Map<String, String>>> processPageLines(
      List<LineCropData> lines) async {
    await initialize();
    final contacts = <Map<String, String>>[];

    for (final line in lines) {
      final raw = line.rawRgbBytes;
      final w = line.rawWidth;
      final h = line.rawHeight;

      // ── Find separator gap between name and phone regions ──
      final int splitX = _findSplitX(raw, w, h);

      // ── Name crop: columns 0 → splitX ──
      final nameCrop = _extractCrop(raw, w, h, 0, splitX);
      final nameRaw = await _runOnnx(nameCrop, splitX, h);
      final cleanName = _cleanLetters(nameRaw);

      // ── Phone crop: columns splitX → w ──
      final int phoneStart = max(0, splitX - 4);
      final phoneW = w - phoneStart;
      String cleanPhone = '';
      if (phoneW > 10) {
        final phoneCrop = _extractCrop(raw, w, h, phoneStart, w);
        final phoneRaw = await _runOnnx(phoneCrop, phoneW, h);
        // Extract digit runs from decoded text
        final m = RegExp(r'\d{4,}').firstMatch(phoneRaw);
        if (m != null) cleanPhone = m.group(0)!;
      }

      if (cleanName.isNotEmpty || cleanPhone.isNotEmpty) {
        contacts.add({'name': cleanName, 'phone': cleanPhone});
      }
    }
    return contacts;
  }

  // ─── Crop helpers ──────────────────────────────────────────────────────────

  /// Finds the best split x-coordinate (lowest ink density in middle 25–70%).
  static int _findSplitX(Uint8List rgb, int w, int h) {
    final colInk = List<int>.filled(w, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final off = (y * w + x) * 3;
        if (off + 2 < rgb.length) {
          final lum = (0.299 * rgb[off] + 0.587 * rgb[off + 1] + 0.114 * rgb[off + 2]).round();
          if (lum < 185) colInk[x]++;
        }
      }
    }
    int bestX = (w * 0.45).round();
    int minInk = 9999999;
    final s = (w * 0.25).round();
    final e = (w * 0.70).round();
    for (int x = s; x < e; x++) {
      int win = 0;
      for (int dx = -3; dx <= 3; dx++) win += colInk[(x + dx).clamp(0, w - 1)];
      if (win < minInk) { minInk = win; bestX = x; }
    }
    return bestX;
  }

  /// Extracts columns [x0, x1) from a flat H×W×3 RGB buffer.
  static Uint8List _extractCrop(Uint8List src, int w, int h, int x0, int x1) {
    final cw = max(1, x1 - x0);
    final out = Uint8List(h * cw * 3)..fillRange(0, h * cw * 3, 255);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < cw; x++) {
        final si = (y * w + (x0 + x)) * 3;
        final di = (y * cw + x) * 3;
        if (si + 2 < src.length) {
          out[di] = src[si]; out[di + 1] = src[si + 1]; out[di + 2] = src[si + 2];
        }
      }
    }
    return out;
  }

  // ─── ONNX Inference ────────────────────────────────────────────────────────

  /// Resizes srcRgb (srcH × srcW × 3) to [1, 32, 128, 3], runs ONNX, CTC-decodes.
  static Future<String> _runOnnx(Uint8List srcRgb, int srcW, int srcH) async {
    const int tH = 32, tW = 128;

    // Build Float32List input tensor [1 * 32 * 128 * 3]
    final input = Float32List(tH * tW * 3);
    for (int y = 0; y < tH; y++) {
      for (int x = 0; x < tW; x++) {
        final sx = ((x / tW) * srcW).floor().clamp(0, srcW - 1);
        final sy = ((y / tH) * srcH).floor().clamp(0, srcH - 1);
        final si = (sy * srcW + sx) * 3;
        final di = (y * tW + x) * 3;
        if (si + 2 < srcRgb.length) {
          input[di]     = srcRgb[si].toDouble();
          input[di + 1] = srcRgb[si + 1].toDouble();
          input[di + 2] = srcRgb[si + 2].toDouble();
        } else {
          input[di] = input[di + 1] = input[di + 2] = 255.0;
        }
      }
    }

    // Determine input name from session (the Ruth ONNX model uses "input")
    final inputName = _session!.inputNames.isNotEmpty
        ? _session!.inputNames.first
        : 'input';

    final inputOrt = await OrtValue.fromList(input, [1, tH, tW, 3]);
    final outputs = await _session!.run({inputName: inputOrt});

    // Output shape: [1, T, 75]
    final outOrt = outputs.values.first;
    final raw = await outOrt.asList() as List<dynamic>;
    final batchOut = raw[0] as List<dynamic>; // [T, 75]
    final T = batchOut.length;

    // CTC greedy decode
    final sb = StringBuffer();
    int prev = -1;
    for (int t = 0; t < T; t++) {
      final step = batchOut[t] as List<dynamic>;
      int best = 0; double bestV = (step[0] as num).toDouble();
      for (int c = 1; c < step.length; c++) {
        final v = (step[c] as num).toDouble();
        if (v > bestV) { bestV = v; best = c; }
      }
      if (best != _blankIdx && best != prev && best < _vocab.length) {
        sb.write(_vocab[best]);
      }
      prev = best;
    }

    await inputOrt.dispose();
    await outOrt.dispose();
    return sb.toString();
  }

  // ─── Text cleanup ──────────────────────────────────────────────────────────

  static String _cleanLetters(String raw) =>
      raw.replaceAll(RegExp(r"[^a-zA-Z '\-]"), ' ')
         .replaceAll(RegExp(r'\s+'), ' ')
         .trim();

  // ─── Legacy parser (kept for compatibility) ────────────────────────────────

  static List<Map<String, String>> parseContactsFromTranscriptions(
      List<String> lines) {
    final contacts = <Map<String, String>>[];
    String pendingName = '', pendingPhone = '';
    final phoneRx = RegExp(r'(\+?[0-9][0-9\s\-]{6,14}[0-9])');

    for (final line in lines) {
      final m = phoneRx.firstMatch(line);
      if (m != null) {
        final rawPhone = m.group(0)!;
        final phone = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
        String name = line.replaceFirst(rawPhone, '')
            .replaceAll(RegExp(r'^[\s\-\:\;\.\,\|]+|[\s\-\:\;\.\,\|]+$'), '')
            .trim();
        if (name.isEmpty) {
          if (pendingName.isNotEmpty) { contacts.add({'name': pendingName, 'phone': phone}); pendingName = ''; }
          else { pendingPhone = phone; }
        } else {
          if (pendingName.isNotEmpty) { contacts.add({'name': pendingName, 'phone': ''}); pendingName = ''; }
          contacts.add({'name': name, 'phone': phone});
        }
      } else {
        final name = line.replaceAll(RegExp(r'^[\s\-\:\;\.\,\|]+|[\s\-\:\;\.\,\|]+$'), '').trim();
        if (name.isNotEmpty) {
          if (pendingPhone.isNotEmpty) { contacts.add({'name': name, 'phone': pendingPhone}); pendingPhone = ''; }
          else if (pendingName.isNotEmpty) { contacts.add({'name': pendingName, 'phone': ''}); pendingName = name; }
          else { pendingName = name; }
        }
      }
    }

    if (pendingName.isNotEmpty && pendingPhone.isNotEmpty) contacts.add({'name': pendingName, 'phone': pendingPhone});
    else if (pendingName.isNotEmpty) contacts.add({'name': pendingName, 'phone': ''});
    else if (pendingPhone.isNotEmpty) contacts.add({'name': 'Unknown', 'phone': pendingPhone});

    return contacts;
  }

  // ─── Disposal ──────────────────────────────────────────────────────────────

  static Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _isInitialized = false;
  }
}
