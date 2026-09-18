import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'camera_screen.dart';
import 'contacts_writer_service.dart';
import 'loading_spinner.dart';
import 'save_success_screen.dart';
import 'temporary_contact_service.dart';

/// Displays parsed contacts in an editable review list before saving.
///
/// Each contact is shown in a [Card] with editable [TextField] widgets
/// for name and phone number. Low-confidence entries (flagged by the AI)
/// show an orange warning badge. Users can delete incorrect entries or
/// add blank cards for contacts the AI missed.
///
/// The "Save All to Contacts" button writes every contact card to the
/// device's native phonebook via [ContactsWriterService].
class ContactReviewScreen extends StatefulWidget {
  /// The structured contacts parsed by AI.
  /// Each map contains at minimum "name" and "phone" keys,
  /// and optionally "confidence": "low" for uncertain entries.
  final List<Map<String, String>> parsedContacts;

  const ContactReviewScreen({super.key, required this.parsedContacts});

  @override
  State<ContactReviewScreen> createState() => _ContactReviewScreenState();
}

class _ContactReviewScreenState extends State<ContactReviewScreen> {
  /// Mutable list of contacts that the user can edit, delete, and add to.
  late List<Map<String, String>> _contacts;

  /// Controllers for each contact's name and phone fields.
  late List<TextEditingController> _nameControllers;
  late List<TextEditingController> _phoneControllers;

  /// Suffix state variables
  final TextEditingController _suffixController = TextEditingController();
  String _appliedSuffix = "";  // tracks what suffix was last applied
  List<bool> _skipSuffix = [];  // one bool per contact card, default false
  String _suffixPreview = "No label applied";

  /// Temporary contact state (per card).
  late List<bool> _isTemporary;
  late List<DateTime> _expiryDateTimes;

  /// Global default expiry for batch operations (defaults to 24h from now).
  DateTime _globalDefaultExpiry =
      DateTime.now().add(const Duration(hours: 24));
  bool _allTemporary = false;

  /// Subscription to live expiration events from the background service.
  StreamSubscription<String>? _expiredSubscription;

  /// True while contacts are being written to the phonebook.
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Deep-copy so edits don't mutate the original data.
    _contacts = widget.parsedContacts
        .map((c) => Map<String, String>.from(c))
        .toList();
    
    // Initialize nameControllers and phoneControllers
    _nameControllers = _contacts
        .map((c) => TextEditingController(text: c['name'] ?? ''))
        .toList();
    _phoneControllers = _contacts
        .map((c) => TextEditingController(text: c['phone'] ?? ''))
        .toList();

    _skipSuffix =
        List.filled(widget.parsedContacts.length, false, growable: true);
    _isTemporary =
        List.filled(widget.parsedContacts.length, false, growable: true);
    _expiryDateTimes = List.generate(
      widget.parsedContacts.length,
      (_) => DateTime.now().add(const Duration(hours: 24)),
      growable: true,
    );

