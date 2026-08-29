#include "desktop_presence.h"

#include <gtk/gtk.h>

#include "appindicator_tray_fallback.h"
#include "status_notifier_item.h"

namespace {

constexpr char kChannelName[] = "dev.leynier.alera/desktop_presence";
constexpr char kLauncherInterface[] = "com.canonical.Unity.LauncherEntry";
// Debug escape hatch: exercise the appindicator path from a desktop that does
// have a StatusNotifierWatcher.
constexpr char kForceFallbackEnv[] = "ALERA_TRAY_FORCE_FALLBACK";

static gchar* launcher_object_path() {
  guint32 hash = g_str_hash(APPLICATION_ID);
  return g_strdup_printf("/com/canonical/unity/launcherentry/%u", hash);
}

}  // namespace

struct _DesktopPresence {
  FlMethodChannel* channel;
  StatusNotifierItem* item;
  AppIndicatorTrayFallback* fallback;
  guint launcher_owner_watch;
  guint status_watcher_watch;
  guint launcher_registration;
  GDBusConnection* bus;
  int badge_count;
  int tray_badge_count;
  gchar* tooltip;
  gboolean tray_visible;
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
  g_autofree gchar* app_uri = launcher_app_uri();
  g_autofree gchar* object_path = launcher_object_path();
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
  g_autofree gchar* app_uri = launcher_app_uri();
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
  g_autofree gchar* object_path = launcher_object_path();
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

static void on_tray_show(gpointer user_data) {
  invoke_event(static_cast<DesktopPresence*>(user_data), "trayShow");
}

static void on_tray_quit(gpointer user_data) {
  invoke_event(static_cast<DesktopPresence*>(user_data), "trayQuit");
}

static gboolean force_fallback() {
  const gchar* value = g_getenv(kForceFallbackEnv);
  return value != nullptr && g_strcmp0(value, "") != 0 &&
         g_strcmp0(value, "0") != 0;
}

static void install_fallback_tray(DesktopPresence* self) {
  if (self->fallback != nullptr) {
    return;
  }
  self->fallback = appindicator_tray_fallback_new(
      "Show " ALERA_APP_NAME, on_tray_show, on_tray_quit, self);
}

// Publishing our own item is what carries the badge, so take it over from the
// fallback as soon as a host shows up.
static gboolean install_own_item(DesktopPresence* self) {
  if (self->item != nullptr) {
    return TRUE;
  }
  StatusNotifierItemCallbacks callbacks = {on_tray_show, on_tray_quit};
  self->item = status_notifier_item_new(ALERA_APP_NAME, callbacks, self);
  if (self->item == nullptr) {
    return FALSE;
  }
  status_notifier_item_set_tooltip(self->item, self->tooltip);
  status_notifier_item_set_badge_count(self->item, self->tray_badge_count);
  if (self->fallback != nullptr) {
    g_clear_pointer(&self->fallback, appindicator_tray_fallback_free);
  }
  return TRUE;
}

static void on_status_watcher_appeared(GDBusConnection*,
                                       const gchar*,
                                       const gchar*,
                                       gpointer user_data) {
  auto* self = static_cast<DesktopPresence*>(user_data);
  if (!self->tray_visible || self->item != nullptr || force_fallback()) {
    return;
  }
  install_own_item(self);
}

static gboolean set_tray(DesktopPresence* self, bool visible,
                         const gchar* tooltip) {
  self->tray_visible = visible;
  g_free(self->tooltip);
  self->tooltip = g_strdup(tooltip);
  if (!visible) {
    status_notifier_item_set_active(self->item, FALSE);
    appindicator_tray_fallback_set_active(self->fallback, FALSE);
    return TRUE;
  }
  if (self->item == nullptr && self->fallback == nullptr) {
    if (!force_fallback() && status_notifier_item_host_available()) {
      install_own_item(self);
    }
    if (self->item == nullptr) {
      install_fallback_tray(self);
    }
    if (self->status_watcher_watch == 0) {
      self->status_watcher_watch = g_bus_watch_name(
          G_BUS_TYPE_SESSION, "org.kde.StatusNotifierWatcher",
          G_BUS_NAME_WATCHER_FLAGS_NONE, on_status_watcher_appeared, nullptr,
          self, nullptr);
    }
  }
  status_notifier_item_set_tooltip(self->item, self->tooltip);
  status_notifier_item_set_active(self->item, TRUE);
  appindicator_tray_fallback_set_active(self->fallback, TRUE);
  return self->item != nullptr || self->fallback != nullptr;
}

static void set_tray_badge_count(DesktopPresence* self, int count) {
  self->tray_badge_count = count < 0 ? 0 : count;
  status_notifier_item_set_badge_count(self->item, self->tray_badge_count);
}

static int lookup_int(FlValue* args, const gchar* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return 0;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return 0;
  }
  return static_cast<int>(fl_value_get_int(value));
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
    set_tray_badge_count(self, lookup_int(args, "badgeCount"));
    const gboolean installed = set_tray(self, visible, tooltip);
    g_autoptr(FlValue) response = fl_value_new_bool(installed);
    fl_method_call_respond_success(method_call, response, nullptr);
    return;
  }
  if (g_strcmp0(method, "setBadgeCount") == 0) {
    const int count = lookup_int(args, "count");
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
  if (presence->status_watcher_watch != 0) {
    g_bus_unwatch_name(presence->status_watcher_watch);
  }
  g_clear_pointer(&presence->item, status_notifier_item_free);
  g_clear_pointer(&presence->fallback, appindicator_tray_fallback_free);
  if (presence->bus != nullptr && presence->launcher_registration != 0) {
    g_dbus_connection_unregister_object(presence->bus,
                                        presence->launcher_registration);
  }
  g_clear_object(&presence->bus);
  g_clear_object(&presence->channel);
  g_clear_pointer(&presence->tooltip, g_free);
  g_free(presence);
}
