import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_key_service.dart';

/// Sends an image of handwritten contacts to Gemini Vision API and receives
/// structured contact data (name + phone pairs) as a JSON array.
///
/// Replaces the old Phase 3 (ML Kit OCR) and Phase 4 (Anthropic AI parsing)
/// with a single Gemini Vision call that handles both text recognition and
/// structured extraction in one shot.
///
/// Uses the free Gemini 1.5 Flash model via REST HTTP (no SDK dependency).
/// Free tier: 1500 requests/day, no credit card required.
class VisionParserService {
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent';

  /// Reads the image at [imagePath], sends it to Gemini Vision, and returns
  /// a list of parsed contact maps.
  ///
  /// Each map contains at minimum "name" and "phone" keys. Entries with
  /// unclear or incomplete phone numbers also include "confidence": "low".
  ///
  /// Throws an [Exception] with a descriptive message on failure.
  static Future<List<Map<String, String>>> extractAndParseContacts(
    String imagePath,
  ) async {
    // Use ApiKeyService: user-saved key takes priority, .env key is fallback.
    final apiKey = await ApiKeyService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception(
        'No Gemini API key configured. '
        'Please add your key in Settings, or set GEMINI_API_KEY in the .env file. '
        'Get a free key at https://aistudio.google.com/app/apikey',
      );
    }

    // Read and base64-encode the image file once.
    final bytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(bytes);

    // Determine MIME type from file extension.
    final mimeType = imagePath.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';

    List<Map<String, String>> contacts = [];
    
    try {
      // First attempt
      contacts = await _doApiCall(apiKey, base64Image, mimeType);
    } catch (e) {
      if (e is TimeoutException || (e is Exception && e.toString().contains('Request timed out'))) {
        // Do not retry on timeout. Just throw the timeout message.
        rethrow;
      }
      
      // Auto-retry ONCE on malformed/empty response
      try {
        contacts = await _doApiCall(apiKey, base64Image, mimeType);
      } catch (retryException) {
        // If retry fails, throw the final error.
        rethrow;
      }
    }

    if (contacts.isEmpty) {
      throw Exception(
        'No contacts detected — try better lighting or hold phone closer',
      );
    }

