#include "wallpaper_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <cstdlib>
#include <cstring>
#include <cstdio>

static bool is_gnome() {
  const char* desktop = g_getenv("XDG_CURRENT_DESKTOP");
  return desktop && (strstr(desktop, "GNOME") || strstr(desktop, "Unity"));
}

static bool is_kde() {
  const char* desktop = g_getenv("XDG_CURRENT_DESKTOP");
  return desktop && strstr(desktop, "KDE");
}

static bool set_wallpaper_gnome(const char* image_path) {
  char cmd[1024];
  snprintf(cmd, sizeof(cmd),
           "gsettings set org.gnome.desktop.background picture-uri 'file://%s'",
           image_path);
  int ret = system(cmd);
  if (ret != 0) return false;

  snprintf(cmd, sizeof(cmd),
           "gsettings set org.gnome.desktop.background picture-uri-dark 'file://%s'",
           image_path);
  system(cmd);

  snprintf(cmd, sizeof(cmd),
           "gsettings set org.gnome.desktop.background picture-options 'zoom'");
  system(cmd);

  return true;
}

static bool set_wallpaper_kde(const char* image_path) {
  char cmd[2048];
  snprintf(cmd, sizeof(cmd),
           "qdbus org.kde.plasmashell /PlasmaShell "
           "org.kde.PlasmaShell.evaluateScript '"
           "var allDesktops = desktops();"
           "for (i=0;i<allDesktops.length;i++) {"
           "  d = allDesktops[i];"
           "  d.wallpaperPlugin = \"org.kde.image\";"
           "  d.currentConfigGroup = Array(\"Wallpaper\", \"org.kde.image\", \"General\");"
           "  d.writeConfig(\"Image\", \"file://%s\");"
           "}'", image_path);
  return system(cmd) == 0;
}

static void wallpaper_method_call_handler(FlMethodChannel* channel,
                                          FlMethodCall* method_call,
                                          gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "setWallpaper") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* path_val = fl_value_lookup_string(args, "imagePath");
    const char* path = fl_value_get_string(path_val);

    bool success = false;
    if (is_gnome()) {
      success = set_wallpaper_gnome(path);
    } else if (is_kde()) {
      success = set_wallpaper_kde(path);
    }

    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(success)));

  } else if (strcmp(method, "getScreens") == 0) {
    // Use GDK to enumerate monitors
    GdkDisplay* display = gdk_display_get_default();
    g_autoptr(FlValue) screens = fl_value_new_list();

    int n = gdk_display_get_n_monitors(display);
    for (int i = 0; i < n; i++) {
      GdkMonitor* monitor = gdk_display_get_monitor(display, i);
      GdkRectangle geom;
      gdk_monitor_get_geometry(monitor, &geom);

      g_autoptr(FlValue) screen_map = fl_value_new_map();
      fl_value_set_string_take(screen_map, "id", fl_value_new_int(i));
      fl_value_set_string_take(screen_map, "name",
          fl_value_new_string(gdk_monitor_get_model(monitor) ? gdk_monitor_get_model(monitor) : "Screen"));
      fl_value_set_string_take(screen_map, "width", fl_value_new_int(geom.width));
      fl_value_set_string_take(screen_map, "height", fl_value_new_int(geom.height));
      fl_value_set_string_take(screen_map, "left", fl_value_new_int(geom.x));
      fl_value_set_string_take(screen_map, "top", fl_value_new_int(geom.y));
      fl_value_set_string_take(screen_map, "isPrimary",
          fl_value_new_bool(gdk_monitor_is_primary(monitor)));

      fl_value_append(screens, screen_map);
    }

    response = FL_METHOD_RESPONSE(fl_method_success_response_new(screens));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void lockscreen_method_call_handler(FlMethodChannel* channel,
                                           FlMethodCall* method_call,
                                           gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(method, "isSupported") == 0) {
    // Lockscreen on GNOME only
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(is_gnome())));

  } else if (strcmp(method, "setLockscreen") == 0 && is_gnome()) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* path_val = fl_value_lookup_string(args, "imagePath");
    const char* path = fl_value_get_string(path_val);

    char cmd[1024];
    snprintf(cmd, sizeof(cmd),
             "gsettings set org.gnome.desktop.screensaver picture-uri 'file://%s'",
             path);
    bool success = (system(cmd) == 0);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(success)));

  } else if (strcmp(method, "isAdmin") == 0) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(
        fl_value_new_bool(getuid() == 0)));

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

void wallpaper_plugin_register(FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  FlMethodChannel* wallpaper_channel = fl_method_channel_new(
      messenger, "eu.universe_photo_archive/wallpaper",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(wallpaper_channel,
      wallpaper_method_call_handler, nullptr, nullptr);

  FlMethodChannel* lockscreen_channel = fl_method_channel_new(
      messenger, "eu.universe_photo_archive/lockscreen",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(lockscreen_channel,
      lockscreen_method_call_handler, nullptr, nullptr);
}
