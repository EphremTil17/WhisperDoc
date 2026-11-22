import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
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

  // The window's style, size and position are set natively before the
  // Flutter view exists (windows/runner/win32_window.cpp): doing it here
  // resized a live view twice and cost about 230 ms of startup.
  runApp(const WhisperDocApp());
}
