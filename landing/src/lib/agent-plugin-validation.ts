import Ajv2020 from 'ajv/dist/2020.js';
import pluginSchema from '../../config/schemas/agent-plugins-1.0.0/plugin.schema.json' with { type: 'json' };
import mcpSchema from '../../config/schemas/agent-plugins-1.0.0/mcp.schema.json' with { type: 'json' };

const ajv = new Ajv2020({ allErrors: true, strict: true });
export const validateAgentPluginManifest = ajv.compile(pluginSchema);
export const validateAgentPluginMcp = ajv.compile(mcpSchema);

export function assertPureAgentPlugin(manifest: any, mcp: any) {
  if (!validateAgentPluginManifest(manifest)) throw new Error(`Invalid Agent Plugin manifest: ${ajv.errorsText(validateAgentPluginManifest.errors)}`);
  if (!validateAgentPluginMcp(mcp)) throw new Error(`Invalid Agent Plugin MCP: ${ajv.errorsText(validateAgentPluginMcp.errors)}`);
  if ('extensions' in manifest) throw new Error('Pure Agent Plugin cannot contain extensions');
  const server = (mcp.mcpServers as Record<string, { type: string; url: string }>).alera;
  if (Object.keys(mcp.mcpServers).length !== 1 || server?.type !== 'streamable-http' || server.url !== 'https://api.alera.build/v1/mcp' || Object.keys(server).some((key) => !['type', 'url'].includes(key))) throw new Error('Agent Plugin must use the fixed credential-free Alera server');
  const url = new URL(server.url);
  if (url.protocol !== 'https:' || url.username || url.password || url.hash) throw new Error('Invalid portable remote URL');
}
