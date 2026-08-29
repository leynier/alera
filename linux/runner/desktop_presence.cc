#include "desktop_presence.h"

#include <gtk/gtk.h>

#include <libayatana-appindicator/app-indicator.h>

namespace {

constexpr char kChannelName[] = "dev.leynier.alera/desktop_presence";
constexpr char kLauncherInterface[] = "com.canonical.Unity.LauncherEntry";

static gchar* launcher_object_path() {
  guint32 hash = g_str_hash(APPLICATION_ID);
  return g_strdup_printf("/com/canonical/unity/launcherentry/%u", hash);
}

}  // namespace

struct _DesktopPresence {
  FlMethodChannel* channel;
  AppIndicator* indicator;
  GtkWidget* menu;
  GtkWidget* show_item;
  guint launcher_owner_watch;
  guint launcher_registration;
  GDBusConnection* bus;
  int badge_count;
};

static gchar* launcher_app_uri() {
  return g_strdup_printf("application://%s.desktop", APPLICATION_ID);
}

static void ensure_launcher_object(DesktopPresence* self);

static void emit_launcher_update(DesktopPresence* self) {
  GDBusConnection* bus = self->bus;
  if (bus == nullptr) {
    return;
  }
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  const gboolean visible = self->badge_count > 0;
  g_variant_builder_add(&builder, "{sv}", "count",
                        g_variant_new_int64(self->badge_count));
  g_variant_builder_add(&builder, "{sv}", "count-visible",
                        g_variant_new_boolean(visible));
  g_autoptr(gchar) app_uri = launcher_app_uri();
  g_autoptr(gchar) object_path = launcher_object_path();
  g_dbus_connection_emit_signal(
      bus, nullptr, object_path, kLauncherInterface, "Update",
      g_variant_new("(s@a{sv})", app_uri, g_variant_builder_end(&builder)),
      nullptr);
}

static void launcher_query(GDBusConnection*,
                           const gchar*,
                           const gchar*,
                           const gchar*,
                           const gchar*,
                           GVariant*,
                           GDBusMethodInvocation* invocation,
                           gpointer user_data) {
  auto* self = static_cast<DesktopPresence*>(user_data);
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  const gboolean visible = self->badge_count > 0;
  g_variant_builder_add(&builder, "{sv}", "count",
                        g_variant_new_int64(self->badge_count));
  g_variant_builder_add(&builder, "{sv}", "count-visible",
                        g_variant_new_boolean(visible));
  g_autoptr(gchar) app_uri = launcher_app_uri();
  g_dbus_method_invocation_return_value(
      invocation,
      g_variant_new("(s@a{sv})", app_uri, g_variant_builder_end(&builder)));
}

static void on_unity_appeared(GDBusConnection*,
                              const gchar*,
                              const gchar*,
                              gpointer user_data) {
  auto* self = static_cast<DesktopPresence*>(user_data);
  ensure_launcher_object(self);
  emit_launcher_update(self);
}

static const GDBusInterfaceVTable kLauncherVtable = {
    launcher_query,
    nullptr,
    nullptr,
    {},
};

static void ensure_launcher_object(DesktopPresence* self) {
  if (self->launcher_registration != 0) {
    return;
  }
  if (self->bus == nullptr) {
    self->bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  }
  GDBusConnection* bus = self->bus;
  if (bus == nullptr) {
    return;
  }
  g_autoptr(GDBusNodeInfo) info = g_dbus_node_info_new_for_xml(
      "<node>"
      "  <interface name='com.canonical.Unity.LauncherEntry'>"
      "    <method name='Query'>"
      "      <arg type='s' name='app_uri' direction='out'/>"
      "      <arg type='a{sv}' name='properties' direction='out'/>"
      "    </method>"
      "    <signal name='Update'>"
      "      <arg type='s' name='app_uri'/>"
      "      <arg type='a{sv}' name='properties'/>"
      "    </signal>"
      "  </interface>"
      "</node>",
      nullptr);
  if (info == nullptr) {
    return;
  }
  g_autoptr(gchar) object_path = launcher_object_path();
  self->launcher_registration = g_dbus_connection_register_object(
      bus, object_path, info->interfaces[0], &kLauncherVtable, self, nullptr,
      nullptr);
}

static void invoke_event(DesktopPresence* self, const char* method) {
  if (self->channel == nullptr) {
    return;
  }
  fl_method_channel_invoke_method(self->channel, method, nullptr, nullptr,
                                  nullptr, nullptr);
}

static void on_show_activate(GtkMenuItem*, gpointer user_data) {
  invoke_event(static_cast<DesktopPresence*>(user_data), "trayShow");
}

