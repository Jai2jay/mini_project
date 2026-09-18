import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'contacts_writer_service.dart';

/// Represents a contact scheduled for automated deletion at a specific date and time.
class ScheduledContact {
  final String name;
  final String phone;
  final DateTime expiryDateTime;

  ScheduledContact({
    required this.name,
    required this.phone,
    required this.expiryDateTime,
  });

  Duration get remaining => expiryDateTime.difference(DateTime.now());
  bool get isExpired => DateTime.now().isAfter(expiryDateTime);

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        'expiry': expiryDateTime.toIso8601String(),
      };

  factory ScheduledContact.fromJson(Map<String, dynamic> json) =>
      ScheduledContact(
        name: json['name'] ?? '',
        phone: json['phone'] ?? '',
        expiryDateTime: DateTime.parse(json['expiry']),
      );
}

/// Manages temporary contacts, monitors their expiry date/time,
/// and automatically deletes them from the native device phonebook.
class TemporaryContactService {
  static final TemporaryContactService _instance =
      TemporaryContactService._internal();
  factory TemporaryContactService() => _instance;
  TemporaryContactService._internal();

  Timer? _timer;
  final List<ScheduledContact> _scheduledContacts = [];

  /// Notifier for UI to observe active temporary contacts and countdowns.
  final ValueNotifier<List<ScheduledContact>> activeContacts =
      ValueNotifier<List<ScheduledContact>>([]);

  /// Broadcasts a message when a contact expires and is deleted.
  final StreamController<String> onContactExpired =
      StreamController<String>.broadcast();

  bool _initialized = false;

  /// Initializes the service, loads saved schedules from disk, and starts the timer.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadFromDisk();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// Adds contacts to the scheduled temporary contacts list.
  Future<void> scheduleContacts(List<ScheduledContact> contacts) async {
    await init();
    _scheduledContacts.addAll(contacts);
    _updateNotifier();
    await _saveToDisk();
  }

  /// Removes all scheduled contacts for testing/clearing.
  Future<void> clearAll() async {
    _scheduledContacts.clear();
    _updateNotifier();
    await _saveToDisk();
  }

  /// Removes a single contact from the schedule and optionally deletes it from phonebook.
  Future<void> removeContact(ScheduledContact contact, {bool deleteFromPhone = true}) async {
    _scheduledContacts.removeWhere((c) => c.name == contact.name && c.phone == contact.phone);
    if (deleteFromPhone) {
      await ContactsWriterService.deleteContact(name: contact.name, phone: contact.phone);
    }
    _updateNotifier();
    await _saveToDisk();
  }

  Future<void> _tick() async {
    if (_scheduledContacts.isEmpty) return;

    final now = DateTime.now();
    final List<ScheduledContact> expired = [];

    for (final contact in _scheduledContacts) {
      if (now.isAfter(contact.expiryDateTime)) {
        expired.add(contact);
      }
    }

    if (expired.isNotEmpty) {
      for (final contact in expired) {
        _scheduledContacts.remove(contact);
        debugPrint('[TemporaryContactService] Contact expired: ${contact.name}');
        
        // Execute deletion from native phonebook
        final deleted = await ContactsWriterService.deleteContact(
          name: contact.name,
          phone: contact.phone,
        );

        final msg = deleted
            ? "Temporary contact '${contact.name}' expired and was deleted from phonebook."
            : "Temporary contact '${contact.name}' expired (removed from schedule).";

        onContactExpired.add(msg);
      }

      _updateNotifier();
      await _saveToDisk();
    } else {
      // Just notify active list so countdowns refresh every second
      _updateNotifier();
    }
  }

  void _updateNotifier() {
    activeContacts.value = List.unmodifiable(_scheduledContacts);
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/temporary_contacts_registry.json');
  }

  Future<void> _saveToDisk() async {
    try {
      final file = await _getFile();
      final data = _scheduledContacts.map((c) => c.toJson()).toList();
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('[TemporaryContactService] Error saving to disk: $e');
    }
  }

  Future<void> _loadFromDisk() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _scheduledContacts.clear();
        for (final item in jsonList) {
          _scheduledContacts.add(ScheduledContact.fromJson(item));
        }
        _updateNotifier();
      }
    } catch (e) {
      debugPrint('[TemporaryContactService] Error loading from disk: $e');
    }
  }
}
