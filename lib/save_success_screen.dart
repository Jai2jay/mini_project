import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:confetti/confetti.dart';
import 'package:share_plus/share_plus.dart';

import 'camera_screen.dart';
import 'contacts_writer_service.dart';

/// Displays the result of a batch contact-save operation.
///
/// Shows a large green checkmark with the count of saved contacts,
/// a breakdown summary card, and a dedicated interactive section to view
/// skipped duplicate contacts (names, numbers, reasons).
class SaveSuccessScreen extends StatefulWidget {
  /// The result from [ContactsWriterService.saveAllContacts].
  final ContactSaveResult result;

  const SaveSuccessScreen({super.key, required this.result});

  @override
  State<SaveSuccessScreen> createState() => _SaveSuccessScreenState();
}

class _SaveSuccessScreenState extends State<SaveSuccessScreen> {
  late ConfettiController _confettiController;
  bool _showSkippedListInline = false;

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
    final text =
        'Saved ${widget.result.savedCount} contacts from Contact Scanner! (${widget.result.skippedCount} duplicate numbers skipped)';
    await Share.share(text);
  }

  /// Displays a modal bottom sheet listing all skipped duplicate contacts.
  void _showSkippedContactsModal(BuildContext context) {
    final skippedList = widget.result.skippedContacts;
    final fallbackNames = widget.result.skippedNames;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B26),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.content_copy_outlined,
                        color: Color(0xFF00E5FF),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Skipped Contacts (${widget.result.skippedCount})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Duplicate numbers were not saved to prevent duplicates.',
                            style: TextStyle(
                              color: Color(0xFF8F97A6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF2B3A5E), height: 1),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: skippedList.isNotEmpty
                        ? skippedList.length
                        : fallbackNames.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: Colors.white10, height: 16),
                    itemBuilder: (context, index) {
                      final name = skippedList.isNotEmpty
                          ? skippedList[index].name
                          : fallbackNames[index];
                      final phone = skippedList.isNotEmpty
                          ? skippedList[index].phone
                          : '';
                      final reason = skippedList.isNotEmpty
                          ? skippedList[index].reason
                          : 'Duplicate number';

                      return Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF2B3A5E),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: Color(0xFF00E5FF),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (phone.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.phone_outlined,
                                        size: 13,
                                        color: Color(0xFF8F97A6),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        phone,
                                        style: const TextStyle(
                                          color: Color(0xFF8F97A6),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00E5FF)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF00E5FF)
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              reason,
                              style: const TextStyle(
                                color: Color(0xFF00E5FF),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalScanned = widget.result.savedCount +
        widget.result.skippedCount +
        widget.result.failedCount;

    return Scaffold(
      backgroundColor: const Color(0xFF0E1118),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1118),
        elevation: 0,
        title: const Text(
          'Save Complete',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  const SizedBox(height: 8),

                  // ── Success icon ──────────────────────────────────────
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.greenAccent.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: Colors.greenAccent,
                      size: 54,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Saved count headline ──────────────────────────────
                  Text(
                    '${widget.result.savedCount} Contact${widget.result.savedCount == 1 ? "" : "s"} Saved!',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Successfully added to your phonebook.',
                    style: TextStyle(
                      color: Color(0xFF8F97A6),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // ── Summary Card ──────────────────────────────
                  Card(
                    color: const Color(0xFF161B26),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Color(0xFF2B3A5E)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildSummaryRow(
                            'Total Scanned',
                            '$totalScanned',
                            Colors.white,
                          ),
                          const Divider(color: Color(0xFF2B3A5E), height: 24),
                          _buildSummaryRow(
                            'Successfully Saved',
                            '${widget.result.savedCount}',
                            Colors.greenAccent,
                          ),
                          const Divider(color: Color(0xFF2B3A5E), height: 24),
                          _buildSummaryRow(
                            'Skipped (Duplicate Numbers)',
                            '${widget.result.skippedCount}',
                            const Color(0xFF00E5FF),
                            trailingAction: widget.result.skippedCount > 0
                                ? GestureDetector(
                                    onTap: () =>
                                        _showSkippedContactsModal(context),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00E5FF)
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(0xFF00E5FF)
                                              .withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.visibility_outlined,
                                            size: 13,
                                            color: Color(0xFF00E5FF),
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            'View Names',
                                            style: TextStyle(
                                              color: Color(0xFF00E5FF),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          const Divider(color: Color(0xFF2B3A5E), height: 24),
                          _buildSummaryRow(
                            'Failed to Save',
                            '${widget.result.failedCount}',
                            Colors.redAccent,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Skipped duplicate contacts card with option to view ──
                  if (widget.result.skippedCount > 0) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B26),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(14.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00E5FF)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.person_off_outlined,
                                    color: Color(0xFF00E5FF),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${widget.result.skippedCount} Duplicate Contact${widget.result.skippedCount == 1 ? "" : "s"} Skipped',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      const Text(
                                        'Duplicate numbers were not saved.',
                                        style: TextStyle(
                                          color: Color(0xFF8F97A6),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _showSkippedListInline =
                                          !_showSkippedListInline;
                                    });
                                  },
                                  icon: Icon(
                                    _showSkippedListInline
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 16,
                                    color: const Color(0xFF00E5FF),
                                  ),
                                  label: Text(
                                    _showSkippedListInline ? 'Hide' : 'See Names',
                                    style: const TextStyle(
                                      color: Color(0xFF00E5FF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: const Color(0xFF00E5FF)
                                          .withValues(alpha: 0.5),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Inline list of skipped contact names
                          if (_showSkippedListInline) ...[
                            const Divider(
                              color: Color(0xFF2B3A5E),
                              height: 1,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Column(
                                children: (widget.result.skippedContacts.isNotEmpty
                                        ? widget.result.skippedContacts
                                        : widget.result.skippedNames.map((n) =>
                                            SkippedContactInfo(name: n, phone: '')))
                                    .map((item) {
                                  final name = item.name;
                                  final phone = item.phone;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2B3A5E)
                                                .withValues(alpha: 0.6),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              name.isNotEmpty
                                                  ? name[0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                color: Color(0xFF00E5FF),
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (phone.isNotEmpty)
                                                Text(
                                                  phone,
                                                  style: const TextStyle(
                                                    color: Color(0xFF8F97A6),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF00E5FF)
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Duplicate',
                                            style: TextStyle(
                                              color: Color(0xFF00E5FF),
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

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
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange,
                                size: 20,
                              ),
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
                    label: const Text(
                      'Scan Another Page',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: const Color(0xFF0E1118),
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
                          icon: const Icon(Icons.contacts, color: Colors.white70),
                          label: const Text('Open Contacts'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF2B3A5E)),
                            backgroundColor: const Color(0xFF161B26),
                            minimumSize: const Size(0, 50),
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
                          icon: const Icon(Icons.share, color: Colors.white70),
                          label: const Text('Share Summary'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF2B3A5E)),
                            backgroundColor: const Color(0xFF161B26),
                            minimumSize: const Size(0, 50),
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

  Widget _buildSummaryRow(
    String title,
    String value,
    Color valueColor, {
    Widget? trailingAction,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (trailingAction != null) ...[
              const SizedBox(width: 8),
              trailingAction,
            ],
          ],
        ),
      ],
    );
  }
}
