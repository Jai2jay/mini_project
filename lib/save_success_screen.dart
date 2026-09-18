import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:share_plus/share_plus.dart';

import 'camera_screen.dart';
import 'contacts_writer_service.dart';

/// Displays the result of a batch contact-save operation.
///
/// Shows a large green checkmark with the count of saved contacts,
/// an optional orange warning section listing any failures, a blue section
/// listing duplicates/skipped, and action buttons.
class SaveSuccessScreen extends StatefulWidget {
  /// The result from [ContactsWriterService.saveAllContacts].
  final ContactSaveResult result;

  const SaveSuccessScreen({super.key, required this.result});

  @override
  State<SaveSuccessScreen> createState() => _SaveSuccessScreenState();
}

class _SaveSuccessScreenState extends State<SaveSuccessScreen> {
  late ConfettiController _confettiController;

  /// Method channel shared with [ContactsWriterService].
  static const _channel =
      MethodChannel('com.example.contact_scanner/contacts');

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
    _confettiController.play();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  /// Opens the device's native contacts application via platform channel.
  Future<void> _openContactsApp() async {
    try {
      await _channel.invokeMethod('openContactsApp');
    } catch (_) {
      // Silently fail — user can open contacts manually.
    }
  }

  /// Shares a text summary of the saved contacts.
  Future<void> _shareSummary() async {
    final text = 'Saved ${widget.result.savedCount} contacts from ContactScanner!';
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    final totalScanned = widget.result.savedCount +
        widget.result.skippedCount +
        widget.result.failedCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Save Complete'),
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  const SizedBox(height: 16),

                  // ── Success icon ──────────────────────────────────────
                  const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 96,
                  ),
                  const SizedBox(height: 24),

                  // ── Saved count headline ──────────────────────────────
                  Text(
                    '${widget.result.savedCount} Contact${widget.result.savedCount == 1 ? '' : 's'} Saved!',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Successfully added to your phonebook.',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // ── Summary Card ──────────────────────────────
                  Card(
                    color: Colors.grey[900],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildSummaryRow('Total Scanned', '$totalScanned', Colors.white),
                          const Divider(color: Colors.white24, height: 24),
                          _buildSummaryRow(
                            'Successfully Saved',
                            '${widget.result.savedCount}',
                            Colors.greenAccent,
                          ),
                          const Divider(color: Colors.white24, height: 24),
                          _buildSummaryRow(
                            'Skipped (Already Exists)',
                            '${widget.result.skippedCount}',
                            Colors.blueAccent,
                          ),
                          const Divider(color: Colors.white24, height: 24),
                          _buildSummaryRow(
                            'Failed to Save',
                            '${widget.result.failedCount}',
                            Colors.redAccent,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Failures section (if any) ─────────────────────────
                  if (widget.result.failedCount > 0) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'These could not be saved — add them manually:',
                                  style: TextStyle(
                                    color: Colors.orange.withValues(alpha: 0.9),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ...widget.result.failedNames.map(
                            (name) => Padding(
                              padding: const EdgeInsets.only(left: 28, bottom: 4),
                              child: Text(
                                '• $name',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Skipped section (if any) ─────────────────────────
                  if (widget.result.skippedCount > 0) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  color: Colors.blueAccent, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Already exists in your contacts (skipped):',
                                  style: TextStyle(
                                    color: Colors.blueAccent.withValues(alpha: 0.9),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ...widget.result.skippedNames.map(
                            (name) => Padding(
                              padding: const EdgeInsets.only(left: 28, bottom: 4),
                              child: Text(
                                '• $name',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // ── Action buttons ────────────────────────────────────
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const CameraScreen()),
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.document_scanner),
                    label: const Text('Scan Another Page'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openContactsApp,
                          icon: const Icon(Icons.contacts),
                          label: const Text('Open Contacts'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black87,
                            side: const BorderSide(color: Colors.black26),
                            minimumSize: const Size(0, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _shareSummary,
                          icon: const Icon(Icons.share),
                          label: const Text('Share Summary'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black87,
                            side: const BorderSide(color: Colors.black26),
                            minimumSize: const Size(0, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // Confetti widget aligned to top-center.
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              colors: const [
                Colors.green,
                Colors.blue,
                Colors.pink,
                Colors.orange,
                Colors.purple
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String title, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
