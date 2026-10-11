import manifest from '../../plugin/plugin.json' with { type: 'json' };
import mcp from '../../plugin/mcp.json' with { type: 'json' };

export const PLUGIN_NAME = manifest.name;
export const PLUGIN_VERSION = manifest.version;
export const PLUGIN_ARCHIVE = 'alera-plugin.zip';
export const PLUGIN_DOWNLOAD_URL = `/downloads/${PLUGIN_ARCHIVE}`;
export const PLUGIN_CHECKSUM_URL = `${PLUGIN_DOWNLOAD_URL}.sha256`;
export const PLUGIN_MCP_URL = mcp.mcpServers.alera.url;
export const PLUGIN_MARKETPLACE_COMMAND = 'codex plugin marketplace add /path/to/alera';
export const PLUGIN_INSTALL_COMMAND = 'codex plugin add alera@alera';

export const PLUGIN_SKILLS = [
  { name: 'alera-mcp', label: 'Alera Workspaces', description: 'Runtimes, projects, workspaces, terminals, and pull requests', prompt: 'show my workspaces and agents' },
  { name: 'alera-mcp-orchestration', label: 'Alera Orchestration', description: 'Agent tasks, coordinator runs, gates, and workflow recipes', prompt: 'follow my agent tasks and coordinator runs' },
  { name: 'alera-mcp-automations', label: 'Alera Automations', description: 'Scheduled agent work and automation runs', prompt: 'manage my scheduled agent work' },
  { name: 'alera-mcp-agent-profiles', label: 'Alera Agent Profiles', description: 'Agent launch profiles and configuration', prompt: 'inspect my agent launch profiles' },
] as const;