    return contacts;
  }

  /// Performs the actual HTTP call and parses the response.
  static Future<List<Map<String, String>>> _doApiCall(
    String apiKey,
    String base64Image,
    String mimeType,
  ) async {
    try {
      // Build the Gemini Vision API request with a 30-second timeout.
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'inline_data': {
                    'mime_type': mimeType,
                    'data': base64Image,
                  },
                },
                {
                  'text':
                      'You are an expert handwriting OCR and contact list parser.\n'
                      'The image contains a handwritten list of names and phone numbers arranged row by row.\n'
                      'Each horizontal row has a person\'s Name on the left and their Phone Number on the right, '
                      'often separated by a hyphen "-", dash, colon, or whitespace.\n\n'
                      'CRITICAL RULES & STRIKETHROUGH / CORRECTION HANDLING:\n'
                      '1. STRIKETHROUGH & CROSSED-OUT TEXT DETECTION:\n'
                      '   - Carefully examine each name and number for horizontal strikethrough lines, cross-outs, scratches, or scribble lines (e.g., ~~Maze~~).\n'
                      '   - NEVER transcribe struck-out, crossed-out, or scratched-out text into the output.\n'
                      '   - When a name is struck through and a corrected name is re-written near it (directly underneath, above, or beside it, e.g. "Maziken" written under "Maze"), extract ONLY the clean, non-struck-out correction ("Maziken").\n'
                      '   - Pair that corrected non-struck-out name with the phone number on that row (e.g., {"name": "Maziken", "phone": "6665137"}).\n'
                      '   - Do NOT concatenate the struck-out word with the replacement (NEVER output "Maze Maziken" or "Maze").\n'
                      '   - Do NOT create duplicate contacts or orphan entries for the correction.\n'
                      '   - If a phone number is struck out and a new one is written next to or below it, use ONLY the new non-struck-out phone number.\n'
                      '2. FORMAT REQUIREMENTS:\n'
                      '   - Every contact object MUST have BOTH "name" and "phone" fields: [{"name": "...", "phone": "..."}].\n'
                      '   - Clean phone numbers to digits only.\n'
                      '   - Never output orphan objects with only a name or only a phone.\n'
                      '3. ACCURACY & CLEANLINESS:\n'
                      '   - Never include strikethrough characters (~, -, /) inside the final name.\n'
                      '   - Do not hallucinate or invent missing digits.\n'
                      '4. OUTPUT FORMAT:\n'
                      '   - Return ONLY a valid JSON array of objects with no markdown fences, no code blocks, no backticks, and no explanation text.',
                },
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.1,
            'maxOutputTokens': 1024,
          },
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        String errorMessage = 'Unknown error';
        try {
          final errorJson = jsonDecode(response.body);
          if (errorJson['error'] != null && errorJson['error']['message'] != null) {
            errorMessage = errorJson['error']['message'];
          } else {
            errorMessage = response.body;
          }
        } catch (_) {
          errorMessage = response.body;
        }
        throw Exception(
          'Gemini API Error (Status ${response.statusCode}): $errorMessage',
        );
      }

      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;

      // Extract the text content from the Gemini response.
      final candidates = responseBody['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('Empty response from Gemini API — no candidates returned');
      }

      final content = candidates[0]['content'] as Map<String, dynamic>?;
      if (content == null) {
        throw Exception('Gemini response missing content field');
      }

      final parts = content['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        throw Exception('Gemini response missing parts field');
      }

      String rawJson = parts[0]['text'] as String;

      // Defensively strip markdown code fences if the model wrapped output.
      rawJson = rawJson.trim();
      if (rawJson.startsWith('```json')) {
        rawJson = rawJson.substring(7);
      } else if (rawJson.startsWith('```')) {
        rawJson = rawJson.substring(3);
      }
      if (rawJson.endsWith('```')) {
        rawJson = rawJson.substring(0, rawJson.length - 3);
      }
      rawJson = rawJson.trim();

      // Parse the JSON array.
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) {
        throw Exception(
          'Expected JSON array from Gemini, got: ${decoded.runtimeType}',
        );
      }

      // Convert each entry to Map<String, String> and defensively merge orphan name/phone entries
      final List<Map<String, String>> contacts = [];
      String pendingName = '';
      String pendingPhone = '';

      for (final item in decoded) {
        if (item is Map) {
          String rawName = (item['name'] ?? item['fullName'] ?? '').toString();
          String name = _cleanName(rawName);
          String phone = (item['phone'] ?? item['phoneNumber'] ?? item['number'] ?? '')
              .toString().replaceAll(RegExp(r'[^0-9+]'), '').trim();

          // If entry has both name and phone
          if (name.isNotEmpty && phone.isNotEmpty) {
            // Check if this contact has the exact same phone number as the immediately preceding contact
            // (happens when a re-written correction was output alongside the original struck-out line).
            if (contacts.isNotEmpty && contacts.last['phone'] == phone) {
              // Replace previous with the cleaner/non-empty correction
              contacts.last['name'] = name;
            } else {
              contacts.add({'name': name, 'phone': phone});
            }
          } else if (name.isNotEmpty && phone.isEmpty) {
            if (pendingPhone.isNotEmpty) {
              // Pair with previous orphan phone
              contacts.add({'name': name, 'phone': pendingPhone});
              pendingPhone = '';
            } else if (contacts.isNotEmpty) {
              // Might be a rewritten correction for the previous row with a strikethrough
              contacts.last['name'] = name;
            } else {
              pendingName = name;
            }
          } else if (phone.isNotEmpty && name.isEmpty) {
            if (pendingName.isNotEmpty) {
              // Pair with previous orphan name
              contacts.add({'name': pendingName, 'phone': phone});
              pendingName = '';
            } else {
              pendingPhone = phone;
            }
          }
        }
      }

      // Flush remaining dangling entries
      if (pendingName.isNotEmpty && pendingPhone.isNotEmpty) {
        contacts.add({'name': pendingName, 'phone': pendingPhone});
      } else if (pendingName.isNotEmpty) {
        contacts.add({'name': pendingName, 'phone': ''});
      } else if (pendingPhone.isNotEmpty) {
        contacts.add({'name': 'Unknown', 'phone': pendingPhone});
      }

      return contacts;
    } on TimeoutException {
      throw Exception('Request timed out — check your internet connection');
    } on FormatException catch (e) {
      throw Exception('Failed to parse Gemini response as JSON: $e');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Vision parsing failed: $e');
    }
  }

  /// Cleans OCR names to remove strikethroughs, parenthetical strike markers, and noise.
  static String _cleanName(String rawName) {
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
}
