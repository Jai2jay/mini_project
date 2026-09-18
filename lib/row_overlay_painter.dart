import 'package:flutter/material.dart';
import 'row_segmentation_service.dart';

/// CustomPainter that renders live per-row bounding box overlays
/// (replacing the document-level single polygon outline).
class RowOverlayPainter extends CustomPainter {
  final List<RowCropData> detectedRows;
  final int? selectedRowIndex;
  final Animation<double>? scanAnimation;

  RowOverlayPainter({
    required this.detectedRows,
    this.selectedRowIndex,
    this.scanAnimation,
  }) : super(repaint: scanAnimation);

  @override
  void paint(Canvas canvas, Size size) {
    if (detectedRows.isEmpty) return;

    final boxPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final cornerPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = const Color(0x1A00E5FF)
      ..style = PaintingStyle.fill;

    final selectedPaint = Paint()
      ..color = const Color(0xFFFFD700)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    for (final row in detectedRows) {
      final norm = row.normalizedRect;
      final Rect rect = Rect.fromLTWH(
        norm.left * size.width,
        norm.top * size.height,
        norm.width * size.width,
        norm.height * size.height,
      );

      final isSelected = selectedRowIndex == row.rowIndex;

      // 1. Subtle translucent fill
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        fillPaint,
      );

      // 2. Base bounding box
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        isSelected ? selectedPaint : boxPaint,
      );

      // 3. High-contrast corner brackets (top-left, top-right, bottom-left, bottom-right)
      final double cornerLen = (rect.height * 0.35).clamp(8.0, 24.0);

      // Top-Left
      canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left + cornerLen, rect.top), cornerPaint);
      canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left, rect.top + cornerLen), cornerPaint);

      // Top-Right
      canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right - cornerLen, rect.top), cornerPaint);
      canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right, rect.top + cornerLen), cornerPaint);

      // Bottom-Left
      canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left + cornerLen, rect.bottom), cornerPaint);
      canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left, rect.bottom - cornerLen), cornerPaint);

      // Bottom-Right
      canvas.drawLine(Offset(rect.right, rect.bottom), Offset(rect.right - cornerLen, rect.bottom), cornerPaint);
      canvas.drawLine(Offset(rect.right, rect.bottom), Offset(rect.right, rect.bottom - cornerLen), cornerPaint);

      // 4. "Row X" Tag Pill
      final tagText = 'Row ${row.rowIndex}';
      final textSpan = TextSpan(
        text: tagText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final tagWidth = textPainter.width + 12;
      final tagHeight = textPainter.height + 6;
      final tagRect = Rect.fromLTWH(
        rect.left + 2,
        (rect.top - tagHeight - 2).clamp(0.0, size.height - tagHeight),
        tagWidth,
        tagHeight,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(tagRect, const Radius.circular(4)),
        Paint()..color = const Color(0xDD00838F),
      );

      textPainter.paint(
        canvas,
        Offset(tagRect.left + 6, tagRect.top + 3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant RowOverlayPainter oldDelegate) {
    return oldDelegate.detectedRows != detectedRows ||
        oldDelegate.selectedRowIndex != selectedRowIndex;
  }
}
