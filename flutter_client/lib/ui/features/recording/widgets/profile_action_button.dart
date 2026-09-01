import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/logic/mappers/dictation_profile_ui_mapper.dart';
import 'package:flutter_client/logic/models/custom_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/features/recording/widgets/add_custom_profile_tile.dart';
import 'package:flutter_client/ui/features/recording/widgets/profile_menu_item_tile.dart';
import 'package:flutter_client/ui/screens/home/dialogs/profile_editor_dialog.dart';

/// Compact rectangular profile action button designed for the [ActionBar].
/// Matches the height and gray glass aesthetic of adjacent controls.
/// Displays an aligned vertical menu overlay on hover or click with zero layout jitter.
class ProfileActionButton extends StatefulWidget {
  const ProfileActionButton({super.key});

  static const double buttonWidth = 92;
  static const double buttonHeight = 34;
  static const double menuWidth = 224;

  static const double _buttonHoverBgAlpha = 0.2;
  static const double _buttonIdleBgAlpha = 0.08;
  static const double _buttonHoverBorderAlpha = 0.5;
  static const double _buttonIdleBorderAlpha = 0.15;
  static const double _buttonTooltipOffset = 20;
  static const double _menuBorderAlpha = 0.16;
  static const double _menuShadowAlpha = 0.6;
  static const double _menuShadowBlur = 20;
  static const double _menuShadowOffsetY = 6;
  static const double _buttonIconSize = 14;
  static const double _buttonChevronSize = 13;
  static const double _buttonFontSize = 11.5;
  static const double _buttonLetterSpacing = 0.15;
  static const double _buttonLineHeight = 1.2;
  static const double _buttonChevronAlpha = 0.75;

  @override
  State<ProfileActionButton> createState() => _ProfileActionButtonState();
}

class _ProfileActionButtonState extends State<ProfileActionButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isButtonHovered = false;
  bool _isMenuOpen = false;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isMenuOpen = false;
  }

  void _openMenu(BuildContext context) {
    if (_isMenuOpen) return;

    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          // Dismiss barrier when clicking outside the menu
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeMenu,
            ),
          ),
          Positioned(
            width: ProfileActionButton.menuWidth,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topRight,
              followerAnchor: Alignment.bottomRight,
              offset: const Offset(0, -6),
              child: Material(
                color: Colors.transparent,
                child: _buildVerticalMenu(ctx),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(entry);
    setState(() {
      _overlayEntry = entry;
      _isMenuOpen = true;
    });
  }

  void _closeMenu() {
    if (_isMenuOpen) {
      setState(() {
        _removeOverlay();
      });
    }
  }

  void _toggleMenu(BuildContext context) {
    if (_isMenuOpen) {
      _closeMenu();
    } else {
      _openMenu(context);
    }
  }

  void _selectProfile(SettingsService settings, DictationProfileSpec profile) {
    _closeMenu();
    unawaited(settings.setDictationProfile(profile));
  }

  void _openEditor(CustomProfile profile) {
    _closeMenu();
    unawaited(
      showDialog(
        context: context,
        builder: (_) =>
            ProfileEditorDialog(slotKey: profile.storageKey, existing: profile),
      ),
    );
  }

  void _openCreateEditor(String slotKey) {
    _closeMenu();
    unawaited(
      showDialog(
        context: context,
        builder: (_) => ProfileEditorDialog(slotKey: slotKey),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final controller = context.watch<RecordingController>();

    final activeProfile = settings.dictationProfile;

    // Auto-close menu if a recording session begins
    if (controller.isSessionActive && _isMenuOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _closeMenu());
    }

    final tooltip =
        'Profile: ${activeProfile.label} (${DictationProfileUiMapper.subtitleFor(activeProfile)})';

    final Color backgroundColor = _isButtonHovered || _isMenuOpen
        ? Colors.white.withValues(
            alpha: ProfileActionButton._buttonHoverBgAlpha,
          )
        : Colors.white.withValues(
            alpha: ProfileActionButton._buttonIdleBgAlpha,
          );

    final Color borderColor = _isButtonHovered || _isMenuOpen
        ? Colors.white.withValues(
            alpha: ProfileActionButton._buttonHoverBorderAlpha,
          )
        : Colors.white.withValues(
            alpha: ProfileActionButton._buttonIdleBorderAlpha,
          );

    final Color contentColor = _isButtonHovered || _isMenuOpen
        ? Colors.white
        : const Color(0xFFD0D0D8);

    return Tooltip(
      message: tooltip,
      preferBelow: true,
      verticalOffset: ProfileActionButton._buttonTooltipOffset,
      child: CompositedTransformTarget(
        link: _layerLink,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isButtonHovered = true),
          onExit: (_) => setState(() => _isButtonHovered = false),
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _toggleMenu(context),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: ProfileActionButton.buttonWidth,
              height: ProfileActionButton.buttonHeight,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: const BorderRadius.all(Radius.circular(8)),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    DictationProfileUiMapper.iconFor(activeProfile),
                    size: ProfileActionButton._buttonIconSize,
                    color: contentColor,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      activeProfile.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: contentColor,
                        fontSize: ProfileActionButton._buttonFontSize,
                        fontWeight: FontWeight.w600,
                        letterSpacing: ProfileActionButton._buttonLetterSpacing,
                        height: ProfileActionButton._buttonLineHeight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    _isMenuOpen
                        ? Icons.arrow_drop_up_rounded
                        : Icons.unfold_more_rounded,
                    size: ProfileActionButton._buttonChevronSize,
                    color: contentColor.withValues(
                      alpha: ProfileActionButton._buttonChevronAlpha,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Perfectly spaced and separated vertical list overlay card anchored above the button.
  Widget _buildVerticalMenu(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final activeProfile = settings.dictationProfile;
    final hasGroqKey = settings.cachedGroqApiKey?.isNotEmpty ?? false;
    final freeSlot = settings.nextFreeCustomSlot();

    final List<DictationProfileSpec> allProfiles = [
      ...DictationProfile.values,
      ...settings.customProfiles,
    ];

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xF518181F),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: ProfileActionButton._menuBorderAlpha,
          ),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: ProfileActionButton._menuShadowAlpha,
            ),
            blurRadius: ProfileActionButton._menuShadowBlur,
            offset: const Offset(0, ProfileActionButton._menuShadowOffsetY),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...allProfiles.map((profile) {
            final isSelected = activeProfile.storageKey == profile.storageKey;
            final bool isLlm = profile.requiresLlm;
            final bool isKeyBlocked = isLlm && !hasGroqKey;
            final bool isEnabled = !isKeyBlocked;

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ProfileMenuItemTile(
                profile: profile,
                isSelected: isSelected,
                isEnabled: isEnabled,
                isKeyBlocked: isKeyBlocked,
                onTap: isEnabled
                    ? () => _selectProfile(settings, profile)
                    : null,
                onEdit: profile.isEditable
                    ? () => _openEditor(profile as CustomProfile)
                    : null,
              ),
            );
          }),
          if (freeSlot != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: AddCustomProfileTile(
                onTap: () => _openCreateEditor(freeSlot),
              ),
            ),
        ],
      ),
    );
  }
}
