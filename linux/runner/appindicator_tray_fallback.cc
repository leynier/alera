#include "appindicator_tray_fallback.h"

#include <gtk/gtk.h>

#include <libayatana-appindicator/app-indicator.h>

namespace {

constexpr char kStatusNotifierInterface[] = "org.kde.StatusNotifierItem";
constexpr char kIconName[] = "alera";

}  // namespace

struct _AppIndicatorTrayFallback {
  AppIndicator* indicator;
  GtkWidget* menu;
  GtkWidget* show_item;
  GDBusConnection* bus;
  guint activate_filter;
  AppIndicatorTrayCallback on_show;
  AppIndicatorTrayCallback on_quit;
  gpointer user_data;
};

// libayatana-appindicator's StatusNotifierItem exports no Activate method, so a
// host that maps the primary click to it (Plasma, the GNOME AppIndicator
// extension) sees that call fail and opens the context menu instead, which made
// left and right click behave the same. The object belongs to the library, so
// answering Activate from a filter on the shared session bus is the only place
// left to add it.
struct TrayActivateRelay {
  GMutex lock;
  AppIndicatorTrayFallback* tray;
  guint pending_show;
};

// Statically allocated so a filter still running on the GDBus worker thread
// during teardown can never reach freed memory; the tray pointer is what is
// cleared instead.
static TrayActivateRelay tray_activate_relay = {};

static void on_show_activate(GtkMenuItem*, gpointer user_data) {
  auto* self = static_cast<AppIndicatorTrayFallback*>(user_data);
  if (self->on_show != nullptr) {
    self->on_show(self->user_data);
  }
}

static void on_quit_activate(GtkMenuItem*, gpointer user_data) {
  auto* self = static_cast<AppIndicatorTrayFallback*>(user_data);
  if (self->on_quit != nullptr) {
    self->on_quit(self->user_data);
  }
}

static gboolean deliver_tray_show(gpointer user_data) {
  auto* relay = static_cast<TrayActivateRelay*>(user_data);
  g_mutex_lock(&relay->lock);
  relay->pending_show = 0;
  AppIndicatorTrayFallback* tray = relay->tray;
  g_mutex_unlock(&relay->lock);
  if (tray != nullptr && tray->on_show != nullptr) {
    tray->on_show(tray->user_data);
  }
  return G_SOURCE_REMOVE;
}

static GDBusMessage* activate_filter(GDBusConnection* connection,
                                     GDBusMessage* message,
                                     gboolean incoming,
                                     gpointer user_data) {
  if (!incoming ||
      g_dbus_message_get_message_type(message) !=
          G_DBUS_MESSAGE_TYPE_METHOD_CALL ||
      g_strcmp0(g_dbus_message_get_interface(message),
                kStatusNotifierInterface) != 0 ||
      g_strcmp0(g_dbus_message_get_member(message), "Activate") != 0) {
    return message;
  }
  if ((g_dbus_message_get_flags(message) &
       G_DBUS_MESSAGE_FLAGS_NO_REPLY_EXPECTED) == 0) {
    g_autoptr(GDBusMessage) reply = g_dbus_message_new_method_reply(message);
    g_dbus_connection_send_message(connection, reply,
                                   G_DBUS_SEND_MESSAGE_FLAGS_NONE, nullptr,
                                   nullptr);
  }
  // Filters run on the GDBus worker thread and the callback ends up on the
  // Flutter method channel, which may only be touched from the main loop.
  auto* relay = static_cast<TrayActivateRelay*>(user_data);
  g_mutex_lock(&relay->lock);
  if (relay->pending_show == 0) {
    relay->pending_show = g_idle_add(deliver_tray_show, relay);
  }
  g_mutex_unlock(&relay->lock);
  g_object_unref(message);
  return nullptr;
}

static void install_activate_filter(AppIndicatorTrayFallback* self) {
  if (self->activate_filter != 0) {
    return;
  }
  self->bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (self->bus == nullptr) {
    return;
  }
  g_mutex_lock(&tray_activate_relay.lock);
  tray_activate_relay.tray = self;
  g_mutex_unlock(&tray_activate_relay.lock);
  self->activate_filter = g_dbus_connection_add_filter(
      self->bus, activate_filter, &tray_activate_relay, nullptr);
}

static GtkWidget* build_menu(AppIndicatorTrayFallback* self,
                             const gchar* show_label) {
  GtkWidget* menu = gtk_menu_new();
  GtkWidget* show_item = gtk_menu_item_new_with_label(show_label);
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

AppIndicatorTrayFallback* appindicator_tray_fallback_new(
    const gchar* show_label,
    AppIndicatorTrayCallback on_show,
    AppIndicatorTrayCallback on_quit,
    gpointer user_data) {
  auto* self = g_new0(AppIndicatorTrayFallback, 1);
  self->on_show = on_show;
  self->on_quit = on_quit;
  self->user_data = user_data;
  self->menu = build_menu(self, show_label);
  // libayatana-appindicator 0.5.94 deprecates both constructors without
  // naming a replacement, and the runner builds with -Werror. Ubuntu 24.04
  // ships an older header, so this only bites on newer distros.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
  self->indicator = app_indicator_new(APPLICATION_ID, kIconName,
                                      APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
#pragma GCC diagnostic pop
  app_indicator_set_menu(self->indicator, GTK_MENU(self->menu));
  // Middle-click / secondary activate also runs Show; primary click is
  // answered by activate_filter.
  app_indicator_set_secondary_activate_target(self->indicator,
                                              self->show_item);
  install_activate_filter(self);
  app_indicator_set_status(self->indicator, APP_INDICATOR_STATUS_ACTIVE);
  return self;
}

void appindicator_tray_fallback_set_active(AppIndicatorTrayFallback* tray,
                                           gboolean active) {
  if (tray == nullptr || tray->indicator == nullptr) {
    return;
  }
  app_indicator_set_status(tray->indicator, active
                                                ? APP_INDICATOR_STATUS_ACTIVE
                                                : APP_INDICATOR_STATUS_PASSIVE);
}

void appindicator_tray_fallback_free(AppIndicatorTrayFallback* tray) {
  if (tray == nullptr) {
    return;
  }
  if (tray->activate_filter != 0 && tray->bus != nullptr) {
    g_dbus_connection_remove_filter(tray->bus, tray->activate_filter);
    tray->activate_filter = 0;
  }
  g_mutex_lock(&tray_activate_relay.lock);
  if (tray_activate_relay.tray == tray) {
    tray_activate_relay.tray = nullptr;
  }
  if (tray_activate_relay.pending_show != 0) {
    g_source_remove(tray_activate_relay.pending_show);
    tray_activate_relay.pending_show = 0;
  }
  g_mutex_unlock(&tray_activate_relay.lock);
  if (tray->indicator != nullptr) {
    app_indicator_set_status(tray->indicator, APP_INDICATOR_STATUS_PASSIVE);
    g_clear_object(&tray->indicator);
  }
  g_clear_object(&tray->bus);
  g_free(tray);
}
