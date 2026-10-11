import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { strToU8, zipSync, type Zippable } from 'fflate';
import { buildSkillCatalog } from '../../../edge/tool/skill_catalog';
import { PLUGIN_ARCHIVE, PLUGIN_MCP_URL, PLUGIN_NAME, PLUGIN_SKILLS, PLUGIN_VERSION } from '../data/plugin';

const templateFiles = [
  'plugin.json',
  'mcp.json',
  'README.md',
  'skills/alera-setup/SKILL.md',
  'skills/alera-setup/agents/openai.yaml',
];

/** Build-time only. Explicit inputs keep credentials and unrelated files out of the download. */
export function buildPluginBundle(landingRoot: string) {
  const files: Record<string, Uint8Array> = {};
  const add = (path: string, bytes: Uint8Array) => {
    if (path.startsWith('/') || path.includes('\\') || path.split('/').some((part) => part === '..' || !part)) {
      throw new Error(`Unsafe plugin path: ${path}`);
    }
    if (files[path]) throw new Error(`Duplicate plugin path: ${path}`);
    files[path] = bytes;
  };
  const json = (path: string, value: unknown) => add(path, strToU8(`${JSON.stringify(value, null, 2)}\n`));

  for (const path of templateFiles) add(path, readFileSync(join(landingRoot, 'plugin', path)));
  add('assets/logo.png', readFileSync(join(landingRoot, '..', 'assets', 'logo', 'alera-logo.png')));
  add('assets/logo-dark.png', readFileSync(join(landingRoot, 'public', 'logo.png')));
  add('LICENSE', readFileSync(join(landingRoot, '..', 'LICENSE')));

  const catalog = buildSkillCatalog(join(landingRoot, '..', 'edge', 'skills'));
  const expected = PLUGIN_SKILLS.map((skill) => skill.name).sort();
  if (JSON.stringify(catalog.skills.map((skill) => skill.name).sort()) !== JSON.stringify(expected)) {
    throw new Error('Plugin skill metadata must cover every MCP skill');
  }
  for (const skill of catalog.skills) {
    for (const file of skill.files) add(`skills/${skill.name}/${file.path}`, strToU8(file.text));
    const display = PLUGIN_SKILLS.find((entry) => entry.name === skill.name)!;
    const quote = (value: string) => JSON.stringify(value);
    add(`skills/${skill.name}/agents/openai.yaml`, strToU8([
      'interface:',
      `  display_name: ${quote(display.label)}`,
      `  short_description: ${quote(`Use Alera to ${display.prompt}`)}`,
      `  default_prompt: ${quote(`Use $${skill.name} to ${display.prompt}.`)}`,
      'dependencies:',
      '  tools:',
      '    - type: "mcp"',
      '      value: "alera"',
      '      description: "Connect to your Alera runtimes"',
      '      transport: "streamable_http"',
      `      url: ${quote(PLUGIN_MCP_URL)}`,
      '',
    ].join('\n')));
  }

  const manifest = JSON.parse(new TextDecoder().decode(files['plugin.json']!));
  const portableMcp = JSON.parse(new TextDecoder().decode(files['mcp.json']!));
  const openai = manifest.extensions['com.openai'];
  if (manifest.name !== PLUGIN_NAME || manifest.version !== PLUGIN_VERSION) {
    throw new Error('Plugin metadata does not match the package sources');
  }
  for (const path of [openai.onboardingSkill, openai.interface.logo, openai.interface.logoDark, openai.interface.composerIcon, openai.interface.composerIconDark]) {
    if (typeof path !== 'string' || !path.startsWith('./') || !files[path.slice(2)]) {
      throw new Error(`Missing plugin resource: ${path}`);
    }
  }

  json('.codex-plugin/plugin.json', {
    name: manifest.name,
    version: manifest.version,
    description: manifest.description,
    author: manifest.author,
    homepage: manifest.homepage,
    repository: manifest.repository,
    license: manifest.license,
    skills: './skills/',
    mcpServers: './.mcp.json',
    interface: openai.interface,
    extensions: { 'com.openai': { onboardingSkill: openai.onboardingSkill } },
  });
  json('.mcp.json', {
    mcpServers: Object.fromEntries(Object.entries(portableMcp.mcpServers).map(([name, server]) => {
      const { type: _transport, ...connection } = server as Record<string, unknown>;
      return [name, connection];
    })),
  });
  json('.agents/plugins/marketplace.json', {
    name: PLUGIN_NAME,
    interface: { displayName: 'Alera' },
    plugins: [{
      name: PLUGIN_NAME,
      source: { source: 'local', path: './' },
      policy: { installation: 'AVAILABLE', authentication: 'ON_INSTALL' },
      category: openai.interface.category,
    }],
  });

  const entries: Zippable = {};
  for (const path of Object.keys(files).sort()) {
    // Fixed timestamps and Unix file modes make the ZIP identical across build hosts.
    entries[`${PLUGIN_NAME}/${path}`] = [files[path]!, { mtime: new Date(2026, 0, 1), os: 3, attrs: (0o100644 << 16) >>> 0 }];
  }
  const bytes = zipSync(entries, { level: 9 });
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  return { bytes, sha256, files, version: manifest.version as string, checksum: `${sha256}  ${PLUGIN_ARCHIVE}\n` };
}
