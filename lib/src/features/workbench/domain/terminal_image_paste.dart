String sanitizeTerminalImagePastePath(String path) =>
    path.replaceAll('\x1b', '\u241b');
