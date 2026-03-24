import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/controllers/recording_controller.dart';

// Toggle chip colors — active uses the app's crimson accent.
const Color _activeChipBg = Color(0x33DC143C); // crimson @ ~20% opacity
const Color _activeChipBorder = AppTheme.crimsonPrimary;
const Color _activeChipText = AppTheme.crimsonPrimary;
const Color _inactiveChipBorder = Colors.white24;
const Color _inactiveChipText = Colors.white70;

class ConnectionSection extends StatefulWidget {
  final TextEditingController uriController;
  final TextEditingController groqApiKeyController;
  final TextEditingController groqLanguageController;
  final TextEditingController groqPromptController;

  const ConnectionSection({
    super.key,
    required this.uriController,
    required this.groqApiKeyController,
    required this.groqLanguageController,
    required this.groqPromptController,
  });

  @override
  State<ConnectionSection> createState() => _ConnectionSectionState();
}

class _ConnectionSectionState extends State<ConnectionSection> {
  String? _languageError;

  @override
  void initState() {
    super.initState();
    widget.groqLanguageController.addListener(_validateLanguage);
    // Validate initial value
    _validateLanguage();
  }

  @override
  void dispose() {
    widget.groqLanguageController.removeListener(_validateLanguage);
    super.dispose();
  }

  void _validateLanguage() {
    final code = widget.groqLanguageController.text.trim();
    final String? error;
    if (code.isEmpty || AppConstants.isValidGroqLanguage(code)) {
      error = null;
    } else {
      error = 'Unsupported language code: "$code"';
    }
    if (error != _languageError) {
      setState(() => _languageError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final controller = context.watch<RecordingController>();
    final isGroqMode = settings.isGroqMode;
    final bool sessionActive =
        controller.isRecording || controller.isTranscribing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row: CONNECTION label + mode toggle
        Row(
          children: [
            Text('CONNECTION', style: AppTheme.sectionTitleStyle),
            if (sessionActive) ...[
              const SizedBox(width: 8),
              const Text(
                '(Active Session)',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 9),
              ),
            ],
            const Spacer(),
            _ModeToggle(
              isGroqMode: isGroqMode,
              enabled: !sessionActive,
              onChanged: (bool groq) async {
                final newMode = groq ? 'groq' : 'backend';
                await settings.setTranscriptionMode(newMode);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Mode-aware content
        if (isGroqMode) ...[
          _buildGroqFields(),
        ] else ...[
          _buildServerUriField(),
        ],
      ],
    );
  }

  Widget _buildServerUriField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Server URI',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.uriController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            hintText: 'ws://localhost:9989/ws',
            hintStyle: const TextStyle(color: Colors.white24),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGroqFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Groq API Key
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Groq API Key',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            Text(
              'console.groq.com',
              style: TextStyle(color: Colors.white24, fontSize: 9),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SecureKeyField(controller: widget.groqApiKeyController),
        const SizedBox(height: 12),

        // Language hint with inline validation
        const Text(
          'LANGUAGE HINT',
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: widget.groqLanguageController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: _languageError != null
                  ? const BorderSide(color: Colors.redAccent, width: 1)
                  : BorderSide.none,
            ),
            hintText: 'e.g. en, es, fr (empty = auto)',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
        if (_languageError != null) ...[
          const SizedBox(height: 4),
          Text(
            _languageError!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 10),
          ),
        ],
        const SizedBox(height: 8),

        // Prompt hint
        const Text(
          'PROMPT HINT',
          style: TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: widget.groqPromptController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          maxLines: 2,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            hintText: 'Spelling/style hints (max 224 tokens)',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'No backend needed. Free tier: 20 req/min.',
          style: TextStyle(color: Colors.white24, fontSize: 9),
        ),
      ],
    );
  }
}

/// Compact inline toggle for switching between WhisperDoc and Groq Cloud.
class _ModeToggle extends StatelessWidget {
  final bool isGroqMode;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ModeToggle({
    required this.isGroqMode,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip('WhisperDoc', selected: !isGroqMode, onTap: () {
            if (enabled) onChanged(false);
          }),
          const SizedBox(width: 4),
          _chip('Groq Cloud', selected: isGroqMode, onTap: () {
            if (enabled) onChanged(true);
          }),
        ],
      ),
    );
  }

  Widget _chip(
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? _activeChipBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? _activeChipBorder : _inactiveChipBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _activeChipText : _inactiveChipText,
            fontSize: 9,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _SecureKeyField extends StatefulWidget {
  final TextEditingController controller;
  const _SecureKeyField({required this.controller});
  @override
  State<_SecureKeyField> createState() => _SecureKeyFieldState();
}

class _SecureKeyFieldState extends State<_SecureKeyField> {
  bool _obscureText = true;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscureText,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility_off : Icons.visibility,
            color: Colors.white38,
            size: 18,
          ),
          onPressed: () => setState(() => _obscureText = !_obscureText),
        ),
      ),
    );
  }
}
