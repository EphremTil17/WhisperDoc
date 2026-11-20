import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/ui/whisper_doc_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure the window while it is still hidden. The native runner shows it
  // on Flutter's first frame (flutter_window.cpp), and that frame is the boot
  // screen, so a blank window is never visible.
  try {
    final window = WindowManager.instance.getCurrent();
    if (window != null) {
      const size = Size(AppConstants.windowWidth, AppConstants.windowHeight);
      window
        ..titleBarStyle = TitleBarStyle.hidden
        ..setSize(size.toNative(), false)
        ..center()
        ..backgroundColor = Colors.transparent.toNative()
        ..title = 'WhisperDoc'
        ..isResizable = false;
    }
  } catch (e) {
    debugPrint('Window configuration failed: $e');
  }

  runApp(const WhisperDocApp());
}
