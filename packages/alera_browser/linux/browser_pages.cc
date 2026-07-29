#include "browser_state.h"

#include "browser_overlay_allocation.h"

namespace {

GQuark page_error_quark() {
  return g_quark_from_static_string("alera-browser-page-error");
}

void add_page_to_overlay(AleraBrowserPlugin* plugin, LinuxBrowserPage* page) {
  GtkWidget* widget = GTK_WIDGET(page->web_view);
  gtk_widget_set_halign(widget, GTK_ALIGN_START);
  gtk_widget_set_valign(widget, GTK_ALIGN_START);
  gtk_widget_set_hexpand(widget, FALSE);
  gtk_widget_set_vexpand(widget, FALSE);
  gtk_widget_set_can_focus(widget, TRUE);
  gtk_widget_set_sensitive(widget, FALSE);
  // Position comes only from get-child-position; margins must stay zero so the
  // hard allocation is not double-offset.
  gtk_widget_set_margin_start(widget, 0);
  gtk_widget_set_margin_top(widget, 0);
  gtk_widget_set_margin_end(widget, 0);
  gtk_widget_set_margin_bottom(widget, 0);
  gtk_widget_set_size_request(widget, 1, 1);
  gtk_overlay_add_overlay(plugin->overlay, widget);
  gtk_overlay_set_overlay_pass_through(plugin->overlay, widget, FALSE);
  gtk_widget_hide(widget);
}

}  // namespace

LinuxBrowserPage* browser_page_create(AleraBrowserPlugin* plugin,
                                      const gchar* id,
                                      LinuxBrowserProfile* profile,
                                      LinuxBrowserPage* opener,
                                      gboolean transient,
                                      GError** error) {
  if (plugin->overlay == nullptr) {
    g_set_error(error, page_error_quark(), 1,
                "The Flutter view is not hosted by a GtkOverlay.");
    return nullptr;
  }
  if (id == nullptr || *id == '\0' ||
      g_hash_table_contains(plugin->pages, id)) {
    g_set_error(error, page_error_quark(), 2,
                "The browser page id is empty or already exists.");
    return nullptr;
  }
  if (opener != nullptr && g_strcmp0(opener->profile_id, profile->id) != 0) {
    g_set_error(error, page_error_quark(), 3,
                "Popup opener and child must share one profile.");
    return nullptr;
  }

  LinuxBrowserPage* page = g_new0(LinuxBrowserPage, 1);
  page->plugin = plugin;
  page->id = g_strdup(id);
  page->profile_id = g_strdup(profile->id);
  page->opener_page_id = opener != nullptr ? g_strdup(opener->id) : nullptr;
  page->transient = transient;
  page->adopted = !transient;
  page->pending_upload_paths =
      g_ptr_array_new_with_free_func(static_cast<GDestroyNotify>(g_free));
  page->web_view = WEBKIT_WEB_VIEW(
      opener != nullptr
          ? webkit_web_view_new_with_related_view(opener->web_view)
          : webkit_web_view_new_with_context(profile->context));
  g_object_ref_sink(page->web_view);
  g_object_set_data(G_OBJECT(page->web_view), "alera-browser-page", page);

  WebKitSettings* settings = webkit_web_view_get_settings(page->web_view);
  webkit_settings_set_enable_javascript(settings, TRUE);
  webkit_settings_set_javascript_can_open_windows_automatically(settings,
                                                                FALSE);
  webkit_settings_set_enable_developer_extras(settings, TRUE);

  add_page_to_overlay(plugin, page);
  browser_page_connect_signals(page);
  return page;
}

void browser_page_destroy(gpointer data) {
  LinuxBrowserPage* page = static_cast<LinuxBrowserPage*>(data);
  if (page == nullptr) {
    return;
  }
  if (page->web_view != nullptr) {
    g_object_set_data(G_OBJECT(page->web_view), "alera-browser-page", nullptr);
    gtk_widget_destroy(GTK_WIDGET(page->web_view));
    g_object_unref(page->web_view);
  }
  if (page->pending_upload_paths != nullptr) {
    g_ptr_array_unref(page->pending_upload_paths);
  }
  g_clear_pointer(&page->id, g_free);
  g_clear_pointer(&page->profile_id, g_free);
  g_clear_pointer(&page->opener_page_id, g_free);
  g_free(page);
}

gboolean browser_overlay_get_child_position(GtkOverlay* overlay,
                                            GtkWidget* widget,
                                            GdkRectangle* allocation,
                                            gpointer user_data) {
  (void)overlay;
  (void)user_data;
  LinuxBrowserPage* page = static_cast<LinuxBrowserPage*>(
      g_object_get_data(G_OBJECT(widget), "alera-browser-page"));
  if (page == nullptr || allocation == nullptr) {
    return FALSE;
  }
  BrowserOverlayAllocation frame{};
  if (!browser_page_fill_overlay_allocation(page->frame_x, page->frame_y,
                                            page->frame_width,
                                            page->frame_height, &frame)) {
    return FALSE;
  }
  allocation->x = frame.x;
  allocation->y = frame.y;
  allocation->width = frame.width;
  allocation->height = frame.height;
  return TRUE;
}

void browser_page_update_visibility(LinuxBrowserPage* page) {
  GtkWidget* widget = GTK_WIDGET(page->web_view);
  const gboolean visible =
      page->attached && !page->obscured && page->frame_width > 0 &&
      page->frame_height > 0;
  // Origin is applied only by get-child-position; keep margins zero.
  gtk_widget_set_margin_start(widget, 0);
  gtk_widget_set_margin_top(widget, 0);
  gtk_widget_set_margin_end(widget, 0);
  gtk_widget_set_margin_bottom(widget, 0);
  gtk_widget_set_size_request(
      widget, MAX(page->frame_width, 1), MAX(page->frame_height, 1));
  gtk_widget_set_sensitive(widget, visible);
  if (visible) {
    gtk_widget_show(widget);
  } else {
    gtk_widget_hide(widget);
  }
  // Force GtkOverlay to re-query get-child-position after frame changes.
  gtk_widget_queue_resize(widget);
  browser_update_flutter_input_region(page->plugin);
}

void browser_update_flutter_input_region(AleraBrowserPlugin* plugin) {
  // GtkOverlay owns input stacking. Shaping its parent also clips WebKit's
  // child windows and makes the browser surface non-interactive.
  if (plugin->overlay != nullptr) {
    gtk_widget_queue_draw(GTK_WIDGET(plugin->overlay));
  }
}
