#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <time.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* clipboard_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

namespace {

constexpr char kClipboardChannel[] = "dev.leynier.alera/clipboard";
constexpr char kSaveClipboardImageMethod[] = "saveImageAsTempFile";
constexpr char kClipboardImagePrefix[] = "alera-paste-";
constexpr char kClipboardImageSuffix[] = ".png";
constexpr gint64 kClipboardImageMaxPixels = 32LL * 1024LL * 1024LL;
constexpr goffset kClipboardImageMaxPngBytes = 18LL * 1024LL * 1024LL;
constexpr time_t kClipboardImageMaxAgeSeconds = 24 * 60 * 60;

struct ClipboardImageRequest {
  FlMethodCall* method_call;
  GdkPixbuf* pixbuf;
  GFile* file;
  GOutputStream* stream;
  gchar* path;
};

void clipboard_image_request_free(ClipboardImageRequest* request) {
  g_clear_object(&request->method_call);
  g_clear_object(&request->pixbuf);
  g_clear_object(&request->file);
  g_clear_object(&request->stream);
  g_clear_pointer(&request->path, g_free);
  g_free(request);
}

void respond_clipboard_error(ClipboardImageRequest* request,
                             const gchar* message) {
  if (request->path != nullptr) {
    g_remove(request->path);
  }
  fl_method_call_respond_error(request->method_call, "clipboard-image-error",
                               message, nullptr, nullptr);
  clipboard_image_request_free(request);
}

void cleanup_expired_clipboard_images(GTask* task,
                                      gpointer source_object,
                                      gpointer task_data,
                                      GCancellable* cancellable) {
  g_autoptr(GDir) directory = g_dir_open(g_get_tmp_dir(), 0, nullptr);
  if (directory == nullptr) {
    g_task_return_boolean(task, TRUE);
    return;
  }

  const time_t now = time(nullptr);
  const gchar* name = nullptr;
  while ((name = g_dir_read_name(directory)) != nullptr) {
    if (!g_str_has_prefix(name, kClipboardImagePrefix) ||
        !g_str_has_suffix(name, kClipboardImageSuffix)) {
      continue;
    }
    g_autofree gchar* path = g_build_filename(g_get_tmp_dir(), name, nullptr);
    GStatBuf stat_buffer;
    if (g_stat(path, &stat_buffer) == 0 && now >= stat_buffer.st_mtime &&
        now - stat_buffer.st_mtime > kClipboardImageMaxAgeSeconds) {
      g_remove(path);
    }
  }
  g_task_return_boolean(task, TRUE);
}

void schedule_clipboard_image_cleanup() {
  GTask* task = g_task_new(nullptr, nullptr, nullptr, nullptr);
  g_task_run_in_thread(task, cleanup_expired_clipboard_images);
  g_object_unref(task);
}

void clipboard_image_stream_closed_cb(GObject* source_object,
                                      GAsyncResult* result,
                                      gpointer user_data) {
  auto* request = static_cast<ClipboardImageRequest*>(user_data);
  g_autoptr(GError) error = nullptr;
  if (!g_output_stream_close_finish(G_OUTPUT_STREAM(source_object), result,
                                    &error)) {
    respond_clipboard_error(request, error->message);
    return;
  }

  GStatBuf stat_buffer;
  if (g_stat(request->path, &stat_buffer) != 0 ||
      stat_buffer.st_size > kClipboardImageMaxPngBytes) {
    respond_clipboard_error(request, "Clipboard image is too large.");
    return;
  }

  g_autoptr(FlValue) path = fl_value_new_string(request->path);
  fl_method_call_respond_success(request->method_call, path, nullptr);
  schedule_clipboard_image_cleanup();
  clipboard_image_request_free(request);
}

void clipboard_image_saved_cb(GObject* source_object,
                              GAsyncResult* result,
                              gpointer user_data) {
  auto* request = static_cast<ClipboardImageRequest*>(user_data);
  g_autoptr(GError) error = nullptr;
  if (!gdk_pixbuf_save_to_stream_finish(result, &error)) {
    respond_clipboard_error(request, error->message);
    return;
  }
  g_output_stream_close_async(request->stream, G_PRIORITY_DEFAULT, nullptr,
                              clipboard_image_stream_closed_cb, request);
}

void clipboard_image_file_created_cb(GObject* source_object,
                                     GAsyncResult* result,
                                     gpointer user_data) {
  auto* request = static_cast<ClipboardImageRequest*>(user_data);
  g_autoptr(GError) error = nullptr;
  GFileOutputStream* stream =
      g_file_create_finish(G_FILE(source_object), result, &error);
  if (stream == nullptr) {
    respond_clipboard_error(request, error->message);
    return;
  }
  request->stream = G_OUTPUT_STREAM(stream);
  gdk_pixbuf_save_to_streamv_async(request->pixbuf, request->stream, "png",
                                   nullptr, nullptr, nullptr,
                                   clipboard_image_saved_cb, request);
}

void clipboard_image_received_cb(GtkClipboard* clipboard,
                                 GdkPixbuf* pixbuf,
                                 gpointer user_data) {
  auto* request = static_cast<ClipboardImageRequest*>(user_data);
  if (pixbuf == nullptr) {
    fl_method_call_respond_success(request->method_call, nullptr, nullptr);
    clipboard_image_request_free(request);
    return;
  }

  const gint64 width = gdk_pixbuf_get_width(pixbuf);
  const gint64 height = gdk_pixbuf_get_height(pixbuf);
  if (width <= 0 || height <= 0 || width > kClipboardImageMaxPixels / height) {
    respond_clipboard_error(request, "Clipboard image is too large.");
    return;
  }

  request->pixbuf = GDK_PIXBUF(g_object_ref(pixbuf));
  g_autofree gchar* uuid = g_uuid_string_random();
  g_autofree gchar* name = g_strdup_printf(
      "%s%s%s", kClipboardImagePrefix, uuid, kClipboardImageSuffix);
  request->path = g_build_filename(g_get_tmp_dir(), name, nullptr);
  request->file = g_file_new_for_path(request->path);
  g_file_create_async(request->file, G_FILE_CREATE_PRIVATE, G_PRIORITY_DEFAULT,
                      nullptr, clipboard_image_file_created_cb, request);
}

void clipboard_channel_method_cb(FlMethodChannel* channel,
                                 FlMethodCall* method_call,
                                 gpointer user_data) {
  if (!g_str_equal(fl_method_call_get_name(method_call),
                   kSaveClipboardImageMethod)) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }

  auto* request = g_new0(ClipboardImageRequest, 1);
  request->method_call = FL_METHOD_CALL(g_object_ref(method_call));
  gtk_clipboard_request_image(gtk_clipboard_get(GDK_SELECTION_CLIPBOARD),
                              clipboard_image_received_cb, request);
}

}  // namespace

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

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
    gtk_header_bar_set_title(header_bar, "Alera");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Alera");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) clipboard_codec =
      fl_standard_method_codec_new();
  self->clipboard_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), kClipboardChannel,
      FL_METHOD_CODEC(clipboard_codec));
  fl_method_channel_set_method_call_handler(
      self->clipboard_channel, clipboard_channel_method_cb, self, nullptr);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->clipboard_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
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

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
