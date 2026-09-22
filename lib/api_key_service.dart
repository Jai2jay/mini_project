import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages API key storage and retrieval with a "user key first, hardcoded
/// fallback" strategy.
///
/// The user can optionally provide their own Gemini API key via the Settings
/// screen. When present, it takes priority over the hardcoded key bundled in
/// the `.env` file.
class ApiKeyService {
  static const String _storageKey = 'user_gemini_api_key';

  /// Returns the active Gemini API key.
  ///
  /// Priority order:
  /// 1. User-provided key saved in local storage (if non-empty).
  /// 2. Hardcoded key from the `.env` file.
  ///
  /// Returns `null` only when *both* sources are empty/missing.
  static Future<String?> getApiKey() async {
    // 1. Check for user-saved key first.
    final prefs = await SharedPreferences.getInstance();
    final userKey = prefs.getString(_storageKey);
    if (userKey != null && userKey.trim().isNotEmpty) {
      return userKey.trim();
    }

    // 2. Fall back to the hardcoded .env key.
    final envKey = dotenv.env['GEMINI_API_KEY'];
    if (envKey != null &&
        envKey.trim().isNotEmpty &&
        envKey != 'your_gemini_api_key_here') {
      return envKey.trim();
    }

    return null;
  }

  /// Saves the user's custom Gemini API key to local storage.
  static Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, key.trim());
  }

  /// Clears the user's custom API key, reverting to the hardcoded fallback.
  static Future<void> clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  /// Returns the user-saved key (or empty string if none saved).
  /// Used by the Settings screen to pre-fill the text field.
  static Future<String> getSavedUserKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storageKey) ?? '';
  }

  /// Returns `true` when the user has their own key saved.
  static Future<bool> hasUserKey() async {
    final key = await getSavedUserKey();
    return key.trim().isNotEmpty;
  }
}
