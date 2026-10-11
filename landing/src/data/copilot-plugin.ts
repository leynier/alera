import manifest from '../../copilot-plugin/plugin.json' with { type: 'json' };

export const COPILOT_PLUGIN_LABEL = 'GitHub Copilot';
export const COPILOT_PLUGIN_NAME = manifest.name;
export const COPILOT_PLUGIN_VERSION = manifest.version;
export const COPILOT_PLUGIN_ARCHIVE = 'alera-copilot-plugin.zip';
export const COPILOT_PLUGIN_DOWNLOAD_URL = `/downloads/${COPILOT_PLUGIN_ARCHIVE}`;
