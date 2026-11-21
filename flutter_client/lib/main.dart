import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/ui/whisper_doc_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Fonts ship with the app (no runtime download); register their licences.
  LicenseRegistry.addLicense(() async* {
    for (final (font, path) in AppConstants.bundledFontLicenses) {
      yield LicenseEntryWithLineBreaks([font], await rootBundle.loadString(path));
    }
  });

  // Configure the window while it is still hidden. The native runner shows it
  // on Flutter's first frame (flutter_window.cpp), and that frame is the boot
  // screen, so a blank window is never visible.
  try {
    final window = WindowManager.instance.getCurrent();
    if (window != null) {
      window
        ..titleBarStyle = TitleBarStyle.hidden
        ..backgroundColor = Colors.transparent.toNative()
        ..title = 'WhisperDoc'
        ..isResizable = false;

      // Size the client area, not the frame. With a hidden title bar Windows
      // keeps an invisible resize border, which would otherwise squeeze the
      // layout (420×600 rendered as 404×591) and put centred text on half
      // pixels. Measure the border once styles are applied and grow by it.
      final frame = window.size.toSize();
      final content = window.contentSize.toSize();
      final size = Size(
        AppConstants.windowWidth + frame.width - content.width,
        AppConstants.windowHeight + frame.height - content.height,
      );
      window
        ..setSize(size.toNative(), false)
        ..center();
    }
  } catch (e) {
    debugPrint('Window configuration failed: $e');
  }

  runApp(const WhisperDocApp());
}
