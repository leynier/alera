#ifndef FLUTTER_PLUGIN_ALERA_BROWSER_PLUGIN_H_
#define FLUTTER_PLUGIN_ALERA_BROWSER_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define ALERA_BROWSER_EXPORT __attribute__((visibility("default")))
#else
#define ALERA_BROWSER_EXPORT
#endif

typedef struct _AleraBrowserPlugin AleraBrowserPlugin;
typedef struct {
  GObjectClass parent_class;
} AleraBrowserPluginClass;

ALERA_BROWSER_EXPORT GType alera_browser_plugin_get_type();
ALERA_BROWSER_EXPORT void alera_browser_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif
