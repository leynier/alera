import manifest from '../../claude-plugin/.claude-plugin/plugin.json' with { type: 'json' };
import mcp from '../../claude-plugin/.mcp.json' with { type: 'json' };

export const CLAUDE_PLUGIN_NAME = manifest.name;
export const CLAUDE_PLUGIN_VERSION = manifest.version;
export const CLAUDE_PLUGIN_ARCHIVE = 'alera-claude-plugin.zip';
export const CLAUDE_PLUGIN_ALIAS = 'alera-claude.plugin';
export const CLAUDE_PLUGIN_DOWNLOAD_URL = `/downloads/${CLAUDE_PLUGIN_ARCHIVE}`;
export const CLAUDE_PLUGIN_ALIAS_URL = `/downloads/${CLAUDE_PLUGIN_ALIAS}`;
export const CLAUDE_PLUGIN_MCP_URL = mcp.mcpServers.alera.url;
