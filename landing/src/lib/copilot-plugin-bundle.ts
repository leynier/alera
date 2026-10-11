import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { COPILOT_PLUGIN_ARCHIVE, COPILOT_PLUGIN_NAME, COPILOT_PLUGIN_VERSION } from '../data/copilot-plugin';
import { assertPureAgentPlugin } from './agent-plugin-validation';
import { buildPluginArchive } from './plugin-archive';
import { portableAleraSkillFiles } from './portable-alera-skills';

export function buildCopilotPluginBundle(landingRoot: string) {
  const files = portableAleraSkillFiles(landingRoot);
  for (const path of ['plugin.json', 'mcp.json', 'README.md', 'skills/alera-setup/SKILL.md']) files[path] = readFileSync(join(landingRoot, 'copilot-plugin', path));
  files.LICENSE = readFileSync(join(landingRoot, '..', 'LICENSE'));
  const manifest = JSON.parse(new TextDecoder().decode(files['plugin.json']!));
  assertPureAgentPlugin(manifest, JSON.parse(new TextDecoder().decode(files['mcp.json']!)));
  if (manifest.name !== COPILOT_PLUGIN_NAME || manifest.version !== COPILOT_PLUGIN_VERSION) throw new Error('Copilot plugin identity/version mismatch');
  return { ...buildPluginArchive(files, COPILOT_PLUGIN_NAME, COPILOT_PLUGIN_ARCHIVE), version: manifest.version as string };
}
