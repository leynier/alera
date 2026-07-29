#include "browser_state.h"

#include <cstring>

#define ALERA_BROWSER_PLUGIN(obj)                                      \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), alera_browser_plugin_get_type(), \
                              AleraBrowserPlugin))

G_DEFINE_TYPE(AleraBrowserPlugin, alera_browser_plugin, g_object_get_type())

static FlMethodErrorResponse* event_listen_cb(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  ALERA_BROWSER_PLUGIN(user_data)->event_listening = TRUE;
  return nullptr;
}

static FlMethodErrorResponse* event_cancel_cb(FlEventChannel* channel,
                                              FlValue* args,
                                              gpointer user_data) {
  ALERA_BROWSER_PLUGIN(user_data)->event_listening = FALSE;
  return nullptr;
}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  browser_handle_method_call(ALERA_BROWSER_PLUGIN(user_data), method_call);
}

static void alera_browser_plugin_dispose(GObject* object) {
  AleraBrowserPlugin* self = ALERA_BROWSER_PLUGIN(object);
  if (self->decisions != nullptr) {
    g_hash_table_destroy(self->decisions);
    self->decisions = nullptr;
  }
  if (self->pages != nullptr) {
    g_hash_table_destroy(self->pages);
    self->pages = nullptr;
  }
  if (self->profiles != nullptr) {
    g_hash_table_destroy(self->profiles);
    self->profiles = nullptr;
  }
  g_clear_object(&self->method_channel);
  g_clear_object(&self->event_channel);
  g_clear_object(&self->registrar);
  g_clear_pointer(&self->profile_root, g_free);
  G_OBJECT_CLASS(alera_browser_plugin_parent_class)->dispose(object);
}

static void alera_browser_plugin_class_init(AleraBrowserPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = alera_browser_plugin_dispose;
}

static void alera_browser_plugin_init(AleraBrowserPlugin* self) {
  self->next_page_id = 1;
  self->next_decision_id = 1;
  self->profiles = g_hash_table_new_full(
      g_str_hash, g_str_equal, g_free, browser_profile_destroy);
  self->pages = g_hash_table_new_full(
      g_str_hash, g_str_equal, g_free, browser_page_destroy);
  self->decisions = g_hash_table_new_full(
      g_str_hash, g_str_equal, g_free, browser_decision_destroy);
}

static void install_persistent_profiles(AleraBrowserPlugin* plugin) {
  g_autoptr(GError) directory_error = nullptr;
  g_autoptr(GDir) directory =
      g_dir_open(plugin->profile_root, 0, &directory_error);
  if (directory == nullptr) {
    g_warning("Failed to inspect browser profiles: %s",
              directory_error != nullptr ? directory_error->message
                                         : "unknown error");
    return;
  }
  while (const gchar* id = g_dir_read_name(directory)) {
    if (g_str_equal(id, "default")) {
      continue;
    }
    g_autofree gchar* path =
        g_build_filename(plugin->profile_root, id, nullptr);
    if (!g_file_test(path, G_FILE_TEST_IS_DIR)) {
      continue;
    }
    GError* profile_error = nullptr;
    LinuxBrowserProfile* profile =
        browser_profile_create(plugin, id, FALSE, &profile_error);
    if (profile == nullptr) {
      g_warning("Failed to restore browser profile %s: %s", id,
                profile_error != nullptr ? profile_error->message
                                         : "unknown error");
      g_clear_error(&profile_error);
      continue;
    }
    g_hash_table_insert(plugin->profiles, g_strdup(id), profile);
  }
}

void alera_browser_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  AleraBrowserPlugin* plugin = ALERA_BROWSER_PLUGIN(
      g_object_new(alera_browser_plugin_get_type(), nullptr));
  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));

  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view != nullptr) {
    GtkWidget* parent = gtk_widget_get_parent(GTK_WIDGET(view));
    if (parent != nullptr && GTK_IS_OVERLAY(parent)) {
      plugin->overlay = GTK_OVERLAY(parent);
      // Hard-allocate browser pages to the Flutter-reported frame. Without
      // this, WebKitGTK's preferred size grows across the overlay and covers
      // the right sidebar and status bar.
      g_signal_connect(plugin->overlay, "get-child-position",
                       G_CALLBACK(browser_overlay_get_child_position), plugin);
    }
  }

  GApplication* application = g_application_get_default();
  const gchar* application_id = application != nullptr
                                    ? g_application_get_application_id(application)
                                    : nullptr;
  plugin->profile_root = g_build_filename(
      g_get_user_data_dir(),
      application_id != nullptr ? application_id : "dev.leynier.alera",
      "browser", "profiles", nullptr);

  GError* profile_error = nullptr;
  LinuxBrowserProfile* default_profile =
      browser_profile_create(plugin, "default", FALSE, &profile_error);
  if (default_profile != nullptr) {
    g_hash_table_insert(plugin->profiles, g_strdup("default"), default_profile);
    install_persistent_profiles(plugin);
  } else {
    g_warning("Failed to create default browser profile: %s",
              profile_error != nullptr ? profile_error->message : "unknown");
  }
  g_clear_error(&profile_error);

  plugin->method_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "dev.leynier.alera/browser", browser_method_codec());
  fl_method_channel_set_method_call_handler(
      plugin->method_channel, method_call_cb, g_object_ref(plugin),
      g_object_unref);

  plugin->event_channel = fl_event_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "dev.leynier.alera/browser/events", browser_method_codec());
  fl_event_channel_set_stream_handlers(
      plugin->event_channel, event_listen_cb, event_cancel_cb,
      g_object_ref(plugin), g_object_unref);
  g_object_unref(plugin);
}
