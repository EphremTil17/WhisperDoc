import 'package:material_ui/material_ui.dart';

/// Every icon the app draws, from the bundled Lucide font (ISC licence).
///
/// One stroke family for the whole UI. Only the glyphs named here are used,
/// so release builds tree-shake the font down to these code points. To add an
/// icon, copy its code point from lucide.dev into a new constant.
abstract final class AppIcons {
  static const String _family = 'Lucide';

  /// Output style: Pro.
  static const IconData briefcase = IconData(57442, fontFamily: _family);

  /// Done, copied.
  static const IconData check = IconData(57452, fontFamily: _family);

  /// Menu closed.
  static const IconData chevronDown = IconData(57453, fontFamily: _family);

  /// Menu open.
  static const IconData chevronUp = IconData(57456, fontFamily: _family);

  /// Groq Cloud account.
  static const IconData cloud = IconData(57480, fontFamily: _family);

  /// Output style: Tech.
  static const IconData code = IconData(57491, fontFamily: _family);

  /// Copy to clipboard.
  static const IconData copy = IconData(57502, fontFamily: _family);

  /// Incognito.
  static const IconData eyeOff = IconData(57531, fontFamily: _family);

  /// Logs.
  static const IconData fileText = IconData(57548, fontFamily: _family);

  /// History.
  static const IconData history = IconData(57845, fontFamily: _family);

  /// Account key or sign-in problem.
  static const IconData keyRound = IconData(58531, fontFamily: _family);

  /// Locked while recording.
  static const IconData lock = IconData(57611, fontFamily: _family);

  /// Output style: Casual.
  static const IconData messageCircle = IconData(57622, fontFamily: _family);

  /// Output style Raw (in the style menu); choose a microphone.
  static const IconData mic = IconData(57624, fontFamily: _family);

  /// Microphone missing or blocked.
  static const IconData micOff = IconData(57625, fontFamily: _family);

  /// Minimize window.
  static const IconData minus = IconData(57628, fontFamily: _family);

  /// Edit a custom style.
  static const IconData pencil = IconData(57849, fontFamily: _family);

  /// Settings; custom output style.
  static const IconData slidersHorizontal = IconData(
    58010,
    fontFamily: _family,
  );

  /// Output style: Clean.
  static const IconData sparkles = IconData(58386, fontFamily: _family);

  /// Self-hosted account.
  static const IconData user = IconData(57759, fontFamily: _family);

  /// Close.
  static const IconData x = IconData(57778, fontFamily: _family);

  /// Connection paused by the server.
  static const IconData ban = IconData(57425, fontFamily: _family);

  /// Try again; reconnect.
  static const IconData refreshCw = IconData(57669, fontFamily: _family);

  /// The output-style picker.
  static const IconData type = IconData(57752, fontFamily: _family);

  /// Create something new (a custom style).
  static const IconData plus = IconData(57661, fontFamily: _family);

  /// Something failed (sign-in errors).
  static const IconData circleAlert = IconData(57463, fontFamily: _family);

  // Panels: navigation and the rows in Account and Settings.

  /// Panel back button.
  static const IconData chevronLeft = IconData(57454, fontFamily: _family);

  /// A row that opens another panel.
  static const IconData chevronRight = IconData(57455, fontFamily: _family);

  /// Settings: shortcut.
  static const IconData keyboard = IconData(57988, fontFamily: _family);

  /// Settings: the moving contour background.
  static const IconData mountain = IconData(57905, fontFamily: _family);

  /// Settings: level meter.
  static const IconData audioLines = IconData(58714, fontFamily: _family);

  /// Settings: copy to clipboard.
  static const IconData clipboard = IconData(57477, fontFamily: _family);

  /// Settings: paste where the cursor is.
  static const IconData arrowRightToLine = IconData(58457, fontFamily: _family);

  /// Account: transcription model.
  static const IconData cpu = IconData(57513, fontFamily: _family);

  /// Account: language.
  static const IconData globe = IconData(57576, fontFamily: _family);

  /// Account: prompt hint.
  static const IconData textCursorInput = IconData(57957, fontFamily: _family);

  /// Account: self-hosted server address.
  static const IconData server = IconData(57683, fontFamily: _family);

  /// Account: sign in.
  static const IconData logIn = IconData(57613, fontFamily: _family);

  /// Account: update available.
  static const IconData download = IconData(57522, fontFamily: _family);

  /// Account: up to date.
  static const IconData circleCheck = IconData(57894, fontFamily: _family);

  /// Style editor: the safety preamble note.
  static const IconData shieldCheck = IconData(57855, fontFamily: _family);

  /// Secret fields: reveal.
  static const IconData eye = IconData(57530, fontFamily: _family);

  /// Home: the server isn't answering.
  static const IconData serverOff = IconData(57834, fontFamily: _family);

  /// Home: a server not yet trusted with the sign-in.
  static const IconData shieldAlert = IconData(57854, fontFamily: _family);
}
