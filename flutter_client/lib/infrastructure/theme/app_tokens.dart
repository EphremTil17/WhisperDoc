// Every design token class lives here together, so no class matches the
// file name by design.
// ignore_for_file: prefer-match-file-name
import 'package:material_ui/material_ui.dart';

/// Design tokens for the Captions world (see the home surface brief).
///
/// One dark theme, so tokens are compile-time constants rather than a
/// ThemeExtension lookup. Widgets read these directly; nothing else should
/// declare a colour, text size, spacing step or radius.
abstract final class AppColors {
  /// Window ground.
  static const Color ground = Color(0xFF0B0A0C);

  /// Raised surfaces that float over the ground: menus, popovers.
  static const Color surface = Color(0xFF171415);

  /// Caption bands, keycaps and pressed/hovered surfaces.
  static const Color band = Color(0xFF26211F);

  /// 1px dividers.
  static const Color rule = Color(0xFF221E20);

  /// Dashed and disabled outlines.
  static const Color outline = Color(0xFF4A4245);

  static const Color text = Color(0xFFFFFFFF);

  /// Secondary text; 7:1 on [ground].
  static const Color textMuted = Color(0xFFA69DA0);

  /// Chevrons and locked icons only, never text (below 4.5:1).
  static const Color iconFaint = Color(0xFF6B6265);

  /// Record and "needs you": fills only.
  static const Color record = Color(0xFFDC143C);

  /// Crimson that reads as text or a thin icon on [ground] (5.7:1).
  static const Color alert = Color(0xFFF2566F);

  /// "Update available" only.
  static const Color update = Color(0xFFF2B640);

  /// Text on light fills (primary buttons).
  static const Color onLight = Color(0xFF0B0A0C);
}

/// Meter palette: flat tiers by column age, newest first.
abstract final class AppMeterColors {
  static const Color tip = Color(0xFFFF9AAE);
  static const Color bright = Color(0xFFE7425F);
  static const Color mid = Color(0xFFA3203D);
  static const Color dim = Color(0xFF5A1121);
  static const Color peak = Color(0xFFFFFFFF);
}

/// Four-step type scale.
///
/// Lexend's ascent is 1.0 em and descent 0.25 em, and every pair here keeps
/// (line height − 1.25 × size) even, so with even leading the baseline lands
/// on a whole pixel at 1× scale. Do not add sizes without keeping that rule.
abstract final class AppType {
  static const String family = 'Lexend';
  static const String monoFamily = 'JetBrains Mono';

  static const double _captionSize = 12;
  static const double _bodySize = 16;
  static const double _titleSize = 20;
  static const double _displaySize = 28;

  /// 12/17: labels, meta, cues.
  static const TextStyle caption = TextStyle(
    fontFamily: family,
    fontSize: _captionSize,
    height: 17 / _captionSize,
    leadingDistribution: TextLeadingDistribution.even,
    color: AppColors.text,
  );

  /// 12/17 medium, muted: section headings in panels and settings.
  static const TextStyle label = TextStyle(
    fontFamily: family,
    fontSize: _captionSize,
    height: 17 / _captionSize,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );

  /// 16/24: body, values, buttons.
  static const TextStyle body = TextStyle(
    fontFamily: family,
    fontSize: _bodySize,
    height: 24 / _bodySize,
    leadingDistribution: TextLeadingDistribution.even,
    color: AppColors.text,
  );

  /// 16/30: transcript set in caption bands (room for the band's padding).
  static const TextStyle captionBand = TextStyle(
    fontFamily: family,
    fontSize: _bodySize,
    height: 30 / _bodySize,
    leadingDistribution: TextLeadingDistribution.even,
    color: AppColors.text,
  );

  /// 20/29: headlines and the main cue line.
  static const TextStyle title = TextStyle(
    fontFamily: family,
    fontSize: _titleSize,
    height: 29 / _titleSize,
    leadingDistribution: TextLeadingDistribution.even,
    color: AppColors.text,
  );

  /// 12/17 mono: log lines.
  static const TextStyle mono = TextStyle(
    fontFamily: monoFamily,
    fontSize: _captionSize,
    height: 17 / _captionSize,
    leadingDistribution: TextLeadingDistribution.even,
    color: AppColors.text,
  );

  /// 28/37: the recording timer.
  static const TextStyle display = TextStyle(
    fontFamily: family,
    fontSize: _displaySize,
    height: 37 / _displaySize,
    leadingDistribution: TextLeadingDistribution.even,
    fontWeight: FontWeight.w500,
    color: AppColors.text,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// 4px spacing grid.
abstract final class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadius {
  /// Controls: buttons, keycaps, bands, dialogs, menus, inputs. Square, like
  /// the window itself; circles are kept for status marks only.
  static const Radius control = Radius.zero;
  static const BorderRadius controlAll = BorderRadius.all(control);
}

abstract final class AppSizes {
  static const double titleBar = 40;
  static const double bottomBar = 64;

  /// Dialog and panel headers.
  static const double header = 48;

  /// One row in a panel list.
  static const double row = 48;

  /// How far a pressed control drops, in whole pixels.
  static const int pressDepth = 2;
  static const double iconButton = 40;
  static const double controlHeight = 40;
  static const double iconSize = 18;
  static const double smallIconSize = 16;
}

abstract final class AppMotion {
  /// State swaps (hover, focus, panel open). Short and decisive.
  static const Duration quick = Duration(milliseconds: 120);
  static const Curve ease = Curves.easeOutCubic;

  /// A released control climbs back one pixel per step: stepped, not eased.
  static const Duration pressStep = Duration(milliseconds: 50);
}
