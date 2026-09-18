import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import 'main.dart';        // For the global `cameras` list
import 'review_screen.dart';
import 'document_crop_service.dart';
import 'contact_review_screen.dart';

/// Displays a full-screen camera preview with two capture options:
///
/// 1. **Shutter button** (bottom center) — Quick capture without edge detection.
///    Takes a photo and navigates directly to ReviewScreen.
/// 2. **"Scan Document" button** (bottom left) — Opens the native document scanner
///    with automatic edge detection, corner adjustment, and perspective correction.
///    Returns a cropped, flattened document image to ReviewScreen.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;

  /// True while a picture is being taken, to prevent double-taps.
  bool _isCapturing = false;

  /// True while the document scanner is active.
  bool _isScanning = false;

  /// Control banner visibility.
  bool _showBanner = true;
  Timer? _bannerTimer;

  /// Torch status.
  bool _isTorchOn = false;

  /// Error message if camera initialization fails.
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Observe app lifecycle to handle camera when app is backgrounded.
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();

    _bannerTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showBanner = false;
        });
      }
    });
  }

  Future<void> _initializeCamera() async {
    try {
      // 1. Dispose any existing _controller before creating a new one:
      if (_controller != null) {
        await _controller!.dispose();
        _controller = null;
      }

      // 2. Re-fetch available cameras:
      cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('No cameras available on this device.');
      }

      // Prefer the rear-facing (back) camera for document scanning.
      CameraDescription selectedCamera = cameras.first;
      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selectedCamera = camera;
          break;
        }
      }

      // 3. Create a brand new CameraController instance every time initState runs
      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.max,
        enableAudio: false, // No audio needed for photo capture.
      );

      _controller = controller;

      // 4. Call await _controller!.initialize()
      await controller.initialize();

      // 5. Only call setState(() {}) AFTER initialization is confirmed complete
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _toggleTorch() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      if (_isTorchOn) {
        await _controller!.setFlashMode(FlashMode.off);
      } else {
        await _controller!.setFlashMode(FlashMode.torch);
      }
      if (mounted) {
        setState(() {
          _isTorchOn = !_isTorchOn;
        });
      }
    } catch (e) {
      debugPrint('Failed to set flash mode: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't interact with the camera if it isn't initialized.
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      // Release the camera when the app goes inactive.
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      // Re-initialize the camera when the app comes back.
      _initializeCamera();
    }
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_controller != null) {
      _controller!.dispose();
      _controller = null;
    }
    super.dispose();
  }

  /// Takes a picture and navigates to the review screen (quick capture).
  Future<void> _captureImage() async {
    if (_isCapturing || _isScanning) return; // Guard against double-taps.

    if (mounted) {
      setState(() => _isCapturing = true);
    }

    try {
      // Ensure the camera is fully initialized before taking a picture.
      if (_controller == null || !_controller!.value.isInitialized) {
        throw Exception('Camera is not initialized');
      }

      // Capture the image and get the file reference.
      final XFile imageFile = await _controller!.takePicture();

      if (!mounted) return;

      // Navigate to the review screen with the captured image path.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ReviewScreen(imagePath: imageFile.path),
        ),
      );
    } catch (e) {
      // Show a snackbar with the error if capture fails.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error capturing image: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  /// Launches the native document scanner with edge detection and crop.
  Future<void> _scanDocument() async {
    if (_isCapturing || _isScanning) return; // Guard against double-taps.

    if (mounted) {
      setState(() => _isScanning = true);
    }

    try {
      // Launch the native document scanner (edge detection + corner adjustment).
      final croppedFile = await DocumentCropService.scanAndCropDocument();

      if (!mounted) return;

      // User cancelled the scanner.
      if (croppedFile == null) {
        return;
      }

      // Navigate to the review screen with the cropped document image.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ReviewScreen(imagePath: croppedFile.path),
        ),
      );
    } catch (e) {
      // Show a user-facing error if scanning fails.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.red[700],
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'Failed to initialize camera:\n$_errorMessage',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : (_controller != null && _controller!.value.isInitialized)
              ? _buildCameraPreview()
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
      // Bottom action bar with two buttons: Scan Document and Quick Capture.
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // "Scan Document" button — opens native scanner with edge detection.
              _buildActionButton(
                icon: _isScanning
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.document_scanner, size: 28),
                label: _isScanning ? 'Scanning...' : 'Scan Doc',
                onTap: _scanDocument,
                isActive: !_isCapturing && !_isScanning,
              ),
              // Shutter button — quick capture (existing Phase 1 behavior).
              GestureDetector(
                onTap: (_isCapturing || _isScanning) ? null : _captureImage,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.white30, width: 4),
                  ),
                  child: Center(
                    child: _isCapturing
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.camera_alt,
                            size: 32, color: Colors.black),
                  ),
                ),
              ),
              // Contacts review button
              _buildActionButton(
                icon: const Icon(Icons.contacts, size: 28),
                label: 'Contacts',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const ContactReviewScreen(
                        parsedContacts: [],
                      ),
                    ),
                  );
                },
                isActive: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a small labeled action button for the bottom bar.
  Widget _buildActionButton({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
    required bool isActive,
  }) {
    return GestureDetector(
      onTap: isActive ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isActive ? 1.0 : 0.4,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.15),
                border: Border.all(color: Colors.white30, width: 1.5),
              ),
              child: Center(
                child: IconTheme(
                  data: const IconThemeData(color: Colors.white),
                  child: icon,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a full-screen camera preview that fills the available space.
  Widget _buildCameraPreview() {
    final previewSize = _controller!.value.previewSize!;

    // previewSize is in landscape orientation (width > height), so we swap.

    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: previewSize.height,
                  height: previewSize.width,
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: CameraPreview(_controller!),
                  ),
                ),
              ),
            ),
          ),
        ),
        // App logo & title badge (top left)
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 22,
                    height: 22,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.contacts, size: 20, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'ContactScanner',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Torch toggle button (top right corner)
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                _isTorchOn ? Icons.flash_on : Icons.flash_off,
                color: _isTorchOn ? Colors.yellow : Colors.white,
              ),
              onPressed: _toggleTorch,
              tooltip: 'Toggle Flashlight',
            ),
          ),
        ),
        // Instruction banner (bottom center, above bottom bar)
        if (_showBanner)
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: AnimatedOpacity(
              opacity: _showBanner ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Place the paper flat. Ensure all edges are visible.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
