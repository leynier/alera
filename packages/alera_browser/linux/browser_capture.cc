#include "browser_state.h"

#include <glib/gstdio.h>

#include <cerrno>
#include <cmath>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>

namespace {

struct CaptureCall {
  FlMethodCall* call;
  WebKitWebView* web_view;
  WebKitPrintOperation* print_operation;
  gchar* destination_path;
  gchar* temporary_path;
  gchar* failure;
  double scale;
  gboolean previous_print_backgrounds;
};

CaptureCall* capture_call_new(FlMethodCall* call,
                              LinuxBrowserPage* page,
                              const gchar* destination_path) {
  CaptureCall* context = g_new0(CaptureCall, 1);
  context->call = FL_METHOD_CALL(g_object_ref(call));
  context->web_view =
      WEBKIT_WEB_VIEW(g_object_ref(page->web_view));
  context->destination_path = g_strdup(destination_path);
  return context;
}

void capture_call_free(CaptureCall* context) {
  if (context == nullptr) {
    return;
  }
  g_clear_object(&context->call);
  g_clear_object(&context->web_view);
  g_clear_object(&context->print_operation);
  g_clear_pointer(&context->destination_path, g_free);
  g_clear_pointer(&context->temporary_path, g_free);
  g_clear_pointer(&context->failure, g_free);
  g_free(context);
}

LinuxBrowserPage* lookup_page(AleraBrowserPlugin* plugin, FlValue* args) {
  const gchar* page_id = browser_map_string(args, "pageId");
  return page_id != nullptr
             ? static_cast<LinuxBrowserPage*>(
                   g_hash_table_lookup(plugin->pages, page_id))
             : nullptr;
}

gboolean valid_destination(const gchar* path) {
  if (path == nullptr || !g_path_is_absolute(path) ||
      g_file_test(path, G_FILE_TEST_EXISTS)) {
    return FALSE;
  }
  g_autofree gchar* parent = g_path_get_dirname(path);
  return g_file_test(parent, G_FILE_TEST_IS_DIR);
}

FlValue* artifact_value(const gchar* path,
                        const gchar* mime_type,
                        gint width,
                        gint height) {
  GStatBuf stats = {};
  if (g_stat(path, &stats) != 0 || !S_ISREG(stats.st_mode)) {
    return nullptr;
  }
  FlValue* value = fl_value_new_map();
  fl_value_set_string_take(value, "path", fl_value_new_string(path));
  fl_value_set_string_take(
      value, "mimeType", fl_value_new_string(mime_type));
  fl_value_set_string_take(
      value, "sizeBytes", fl_value_new_int(stats.st_size));
  if (width > 0 && height > 0) {
    fl_value_set_string_take(value, "width", fl_value_new_int(width));
    fl_value_set_string_take(value, "height", fl_value_new_int(height));
  }
  g_autofree gchar* basename = g_path_get_basename(path);
  fl_value_set_string_take(
      value, "suggestedFileName", fl_value_new_string(basename));
  return value;
}

cairo_status_t write_png_chunk(void* closure,
                               const unsigned char* data,
                               unsigned int length) {
  const int fd = GPOINTER_TO_INT(closure);
  unsigned int offset = 0;
  while (offset < length) {
    const ssize_t written = write(fd, data + offset, length - offset);
    if (written < 0 && errno == EINTR) {
      continue;
    }
    if (written <= 0) {
      return CAIRO_STATUS_WRITE_ERROR;
    }
    offset += static_cast<unsigned int>(written);
  }
  return CAIRO_STATUS_SUCCESS;
}

gboolean write_png_exclusive(cairo_surface_t* surface,
                             const gchar* path,
                             GError** error) {
  int flags = O_WRONLY | O_CREAT | O_EXCL;
#ifdef O_CLOEXEC
  flags |= O_CLOEXEC;
#endif
#ifdef O_NOFOLLOW
  flags |= O_NOFOLLOW;
#endif
  const int fd = g_open(path, flags, 0600);
  if (fd < 0) {
    g_set_error(error, G_FILE_ERROR, g_file_error_from_errno(errno),
                "Could not reserve the screenshot destination: %s.",
                g_strerror(errno));
    return FALSE;
  }
  const cairo_status_t status =
      cairo_surface_write_to_png_stream(surface, write_png_chunk,
                                        GINT_TO_POINTER(fd));
  const int close_result = close(fd);
  if (status != CAIRO_STATUS_SUCCESS || close_result != 0) {
    const gchar* detail = status != CAIRO_STATUS_SUCCESS
                              ? cairo_status_to_string(status)
                              : g_strerror(errno);
    g_unlink(path);
    g_set_error(error, G_FILE_ERROR, G_FILE_ERROR_FAILED,
                "Could not write the screenshot: %s.", detail);
    return FALSE;
  }
  return TRUE;
}

void snapshot_done(GObject* object,
                   GAsyncResult* result,
                   gpointer user_data) {
  CaptureCall* context = static_cast<CaptureCall*>(user_data);
  GError* error = nullptr;
  cairo_surface_t* source = webkit_web_view_get_snapshot_finish(
      WEBKIT_WEB_VIEW(object), result, &error);
  if (source == nullptr) {
    browser_respond(
        context->call,
        browser_error("screenshot_failed",
                      error != nullptr ? error->message
                                       : "WebKit did not return a snapshot."));
    g_clear_error(&error);
    capture_call_free(context);
    return;
  }
  if (cairo_surface_get_type(source) != CAIRO_SURFACE_TYPE_IMAGE) {
    browser_respond(
        context->call,
        browser_error("screenshot_failed",
                      "WebKit returned an unsupported snapshot surface."));
    cairo_surface_destroy(source);
    capture_call_free(context);
    return;
  }
  const gint source_width = cairo_image_surface_get_width(source);
  const gint source_height = cairo_image_surface_get_height(source);
  const double scaled_width = source_width * context->scale;
  const double scaled_height = source_height * context->scale;
  if (scaled_width < 1 || scaled_height < 1 ||
      scaled_width > G_MAXINT || scaled_height > G_MAXINT ||
      scaled_width * scaled_height > 100000000) {
    browser_respond(
        context->call,
        browser_error("screenshot_too_large",
                      "The requested screenshot exceeds the pixel limit."));
    cairo_surface_destroy(source);
    capture_call_free(context);
    return;
  }
  const gint width = std::lround(scaled_width);
  const gint height = std::lround(scaled_height);
  cairo_surface_t* output = source;
  if (context->scale != 1) {
    output =
        cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    cairo_t* painter = cairo_create(output);
    cairo_scale(painter, context->scale, context->scale);
    cairo_set_source_surface(painter, source, 0, 0);
    cairo_paint(painter);
    cairo_destroy(painter);
  }
  if (!write_png_exclusive(output, context->destination_path, &error)) {
    browser_respond(
        context->call,
        browser_error("screenshot_write_failed", error->message));
  } else {
    g_autoptr(FlValue) artifact = artifact_value(
        context->destination_path, "image/png", width, height);
    browser_respond(context->call, browser_success(artifact));
  }
  g_clear_error(&error);
  if (output != source) {
    cairo_surface_destroy(output);
  }
  cairo_surface_destroy(source);
  capture_call_free(context);
}

void print_failed(WebKitPrintOperation* operation,
                  GError* error,
                  gpointer user_data) {
  CaptureCall* context = static_cast<CaptureCall*>(user_data);
  g_free(context->failure);
  context->failure =
      g_strdup(error != nullptr ? error->message : "PDF printing failed.");
}

void print_finished(WebKitPrintOperation* operation, gpointer user_data) {
  CaptureCall* context = static_cast<CaptureCall*>(user_data);
  WebKitSettings* settings =
      webkit_web_view_get_settings(context->web_view);
  webkit_settings_set_print_backgrounds(
      settings, context->previous_print_backgrounds);
  if (context->failure != nullptr) {
    browser_respond(
        context->call, browser_error("pdf_failed", context->failure));
  } else {
    if (link(context->temporary_path, context->destination_path) != 0) {
      browser_respond(
          context->call,
          browser_error(
              errno == EEXIST ? "destination_exists" : "pdf_failed",
              errno == EEXIST
                  ? "The PDF destination already exists."
                  : "The PDF could not be moved to its destination."));
    } else {
      g_chmod(context->destination_path, 0600);
      g_autoptr(FlValue) artifact = artifact_value(
          context->destination_path, "application/pdf", 0, 0);
      if (artifact == nullptr) {
        g_unlink(context->destination_path);
        browser_respond(
            context->call,
            browser_error("pdf_failed",
                          "The PDF destination was not created."));
      } else {
        browser_respond(context->call, browser_success(artifact));
      }
    }
  }
  g_unlink(context->temporary_path);
  capture_call_free(context);
}

gboolean begin_pdf(CaptureCall* context,
                   gboolean landscape,
                   gboolean print_background,
                   GError** error) {
  g_autofree gchar* parent =
      g_path_get_dirname(context->destination_path);
  context->temporary_path =
      g_build_filename(parent, ".alera-browser-pdf-XXXXXX", nullptr);
  int flags = O_RDWR;
#ifdef O_CLOEXEC
  flags |= O_CLOEXEC;
#endif
  const int temporary_fd =
      g_mkstemp_full(context->temporary_path, flags, 0600);
  if (temporary_fd < 0) {
    g_set_error(error, G_FILE_ERROR, g_file_error_from_errno(errno),
                "Could not reserve a temporary PDF file: %s.",
                g_strerror(errno));
    return FALSE;
  }
  if (close(temporary_fd) != 0) {
    g_unlink(context->temporary_path);
    g_set_error(error, G_FILE_ERROR, g_file_error_from_errno(errno),
                "Could not prepare the temporary PDF file: %s.",
                g_strerror(errno));
    return FALSE;
  }

  WebKitSettings* web_settings =
      webkit_web_view_get_settings(context->web_view);
  context->previous_print_backgrounds =
      webkit_settings_get_print_backgrounds(web_settings);
  webkit_settings_set_print_backgrounds(web_settings, print_background);

  context->print_operation =
      webkit_print_operation_new(context->web_view);
  GtkPrintSettings* print_settings = gtk_print_settings_new();
  g_autofree gchar* destination_uri =
      g_filename_to_uri(context->temporary_path, nullptr, error);
  if (destination_uri == nullptr) {
    g_unlink(context->temporary_path);
    webkit_settings_set_print_backgrounds(
        web_settings, context->previous_print_backgrounds);
    return FALSE;
  }
  gtk_print_settings_set_printer(print_settings, "Print to File");
  gtk_print_settings_set(
      print_settings, GTK_PRINT_SETTINGS_OUTPUT_FILE_FORMAT, "pdf");
  gtk_print_settings_set(
      print_settings, GTK_PRINT_SETTINGS_OUTPUT_URI, destination_uri);
  webkit_print_operation_set_print_settings(
      context->print_operation, print_settings);
  g_object_unref(print_settings);

  GtkPageSetup* page_setup = gtk_page_setup_new();
  gtk_page_setup_set_orientation(
      page_setup, landscape ? GTK_PAGE_ORIENTATION_LANDSCAPE
                            : GTK_PAGE_ORIENTATION_PORTRAIT);
  webkit_print_operation_set_page_setup(
      context->print_operation, page_setup);
  g_object_unref(page_setup);

  g_signal_connect(
      context->print_operation, "failed", G_CALLBACK(print_failed), context);
  g_signal_connect(
      context->print_operation, "finished", G_CALLBACK(print_finished),
      context);
  webkit_print_operation_print(context->print_operation);
  return TRUE;
}

}  // namespace

