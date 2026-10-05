#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // 主窗口(weak pointer,窗口销毁时自动置 nullptr)。第二次启动时用嚟带返前面。
  GtkWindow* main_window;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView *view)
{
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // [2026-09-22 单实例 + ylink:// 深链] 已经有主窗口 ⇒ 呢次 activate 係第二个进程
  // (再撳菜单图标 / 浏览器 xdg-open ylink://login?…)经 D-Bus 转过嚟:
  // 唔好再开第二个窗口 + 第二个 Flutter 引擎,只把现有窗口带返前面。
  // 收埋去托盘时 Dart 会 setSkipTaskbar(true),呢度同 Window.show() 一样还原任务栏图标。
  if (self->main_window != nullptr) {
    gtk_window_set_skip_taskbar_hint(self->main_window, FALSE);
    gtk_window_present(self->main_window);
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->main_window = window;
  g_object_add_weak_pointer(G_OBJECT(window),
                            reinterpret_cast<gpointer*>(&self->main_window));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Voguesly");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Voguesly");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000 for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  // 先 register:喺 session D-Bus 度认领 APPLICATION_ID。已有主实例在跑 ⇒ 呢个进程变「remote」。
  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  // 主实例:喺度开窗口 + fl_register_plugins(gtk 插件要喺 command-line 信号之前 connect,
  //   冷启动带住 ylink://… 启动先收得到)。
  // remote(第二个进程):activate 经 D-Bus 交畀主实例 ⇒ 主实例 present 现有窗口;本进程唔开窗口。
  g_application_activate(application);
  *exit_status = 0;

  // 返回 FALSE(app_links 官方 README_linux 做法):g_application_run 会继续把 argv 当
  // command-line 交畀主实例(remote 时经 D-Bus 转交,转交完本进程就退出),
  // app_links_linux 经 gtk 插件喺 command-line 信号攞到链接 ⇒ lib/common/link.dart 嘅 uriLinkStream。
  return FALSE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // 由 G_APPLICATION_NON_UNIQUE 改为单实例 + 处理命令行 / open(app_links README_linux)。
  // [2026-09-23] APPLICATION_ID 已经由 `com.follow.clash` 改做 `com.voguesly.app`。
  //    原本嘅顾虑係:path_provider_linux 喺 dlopen 到 libgio-2.0.so 嘅机(装咗 libglib2.0-dev)
  //    用佢做数据目录名 ~/.local/share/<ID>,改咗嗰批用户登录态 / 配置会「冇晒」。
  //    ⇒ 而家由 `lib/common/path.dart` 嘅 `_migrateLinuxLegacyDataDir()` 兜住
  //      (旧目录有嘢、新目录空先搬,而且**唔删**旧嘅)。
  //    改嘅原因(原本记低但一直未修嘅副作用):D-Bus **单实例名都係佢**,
  //    同上游 FlClash(同一个 com.follow.clash、亦係单实例)同时开会互相转交。
  //    时机:Linux 版 2026-09-22 先加,存量用户约等于零,而家改代价最细。
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_HANDLES_COMMAND_LINE | G_APPLICATION_HANDLES_OPEN,
                                     nullptr));
}
