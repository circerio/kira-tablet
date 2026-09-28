#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "window_state.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::EnterFullscreen() {
  if (is_fullscreen_) return;
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;

  restore_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
  restore_ex_style_ = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  restore_placement_.length = sizeof(WINDOWPLACEMENT);
  if (!GetWindowPlacement(hwnd, &restore_placement_)) return;

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  if (!GetMonitorInfo(monitor, &monitor_info)) return;

  ShowWindow(hwnd, SW_RESTORE);
  SetWindowLongPtr(
      hwnd, GWL_STYLE,
      (restore_style_ & ~static_cast<LONG_PTR>(WS_OVERLAPPEDWINDOW)) |
          WS_POPUP | WS_VISIBLE);
  SetWindowLongPtr(
      hwnd, GWL_EXSTYLE,
      restore_ex_style_ &
          ~static_cast<LONG_PTR>(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE |
                                 WS_EX_CLIENTEDGE | WS_EX_STATICEDGE));
  const RECT& bounds = monitor_info.rcMonitor;
  SetWindowPos(hwnd, HWND_TOP, bounds.left, bounds.top,
               bounds.right - bounds.left, bounds.bottom - bounds.top,
               SWP_NOOWNERZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  is_fullscreen_ = true;
}

void FlutterWindow::ExitFullscreen() {
  if (!is_fullscreen_) return;
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) return;

  SetWindowLongPtr(hwnd, GWL_STYLE, restore_style_);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, restore_ex_style_);
  SetWindowPlacement(hwnd, &restore_placement_);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                   SWP_FRAMECHANGED);
  is_fullscreen_ = false;
}

bool FlutterWindow::ToggleFullscreen() {
  if (is_fullscreen_) {
    ExitFullscreen();
  } else {
    EnterFullscreen();
  }
  return is_fullscreen_;
}

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

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "io.github.caolib.kira/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<
                 flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "toggleFullscreen") {
          result->Success(flutter::EncodableValue(ToggleFullscreen()));
          return;
        }
        if (call.method_name() == "enterFullscreen") {
          EnterFullscreen();
          result->Success(flutter::EncodableValue(is_fullscreen_));
          return;
        }
        if (call.method_name() == "exitFullscreen") {
          ExitFullscreen();
          result->Success(flutter::EncodableValue(is_fullscreen_));
          return;
        }
        if (call.method_name() == "isFullscreen") {
          result->Success(flutter::EncodableValue(is_fullscreen_));
          return;
        }
        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_CLOSE:
      if (is_fullscreen_) {
        ExitFullscreen();
      }
      window_state::Save(hwnd);
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
