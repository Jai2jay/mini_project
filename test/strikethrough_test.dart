import 'package:flutter_test/flutter_test.dart';

// Standalone function matching VisionParserService._cleanName for deterministic unit testing
String cleanOcrName(String rawName) {
  String name = rawName.trim();

  // 1. Remove markdown strikethrough markers like ~~Maze~~
  name = name.replaceAll(RegExp(r'~~.*?~~'), '');

  // 2. Remove parenthetical or bracketed crossed-out notes
  name = name.replaceAll(
      RegExp(r'\(.*?(crossed|struck|strike|scratched).*?\)',
          caseSensitive: false),
      '');
  name = name.replaceAll(
      RegExp(r'\[.*?(crossed|struck|strike|scratched).*?\]',
          caseSensitive: false),
      '');

  // 3. If multi-line (e.g. struck-out line 1, correction line 2), take the bottom line
  if (name.contains('\n')) {
    final lines = name
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('~~'))
        .toList();
    if (lines.isNotEmpty) {
      name = lines.last;
    }
  }

  // 4. Remove leading/trailing unwanted punctuation (e.g. - , ~ /)
  name = name.replaceAll(RegExp(r'^[~—\-–/:;.,\s]+'), '');
  name = name.replaceAll(RegExp(r'[~—\-–/:;.,\s]+$'), '');

  // 5. Normalize multiple spaces
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

  return name;
}

void main() {
  group('Strikethrough and Correction Handling Tests', () {
    test('Strips markdown strikethrough markup', () {
      expect(cleanOcrName('~~Maze~~ Maziken'), equals('Maziken'));
      expect(cleanOcrName('~~Old Name~~ New Name'), equals('New Name'));
    });

    test('Takes rewritten name from multi-line corrections', () {
      expect(cleanOcrName('~~Maze~~\nMaziken'), equals('Maziken'));
      expect(cleanOcrName('Maze (struck out)\nMaziken'), equals('Maziken'));
    });

    test('Cleans crossed-out parenthetical artifacts', () {
      expect(cleanOcrName('(crossed out) Maziken'), equals('Maziken'));
      expect(cleanOcrName('[struck through] Maziken'), equals('Maziken'));
    });

    test('Preserves clean single names', () {
      expect(cleanOcrName('test V'), equals('test V'));
      expect(cleanOcrName('Arun Kumar'), equals('Arun Kumar'));
    });
  });
}
