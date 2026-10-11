import manifest from '../../agent-plugin/plugin.json' with { type: 'json' };

export const AGENT_PLUGIN_LABEL = 'Agent Plugin';
export const AGENT_PLUGIN_NAME = manifest.name;
export const AGENT_PLUGIN_VERSION = manifest.version;
export const AGENT_PLUGIN_ARCHIVE = 'alera-agent-plugin.zip';
export const AGENT_PLUGIN_DOWNLOAD_URL = `/downloads/${AGENT_PLUGIN_ARCHIVE}`;
