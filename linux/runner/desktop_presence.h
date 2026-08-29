#ifndef FLUTTER_DESKTOP_PRESENCE_H_
#define FLUTTER_DESKTOP_PRESENCE_H_

#include <flutter_linux/flutter_linux.h>

typedef struct _DesktopPresence DesktopPresence;

DesktopPresence* desktop_presence_new(FlEngine* engine);

void desktop_presence_free(DesktopPresence* presence);

#endif  // FLUTTER_DESKTOP_PRESENCE_H_