void browser_capture_handle_method(AleraBrowserPlugin* plugin,
                                   FlMethodCall* method_call,
                                   const gchar* method,
                                   FlValue* args) {
  LinuxBrowserPage* page = lookup_page(plugin, args);
  if (page == nullptr) {
    browser_respond(
        method_call,
        browser_error("page_not_found", "The browser page does not exist."));
    return;
  }
  const gchar* destination =
      browser_map_string(args, "destinationPath");
  if (!valid_destination(destination)) {
    browser_respond(
        method_call,
        browser_error("invalid_destination",
                      "The destination must be an unused absolute file path."));
    return;
  }
  if (std::strcmp(method, "capture.screenshot") == 0) {
    const double scale = browser_map_double(args, "scale", 1);
    if (!std::isfinite(scale) || scale <= 0 || scale > 4) {
      browser_respond(
          method_call,
          browser_error("invalid_scale",
                        "Screenshot scale must be greater than 0 and at most 4."));
      return;
    }
    CaptureCall* context =
        capture_call_new(method_call, page, destination);
    context->scale = scale;
    webkit_web_view_get_snapshot(
        page->web_view,
        browser_map_bool(args, "fullPage", FALSE)
            ? WEBKIT_SNAPSHOT_REGION_FULL_DOCUMENT
            : WEBKIT_SNAPSHOT_REGION_VISIBLE,
        WEBKIT_SNAPSHOT_OPTIONS_NONE, nullptr, snapshot_done, context);
  } else if (std::strcmp(method, "capture.pdf") == 0) {
    CaptureCall* context =
        capture_call_new(method_call, page, destination);
    GError* error = nullptr;
    if (!begin_pdf(context, browser_map_bool(args, "landscape", FALSE),
                   browser_map_bool(args, "printBackground", TRUE), &error)) {
      browser_respond(
          method_call,
          browser_error("pdf_failed",
                        error != nullptr
                            ? error->message
                            : "The PDF capture could not start."));
      g_clear_error(&error);
      capture_call_free(context);
    }
  } else {
    browser_respond(
        method_call,
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
  }
}
