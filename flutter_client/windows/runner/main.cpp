#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Enforce single instance to prevent resource conflicts (Hotkey/Audio)
  HANDLE hMutex = CreateMutex(NULL, TRUE, L"WhisperDocSingleInstanceMutex");
  if (hMutex == NULL || GetLastError() == ERROR_ALREADY_EXISTS) {
    // Another instance is running or failed to acquire mutex, exit silently
    if (hMutex != NULL) {
      ::CloseHandle(hMutex);
    }
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // The client area, in logical pixels (AppConstants.windowWidth/Height). The
  // window is created captionless at exactly this size and centred on the
  // monitor nearest |origin|, so Dart never has to resize it.
  Win32Window::Size size(420, 600);
  if (!window.Create(L"WhisperDoc", origin, size)) {
    ::CoUninitialize();
    ::CloseHandle(hMutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // The title-bar close quits the loop while the window still exists. Tear it
  // down here, while FlutterWindow is whole: left to ~Win32Window, OnDestroy
  // dispatches to the base no-op, so the hotkey thread is never woken and the
  // engine outlives COM and the instance mutex. Harmless after Alt+F4, where
  // the window is already gone.
  window.Destroy();

  ::CoUninitialize();
  ::CloseHandle(hMutex);
  return EXIT_SUCCESS;
}
