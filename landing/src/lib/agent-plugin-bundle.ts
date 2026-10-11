import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { AGENT_PLUGIN_ARCHIVE, AGENT_PLUGIN_NAME, AGENT_PLUGIN_VERSION } from '../data/agent-plugin';
import { assertPureAgentPlugin } from './agent-plugin-validation';
import { buildPluginArchive } from './plugin-archive';
import { portableAleraSkillFiles } from './portable-alera-skills';

export function buildAgentPluginBundle(landingRoot: string) {
  const files = portableAleraSkillFiles(landingRoot);
  for (const path of ['plugin.json', 'mcp.json', 'README.md', 'skills/alera-setup/SKILL.md']) files[path] = readFileSync(join(landingRoot, 'agent-plugin', path));
  files.LICENSE = readFileSync(join(landingRoot, '..', 'LICENSE'));
  const manifest = JSON.parse(new TextDecoder().decode(files['plugin.json']!));
  assertPureAgentPlugin(manifest, JSON.parse(new TextDecoder().decode(files['mcp.json']!)));
  if (manifest.name !== AGENT_PLUGIN_NAME || manifest.version !== AGENT_PLUGIN_VERSION) throw new Error('Agent Plugin identity/version mismatch');
  for (const path of Object.keys(files)) if (!['plugin.json', 'mcp.json', 'README.md', 'LICENSE'].includes(path) && !/^skills\/[^/]+\/(?:SKILL\.md|references\/[^/]+\.md)$/.test(path)) throw new Error(`Non-portable package file: ${path}`);
  return { ...buildPluginArchive(files, AGENT_PLUGIN_NAME, AGENT_PLUGIN_ARCHIVE), version: manifest.version as string };
}
