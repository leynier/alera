import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { strToU8, zipSync, type Zippable } from 'fflate';
import { buildSkillCatalog } from '../../../edge/tool/skill_catalog';
import { CLAUDE_PLUGIN_ALIAS, CLAUDE_PLUGIN_ARCHIVE, CLAUDE_PLUGIN_VERSION } from '../data/claude-plugin';

const templates = ['.claude-plugin/plugin.json', '.mcp.json', 'README.md', 'skills/alera-setup/SKILL.md'];
const remoteReferenceInstruction = 'Read only the references the task needs. Read them with `read_skill`, passing the reference path as `file`.';
const bundledReferenceInstruction = 'Read only the bundled references the task needs using Claude\'s skill file-reading facilities. Relative links resolve inside this skill folder. If a bundled reference is unavailable, use the Alera connector\'s `read_skill` tool with this skill name and the reference path as `file`; report that the remote copy can differ from the installed plugin version.';

/** Claude-only adaptation keeps the shared MCP sources and ChatGPT archive unchanged. */
export function adaptClaudeSkill(text: string, entrypoint: boolean): string {
  const adapted = text.replace(remoteReferenceInstruction, bundledReferenceInstruction);
  if (!entrypoint) return adapted;
  return `${adapted.trimEnd()}\n\n## Claude Web Connection\n\nUse the remote Alera connector already connected on the user's Claude account. If its tools are missing, load the bundled alera-setup skill and guide the user through the plugin's Connectors tab. Do not run Alera CLI commands or a local MCP server in the chat sandbox. The agents and coordinator terminals described here run on the selected Alera runtime, not as Claude web subagents.\n`;
}

export function buildClaudePluginBundle(landingRoot: string) {
  const files: Record<string, Uint8Array> = {};
  const add = (path: string, bytes: Uint8Array) => {
    const parts = path.split('/');
    if (!/^[a-zA-Z0-9_ .\/(),-]+$/.test(path) || parts.some((part) => !part || part === '..' || part === '.') || parts.length > 12 || path.length > 472 || parts.some((part) => part.length > 255)) {
      throw new Error(`Unsafe Claude plugin path: ${path}`);
    }
    if (files[path]) throw new Error(`Duplicate Claude plugin file: ${path}`);
    files[path] = bytes;
  };
  for (const path of templates) add(path, readFileSync(join(landingRoot, 'claude-plugin', path)));
  add('assets/logo.png', readFileSync(join(landingRoot, '..', 'assets', 'logo', 'alera-logo.png')));
  add('LICENSE', readFileSync(join(landingRoot, '..', 'LICENSE')));
  const catalog = buildSkillCatalog(join(landingRoot, '..', 'edge', 'skills'));
  for (const skill of catalog.skills) {
    for (const file of skill.files) add(`skills/${skill.name}/${file.path}`, strToU8(adaptClaudeSkill(file.text, file.path === 'SKILL.md')));
  }
  const manifest = JSON.parse(new TextDecoder().decode(files['.claude-plugin/plugin.json']!));
  if (manifest.version !== CLAUDE_PLUGIN_VERSION || !/^[a-z0-9-]{1,64}$/.test(manifest.name) || manifest.displayName.length > 64 || manifest.description.length > 500 || !files[manifest.icon.slice(2)]) {
    throw new Error('Invalid Claude plugin manifest');
  }
  if (Object.keys(files).length > 5000 || Object.values(files).reduce((sum, file) => sum + file.length, 0) > 200_000_000) throw new Error('Claude plugin exceeds upload limits');
  const entries: Zippable = {};
  for (const path of Object.keys(files).sort()) {
    entries[path] = [files[path]!, { mtime: new Date(2026, 0, 1), os: 3, attrs: (0o100644 << 16) >>> 0 }];
  }
  const bytes = zipSync(entries, { level: 9 });
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  return { bytes, files, sha256, version: manifest.version as string, checksums: {
    [CLAUDE_PLUGIN_ARCHIVE]: `${sha256}  ${CLAUDE_PLUGIN_ARCHIVE}\n`,
    [CLAUDE_PLUGIN_ALIAS]: `${sha256}  ${CLAUDE_PLUGIN_ALIAS}\n`,
  } };
}
