import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_key_service.dart';

/// Full-page Settings screen where users can configure their own Gemini API key.
///
/// Matches the dark navy/slate theme (#0E1118) used throughout Contact Scanner.
/// Includes:
/// - An instruction card explaining how to obtain a key from Google AI Studio
/// - A secure text field with visibility toggle
/// - Save / Clear buttons with status feedback
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _keyController = TextEditingController();
  bool _obscureText = true;
  bool _isSaving = false;
  bool _hasExistingKey = false;
  bool _showSavedBanner = false;

  late final AnimationController _bannerController;
  late final Animation<double> _bannerOpacity;

  // Theme constants matching the app's design language
  static const Color _bgColor = Color(0xFF0E1118);
  static const Color _surfaceColor = Color(0xFF141720);
  static const Color _borderColor = Color(0xFF232838);
  static const Color _accentBlue = Color(0xFF6C93D6);
  static const Color _subtitleColor = Color(0xFF8F97A6);
  static const Color _cardGradientStart = Color(0xFF1A2235);
  static const Color _cardGradientEnd = Color(0xFF141A28);

  @override
  void initState() {
    super.initState();
    _bannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _bannerOpacity = CurvedAnimation(
      parent: _bannerController,
      curve: Curves.easeOut,
    );
    _loadExistingKey();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _bannerController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingKey() async {
    final saved = await ApiKeyService.getSavedUserKey();
    if (mounted) {
      setState(() {
        _keyController.text = saved;
        _hasExistingKey = saved.isNotEmpty;
      });
    }
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      _showSnackBar('Please enter an API key first', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      await ApiKeyService.saveApiKey(key);
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _hasExistingKey = true;
        _showSavedBanner = true;
      });

      _bannerController.forward(from: 0.0);

      // Auto-dismiss after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _showSavedBanner) {
          _bannerController.reverse().then((_) {
            if (mounted) setState(() => _showSavedBanner = false);
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnackBar('Failed to save: $e', isError: true);
      }
    }
  }

  Future<void> _clearKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _borderColor),
        ),
        title: const Text(
          'Clear API Key?',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: const Text(
          'This will remove your saved key and revert to the default. You can add a new key anytime.',
          style: TextStyle(color: _subtitleColor, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _subtitleColor)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ApiKeyService.clearApiKey();
      if (mounted) {
        setState(() {
          _keyController.clear();
          _hasExistingKey = false;
        });
        _showSnackBar('API key cleared — using default key');
      }
    }
  }

  Future<void> _openAIStudio() async {
    final uri = Uri.parse('https://aistudio.google.com/app/apikey');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        // Fallback: copy URL to clipboard
        await Clipboard.setData(
          const ClipboardData(text: 'https://aistudio.google.com/app/apikey'),
        );
        _showSnackBar('Link copied to clipboard');
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent.shade700 : const Color(0xFF1E2433),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            // ── Success Banner ──
            if (_showSavedBanner)
              FadeTransition(
                opacity: _bannerOpacity,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A3326), Color(0xFF142822)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2A5E40), width: 1),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF5FD68B), size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'API key saved successfully! Your key will be used for all future scans.',
                          style: TextStyle(
                            color: Color(0xFFB8E6CC),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Section Header ──
            const Text(
              'Gemini API Configuration',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Use your own Google Gemini API key for contact scanning. Your personal key takes priority over the built-in default.',
              style: TextStyle(
                color: _subtitleColor,
                fontSize: 13,
                height: 1.45,
              ),
            ),

            const SizedBox(height: 20),

            // ── Instruction Card ──
            _buildInstructionCard(),

            const SizedBox(height: 24),

            // ── API Key Input Section ──
            _buildApiKeyInput(),

            const SizedBox(height: 20),

            // ── Save Button ──
            _buildSaveButton(),

            // ── Clear Button (only when key exists) ──
            if (_hasExistingKey) ...[
              const SizedBox(height: 12),
              _buildClearButton(),
            ],

            const SizedBox(height: 32),

            // ── Privacy & About Section ──
            _buildPrivacySection(),
          ],
        ),
      ),
    );
  }

  /// Instruction card with numbered steps and a link to Google AI Studio.
  Widget _buildInstructionCard() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_cardGradientStart, _cardGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A3752), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Header
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFF232C42), width: 1),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.lightbulb_outline_rounded, color: Color(0xFFE8C55A), size: 20),
                SizedBox(width: 10),
                Text(
                  'How to get your API key',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Steps
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Column(
              children: [
                _buildStep(
                  number: '1',
                  text: 'Go to Google AI Studio',
                  highlight: true,
                ),
                _buildStep(
                  number: '2',
                  text: 'Sign in with your Google account',
                ),
                _buildStep(
                  number: '3',
                  text: 'Click "Create API Key" and copy it',
                ),
              ],
            ),
          ),

          // AI Studio Link Button
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _openAIStudio,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B3A5E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF3E5488),
                      width: 1,
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.open_in_new_rounded, color: Color(0xFF9EC2FF), size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Open Google AI Studio',
                        style: TextStyle(
                          color: Color(0xFF9EC2FF),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Free tier note
          Container(
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF111620),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E2535), width: 1),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: _subtitleColor, size: 15),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Free tier: 1,500 requests/day — no credit card needed.',
                    style: TextStyle(
                      color: _subtitleColor,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A single numbered step row in the instruction card.
  Widget _buildStep({
    required String number,
    required String text,
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: highlight
                  ? _accentBlue.withValues(alpha: 0.18)
                  : const Color(0xFF1E2535),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              number,
              style: TextStyle(
                color: highlight ? _accentBlue : const Color(0xFF7A8498),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFFCAD0DC),
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Secure text field with visibility toggle.
  Widget _buildApiKeyInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Row(
          children: [
            const Icon(Icons.vpn_key_rounded, color: _accentBlue, size: 16),
            const SizedBox(width: 8),
            const Text(
              'API Key',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (_hasExistingKey)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A3326),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF2A5E40), width: 0.8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF5FD68B), size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Saved',
                      style: TextStyle(
                        color: Color(0xFF5FD68B),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Text Field
        Container(
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borderColor, width: 1),
          ),
          child: TextField(
            controller: _keyController,
            obscureText: _obscureText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
            decoration: InputDecoration(
              hintText: 'Paste your Gemini API key here...',
              hintStyle: TextStyle(
                color: _subtitleColor.withValues(alpha: 0.5),
                fontSize: 14,
                fontFamily: 'monospace',
              ),
              contentPadding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
              border: InputBorder.none,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureText
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: _subtitleColor,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscureText = !_obscureText);
                },
              ),
            ),
            onChanged: (_) {
              // Reset saved state when user modifies the key
              if (_hasExistingKey) {
                setState(() => _hasExistingKey = false);
              }
            },
          ),
        ),
      ],
    );
  }

  /// "Save Configuration" button.
  Widget _buildSaveButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isSaving ? null : _saveKey,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2B3A5E), Color(0xFF384E7E)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF4A6AA5), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2B3A5E).withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.save_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 10),
                      Text(
                        'Save Configuration',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// "Clear Saved Key" button (appears only when a key is saved).
  Widget _buildClearButton() {
    return TextButton(
      onPressed: _clearKey,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF2A1E1E), width: 1),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.delete_outline_rounded, color: Color(0xFFE57373), size: 17),
          SizedBox(width: 8),
          Text(
            'Clear Saved Key',
            style: TextStyle(
              color: Color(0xFFE57373),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Privacy & version info section at the bottom.
  Widget _buildPrivacySection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Privacy & About',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          _buildInfoRow(
            icon: Icons.shield_outlined,
            title: 'Your key stays on-device',
            subtitle: 'Stored locally — never sent to our servers',
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.timer_outlined,
            title: 'Temporary Contacts Engine',
            subtitle: 'Auto-deletes expired contacts natively',
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            icon: Icons.info_outline,
            title: 'Version',
            subtitle: 'Contact Scanner v1.0.0',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _accentBlue, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _subtitleColor,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
