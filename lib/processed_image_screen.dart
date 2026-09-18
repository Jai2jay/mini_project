import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import 'row_segmentation_service.dart';
import 'row_overlay_painter.dart';
import 'offline_crnn_service.dart';
import 'vision_parser_service.dart';
import 'contact_review_screen.dart';
import 'loading_spinner.dart';

/// Screen displayed after document capture and line-item row segmentation.
/// Shows individual row crops (row_1.jpg, row_2.jpg, ...) and sends each
/// row crop individually into the ML model for structured parsing.
class ProcessedImageScreen extends StatefulWidget {
  final String processedImagePath;
  final String rawImagePath;
  final List<RowCropData>? rowCrops;

  const ProcessedImageScreen({
    super.key,
    required this.processedImagePath,
    required this.rawImagePath,
    this.rowCrops,
  });

  @override
  State<ProcessedImageScreen> createState() => _ProcessedImageScreenState();
}

class _ProcessedImageScreenState extends State<ProcessedImageScreen> {
  bool _isExtracting = false;
  bool _showOriginal = true;
  String _qualityStatus = 'Good Quality';
  
  bool _useOfflineCRNN = false; // Default to robust Vision parser or offline toggle

  late List<RowCropData> _rowCrops;
  int? _selectedCropIndex;

  @override
  void initState() {
    super.initState();
    _rowCrops = widget.rowCrops != null ? List.from(widget.rowCrops!) : [];
    if (_rowCrops.isEmpty) {
      _loadRowCrops();
    }
  }

  Future<void> _loadRowCrops() async {
    try {
      final imageToSegment = (widget.rawImagePath.isNotEmpty && File(widget.rawImagePath).existsSync())
          ? widget.rawImagePath
          : widget.processedImagePath;
      final crops = await RowSegmentationService.segmentAndCropRows(imageToSegment);
      if (mounted) {
        setState(() {
          _rowCrops = crops;
        });
      }
    } catch (e) {
      debugPrint('Error loading row crops: $e');
    }
  }

  Future<void> _extractAndParseContacts() async {
    if (_isExtracting) return;

    setState(() => _isExtracting = true);

    try {
      final imageToParse = (widget.rawImagePath.isNotEmpty && File(widget.rawImagePath).existsSync())
          ? widget.rawImagePath
          : widget.processedImagePath;

      List<Map<String, String>> contacts = [];

      if (_useOfflineCRNN) {
        // Run on-device CRNN model
        contacts = await OfflineCRNNService.extractAndParseContacts(imageToParse);
      } else {
        // Send row-segmented high-fidelity image to Vision Parser
        contacts = await VisionParserService.extractAndParseContacts(imageToParse);
      }

      if (!mounted) return;

      if (contacts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No contacts could be extracted from the detected rows.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ContactReviewScreen(
            parsedContacts: contacts,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Extraction error: $errorMsg',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _extractAndParseContacts,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExtracting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          _rowCrops.isNotEmpty
              ? '${_rowCrops.length} Row Crops Ready'
              : 'Line-Item Auto-Crop',
        ),
        automaticallyImplyLeading: false,
        actions: [
          // Engine Toggle Chip
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ActionChip(
              avatar: Icon(
                _useOfflineCRNN ? Icons.offline_bolt : Icons.cloud_done,
                color: Colors.white,
                size: 16,
              ),
              label: Text(
                _useOfflineCRNN ? 'Offline CRNN' : 'Cloud AI',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              backgroundColor: _useOfflineCRNN ? Colors.teal.shade800 : Colors.indigo.shade800,
              onPressed: () {
                setState(() => _useOfflineCRNN = !_useOfflineCRNN);
              },
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Top half: InteractiveViewer with per-row bounding box overlay
          Column(
            children: [
              Expanded(
                flex: 6,
                child: Center(
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
                                File(_showOriginal ? widget.rawImagePath : widget.processedImagePath),
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(
                                    child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
                                  );
                                },
                              ),
                              // Live cyan bounding box overlay for every row
                              CustomPaint(
                                painter: RowOverlayPainter(
                                  detectedRows: _rowCrops,
                                  selectedRowIndex: _selectedCropIndex,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              // Bottom half: Individual Row Crops Carousel (row_1.jpg, row_2.jpg, ...)
              Container(
                height: 120,
                color: const Color(0xFF1E1E2C),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'EXTRACTED ROW CROPS (${_rowCrops.length})',
                            style: const TextStyle(
                              color: Color(0xFF00E5FF),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const Text(
                            'Tap row to highlight',
                            style: TextStyle(color: Colors.white54, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _rowCrops.isEmpty
                          ? const Center(
                              child: Text(
                                'Detecting row strips...',
                                style: TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            )
                          : ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: _rowCrops.length,
                              itemBuilder: (context, index) {
                                final crop = _rowCrops[index];
                                final isSelected = _selectedCropIndex == crop.rowIndex;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedCropIndex = isSelected ? null : crop.rowIndex;
                                    });
                                  },
                                  child: Container(
                                    width: 140,
                                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFFFFD700)
                                            : const Color(0xFF00E5FF),
                                        width: isSelected ? 2.5 : 1.2,
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(7),
                                          child: Image.file(
                                            File(crop.imagePath),
                                            fit: BoxFit.contain,
                                            width: double.infinity,
                                            height: double.infinity,
                                          ),
                                        ),
                                        Positioned(
                                          top: 4,
                                          left: 4,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xDD00838F),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Row ${crop.rowIndex}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isExtracting)
            RotatingLoader(
              message: _useOfflineCRNN
                  ? 'Running On-Device Model on Row Crops...'
                  : 'Parsing ${ _rowCrops.length} Row Crops into Contacts...',
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isExtracting
                      ? null
                      : () {
                          Navigator.of(context).popUntil(
                            (route) => route.isFirst,
                          );
                        },
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
                  onPressed: _isExtracting ? null : _extractAndParseContacts,
                  icon: _isExtracting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isExtracting ? 'Parsing...' : 'Extract Contacts'),
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
