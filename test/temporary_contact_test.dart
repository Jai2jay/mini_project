import 'package:flutter_test/flutter_test.dart';
import 'package:contact_scanner/temporary_contact_service.dart';

void main() {
  group('ScheduledContact Tests', () {
    test('Calculates remaining duration and isExpired correctly', () {
      final pastContact = ScheduledContact(
        name: 'Test Expired',
        phone: '9876543210',
        expiryDateTime: DateTime.now().subtract(const Duration(seconds: 5)),
      );

      expect(pastContact.isExpired, isTrue);
      expect(pastContact.remaining.isNegative, isTrue);

      final futureContact = ScheduledContact(
        name: 'Test Future',
        phone: '9876543211',
        expiryDateTime: DateTime.now().add(const Duration(hours: 2)),
      );

      expect(futureContact.isExpired, isFalse);
      expect(futureContact.remaining.isNegative, isFalse);
      expect(futureContact.remaining.inMinutes, greaterThanOrEqualTo(119));
    });

    test('Serializes to and from JSON correctly', () {
      final now = DateTime.now();
      final contact = ScheduledContact(
        name: 'Alice Smith',
        phone: '9123456780',
        expiryDateTime: now,
      );

      final json = contact.toJson();
      expect(json['name'], equals('Alice Smith'));
      expect(json['phone'], equals('9123456780'));
      expect(json['expiry'], equals(now.toIso8601String()));

      final recovered = ScheduledContact.fromJson(json);
      expect(recovered.name, equals('Alice Smith'));
      expect(recovered.phone, equals('9123456780'));
      expect(
        recovered.expiryDateTime.millisecondsSinceEpoch,
        equals(now.millisecondsSinceEpoch),
      );
    });

    test('Batch custom date/hour assignment', () {
      final customExpiry = DateTime(2026, 9, 20, 18, 30);
      final rawContacts = [
        {'name': 'Contact 1', 'phone': '9876543201'},
        {'name': 'Contact 2', 'phone': '9876543202'},
        {'name': 'Contact 3', 'phone': '9876543203'},
      ];

      final scheduledList = rawContacts
          .map((c) => ScheduledContact(
                name: c['name']!,
                phone: c['phone']!,
                expiryDateTime: customExpiry,
              ))
          .toList();

      expect(scheduledList.length, equals(3));
      for (final sc in scheduledList) {
        expect(sc.expiryDateTime, equals(customExpiry));
      }
    });
  });
}
