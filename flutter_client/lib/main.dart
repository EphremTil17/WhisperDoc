import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_client/ui/whisper_doc_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure the window while it is still hidden. The native runner shows it
  // on Flutter's first frame (flutter_window.cpp), and that frame is the boot
  // screen, so a blank window is never visible.
  try {
    const windowOptions = WindowOptions(
      size: Size(420, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'WhisperDoc',
    );
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(windowOptions);
    await windowManager.setResizable(false);
  } catch (e) {
    debugPrint('Window configuration failed: $e');
  }

  runApp(const WhisperDocApp());
}