static void on_quit_activate(GtkMenuItem*, gpointer user_data) {
  invoke_event(static_cast<DesktopPresence*>(user_data), "trayQuit");
}

static GtkWidget* build_menu(DesktopPresence* self) {
  GtkWidget* menu = gtk_menu_new();
  GtkWidget* show_item = gtk_menu_item_new_with_label("Show " ALERA_APP_NAME);
  GtkWidget* quit_item = gtk_menu_item_new_with_label("Quit");
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), show_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), gtk_separator_menu_item_new());
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit_item);
  g_signal_connect(show_item, "activate", G_CALLBACK(on_show_activate), self);
  g_signal_connect(quit_item, "activate", G_CALLBACK(on_quit_activate), self);
  gtk_widget_show_all(menu);
  self->show_item = show_item;
  return menu;
}

static void set_tray(DesktopPresence* self, bool visible,
                     const gchar* tooltip) {
  if (!visible) {
    if (self->indicator != nullptr) {
      app_indicator_set_status(self->indicator, APP_INDICATOR_STATUS_PASSIVE);
    }
    return;
  }
  if (self->indicator == nullptr) {
    self->menu = build_menu(self);
    self->indicator = app_indicator_new(APPLICATION_ID, "alera",
                                        APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
    app_indicator_set_menu(self->indicator, GTK_MENU(self->menu));
    // Primary click opens the AppIndicator menu. Middle-click / secondary
    // activate runs Show, which is the protocol the indicator actually
    // exposes for a direct show action.
    app_indicator_set_secondary_activate_target(self->indicator,
                                                self->show_item);
  }
  (void)tooltip;
  app_indicator_set_status(self->indicator, APP_INDICATOR_STATUS_ACTIVE);
}

static void method_call_cb(FlMethodChannel*,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  auto* self = static_cast<DesktopPresence*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  if (g_strcmp0(method, "setTray") == 0) {
    bool visible = false;
    const gchar* tooltip = "";
    if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* visible_value = fl_value_lookup_string(args, "visible");
      if (visible_value != nullptr &&
          fl_value_get_type(visible_value) == FL_VALUE_TYPE_BOOL) {
        visible = fl_value_get_bool(visible_value);
      }
      FlValue* tooltip_value = fl_value_lookup_string(args, "tooltip");
      if (tooltip_value != nullptr &&
          fl_value_get_type(tooltip_value) == FL_VALUE_TYPE_STRING) {
        tooltip = fl_value_get_string(tooltip_value);
      }
    }
    set_tray(self, visible, tooltip);
    g_autoptr(FlValue) installed = fl_value_new_bool(TRUE);
    fl_method_call_respond_success(method_call, installed, nullptr);
    return;
  }
  if (g_strcmp0(method, "setBadgeCount") == 0) {
    int count = 0;
    if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* count_value = fl_value_lookup_string(args, "count");
      if (count_value != nullptr) {
        switch (fl_value_get_type(count_value)) {
          case FL_VALUE_TYPE_INT:
            count = static_cast<int>(fl_value_get_int(count_value));
            break;
          default:
            break;
        }
      }
    }
    self->badge_count = count < 0 ? 0 : count;
    ensure_launcher_object(self);
    emit_launcher_update(self);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  if (g_strcmp0(method, "destroy") == 0) {
    set_tray(self, false, "");
    self->badge_count = 0;
    emit_launcher_update(self);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  fl_method_call_respond_not_implemented(method_call, nullptr);
}

DesktopPresence* desktop_presence_new(FlEngine* engine) {
  auto* self = g_new0(DesktopPresence, 1);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                                        kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb, self,
                                            nullptr);
  self->launcher_owner_watch = g_bus_watch_name(
      G_BUS_TYPE_SESSION, "com.canonical.Unity", G_BUS_NAME_WATCHER_FLAGS_NONE,
      on_unity_appeared, nullptr, self, nullptr);
  return self;
}

void desktop_presence_free(DesktopPresence* presence) {
  if (presence == nullptr) {
    return;
  }
  if (presence->launcher_owner_watch != 0) {
    g_bus_unwatch_name(presence->launcher_owner_watch);
  }
  if (presence->bus != nullptr && presence->launcher_registration != 0) {
    g_dbus_connection_unregister_object(presence->bus,
                                        presence->launcher_registration);
  }
  g_clear_object(&presence->bus);
  if (presence->indicator != nullptr) {
    app_indicator_set_status(presence->indicator, APP_INDICATOR_STATUS_PASSIVE);
    g_clear_object(&presence->indicator);
  }
  g_clear_object(&presence->channel);
  g_free(presence);
}
