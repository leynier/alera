import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { CURSOR_PLUGIN_ARCHIVE, CURSOR_PLUGIN_NAME, CURSOR_PLUGIN_VERSION } from '../data/cursor-plugin';
import { buildPluginArchive } from './plugin-archive';
import { portableAleraSkillFiles } from './portable-alera-skills';

export function buildCursorPluginBundle(landingRoot: string) {
  const files = portableAleraSkillFiles(landingRoot);
  for (const path of ['.cursor-plugin/plugin.json', 'mcp.json', 'README.md', 'skills/alera-setup/SKILL.md', 'assets/logo.png']) files[path] = readFileSync(join(landingRoot, 'cursor-plugin', path));
  files.LICENSE = readFileSync(join(landingRoot, '..', 'LICENSE'));
  const manifest = JSON.parse(new TextDecoder().decode(files['.cursor-plugin/plugin.json']!));
  if (manifest.name !== CURSOR_PLUGIN_NAME || manifest.version !== CURSOR_PLUGIN_VERSION || !files[manifest.logo]) throw new Error('Invalid Cursor plugin manifest');
  return { ...buildPluginArchive(files, CURSOR_PLUGIN_NAME, CURSOR_PLUGIN_ARCHIVE), version: manifest.version as string };
}
