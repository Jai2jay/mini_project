import 'package:flutter_test/flutter_test.dart';
import 'package:contact_scanner/contacts_writer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Duplicate Number & Phone Normalization Tests', () {
    test('normalizePhoneKey extracts last 10 digits regardless of formatting', () {
      expect(ContactsWriterService.normalizePhoneKey('+91 98765 43210'), '9876543210');
      expect(ContactsWriterService.normalizePhoneKey('(123) 456-7890'), '1234567890');
      expect(ContactsWriterService.normalizePhoneKey('98765-43210'), '9876543210');
      expect(ContactsWriterService.normalizePhoneKey('9876543210'), '9876543210');
      expect(ContactsWriterService.normalizePhoneKey('12345'), '12345');
    });

    test('SkippedContactInfo tracks name, phone, and reason', () {
      const skipped = SkippedContactInfo(
        name: 'Jane Doe',
        phone: '+91 98765 43210',
        reason: 'Duplicate number in scanned list',
      );

      expect(skipped.name, 'Jane Doe');
      expect(skipped.phone, '+91 98765 43210');
      expect(skipped.reason, 'Duplicate number in scanned list');
    });

    test('ContactSaveResult correctly holds skipped contact details', () {
      const result = ContactSaveResult(
        savedCount: 2,
        failedCount: 0,
        failedNames: [],
        skippedCount: 1,
        skippedNames: ['Jane Doe'],
        skippedContacts: [
          SkippedContactInfo(
            name: 'Jane Doe',
            phone: '9876543210',
            reason: 'Number already exists in phone contacts',
          ),
        ],
      );

      expect(result.savedCount, 2);
      expect(result.skippedCount, 1);
      expect(result.skippedNames.first, 'Jane Doe');
      expect(result.skippedContacts.first.name, 'Jane Doe');
      expect(result.skippedContacts.first.phone, '9876543210');
    });
  });
}
