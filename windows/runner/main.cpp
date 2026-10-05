#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

#include "app_links/app_links_plugin_c_api.h"

// [2026-09-22] 网页授权登录 ylink://login?… / clash://install-config?…:客户端已经开住时,
// Windows 会另起一个实例并带住链接参数。原本第二个实例喺 Dart 层 singleInstanceLock 失败即 exit(0),
// 链接就咁冇咗。改为(app_links 官方做法)揾到现有窗口 → 用 WM_COPYDATA 转交链接 → 带返前台。
// 窗口标题要同下面 window.Create 嘅一致。
static bool SendAppLinkToInstance(const std::wstring& title) {
  HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", title.c_str());
  if (!hwnd) return false;
  SendAppLink(hwnd);
  WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
  ::GetWindowPlacement(hwnd, &place);
  ::ShowWindow(hwnd, place.showCmd == SW_SHOWMAXIMIZED ? SW_SHOWMAXIMIZED : SW_RESTORE);
  ::SetForegroundWindow(hwnd);
  return true;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (SendAppLinkToInstance(L"Voguesly")) {
    return EXIT_SUCCESS;
  }
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
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Voguesly", origin, size)) {
    return EXIT_FAILURE;
  }
  // [0.9.85] 安装程序装完勾着「运行 易联 Voguesly」时,客户端是以管理员权限启动的(inno [Run] runascurrentuser)。
  // 管理员进程的窗口默认被 UIPI 拦下来自普通权限进程的 WM_COPYDATA ⇒ 网页「一键登录」拉起的第二个实例
  // 转交不了 ylink:// 链接,点了没反应(win10-test 实测:同一链接,管理员实例收不到,普通实例正常弹确认框)。
  // 只放行 WM_COPYDATA 这一种消息;链接内容照旧由 Dart 层校验 + 弹确认框。
  ::ChangeWindowMessageFilterEx(window.GetHandle(), WM_COPYDATA, MSGFLT_ALLOW, nullptr);
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
