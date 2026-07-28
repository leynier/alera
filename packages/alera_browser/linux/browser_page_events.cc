#include "browser_state.h"

namespace {

struct DownloadState {
  AleraBrowserPlugin* plugin;
  gchar* id;
  gchar* page_id;
  gchar* suggested_file_name;
  gchar* destination_path;
  guint64 received_bytes;
  gint64 total_bytes;
  gboolean has_total_bytes;
  gboolean terminal;
};

void download_state_free(gpointer data) {
  DownloadState* state = static_cast<DownloadState*>(data);
  if (state == nullptr) {
    return;
  }
  g_clear_pointer(&state->id, g_free);
  g_clear_pointer(&state->page_id, g_free);
  g_clear_pointer(&state->suggested_file_name, g_free);
  g_clear_pointer(&state->destination_path, g_free);
  g_free(state);
}

void emit_download_changed(DownloadState* state,
                           const gchar* status,
                           const gchar* error_code = nullptr) {
  FlValue* event = browser_event("downloadChanged", state->page_id);
  fl_value_set_string_take(
      event, "downloadId", fl_value_new_string(state->id));
  fl_value_set_string_take(
      event, "state", fl_value_new_string(status));
  fl_value_set_string_take(
      event, "receivedBytes",
      fl_value_new_int(static_cast<gint64>(MIN(
          state->received_bytes, static_cast<guint64>(G_MAXINT64)))));
  if (state->has_total_bytes) {
    fl_value_set_string_take(
        event, "totalBytes", fl_value_new_int(state->total_bytes));
  }
  if (state->suggested_file_name != nullptr) {
    fl_value_set_string_take(
        event, "suggestedFileName",
        fl_value_new_string(state->suggested_file_name));
  }
  if (state->destination_path != nullptr) {
    fl_value_set_string_take(
        event, "destinationPath",
        fl_value_new_string(state->destination_path));
  }
  if (error_code != nullptr) {
    fl_value_set_string_take(
        event, "errorCode", fl_value_new_string(error_code));
  }
  browser_send_event(state->plugin, event);
}

void download_created_destination_cb(WebKitDownload* download,
                                     const gchar* destination,
                                     gpointer user_data) {
  DownloadState* state = static_cast<DownloadState*>(user_data);
  g_clear_pointer(&state->destination_path, g_free);
  state->destination_path = g_filename_from_uri(destination, nullptr, nullptr);
  if (state->destination_path == nullptr &&
      g_path_is_absolute(destination)) {
    state->destination_path = g_strdup(destination);
  }
  if (!state->terminal) {
    emit_download_changed(state, "inProgress");
  }
}

void download_received_data_cb(WebKitDownload* download,
                               guint64 data_length,
                               gpointer user_data) {
  DownloadState* state = static_cast<DownloadState*>(user_data);
  if (state->terminal) {
    return;
  }
  state->received_bytes =
      data_length > G_MAXUINT64 - state->received_bytes
          ? G_MAXUINT64
          : state->received_bytes + data_length;
  emit_download_changed(state, "inProgress");
}

void download_failed_cb(WebKitDownload* download,
                        GError* error,
                        gpointer user_data) {
  DownloadState* state = static_cast<DownloadState*>(user_data);
  if (state->terminal) {
    return;
  }
  state->terminal = TRUE;
  const gboolean cancelled =
      error != nullptr && error->domain == WEBKIT_DOWNLOAD_ERROR &&
      error->code == WEBKIT_DOWNLOAD_ERROR_CANCELLED_BY_USER;
  const gchar* error_code = "download_failed";
  if (cancelled) {
    error_code = "cancelled_by_user";
  } else if (error != nullptr && error->domain == WEBKIT_DOWNLOAD_ERROR) {
    error_code =
        error->code == WEBKIT_DOWNLOAD_ERROR_NETWORK
            ? "network_error"
            : error->code == WEBKIT_DOWNLOAD_ERROR_DESTINATION
                  ? "destination_error"
                  : "download_failed";
  }
  emit_download_changed(
      state, cancelled ? "cancelled" : "failed", error_code);
}

void download_finished_cb(WebKitDownload* download, gpointer user_data) {
  DownloadState* state = static_cast<DownloadState*>(user_data);
  if (!state->terminal) {
    state->terminal = TRUE;
    emit_download_changed(state, "completed");
  }
}

gchar* current_page_origin(WebKitWebView* web_view) {
  const gchar* current_uri = webkit_web_view_get_uri(web_view);
  if (current_uri == nullptr) {
    return nullptr;
  }
  g_autoptr(GUri) uri =
      g_uri_parse(current_uri, G_URI_FLAGS_NONE, nullptr);
  const gchar* scheme = uri != nullptr ? g_uri_get_scheme(uri) : nullptr;
  const gchar* host = uri != nullptr ? g_uri_get_host(uri) : nullptr;
  if (scheme == nullptr || host == nullptr) {
    return nullptr;
  }
  return g_uri_join(
      G_URI_FLAGS_NONE, scheme, nullptr, host, g_uri_get_port(uri), "",
      nullptr, nullptr);
}

void emit_load_failure(LinuxBrowserPage* page,
                       const gchar* failing_uri,
                       const gchar* description) {
  linux_browser_navigation_failed(&page->navigation_state);
  FlValue* event = browser_event("loadFailed", page->id);
  fl_value_set_string_take(
      event, "url",
      fl_value_new_string(failing_uri != nullptr ? failing_uri : ""));
  fl_value_set_string_take(
      event, "description", fl_value_new_string(description));
  browser_send_event(page->plugin, event);
}

void load_changed_cb(WebKitWebView* web_view,
                     WebKitLoadEvent load_event,
                     gpointer user_data) {
  LinuxBrowserPage* page = static_cast<LinuxBrowserPage*>(user_data);
  const gchar* uri = webkit_web_view_get_uri(web_view);
  if (load_event == WEBKIT_LOAD_STARTED) {
    linux_browser_navigation_started(&page->navigation_state);
    FlValue* event = browser_event("navigationStarted", page->id);
    fl_value_set_string_take(
        event, "url", fl_value_new_string(uri != nullptr ? uri : ""));
    browser_send_event(page->plugin, event);
  } else if (load_event == WEBKIT_LOAD_COMMITTED) {
    FlValue* event = browser_event("navigationCommitted", page->id);
    fl_value_set_string_take(
        event, "url", fl_value_new_string(uri != nullptr ? uri : ""));
    browser_send_event(page->plugin, event);
  } else if (load_event == WEBKIT_LOAD_FINISHED) {
    if (!linux_browser_navigation_should_finish(&page->navigation_state)) {
      return;
    }
    FlValue* event = browser_event("navigationFinished", page->id);
    fl_value_set_string_take(
        event, "url", fl_value_new_string(uri != nullptr ? uri : ""));
    const gchar* title = webkit_web_view_get_title(web_view);
    if (title != nullptr) {
      fl_value_set_string_take(event, "title", fl_value_new_string(title));
    }
    fl_value_set_string_take(
        event, "canGoBack",
        fl_value_new_bool(webkit_web_view_can_go_back(web_view)));
    fl_value_set_string_take(
        event, "canGoForward",
        fl_value_new_bool(webkit_web_view_can_go_forward(web_view)));
    browser_send_event(page->plugin, event);
  }
}

void progress_changed_cb(WebKitWebView* web_view,
                         GParamSpec* spec,
                         gpointer user_data) {
  LinuxBrowserPage* page = static_cast<LinuxBrowserPage*>(user_data);
  FlValue* event = browser_event("progress", page->id);
  fl_value_set_string_take(
      event, "progress",
      fl_value_new_float(
          webkit_web_view_get_estimated_load_progress(web_view)));
  browser_send_event(page->plugin, event);
}

void uri_changed_cb(WebKitWebView* web_view,
                    GParamSpec* spec,
                    gpointer user_data) {
  LinuxBrowserPage* page = static_cast<LinuxBrowserPage*>(user_data);
  const gchar* uri = webkit_web_view_get_uri(web_view);
  if (uri == nullptr) {
    return;
  }
  FlValue* event = browser_event("urlChanged", page->id);
  fl_value_set_string_take(event, "url", fl_value_new_string(uri));
  browser_send_event(page->plugin, event);
}

gboolean load_failed_cb(WebKitWebView* web_view,
                        WebKitLoadEvent load_event,
                        const gchar* failing_uri,
                        GError* error,
                        gpointer user_data) {
  LinuxBrowserPage* page = static_cast<LinuxBrowserPage*>(user_data);
  emit_load_failure(
      page, failing_uri, error != nullptr ? error->message : "Load failed.");
  return FALSE;
}

gboolean permission_request_cb(WebKitWebView* web_view,
                               WebKitPermissionRequest* request,
                               gpointer user_data) {
  LinuxBrowserPage* page = static_cast<LinuxBrowserPage*>(user_data);
  if (!page->plugin->event_listening) {
    webkit_permission_request_deny(request);
    return TRUE;
  }
  if (WEBKIT_IS_USER_MEDIA_PERMISSION_REQUEST(request) &&
      webkit_user_media_permission_is_for_display_device(
          WEBKIT_USER_MEDIA_PERMISSION_REQUEST(request))) {
    webkit_permission_request_deny(request);
    return TRUE;
  }
  const gboolean supported =
      WEBKIT_IS_GEOLOCATION_PERMISSION_REQUEST(request) ||
      WEBKIT_IS_USER_MEDIA_PERMISSION_REQUEST(request) ||
      WEBKIT_IS_NOTIFICATION_PERMISSION_REQUEST(request);
  if (!supported) {
    webkit_permission_request_deny(request);
    return TRUE;
  }
  LinuxBrowserDecision* decision = browser_decision_create(
      page->plugin, LINUX_BROWSER_DECISION_PERMISSION, page);
  decision->native_request = G_OBJECT(g_object_ref(request));
  FlValue* event = browser_event("permissionRequest", page->id);
  fl_value_set_string_take(
      event, "decisionId", fl_value_new_string(decision->id));
  g_autofree gchar* origin = current_page_origin(web_view);
  if (origin != nullptr) {
    fl_value_set_string_take(
        event, "origin", fl_value_new_string(origin));
  }
  FlValue* resources = fl_value_new_list();
  if (WEBKIT_IS_GEOLOCATION_PERMISSION_REQUEST(request)) {
    fl_value_append_take(resources, fl_value_new_string("geolocation"));
  } else if (WEBKIT_IS_USER_MEDIA_PERMISSION_REQUEST(request)) {
    WebKitUserMediaPermissionRequest* media =
        WEBKIT_USER_MEDIA_PERMISSION_REQUEST(request);
    if (webkit_user_media_permission_is_for_video_device(media)) {
      fl_value_append_take(resources, fl_value_new_string("camera"));
    }
    if (webkit_user_media_permission_is_for_audio_device(media)) {
      fl_value_append_take(resources, fl_value_new_string("microphone"));
    }
  } else if (WEBKIT_IS_NOTIFICATION_PERMISSION_REQUEST(request)) {
    fl_value_append_take(resources, fl_value_new_string("notifications"));
  }
  fl_value_set_string_take(event, "resources", resources);
  browser_send_event(page->plugin, event);
  return TRUE;
}

gboolean tls_failed_cb(WebKitWebView* web_view,
                       const gchar* failing_uri,
                       GTlsCertificate* certificate,
                       GTlsCertificateFlags errors,
                       gpointer user_data) {
  LinuxBrowserPage* page = static_cast<LinuxBrowserPage*>(user_data);
  emit_load_failure(
      page, failing_uri,
      "WebKitGTK rejected the TLS certificate and cannot scope an "
      "exception to one tab.");
  return TRUE;
}

GtkWidget* create_web_view_cb(WebKitWebView* web_view,
                              WebKitNavigationAction* navigation_action,
                              gpointer user_data) {
  LinuxBrowserPage* opener = static_cast<LinuxBrowserPage*>(user_data);
  AleraBrowserPlugin* plugin = opener->plugin;
  if (!plugin->event_listening) {
    return nullptr;
  }
  LinuxBrowserProfile* profile = static_cast<LinuxBrowserProfile*>(
      g_hash_table_lookup(plugin->profiles, opener->profile_id));
  g_autofree gchar* page_id = g_strdup_printf(
      "popup-%" G_GUINT64_FORMAT, plugin->next_page_id++);
  GError* error = nullptr;
  LinuxBrowserPage* child = browser_page_create(
      plugin, page_id, profile, opener, TRUE, &error);
  if (child == nullptr) {
    g_warning("Failed to create popup page: %s",
              error != nullptr ? error->message : "unknown");
    g_clear_error(&error);
    return nullptr;
  }
  g_hash_table_insert(plugin->pages, g_strdup(child->id), child);

  LinuxBrowserDecision* decision = browser_decision_create(
      plugin, LINUX_BROWSER_DECISION_POPUP, opener);
  decision->transient_page_id = g_strdup(child->id);
  decision->trusted =
      webkit_navigation_action_is_user_gesture(navigation_action);
  WebKitURIRequest* request =
      webkit_navigation_action_get_request(navigation_action);
  const gchar* request_uri =
      request != nullptr ? webkit_uri_request_get_uri(request) : nullptr;
  FlValue* event = browser_event("popupRequest", opener->id);
  fl_value_set_string_take(
      event, "decisionId", fl_value_new_string(decision->id));
  fl_value_set_string_take(
      event, "transientPageId", fl_value_new_string(child->id));
  fl_value_set_string_take(
      event, "profileId", fl_value_new_string(child->profile_id));
  fl_value_set_string_take(
      event, "url",
      fl_value_new_string(request_uri != nullptr ? request_uri : "about:blank"));
  fl_value_set_string_take(
      event, "userInitiated",
      fl_value_new_bool(
          webkit_navigation_action_is_user_gesture(navigation_action)));
  fl_value_set_string_take(
      event, "trusted",
      fl_value_new_bool(
          webkit_navigation_action_is_user_gesture(navigation_action)));
  fl_value_set_string_take(event, "requiresOpener", fl_value_new_bool(TRUE));
  const gchar* frame_name =
      webkit_navigation_action_get_frame_name(navigation_action);
  if (frame_name != nullptr) {
    fl_value_set_string_take(
        event, "windowName", fl_value_new_string(frame_name));
  }
  browser_send_event(plugin, event);
  return GTK_WIDGET(child->web_view);
}

gboolean file_chooser_cb(WebKitWebView* web_view,
                         WebKitFileChooserRequest* request,
                         gpointer user_data) {
  LinuxBrowserPage* page = static_cast<LinuxBrowserPage*>(user_data);
  if (page->pending_upload_paths->len == 0) {
    webkit_file_chooser_request_cancel(request);
    return TRUE;
  }
  const gchar** files = g_new0(
      const gchar*, page->pending_upload_paths->len + 1);
  for (guint index = 0; index < page->pending_upload_paths->len; index++) {
    files[index] =
        static_cast<const gchar*>(g_ptr_array_index(
            page->pending_upload_paths, index));
  }
  webkit_file_chooser_request_select_files(request, files);
  g_free(files);
  g_ptr_array_set_size(page->pending_upload_paths, 0);
  return TRUE;
}

gboolean download_decide_destination_cb(WebKitDownload* download,
                                        const gchar* suggested_filename,
                                        gpointer user_data) {
  AleraBrowserPlugin* plugin =
      static_cast<AleraBrowserPlugin*>(user_data);
  WebKitWebView* web_view = webkit_download_get_web_view(download);
  LinuxBrowserPage* page =
      web_view != nullptr
          ? static_cast<LinuxBrowserPage*>(
                g_object_get_data(G_OBJECT(web_view), "alera-browser-page"))
          : nullptr;
  if (page == nullptr || !plugin->event_listening) {
    webkit_download_cancel(download);
    return TRUE;
  }
  LinuxBrowserDecision* decision = browser_decision_create(
      plugin, LINUX_BROWSER_DECISION_DOWNLOAD, page);
  decision->native_request = G_OBJECT(g_object_ref(download));

  WebKitURIRequest* request = webkit_download_get_request(download);
  WebKitURIResponse* response = webkit_download_get_response(download);
  DownloadState* state = g_new0(DownloadState, 1);
  state->plugin = plugin;
  state->id = g_strdup(decision->id);
  state->page_id = g_strdup(page->id);
  state->suggested_file_name =
      g_strdup(suggested_filename != nullptr ? suggested_filename : "download");
  if (response != nullptr) {
    const guint64 content_length =
        webkit_uri_response_get_content_length(response);
    if (content_length > 0 &&
        content_length <= static_cast<guint64>(G_MAXINT64)) {
      state->total_bytes = static_cast<gint64>(content_length);
      state->has_total_bytes = TRUE;
    }
  }
  g_object_set_data_full(
      G_OBJECT(download), "alera-download-state", state,
      download_state_free);
  g_signal_connect(
      download, "created-destination",
      G_CALLBACK(download_created_destination_cb), state);
  g_signal_connect(
      download, "received-data", G_CALLBACK(download_received_data_cb), state);
  g_signal_connect(
      download, "failed", G_CALLBACK(download_failed_cb), state);
  g_signal_connect(
      download, "finished", G_CALLBACK(download_finished_cb), state);

  FlValue* event = browser_event("downloadRequest", page->id);
  fl_value_set_string_take(
      event, "decisionId", fl_value_new_string(decision->id));
  fl_value_set_string_take(
      event, "downloadId", fl_value_new_string(decision->id));
  fl_value_set_string_take(
      event, "url",
      fl_value_new_string(
          request != nullptr ? webkit_uri_request_get_uri(request) : ""));
  fl_value_set_string_take(
      event, "suggestedFileName",
      fl_value_new_string(suggested_filename != nullptr
                              ? suggested_filename
                              : "download"));
  if (response != nullptr) {
    const gchar* mime = webkit_uri_response_get_mime_type(response);
    if (mime != nullptr) {
      fl_value_set_string_take(event, "mimeType", fl_value_new_string(mime));
    }
    if (state->has_total_bytes) {
      fl_value_set_string_take(
          event, "totalBytes", fl_value_new_int(state->total_bytes));
    }
  }
  browser_send_event(plugin, event);
  return TRUE;
}

void download_started_cb(WebKitWebContext* context,
                         WebKitDownload* download,
                         gpointer user_data) {
  g_signal_connect(download, "decide-destination",
                   G_CALLBACK(download_decide_destination_cb), user_data);
}

}  // namespace

void browser_page_connect_signals(LinuxBrowserPage* page) {
  g_signal_connect(page->web_view, "load-changed",
                   G_CALLBACK(load_changed_cb), page);
  g_signal_connect(page->web_view, "notify::estimated-load-progress",
                   G_CALLBACK(progress_changed_cb), page);
  g_signal_connect(page->web_view, "notify::uri",
                   G_CALLBACK(uri_changed_cb), page);
  g_signal_connect(page->web_view, "load-failed",
                   G_CALLBACK(load_failed_cb), page);
  g_signal_connect(page->web_view, "permission-request",
                   G_CALLBACK(permission_request_cb), page);
  g_signal_connect(page->web_view, "load-failed-with-tls-errors",
                   G_CALLBACK(tls_failed_cb), page);
  g_signal_connect(page->web_view, "create",
                   G_CALLBACK(create_web_view_cb), page);
  g_signal_connect(page->web_view, "run-file-chooser",
                   G_CALLBACK(file_chooser_cb), page);
}

void browser_profile_connect_signals(AleraBrowserPlugin* plugin,
                                     LinuxBrowserProfile* profile) {
  g_signal_connect(profile->context, "download-started",
                   G_CALLBACK(download_started_cb), plugin);
}