    // Initialize TemporaryContactService to monitor and auto-delete expired contacts
    TemporaryContactService().init();
    _expiredSubscription =
        TemporaryContactService().onContactExpired.stream.listen((message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.greenAccent),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: Colors.grey[900],
            duration: const Duration(seconds: 4),
          ),
        );
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _expiredSubscription?.cancel();
    for (final c in _nameControllers) {
      c.dispose();
    }
    for (final c in _phoneControllers) {
      c.dispose();
    }
    _suffixController.dispose();
    super.dispose();
  }

  /// Removes the contact at [index] from the list.
  void _deleteContact(int index) {
    if (index < 0 || index >= _contacts.length) return;
    setState(() {
      _contacts.removeAt(index);
      _nameControllers[index].dispose();
      _nameControllers.removeAt(index);
      _phoneControllers[index].dispose();
      _phoneControllers.removeAt(index);
      _skipSuffix.removeAt(index);
      _isTemporary.removeAt(index);
      _expiryDateTimes.removeAt(index);
    });
  }

  /// Adds a blank contact card at the top of the list.
  void _addBlankContact() {
    setState(() {
      _contacts.insert(0, {'name': '', 'phone': ''});
      _nameControllers.insert(0, TextEditingController());
      _phoneControllers.insert(0, TextEditingController());
      _skipSuffix.insert(0, false);
      _isTemporary.insert(0, _allTemporary);
      _expiryDateTimes.insert(0, _globalDefaultExpiry);
    });
  }

  /// Formats a [DateTime] into a friendly user-readable string.
  String _formatExpiryDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.isNegative) {
      return 'Expired';
    }
    if (diff.inSeconds < 60) {
      return 'In ${diff.inSeconds}s (Test)';
    }
    if (diff.inMinutes < 60) {
      return 'In ${diff.inMinutes}m';
    }

    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final isTomorrow =
        dt.year == now.year && dt.month == now.month && dt.day == now.day + 1;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute';

    final monthNames = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    if (isToday) {
      return 'Today at $timeStr';
    } else if (isTomorrow) {
      return 'Tomorrow at $timeStr';
    } else {
      return '${dt.day} ${monthNames[dt.month]} ${dt.year}, $timeStr';
    }
  }

  /// Opens a modal bottom sheet allowing the user to select quick test presets
  /// (e.g. 15s, 1m) or choose an exact custom date and hour/minute.
  /// If [index] is null, applies to ALL contacts. Otherwise, applies to contact at [index].
  Future<void> _pickCustomDateAndHour(int? index) async {
    DateTime initial =
        index != null ? _expiryDateTimes[index] : _globalDefaultExpiry;
    if (initial.isBefore(DateTime.now())) {
      initial = DateTime.now().add(const Duration(hours: 1));
    }

    DateTime selected = initial;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                        const Icon(Icons.timer,
                            color: Colors.deepPurpleAccent, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          index == null
                              ? 'Set Expiry for All Contacts'
                              : 'Set Expiry Date & Hour',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Contacts will automatically expire and be deleted from your phonebook at the set time.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Quick test presets
                    const Text(
                      'Quick Presets & Testing:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.bolt,
                              size: 16, color: Colors.amber),
                          label: const Text('15s Test'),
                          backgroundColor: Colors.amber.withValues(alpha: 0.2),
                          side: const BorderSide(color: Colors.amber),
                          labelStyle: const TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          onPressed: () {
                            setModalState(() {
                              selected = DateTime.now()
                                  .add(const Duration(seconds: 15));
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.bolt,
                              size: 16, color: Colors.amber),
                          label: const Text('1m Test'),
                          backgroundColor: Colors.amber.withValues(alpha: 0.2),
                          side: const BorderSide(color: Colors.amber),
                          labelStyle: const TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          onPressed: () {
                            setModalState(() {
                              selected = DateTime.now()
                                  .add(const Duration(minutes: 1));
                            });
                          },
                        ),
                        ActionChip(
                          label: const Text('+1 Hour'),
                          backgroundColor: Colors.white10,
                          labelStyle: const TextStyle(
                              color: Colors.white, fontSize: 12),
                          onPressed: () {
                            setModalState(() {
                              selected = DateTime.now()
                                  .add(const Duration(hours: 1));
                            });
                          },
                        ),
                        ActionChip(
                          label: const Text('+1 Day'),
                          backgroundColor: Colors.white10,
                          labelStyle: const TextStyle(
                              color: Colors.white, fontSize: 12),
                          onPressed: () {
                            setModalState(() {
                              selected = DateTime.now()
                                  .add(const Duration(days: 1));
                            });
                          },
                        ),
                        ActionChip(
                          label: const Text('+1 Week'),
                          backgroundColor: Colors.white10,
                          labelStyle: const TextStyle(
                              color: Colors.white, fontSize: 12),
                          onPressed: () {
                            setModalState(() {
                              selected = DateTime.now()
                                  .add(const Duration(days: 7));
                            });
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 8),

                    // Custom Date & Hour Buttons
                    const Text(
                      'Choose Custom Date & Hour:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final pickedDate = await showDatePicker(
                                context: context,
                                initialDate: selected,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365 * 2)),
                                builder: (context, child) {
                                  return Theme(
                                    data: ThemeData.dark().copyWith(
                                      colorScheme: const ColorScheme.dark(
                                        primary: Colors.deepPurpleAccent,
                                        surface: Color(0xFF212121),
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (pickedDate != null) {
                                setModalState(() {
                                  selected = DateTime(
                                    pickedDate.year,
                                    pickedDate.month,
                                    pickedDate.day,
                                    selected.hour,
                                    selected.minute,
                                    selected.second,
                                  );
                                });
                              }
                            },
                            icon: const Icon(Icons.calendar_month,
                                size: 18, color: Colors.deepPurpleAccent),
                            label: Text(
                              '${selected.day}/${selected.month}/${selected.year}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white30),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final pickedTime = await showTimePicker(
                                context: context,
                                initialTime:
                                    TimeOfDay.fromDateTime(selected),
                                builder: (context, child) {
                                  return Theme(
                                    data: ThemeData.dark().copyWith(
                                      colorScheme: const ColorScheme.dark(
                                        primary: Colors.deepPurpleAccent,
                                        surface: Color(0xFF212121),
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (pickedTime != null) {
                                setModalState(() {
                                  selected = DateTime(
                                    selected.year,
                                    selected.month,
                                    selected.day,
                                    pickedTime.hour,
                                    pickedTime.minute,
                                  );
                                });
                              }
                            },
                            icon: const Icon(Icons.access_time,
                                size: 18, color: Colors.deepPurpleAccent),
                            label: Text(
                              '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white30),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    // Live scheduled preview
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.deepPurpleAccent
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.alarm_on,
                              color: Colors.deepPurpleAccent, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Expiry Scheduled For:',
                                    style: TextStyle(
                                        color: Colors.white60, fontSize: 11)),
                                Text(
                                  _formatExpiryDateTime(selected),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          if (index == null) {
                            _globalDefaultExpiry = selected;
                            for (int i = 0; i < _contacts.length; i++) {
                              _isTemporary[i] = true;
                              _expiryDateTimes[i] = selected;
                            }
                            _allTemporary = true;
                          } else {
                            _isTemporary[index] = true;
                            _expiryDateTimes[index] = selected;
                          }
                        });
                        Navigator.of(ctx).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        index == null
                            ? 'Apply to All Contacts'
                            : 'Confirm Expiry',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Field Validation Helpers ─────────────────────────────────────

  /// Returns an alert message if the phone number recedes (<10) or exceeds (>10)
  /// 10 numbers or contains OCR anomalies, else null.
  String? _phoneWarning(String phone) {
    if (phone.trim().isEmpty) return null;

    // Check for letters or junk characters that OCR might misread
    if (RegExp(r'[a-zA-Z]').hasMatch(phone)) {
      return 'Contains letters — likely an OCR misread';
    }
    if (RegExp(r'[^0-9\s\-().+#*]').hasMatch(phone)) {
      return 'Unexpected characters in phone number';
    }

    // Strip out country code prefix if formatted (e.g. +91, +1)
    String raw = phone.trim();
    if (raw.startsWith('+')) {
      raw = raw.replaceFirst(RegExp(r'^\+\d{1,3}[\s\-]?'), '');
    }
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length < 10) {
      return 'Phone has ${digits.length} digits (< 10) — number may be incomplete';
    }
    if (digits.length > 10) {
      return 'Phone has ${digits.length} digits (> 10) — exceeds standard 10 digits';
    }

    // Repeated dummy digits like 0000000000 or 9999999999
    if (RegExp(r'^(\d)\1{9}$').hasMatch(digits)) {
      return 'Looks like a placeholder or dummy number';
    }

    return null;
  }

  /// Returns an alert message if the name appears garbled or erroneous.
  String? _nameWarning(String name) {
    if (name.trim().isEmpty) return null;
    final trimmed = name.trim();

    if (trimmed.length == 1) {
      return 'Name is only 1 character — may be misread';
    }
    final digitCount = trimmed.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (digitCount > trimmed.length * 0.4) {
      return 'Name contains numbers — may be misread';
    }
    if (RegExp(r'[|\\^~<>{}\[\]=_]').hasMatch(trimmed)) {
      return 'Contains OCR noise characters';
    }
    return null;
  }

  /// Saves all contacts to the device phonebook.
  Future<void> _saveContacts() async {
    // Validate: no cards remain.
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No contacts to save')),
      );
      return;
    }

    // Collect current state of all text fields and temporary contacts.
    final List<Map<String, String>> contactsList = [];
    final List<ScheduledContact> tempToSchedule = [];
    for (int i = 0; i < _contacts.length; i++) {
      final name = _nameControllers[i].text.trim();
      final phone = _phoneControllers[i].text.trim();
      // Skip cards where both fields are empty.
      if (name.isEmpty && phone.isEmpty) continue;
      contactsList.add({'name': name, 'phone': phone});
      if (_isTemporary[i]) {
        tempToSchedule.add(ScheduledContact(
          name: name,
          phone: phone,
          expiryDateTime: _expiryDateTimes[i],
        ));
      }
    }

    if (contactsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No contacts to save')),
      );
      return;
    }

    // Show the rotating loader overlay.
    setState(() => _isSaving = true);

    try {
      final result =
          await ContactsWriterService.saveAllContacts(contactsList);

      if (tempToSchedule.isNotEmpty) {
        await TemporaryContactService().scheduleContacts(tempToSchedule);
      }

      if (!mounted) return;
      setState(() => _isSaving = false);

      if (tempToSchedule.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${tempToSchedule.length} temporary contact(s) scheduled with auto-delete timers.',
            ),
            backgroundColor: Colors.deepPurple,
            duration: const Duration(seconds: 4),
          ),
        );
      }

      // Navigate to the success screen.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => SaveSuccessScreen(result: result),
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);

      final message = e.toString();
      if (message.contains('permission denied') ||
          message.contains('Permission denied')) {
        // Show a dialog explaining the permission requirement.
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text(
              'Permission Required',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'ContactScanner needs access to your contacts to save '
              'scanned entries. Please grant contacts permission in '
              'your device settings.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  openAppSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                ),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      } else {
        // Generic error — show a SnackBar.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving contacts: $message')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/logo.png',
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.contacts, size: 30),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Review Contacts',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  '${_contacts.length} contact${_contacts.length == 1 ? '' : 's'} found',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          // Camera scanner button
          IconButton(
            icon: const Icon(Icons.camera_alt),
            tooltip: 'Camera scanner',
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const CameraScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Suffix Input Panel at the TOP inside a Card with padding
              _buildSuffixPanel(),

              // Batch Temporary Contact Panel
              _buildBatchTemporaryPanel(),

              // Active temporary countdowns monitor (if any contacts currently scheduled)
              _buildActiveExpirationMonitor(),

              // Action header row (Add Manually)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _addBlankContact,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Manually'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.deepPurpleAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),

              // Scrollable list of editable contact cards.
              Expanded(
                child: _contacts.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _contacts.length,
                        itemBuilder: (context, index) {
                          final contact = _contacts[index];
                          final isLowConfidence =
                              contact['confidence']?.toLowerCase() == 'low';

                          // Dynamic reactive validation for name and phone
                          final nameText = _nameControllers[index].text;
                          final phoneText = _phoneControllers[index].text;
                          final nameWarn = _nameWarning(nameText);
                          final phoneWarn = _phoneWarning(phoneText);
                          final hasWarning = isLowConfidence ||
                              nameWarn != null ||
                              phoneWarn != null;

                          return SlideInCard(
                            key: ValueKey(contact),
                            child: Dismissible(
                              key: ObjectKey(contact),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.delete, color: Colors.white),
                              ),
                              onDismissed: (_) {
                                _deleteContact(index);
                              },
                              child: Card(
                                color: Colors.grey[900],
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: hasWarning
                                      ? BorderSide(
                                          color: Colors.orange
                                              .withValues(alpha: 0.7),
                                          width: 1.5,
                                        )
                                      : BorderSide.none,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Low-confidence warning badge.
                                      if (isLowConfidence)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.warning_amber_rounded,
                                                  color: Colors.orange, size: 16),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Low confidence — please verify',
                                                style: TextStyle(
                                                  color: Colors.orange
                                                      .withValues(alpha: 0.9),
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Contact fields.
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // Name field with AnimatedOpacity
                                                AnimatedOpacity(
                                                  opacity: _skipSuffix[index] ? 0.4 : 1.0,
                                                  duration: const Duration(milliseconds: 200),
                                                  child: TextField(
                                                    controller: _nameControllers[index],
                                                    onChanged: (_) => setState(() {}),
                                                    style: TextStyle(
                                                      color: nameWarn != null
                                                          ? Colors.orangeAccent
                                                          : Colors.white,
                                                      fontSize: 16,
                                                    ),
                                                    decoration: InputDecoration(
                                                      labelText: 'Name',
                                                      labelStyle: TextStyle(
                                                        color: nameWarn != null
                                                            ? Colors.orangeAccent
                                                            : Colors.white
                                                                .withValues(alpha: 0.5),
                                                        fontSize: 13,
                                                      ),
                                                      prefixIcon: Icon(
                                                        Icons.person,
                                                        color: nameWarn != null
                                                            ? Colors.orangeAccent
                                                            : Colors.deepPurpleAccent,
                                                        size: 20,
                                                      ),
                                                      suffixIcon: nameWarn != null
                                                          ? Tooltip(
                                                              message: nameWarn,
                                                              triggerMode: TooltipTriggerMode.tap,
                                                              child: const Icon(
                                                                Icons.warning_amber_rounded,
                                                                color: Colors.orangeAccent,
                                                                size: 20,
                                                              ),
                                                            )
                                                          : null,
                                                      border: OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(8),
                                                        borderSide: const BorderSide(
                                                            color: Colors.white24),
                                                      ),
                                                      enabledBorder: OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(8),
                                                        borderSide: BorderSide(
                                                          color: nameWarn != null
                                                              ? Colors.orangeAccent
                                                              : Colors.white24,
                                                          width: nameWarn != null ? 1.5 : 1.0,
                                                        ),
                                                      ),
                                                      focusedBorder: OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(8),
                                                        borderSide: BorderSide(
                                                          color: nameWarn != null
                                                              ? Colors.orangeAccent
                                                              : Colors.deepPurpleAccent,
                                                          width: 2.0,
                                                        ),
                                                      ),
                                                      contentPadding:
                                                          const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 10,
                                                      ),
                                                      isDense: true,
                                                    ),
                                                  ),
                                                ),
                                                if (nameWarn != null)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 4, left: 4, bottom: 2),
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.warning_amber_rounded,
                                                            color: Colors.orangeAccent, size: 14),
                                                        const SizedBox(width: 4),
                                                        Expanded(
                                                          child: Text(
                                                            nameWarn,
                                                            style: const TextStyle(
                                                              color: Colors.orangeAccent,
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                const SizedBox(height: 10),
                                                // Phone field with live warning border and icon.
                                                TextField(
                                                  controller: _phoneControllers[index],
                                                  keyboardType: TextInputType.phone,
                                                  onChanged: (_) => setState(() {}),
                                                  style: TextStyle(
                                                    color: phoneWarn != null
                                                        ? Colors.orangeAccent
                                                        : Colors.white,
                                                    fontSize: 16,
                                                    fontFamily: 'monospace',
                                                  ),
                                                  decoration: InputDecoration(
                                                    labelText: 'Phone',
                                                    labelStyle: TextStyle(
                                                      color: phoneWarn != null
                                                          ? Colors.orangeAccent
                                                          : Colors.white
                                                              .withValues(alpha: 0.5),
                                                      fontSize: 13,
                                                    ),
                                                    prefixIcon: Icon(
                                                      Icons.phone,
                                                      color: phoneWarn != null
                                                          ? Colors.orangeAccent
                                                          : Colors.deepPurpleAccent,
                                                      size: 20,
                                                    ),
                                                    suffixIcon: phoneWarn != null
                                                        ? Tooltip(
                                                            message: phoneWarn,
                                                            triggerMode: TooltipTriggerMode.tap,
                                                            child: const Icon(
                                                              Icons.warning_amber_rounded,
                                                              color: Colors.orangeAccent,
                                                              size: 20,
                                                            ),
                                                          )
                                                        : null,
                                                    border: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(8),
                                                      borderSide: const BorderSide(
                                                          color: Colors.white24),
                                                    ),
                                                    enabledBorder: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(8),
                                                      borderSide: BorderSide(
                                                        color: phoneWarn != null
                                                            ? Colors.orangeAccent
                                                            : Colors.white24,
                                                        width: phoneWarn != null ? 1.5 : 1.0,
                                                      ),
                                                    ),
                                                    focusedBorder: OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(8),
                                                      borderSide: BorderSide(
                                                        color: phoneWarn != null
                                                            ? Colors.orangeAccent
                                                            : Colors.deepPurpleAccent,
                                                        width: 2.0,
                                                      ),
                                                    ),
                                                    contentPadding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 10,
                                                    ),
                                                    isDense: true,
                                                  ),
                                                ),
                                                if (phoneWarn != null)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 4, left: 4, bottom: 2),
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.warning_amber_rounded,
                                                            color: Colors.orangeAccent, size: 14),
                                                        const SizedBox(width: 4),
                                                        Expanded(
                                                          child: Text(
                                                            phoneWarn,
                                                            style: const TextStyle(
                                                              color: Colors.orangeAccent,
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),

                                          // Delete button.
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline,
                                                color: Colors.redAccent, size: 22),
                                            tooltip: 'Remove contact',
                                            onPressed: () => _deleteContact(index),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      // Skip label check box Row
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          Checkbox(
                                            value: _skipSuffix[index],
                                            onChanged: (val) {
                                              setState(() {
                                                _skipSuffix[index] = val ?? false;
                                                // If checking skip AND suffix is already applied to this card, remove it
                                                if (val == true && _appliedSuffix.isNotEmpty &&
                                                    _nameControllers[index].text.endsWith(" - $_appliedSuffix")) {
                                                  _nameControllers[index].text = _nameControllers[index].text
                                                      .replaceAll(" - $_appliedSuffix", "");
                                                }
                                              });
                                            },
                                          ),
                                          const Text(
                                            "Skip label",
                                            style: TextStyle(fontSize: 13, color: Colors.grey),
                                          ),
                                        ],
                                      ),

                                      // ── Mark as Temporary Contact toggle ──
                                      Container(
                                        margin: const EdgeInsets.only(top: 6),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _isTemporary[index]
                                              ? Colors.deepPurple.withValues(alpha: 0.25)
                                              : Colors.white.withValues(alpha: 0.04),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: _isTemporary[index]
                                                ? Colors.deepPurpleAccent
                                                : Colors.white12,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.timer_outlined,
                                              color: _isTemporary[index]
                                                  ? Colors.deepPurpleAccent
                                                  : Colors.white60,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Mark as Temporary Contact',
                                                style: TextStyle(
                                                  color: _isTemporary[index]
                                                      ? Colors.white
                                                      : Colors.white70,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            Switch(
                                              value: _isTemporary[index],
                                              activeThumbColor: Colors.deepPurpleAccent,
                                              onChanged: (val) {
                                                setState(() {
                                                  _isTemporary[index] = val;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ),

                                      // ── Expiry date/hour picker button ───
                                      if (_isTemporary[index])
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: InkWell(
                                            onTap: () => _pickCustomDateAndHour(index),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 12, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.deepPurple
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.deepPurpleAccent
                                                      .withValues(alpha: 0.5),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.access_time,
                                                      color: Colors.deepPurpleAccent,
                                                      size: 16),
                                                  const SizedBox(width: 8),
                                                  const Text(
                                                    'Auto-delete at:',
                                                    style: TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 12),
                                                  ),
                                                  const Spacer(),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: Colors.deepPurpleAccent,
                                                      borderRadius:
                                                          BorderRadius.circular(6),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          _formatExpiryDateTime(
                                                              _expiryDateTimes[index]),
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        const Icon(Icons.edit,
                                                            color: Colors.white,
                                                            size: 12),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),

          // ── Rotating loader overlay while saving ──────────────────
          if (_isSaving)
            const RotatingLoader(message: 'Saving contacts to phonebook...'),
        ],
      ),

      // Save All button — Phase 5: writes to native contacts.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveContacts,
            icon: const Icon(Icons.save),
            label: const Text('Save All to Contacts'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuffixPanel() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1 - Suffix input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _suffixController,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    decoration: const InputDecoration(
                      hintText: 'Add label to all names e.g. "College", "Work"',
                      hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                      border: InputBorder.none,
                    ),
                    onChanged: (val) => setState(() {
                      _suffixPreview = val.isEmpty ? "No label applied" : "Ajay - $val";
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 2 - Preview text
            Text(
              "Preview: $_suffixPreview",
              style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 12),
            ),
            const SizedBox(height: 12),
            // Row 3 - Two buttons side by side
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final suffix = _suffixController.text.trim();
                      if (suffix.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a label first')),
                        );
                        return;
                      }
                      _appliedSuffix = suffix;
                      for (int i = 0; i < _nameControllers.length; i++) {
                        if (_skipSuffix[i]) continue;
                        final name = _nameControllers[i].text;
                        if (name.endsWith(" - $_appliedSuffix")) continue;
                        _nameControllers[i].text = "$name - $_appliedSuffix";
                      }
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text("Apply to All"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (_appliedSuffix.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No label to clear')),
                        );
                        return;
                      }
                      for (int i = 0; i < _nameControllers.length; i++) {
                        final name = _nameControllers[i].text;
                        if (name.endsWith(" - $_appliedSuffix")) {
                          _nameControllers[i].text = name.replaceAll(" - $_appliedSuffix", "");
                        }
                      }
                      _appliedSuffix = "";
                      setState(() {});
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text("Clear All Labels"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchTemporaryPanel() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _allTemporary
              ? Colors.deepPurpleAccent.withValues(alpha: 0.8)
              : Colors.white12,
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.timer,
                  color: _allTemporary
                      ? Colors.deepPurpleAccent
                      : Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Temporary Contacts (All)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Set auto-delete on all contacts at scheduled date/hour',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _allTemporary,
                  activeThumbColor: Colors.deepPurpleAccent,
                  onChanged: (val) {
                    setState(() {
                      _allTemporary = val;
                      for (int i = 0; i < _isTemporary.length; i++) {
                        _isTemporary[i] = val;
                        if (val) {
                          _expiryDateTimes[i] = _globalDefaultExpiry;
                        }
                      }
                    });
                  },
                ),
              ],
            ),
            if (_allTemporary) ...[
              const SizedBox(height: 8),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text(
                    'Expires:',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.deepPurpleAccent
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        _formatExpiryDateTime(_globalDefaultExpiry),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _pickCustomDateAndHour(null),
                    icon: const Icon(Icons.edit_calendar, size: 15),
                    label: const Text('Change'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurpleAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.bolt,
                          size: 14, color: Colors.amber),
                      label: const Text('15s Test'),
                      backgroundColor: Colors.amber.withValues(alpha: 0.2),
                      side: const BorderSide(color: Colors.amber),
                      labelStyle: const TextStyle(
                          color: Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                      onPressed: () {
                        setState(() {
                          _globalDefaultExpiry =
                              DateTime.now().add(const Duration(seconds: 15));
                          for (int i = 0; i < _expiryDateTimes.length; i++) {
                            _expiryDateTimes[i] = _globalDefaultExpiry;
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(Icons.bolt,
                          size: 14, color: Colors.amber),
                      label: const Text('1m Test'),
                      backgroundColor: Colors.amber.withValues(alpha: 0.2),
                      side: const BorderSide(color: Colors.amber),
                      labelStyle: const TextStyle(
                          color: Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                      onPressed: () {
                        setState(() {
                          _globalDefaultExpiry =
                              DateTime.now().add(const Duration(minutes: 1));
                          for (int i = 0; i < _expiryDateTimes.length; i++) {
                            _expiryDateTimes[i] = _globalDefaultExpiry;
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: const Text('+1 Hour'),
                      backgroundColor: Colors.white10,
                      labelStyle:
                          const TextStyle(color: Colors.white, fontSize: 11),
                      onPressed: () {
                        setState(() {
                          _globalDefaultExpiry =
                              DateTime.now().add(const Duration(hours: 1));
                          for (int i = 0; i < _expiryDateTimes.length; i++) {
                            _expiryDateTimes[i] = _globalDefaultExpiry;
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: const Text('+1 Day'),
                      backgroundColor: Colors.white10,
                      labelStyle:
                          const TextStyle(color: Colors.white, fontSize: 11),
                      onPressed: () {
                        setState(() {
                          _globalDefaultExpiry =
                              DateTime.now().add(const Duration(days: 1));
                          for (int i = 0; i < _expiryDateTimes.length; i++) {
                            _expiryDateTimes[i] = _globalDefaultExpiry;
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveExpirationMonitor() {
    return ValueListenableBuilder<List<ScheduledContact>>(
      valueListenable: TemporaryContactService().activeContacts,
      builder: (context, activeList, _) {
        if (activeList.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E142B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.deepPurpleAccent.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.access_alarms,
                      color: Colors.deepPurpleAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Active Temporary Contacts (${activeList.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await TemporaryContactService().clearAll();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Cleared all scheduled timers.')),
                        );
                      }
                    },
                    child: const Text(
                      'Clear All',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: activeList.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final item = activeList[i];
                    final diff = item.remaining;
                    String countdownText;
                    if (diff.isNegative) {
                      countdownText = 'Expiring...';
                    } else if (diff.inSeconds < 60) {
                      countdownText = '${diff.inSeconds}s remaining';
                    } else if (diff.inMinutes < 60) {
                      countdownText =
                          '${diff.inMinutes}m ${diff.inSeconds % 60}s remaining';
                    } else if (diff.inHours < 24) {
                      countdownText =
                          '${diff.inHours}h ${diff.inMinutes % 60}m remaining';
                    } else {
                      countdownText =
                          '${diff.inDays}d ${diff.inHours % 24}h remaining';
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline,
                              color: Colors.white70, size: 15),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${item.name} (${item.phone})',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: diff.inSeconds <= 15
                                  ? Colors.redAccent.withValues(alpha: 0.3)
                                  : Colors.deepPurpleAccent
                                      .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: diff.inSeconds <= 15
                                    ? Colors.redAccent
                                    : Colors.deepPurpleAccent,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              countdownText,
                              style: TextStyle(
                                color: diff.inSeconds <= 15
                                    ? Colors.redAccent
                                    : Colors.amberAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.contacts, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No contacts — go back and rescan',
            style: TextStyle(color: Colors.white70, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const CameraScreen()),
                );
              }
            },
            icon: const Icon(Icons.camera_alt),
            label: const Text('Rescan'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A wrapper widget that animates the card sliding and fading in on mount.
class SlideInCard extends StatefulWidget {
  final Widget child;
  const SlideInCard({super.key, required this.child});

  @override
  State<SlideInCard> createState() => _SlideInCardState();
}

class _SlideInCardState extends State<SlideInCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuad,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _offsetAnimation,
      child: FadeTransition(
        opacity: _controller,
        child: widget.child,
      ),
    );
  }
}
