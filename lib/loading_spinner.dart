import 'package:flutter/material.dart';

/// A reusable full-screen loading overlay with a rotating icon and message.
///
/// Uses a continuously spinning sync icon driven by an [AnimationController]
/// with a semi-transparent black backdrop. Designed to be used as a blocking
/// overlay via a [Stack] whenever an async operation (OCR, AI parsing, etc.)
/// is in progress.
///
/// Usage:
/// ```dart
/// if (_isLoading)
///   RotatingLoader(message: 'Reading handwriting...'),
/// ```
class RotatingLoader extends StatefulWidget {
  /// The message to display below the spinning icon.
  final String message;

  const RotatingLoader({super.key, required this.message});

  @override
  State<RotatingLoader> createState() => _RotatingLoaderState();
}

class _RotatingLoaderState extends State<RotatingLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(); // Continuously rotate.
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Rotating icon with a glow effect.
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.deepPurple.withValues(alpha: 0.2),
              ),
              child: Center(
                child: RotationTransition(
                  turns: _controller,
                  child: const Icon(
                    Icons.sync,
                    color: Colors.deepPurpleAccent,
                    size: 44,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Message text.
            Text(
              widget.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
