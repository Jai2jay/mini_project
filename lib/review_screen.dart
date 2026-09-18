import 'dart:io';
import 'package:flutter/material.dart';

import 'row_segmentation_service.dart';
import 'row_overlay_painter.dart';
import 'processed_image_screen.dart';
import 'preprocessing_service.dart';
import 'loading_spinner.dart';

/// Displays the captured document with Line-Item Auto-Crop bounding boxes
/// drawn around each individual handwritten "Name - Contact Number" row.
class ReviewScreen extends StatefulWidget {
  final String imagePath;

  const ReviewScreen({super.key, required this.imagePath});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen>
    with SingleTickerProviderStateMixin {
  bool _isProcessing = false;
  bool _isDetectingRows = true;
  List<RowCropData> _detectedRows = [];
  int? _selectedRowIndex;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _detectLineRows();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _detectLineRows() async {
    setState(() => _isDetectingRows = true);
    try {
      final rows = await RowSegmentationService.segmentAndCropRows(
        widget.imagePath,
        paddingMargin: 10,
      );
      if (mounted) {
        setState(() {
          _detectedRows = rows;
          _isDetectingRows = false;
        });
      }
    } catch (e) {
      debugPrint('Row detection error: $e');
      if (mounted) {
        setState(() => _isDetectingRows = false);
      }
    }
  }

  Future<void> _processImage() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final processedFile = await PreprocessingService.processImage(
        widget.imagePath,
      );

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ProcessedImageScreen(
            processedImagePath: processedFile.path,
            rawImagePath: widget.imagePath,
            rowCrops: _detectedRows,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image processing failed: $e'),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          _detectedRows.isNotEmpty
              ? '${_detectedRows.length} Line Rows Detected'
              : 'Detecting Rows...',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retake photo',
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-detect rows',
            onPressed: _detectLineRows,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Image with Line-Item Auto-Crop Bounding Box Overlay
          Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(widget.imagePath),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                            );
                          },
                        ),
                        // Live Bounding Box Overlay for each row
                        CustomPaint(
                          painter: RowOverlayPainter(
                            detectedRows: _detectedRows,
                            selectedRowIndex: _selectedRowIndex,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          // Top Chip indicator
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xDD004D40),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.crop, color: Color(0xFF00E5FF), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    _isDetectingRows
                        ? 'Scanning rows...'
                        : '${_detectedRows.length} Line-Item Crops Ready',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isProcessing)
            const RotatingLoader(message: 'Preparing line crops for OCR...'),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Retake'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _processImage,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.arrow_forward),
                  label: Text(_isProcessing ? 'Processing...' : 'Continue to OCR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00838F),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
