import 'dart:async';

import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/mappers/dictation_profile_ui_mapper.dart';
import 'package:flutter_client/logic/models/custom_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/features/recording/widgets/add_custom_profile_tile.dart';
import 'package:flutter_client/ui/features/recording/widgets/profile_menu_item_tile.dart';
import 'package:flutter_client/ui/screens/home/dialogs/profile_editor_dialog.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// Output-style picker for the home bottom bar: the active style's glyph,
/// its name and a chevron. Opens a vertical menu above itself, left-aligned,
/// with zero layout jitter.
class ProfileActionButton extends StatefulWidget {
  const ProfileActionButton({super.key});

  static const double menuWidth = 224;

  static const double _buttonTooltipOffset = 20;
  static const double _chevronSize = 14;
  static const double _contentGap = 6;
  static const double _padX = 10;

  @override
  State<ProfileActionButton> createState() => _ProfileActionButtonState();
}

class _ProfileActionButtonState extends State<ProfileActionButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  RecordingController? _recording;
  bool _isButtonHovered = false;

  bool get _isMenuOpen => _overlayEntry != null;

  @override
  void initState() {
    super.initState();
    // Listen rather than watch: only a session start matters here, and it
    // should close the menu directly instead of rebuilding this button.
    _recording = context.read<RecordingController>()
      ..addListener(_closeMenuOnSessionStart);
  }

  @override
  void dispose() {
    _recording?.removeListener(_closeMenuOnSessionStart);
    _removeOverlay();
    super.dispose();
  }

  void _closeMenuOnSessionStart() {
    if (_recording?.isSessionActive ?? false) _closeMenu();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
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
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
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
    setState(() => _overlayEntry = entry);
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
    final activeProfile = settings.dictationProfile;

    final tooltip =
        'Profile: ${activeProfile.label} (${DictationProfileUiMapper.subtitleFor(activeProfile)})';

    final active = _isButtonHovered || _isMenuOpen;

    return Tooltip(
      message: tooltip,
      preferBelow: false,
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
              duration: AppMotion.quick,
              height: AppSizes.controlHeight,
              padding: const EdgeInsets.symmetric(
                horizontal: ProfileActionButton._padX,
              ),
              decoration: BoxDecoration(
                color: active ? AppColors.band : Colors.transparent,
                borderRadius: AppRadius.controlAll,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: ProfileActionButton._contentGap,
                children: [
                  // One glyph for the picker itself; each style's own glyph
                  // appears in the menu rows.
                  const Icon(
                    AppIcons.type,
                    size: AppSizes.smallIconSize,
                    color: AppColors.textMuted,
                  ),
                  // Custom style names can be long: shrink, never overflow.
                  Flexible(
                    child: CrispText(
                      activeProfile.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  Icon(
                    _isMenuOpen ? AppIcons.chevronUp : AppIcons.chevronDown,
                    size: ProfileActionButton._chevronSize,
                    color: AppColors.textMuted,
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
      padding: const EdgeInsets.all(AppSpace.xs),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.controlAll,
        border: Border.fromBorderSide(BorderSide(color: AppColors.rule)),
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
