#ifndef ALERA_BROWSER_LINUX_BROWSER_STATE_H_
#define ALERA_BROWSER_LINUX_BROWSER_STATE_H_

#include "browser_navigation_state.h"
#include "include/alera_browser/alera_browser_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

typedef struct _LinuxBrowserProfile LinuxBrowserProfile;
typedef struct _LinuxBrowserPage LinuxBrowserPage;
typedef struct _LinuxBrowserDecision LinuxBrowserDecision;

typedef enum {
  LINUX_BROWSER_DECISION_PERMISSION,
  LINUX_BROWSER_DECISION_TLS,
  LINUX_BROWSER_DECISION_POPUP,
  LINUX_BROWSER_DECISION_DOWNLOAD,
} LinuxBrowserDecisionKind;

struct _LinuxBrowserProfile {
  gchar* id;
  gboolean ephemeral;
  gchar* root_path;
  WebKitWebsiteDataManager* data_manager;
  WebKitWebContext* context;
};

struct _LinuxBrowserPage {
  AleraBrowserPlugin* plugin;
  gchar* id;
  gchar* profile_id;
  gchar* opener_page_id;
  WebKitWebView* web_view;
  gboolean transient;
  gboolean adopted;
  gboolean attached;
  gboolean obscured;
  gint frame_x;
  gint frame_y;
  gint frame_width;
  gint frame_height;
  LinuxBrowserNavigationState navigation_state;
  GPtrArray* pending_upload_paths;
};

struct _LinuxBrowserDecision {
  AleraBrowserPlugin* plugin;
  LinuxBrowserDecisionKind kind;
  gchar* id;
  gchar* page_id;
  gchar* transient_page_id;
  gchar* failing_uri;
  GObject* native_request;
  gboolean trusted;
  guint timeout_id;
};

struct _AleraBrowserPlugin {
  GObject parent_instance;
  FlPluginRegistrar* registrar;
  FlMethodChannel* method_channel;
  FlEventChannel* event_channel;
  gboolean event_listening;
  GtkOverlay* overlay;
  GHashTable* profiles;
  GHashTable* pages;
  GHashTable* decisions;
  guint64 next_page_id;
  guint64 next_decision_id;
  gchar* profile_root;
};

FlMethodCodec* browser_method_codec();
FlValue* browser_map_lookup(FlValue* map, const gchar* key);
const gchar* browser_map_string(FlValue* map, const gchar* key);
gboolean browser_map_bool(FlValue* map,
                          const gchar* key,
                          gboolean fallback);
double browser_map_double(FlValue* map,
                          const gchar* key,
                          double fallback);
gint64 browser_map_int(FlValue* map, const gchar* key, gint64 fallback);
FlMethodResponse* browser_success(FlValue* value = nullptr);
FlMethodResponse* browser_error(const gchar* code, const gchar* message);
void browser_respond(FlMethodCall* call, FlMethodResponse* response);
FlValue* browser_event(const gchar* type, const gchar* page_id);
void browser_send_event(AleraBrowserPlugin* plugin, FlValue* event);

LinuxBrowserProfile* browser_profile_create(AleraBrowserPlugin* plugin,
                                            const gchar* id,
                                            gboolean ephemeral,
                                            GError** error);
void browser_profile_destroy(gpointer data);
FlValue* browser_profile_value(LinuxBrowserProfile* profile);
gboolean browser_profile_remove_storage(LinuxBrowserProfile* profile,
                                        GError** error);
void browser_profile_connect_signals(AleraBrowserPlugin* plugin,
                                     LinuxBrowserProfile* profile);

LinuxBrowserPage* browser_page_create(AleraBrowserPlugin* plugin,
                                      const gchar* id,
                                      LinuxBrowserProfile* profile,
                                      LinuxBrowserPage* opener,
                                      gboolean transient,
                                      GError** error);
void browser_page_destroy(gpointer data);
void browser_page_update_visibility(LinuxBrowserPage* page);
void browser_update_flutter_input_region(AleraBrowserPlugin* plugin);
// Exact overlay allocation for WebKitGTK children. Connected once on the
// runner GtkOverlay so preferred-size growth cannot cover Flutter chrome.
gboolean browser_overlay_get_child_position(GtkOverlay* overlay,
                                            GtkWidget* widget,
                                            GdkRectangle* allocation,
                                            gpointer user_data);
void browser_page_connect_signals(LinuxBrowserPage* page);
void browser_page_handle_method(AleraBrowserPlugin* plugin,
                                FlMethodCall* method_call,
                                const gchar* method,
                                FlValue* args);
void browser_profile_handle_method(AleraBrowserPlugin* plugin,
                                   FlMethodCall* method_call,
                                   const gchar* method,
                                   FlValue* args);
void browser_evaluate_javascript(WebKitWebView* web_view,
                                 const gchar* script,
                                 FlMethodCall* method_call);

LinuxBrowserDecision* browser_decision_create(
    AleraBrowserPlugin* plugin,
    LinuxBrowserDecisionKind kind,
    LinuxBrowserPage* page);
void browser_decision_destroy(gpointer data);
void browser_decision_resolve(AleraBrowserPlugin* plugin,
                              FlMethodCall* method_call,
                              FlValue* args);

void browser_cookie_handle_method(AleraBrowserPlugin* plugin,
                                  FlMethodCall* method_call,
                                  const gchar* method,
                                  FlValue* args);
void browser_capture_handle_method(AleraBrowserPlugin* plugin,
                                   FlMethodCall* method_call,
                                   const gchar* method,
                                   FlValue* args);
void browser_import_handle_method(AleraBrowserPlugin* plugin,
                                  FlMethodCall* method_call,
                                  const gchar* method,
                                  FlValue* args);
void browser_handle_method_call(AleraBrowserPlugin* plugin,
                                FlMethodCall* method_call);

#endif
