import manifest from '../../cursor-plugin/.cursor-plugin/plugin.json' with { type: 'json' };

export const CURSOR_PLUGIN_LABEL = 'GrokBot Cursor';
export const CURSOR_PLUGIN_NAME = manifest.name;
export const CURSOR_PLUGIN_VERSION = manifest.version;
export const CURSOR_PLUGIN_ARCHIVE = 'alera-grokbot-cursor-plugin.zip';
export const CURSOR_PLUGIN_DOWNLOAD_URL = `/downloads/${CURSOR_PLUGIN_ARCHIVE}`;
