#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "audio_device_watcher.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Forwards Core Audio endpoint changes to Dart so microphone availability
  // updates the moment a device is plugged in or removed.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      audio_devices_channel_;
  AudioDeviceWatcher* audio_device_watcher_ = nullptr;

  // Tracks the hotkey isolate's Win32 thread ID so OnDestroy can wake its
  // blocking GetMessageW loop (WM_QUIT) before tearing down the Dart VM,
  // even when the window closes via Alt+F4 or the taskbar.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      hotkey_lifecycle_channel_;
  DWORD hotkey_thread_id_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
