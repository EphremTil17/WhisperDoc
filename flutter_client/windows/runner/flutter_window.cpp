#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
// Must match AudioDeviceMonitor.channelName on the Dart side.
constexpr char kAudioDevicesChannel[] = "whisperdoc/audio_devices";
constexpr char kAudioDevicesChangedMethod[] = "audioDevicesChanged";

// Must match HotkeyService lifecycle channel on the Dart side.
constexpr char kHotkeyLifecycleChannel[] = "whisperdoc/hotkey_lifecycle";
constexpr char kSetHotkeyThreadIdMethod[] = "setHotkeyThreadId";
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  audio_devices_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kAudioDevicesChannel,
          &flutter::StandardMethodCodec::GetInstance());
  // Best effort: without Core Audio the app still re-checks on focus/record.
  audio_device_watcher_ = AudioDeviceWatcher::Create(GetHandle());

  hotkey_lifecycle_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kHotkeyLifecycleChannel,
          &flutter::StandardMethodCodec::GetInstance());
  hotkey_lifecycle_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == kSetHotkeyThreadIdMethod) {
          if (const auto* id32 = std::get_if<int32_t>(call.arguments())) {
            hotkey_thread_id_ = *id32 > 0 ? static_cast<DWORD>(*id32) : 0;
          } else if (const auto* id64 =
                         std::get_if<int64_t>(call.arguments())) {
            hotkey_thread_id_ = *id64 > 0 ? static_cast<DWORD>(*id64) : 0;
          } else {
            hotkey_thread_id_ = 0;
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Stop OS callbacks before the channel and engine they feed go away.
  if (audio_device_watcher_) {
    audio_device_watcher_->Shutdown();
    audio_device_watcher_ = nullptr;
  }
  audio_devices_channel_ = nullptr;
  hotkey_lifecycle_channel_ = nullptr;

  // Wake the hotkey isolate's blocking GetMessageW loop before destroying the
  // Flutter engine; otherwise WM_CLOSE (Alt+F4, taskbar close) hangs waiting
  // for that isolate to exit.
  if (hotkey_thread_id_ != 0) {
    ::PostThreadMessage(hotkey_thread_id_, WM_QUIT, 0, 0);
    hotkey_thread_id_ = 0;
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kAudioDevicesChangedMessage) {
    // Re-arm before forwarding so changes during the Dart re-check post again.
    if (audio_device_watcher_) {
      audio_device_watcher_->Acknowledge();
    }
    if (audio_devices_channel_) {
      audio_devices_channel_->InvokeMethod(kAudioDevicesChangedMethod, nullptr);
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_ENDSESSION:
      // Log off or shut down: Windows can end the process after this returns
      // without WM_CLOSE or WM_DESTROY, so release the shortcut now instead
      // of leaving the hotkey thread blocked in GetMessageW.
      if (wparam && hotkey_thread_id_ != 0) {
        ::PostThreadMessage(hotkey_thread_id_, WM_QUIT, 0, 0);
        hotkey_thread_id_ = 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
