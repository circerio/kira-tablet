#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "window_state.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(40, 40);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Kira Tablet", origin, size)) {
    return EXIT_FAILURE;
  }

  RECT saved_bounds;
  if (window_state::Load(saved_bounds)) {
    const auto saved_width = saved_bounds.right - saved_bounds.left;
    const auto saved_height = saved_bounds.bottom - saved_bounds.top;
    // Tablet/desktop build is landscape-first. Ignore legacy phone-like
    // portrait bounds so an old 440x950 state cannot trap the app in portrait.
    if (saved_width > saved_height && saved_width >= 960 && saved_height >= 540) {
      if (const HWND handle = window.GetHandle()) {
        SetWindowPos(handle, nullptr, saved_bounds.left, saved_bounds.top,
                     saved_width, saved_height,
                     SWP_NOZORDER | SWP_NOACTIVATE);
      }
    }
  }

  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  // Terminate directly instead of returning: the CRT exit path runs DLL
  // detach code, where flutter_inappwebview_windows releases a static
  // Compositor after its DispatcherQueue is gone and crashes ("kira.exe -
  // Unknown Hard Error" popup when Windows Error Reporting is disabled;
  // flutter_inappwebview #2419/#2512). The window and Flutter engine are
  // already torn down at this point, so there is nothing left to clean up.
  ::TerminateProcess(::GetCurrentProcess(), EXIT_SUCCESS);
  return EXIT_SUCCESS;
}
