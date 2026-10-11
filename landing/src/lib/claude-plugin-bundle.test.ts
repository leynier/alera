import { describe, expect, test } from 'bun:test';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { strFromU8, unzipSync } from 'fflate';
import { buildSkillCatalog } from '../../../edge/tool/skill_catalog';
import { CLAUDE_PLUGIN_ALIAS, CLAUDE_PLUGIN_ARCHIVE, CLAUDE_PLUGIN_MCP_URL, CLAUDE_PLUGIN_VERSION } from '../data/claude-plugin';
import { adaptClaudeSkill, buildClaudePluginBundle } from './claude-plugin-bundle';
import { buildPluginBundle } from './plugin-bundle';

const root = fileURLToPath(new URL('../../', import.meta.url));
const bundle = buildClaudePluginBundle(root);
const extracted = unzipSync(bundle.bytes);
const read = (path: string) => strFromU8(extracted[path]!);
const json = (path: string) => JSON.parse(read(path));

describe('independent Claude web plugin', () => {
  test('has one root manifest, safe regular files, and upload-compatible limits', () => {
    expect(Object.keys(extracted).filter((path) => path.endsWith('plugin.json'))).toEqual(['.claude-plugin/plugin.json']);
    expect(Object.keys(extracted).length).toBeLessThanOrEqual(5000);
    expect(Object.values(extracted).reduce((sum, file) => sum + file.length, 0)).toBeLessThan(200_000_000);
    expect(bundle.bytes.length).toBeLessThan(200_000_000);
    for (const [path, bytes] of Object.entries(bundle.files)) {
      expect(extracted[path], path).toEqual(new Uint8Array(bytes));
      expect(path).toMatch(/^[a-zA-Z0-9_ .\/(),-]+$/);
      expect(path.split('/').length).toBeLessThanOrEqual(12);
      expect(path.length).toBeLessThanOrEqual(472);
      expect(path.split('/').every((part) => part.length <= 255 && part !== '..' && part !== '.')).toBe(true);
      expect(path).not.toMatch(/(^bin\/|\.zip$|openai\.yaml$|^\.codex-plugin\/|^hooks\/|^agents\/)/);
    }
    expect(read('LICENSE')).toContain('MIT');
    expect(read('README.md').split(/\s+/).length).toBeGreaterThan(40);
  });

  test('uses supported metadata, contained assets, and a fixed remote connector without credentials', () => {
    const manifest = json('.claude-plugin/plugin.json');
    expect(manifest.name).toMatch(/^[a-z0-9-]{1,64}$/);
    expect(manifest.version).toBe(CLAUDE_PLUGIN_VERSION);
    expect(manifest.displayName.length).toBeLessThanOrEqual(64);
    expect(manifest.description.length).toBeLessThanOrEqual(500);
    expect(extracted[manifest.icon.slice(2)]).toBeDefined();
    expect(Array.from(extracted['assets/logo.png']!.slice(0, 8))).toEqual([137, 80, 78, 71, 13, 10, 26, 10]);
    for (const field of ['documentationUrl', 'supportUrl', 'privacyPolicyUrl', 'termsOfServiceUrl']) expect(new URL(manifest[field]).protocol).toBe('https:');
    expect(json('.mcp.json')).toEqual({ mcpServers: { alera: { type: 'http', url: CLAUDE_PLUGIN_MCP_URL } } });
    for (const field of ['extensions', 'userConfig', 'settings', 'hooks', 'agents', 'defaultEnabled', 'dependencies']) expect(manifest[field]).toBeUndefined();
  });

  test('adapts all workflow skills while preserving every maintained reference and permission rule', () => {
    const catalog = buildSkillCatalog(fileURLToPath(new URL('../../../edge/skills/', import.meta.url)));
    const names = new Set<string>();
    for (const path of Object.keys(extracted).filter((path) => path.endsWith('/SKILL.md'))) {
      const text = read(path);
      const frontmatter = /^---\n([\s\S]*?)\n---\n/.exec(text)!;
      expect(frontmatter, path).not.toBeNull();
      const fields = Bun.YAML.parse(frontmatter[1]!) as any;
      expect(fields.name).toBe(path.split('/')[1]);
      expect(fields.description.length).toBeGreaterThan(0);
      expect(fields.description).not.toMatch(/<[^>]+>/);
      expect(fields['allowed-tools']).toBeUndefined();
      expect(names.has(fields.name)).toBe(false);
      names.add(fields.name);
      for (const link of text.matchAll(/\]\((references\/[^)]+)\)/g)) expect(extracted[`skills/${fields.name}/${link[1]}`]).toBeDefined();
    }
    expect(names.size).toBe(5);
    for (const skill of catalog.skills) {
      for (const file of skill.files) expect(read(`skills/${skill.name}/${file.path}`)).toBe(adaptClaudeSkill(file.text, file.path === 'SKILL.md'));
    }
    expect(read('skills/alera-mcp/SKILL.md')).toContain("Claude's skill file-reading facilities");
    expect(read('skills/alera-mcp/SKILL.md')).toContain('honor an explicit request');
    expect(read('skills/alera-setup/SKILL.md')).toContain('does not restrict those scopes');
  });

  test('is deterministic across time zones and has separate checksums for identical ZIP aliases', () => {
    expect(buildClaudePluginBundle(root).bytes).toEqual(bundle.bytes);
    for (const name of [CLAUDE_PLUGIN_ARCHIVE, CLAUDE_PLUGIN_ALIAS] as const) expect(bundle.checksums[name]).toBe(`${bundle.sha256}  ${name}\n`);
    const script = "import { buildClaudePluginBundle } from './src/lib/claude-plugin-bundle.ts'; console.log(buildClaudePluginBundle(process.cwd()).sha256);";
    for (const tz of ['UTC', 'America/Mexico_City', 'Asia/Tokyo']) {
      expect(execFileSync(process.execPath, ['-e', script], { cwd: root, env: { ...process.env, TZ: tz }, encoding: 'utf8' }).trim()).toBe(bundle.sha256);
    }
  });

  test('preserves the existing ChatGPT package byte for byte', () => {
    expect(buildPluginBundle(root).sha256).toBe('4f1fedc3116746ebdc0dc006bab198520bc205660b0fb6242bd0f80305811b91');
  });
});
