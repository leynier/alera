#include "tray_badge_icon.h"

#include <gtk/gtk.h>
#include <pango/pangocairo.h>

#include <math.h>

namespace {

constexpr char kIconName[] = "alera";
// Same red as the Windows taskbar overlay badge in win32_desktop_presence.cpp.
constexpr double kBadgeRed = 0xC0 / 255.0;
constexpr double kBadgeGreen = 0x28 / 255.0;
constexpr double kBadgeBlue = 0x2C / 255.0;

gchar* bundled_icon_path() {
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable == nullptr) {
    return nullptr;
  }
  g_autofree gchar* directory = g_path_get_dirname(executable);
  return g_build_filename(directory, "data", "flutter_assets", "assets", "logo",
                          "alera-logo.png", nullptr);
}

GdkPixbuf* load_base_icon(int size) {
  GtkIconTheme* theme = gtk_icon_theme_get_default();
  if (theme != nullptr) {
    GdkPixbuf* themed = gtk_icon_theme_load_icon(
        theme, kIconName, size, GTK_ICON_LOOKUP_FORCE_SIZE, nullptr);
    if (themed != nullptr) {
      return themed;
    }
  }
  // A build run straight from the bundle has no installed icon theme entry, so
  // fall back to the logo that ships next to the executable.
  g_autofree gchar* path = bundled_icon_path();
  if (path == nullptr) {
    return nullptr;
  }
  return gdk_pixbuf_new_from_file_at_size(path, size, size, nullptr);
}

// Windows caps the same badge at "9+"; a single glyph is all that stays legible
// at 22 pixels.
gchar* badge_label(int count) {
  if (count > 9) {
    return g_strdup("9+");
  }
  return g_strdup_printf("%d", count);
}

void draw_badge(cairo_t* cr, int size, int count) {
  const double diameter = size * 0.55;
  const double radius = diameter / 2.0;
  const double center_x = size - radius;
  const double center_y = radius;
  const double gap = MAX(1.0, size / 16.0);

  // Punch a transparent ring first so the badge keeps its edge against a light
  // panel, where the logo and the badge would otherwise touch.
  cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
  cairo_arc(cr, center_x, center_y, radius + gap, 0, 2 * G_PI);
  cairo_fill(cr);

  cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
  cairo_set_source_rgb(cr, kBadgeRed, kBadgeGreen, kBadgeBlue);
  cairo_arc(cr, center_x, center_y, radius, 0, 2 * G_PI);
  cairo_fill(cr);

  g_autofree gchar* label = badge_label(count);
  PangoLayout* layout = pango_cairo_create_layout(cr);
  PangoFontDescription* font = pango_font_description_from_string("Sans Bold");
  pango_font_description_set_absolute_size(font, size * 0.42 * PANGO_SCALE);
  pango_layout_set_font_description(layout, font);
  pango_font_description_free(font);
  pango_layout_set_text(layout, label, -1);
  int text_width = 0;
  int text_height = 0;
  pango_layout_get_pixel_size(layout, &text_width, &text_height);
  cairo_set_source_rgb(cr, 1.0, 1.0, 1.0);
  cairo_move_to(cr, center_x - text_width / 2.0, center_y - text_height / 2.0);
  pango_cairo_show_layout(cr, layout);
  g_object_unref(layout);
}

}  // namespace

GdkPixbuf* tray_badge_icon_render(int size, int count) {
  GdkPixbuf* base = load_base_icon(size);
  if (base == nullptr) {
    return nullptr;
  }
  if (count <= 0) {
    return base;
  }
  cairo_surface_t* surface =
      cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size, size);
  cairo_t* cr = cairo_create(surface);
  gdk_cairo_set_source_pixbuf(cr, base, 0, 0);
  cairo_paint(cr);
  g_object_unref(base);
  draw_badge(cr, size, count);
  cairo_destroy(cr);
  // Straight back to a pixbuf, which un-premultiplies for us; the wire format
  // wants plain ARGB and cairo works premultiplied.
  GdkPixbuf* badged = gdk_pixbuf_get_from_surface(surface, 0, 0, size, size);
  cairo_surface_destroy(surface);
  return badged;
}
