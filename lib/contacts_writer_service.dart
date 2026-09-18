import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result of a batch contact-save operation.
///
/// Tracks how many contacts were successfully saved, how many failed,
/// how many were skipped because they already exist, and their names.
class ContactSaveResult {
  /// Number of contacts successfully written to the phonebook.
  final int savedCount;

  /// Number of contacts that failed to save.
  final int failedCount;

  /// Display names of the contacts that could not be saved.
  final List<String> failedNames;

  /// Number of contacts skipped because they already exist.
  final int skippedCount;

  /// Display names of the contacts that were skipped.
  final List<String> skippedNames;

  const ContactSaveResult({
    required this.savedCount,
    required this.failedCount,
    required this.failedNames,
    required this.skippedCount,
    required this.skippedNames,
  });
}

/// Service responsible for writing parsed contact data to the device's
/// native contacts storage (Android & iOS).
///
/// Uses a platform method channel to insert contacts with the correct
/// account (Google account on Android) to avoid the "Cannot add contacts
/// to local or SIM accounts" crash on modern devices. Each contact is
/// inserted individually so that a single bad entry does not prevent the
/// rest from being saved.
class ContactsWriterService {
  /// Method channel for native contact insertion.
  static const _channel =
      MethodChannel('com.example.contact_scanner/contacts');

  /// Saves all [contacts] to the device phonebook.
  ///
  /// Each map must contain at least "name" and "phone" keys.
  /// Returns a [ContactSaveResult] with counts and any failed/skipped names.
  ///
  /// Throws an [Exception] if contacts permission is denied.
  static Future<ContactSaveResult> saveAllContacts(
    List<Map<String, String>> contacts,
  ) async {
    // ── Request contacts permission ──────────────────────────────────
    final status = await Permission.contacts.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      throw Exception('Contacts permission denied');
    }

    int savedCount = 0;
    int failedCount = 0;
    int skippedCount = 0;
    final List<String> failedNames = [];
    final List<String> skippedNames = [];

    // ── Save each contact one by one ─────────────────────────────────
    for (final contactMap in contacts) {
      final fullName = (contactMap['name'] ?? '').trim();
      final phone = (contactMap['phone'] ?? '').trim();

      try {
        // Check if the contact name already exists to prevent duplication.
        bool exists = false;
        try {
          exists = await _channel.invokeMethod<bool>(
                'checkContactExists',
                {'name': fullName},
              ) ??
              false;
        } catch (_) {
          // Fallback to false on iOS or error.
          exists = false;
        }

        if (exists) {
          skippedCount++;
          skippedNames.add(fullName.isNotEmpty ? fullName : '(unnamed)');
          continue;
        }

        // Split the full name into first and last parts.
        String firstName;
        String lastName;
        final spaceIndex = fullName.indexOf(' ');
        if (spaceIndex == -1) {
          firstName = fullName;
          lastName = '';
        } else {
          firstName = fullName.substring(0, spaceIndex);
          lastName = fullName.substring(spaceIndex + 1);
        }

        // Insert via platform channel (handles Google account detection).
        await _channel.invokeMethod('insertContact', {
          'firstName': firstName,
          'lastName': lastName,
          'phone': phone,
        });

        savedCount++;
      } catch (e) {
        failedCount++;
        failedNames.add(fullName.isNotEmpty ? fullName : '(unnamed)');
      }
    }

    return ContactSaveResult(
      savedCount: savedCount,
      failedCount: failedCount,
      failedNames: failedNames,
      skippedCount: skippedCount,
      skippedNames: skippedNames,
    );
  }

  /// Deletes a contact matching [name] or [phone] from native phonebook.
  static Future<bool> deleteContact({
    required String name,
    required String phone,
  }) async {
    try {
      final bool result = await _channel.invokeMethod<bool>('deleteContact', {
            'name': name,
            'phone': phone,
          }) ??
          false;
      return result;
    } catch (e) {
      return false;
    }
  }

  /// Checks if a contact with [name] exists in native contacts.
  static Future<bool> checkContactExists(String name) async {
    try {
      return await _channel.invokeMethod<bool>(
            'checkContactExists',
            {'name': name},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the native Android Contacts application.
  static Future<void> openContactsApp() async {
    try {
      await _channel.invokeMethod('openContactsApp');
    } catch (_) {}
  }
}
