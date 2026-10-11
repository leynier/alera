import { describe, expect, test } from 'bun:test';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { strFromU8, unzipSync } from 'fflate';
import { buildSkillCatalog } from '../../../edge/tool/skill_catalog';
import { clientPluginDistributions } from '../../config/client-plugin-downloads';
import { AGENT_PLUGIN_LABEL } from '../data/agent-plugin';
import { CURSOR_PLUGIN_LABEL } from '../data/cursor-plugin';
import { assertPureAgentPlugin, validateAgentPluginManifest, validateAgentPluginMcp } from './agent-plugin-validation';
import { buildClaudePluginBundle } from './claude-plugin-bundle';
import { buildPluginArchive } from './plugin-archive';
import { buildPluginBundle } from './plugin-bundle';
import { adaptPortableAleraSkill } from './portable-alera-skills';

const root = fileURLToPath(new URL('../../', import.meta.url));
const catalog = buildSkillCatalog(fileURLToPath(new URL('../../../edge/skills/', import.meta.url)));

for (const distribution of clientPluginDistributions) {
  describe(`independent ${distribution.channel} plugin`, () => {
    const bundle = distribution.build(root);
    const manifestPath = distribution.channel === 'cursor' ? '.cursor-plugin/plugin.json' : 'plugin.json';
    const read = (path: string) => strFromU8(bundle.files[path]!);
    const manifest = JSON.parse(read(manifestPath));
    const mcp = JSON.parse(read('mcp.json'));

    test('contains only the correct manifest, fixed remote MCP, and supported metadata', () => {
      expect(Object.keys(bundle.files).filter((path) => path.endsWith('plugin.json'))).toEqual([manifestPath]);
      expect(manifest.name).toBe(`alera-${distribution.channel === 'cursor' ? 'grokbot-cursor' : distribution.channel}`);
      expect(manifest.version).toBe('1.0.0');
      expect(manifest.license).toBe('MIT');
      expect(new URL(manifest.homepage).protocol).toBe('https:');
      expect(read('LICENSE')).toContain('MIT');
      if (distribution.channel === 'cursor') {
        expect(Object.keys(manifest).sort()).toEqual(['name', 'version', 'description', 'author', 'homepage', 'repository', 'license', 'keywords', 'logo'].sort());
        expect(mcp).toEqual({ mcpServers: { alera: { url: 'https://api.alera.build/v1/mcp' } } });
        expect(bundle.files[manifest.logo]).toEqual(new Uint8Array(readFileSync(new URL('../../cursor-plugin/assets/logo.png', import.meta.url))));
        expect(Array.from(bundle.files[manifest.logo]!.slice(0, 8))).toEqual([137, 80, 78, 71, 13, 10, 26, 10]);
        expect(read('README.md')).toContain('GrokBot Cursor');
        expect(read('README.md')).toContain('does not make it available');
      } else {
        expect(validateAgentPluginManifest(manifest)).toBe(true);
        expect(validateAgentPluginMcp(mcp)).toBe(true);
        expect(() => assertPureAgentPlugin(manifest, mcp)).not.toThrow();
        expect(mcp.mcpServers.alera).toEqual({ type: 'streamable-http', url: 'https://api.alera.build/v1/mcp' });
        for (const field of ['extensions', 'logo', 'icon', 'interface', 'displayName', 'skills', 'mcpServers']) expect(manifest[field]).toBeUndefined();
        expect(Object.keys(bundle.files).every((path) => ['plugin.json', 'mcp.json', 'README.md', 'LICENSE'].includes(path) || /^skills\/[^/]+\/(SKILL\.md|references\/[^/]+\.md)$/.test(path))).toBe(true);
        expect(Object.keys(bundle.files).some((path) => /com\.|\.cursor|\.claude|\.codex|openai\.yaml|schemas|assets|hooks|agents\//.test(path))).toBe(false);
      }
      if (distribution.channel === 'copilot') {
        expect(read('README.md')).toContain('Logo Investigation');
        expect(read('README.md')).toContain('does not establish that a standalone ZIP can be uploaded');
        expect(read('skills/alera-setup/SKILL.md')).toContain('Microsoft 365 Copilot');
      }
    });

    test('discovers five standard skills with contained references and preserved authority rules', () => {
      const names = new Set<string>();
      for (const path of Object.keys(bundle.files).filter((path) => path.endsWith('/SKILL.md'))) {
        const text = read(path);
        const match = /^---\n([\s\S]*?)\n---\n/.exec(text)!;
        expect(match, path).not.toBeNull();
        const fields = Bun.YAML.parse(match[1]!) as any;
        expect(fields.name).toBe(path.split('/')[1]);
        expect(fields.name).toMatch(/^(?!.*--)[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/);
        expect(fields.name.length).toBeLessThanOrEqual(64);
        expect(fields.description.length).toBeGreaterThan(0);
        expect(fields.description.length).toBeLessThanOrEqual(1024);
        expect(Object.values(fields.metadata).every((value) => typeof value === 'string')).toBe(true);
        expect(Object.keys(fields).sort()).toEqual(['description', 'metadata', 'name']);
        expect(names.has(fields.name)).toBe(false);
        names.add(fields.name);
        for (const link of text.matchAll(/\]\((references\/[^)]+)\)/g)) expect(bundle.files[`skills/${fields.name}/${link[1]}`]).toBeDefined();
      }
      expect(names.size).toBe(5);
      for (const skill of catalog.skills) {
        for (const file of skill.files) expect(read(`skills/${skill.name}/${file.path}`)).toBe(adaptPortableAleraSkill(file.text, file.path === 'SKILL.md'));
      }
      const mcpSkill = read('skills/alera-mcp/SKILL.md');
      expect(mcpSkill).toContain('honor an explicit request');
      expect(mcpSkill).toContain('preview_workspace_removal');
      expect(mcpSkill).toContain('same `clientRequestId`');
      expect(mcpSkill).toContain("client's file-reading facilities");
      expect(read('skills/alera-mcp-agent-profiles/SKILL.md')).toContain('confirmReducedProtections');
      expect(read('skills/alera-mcp-agent-profiles/SKILL.md')).toContain("user's explicit intent");
      expect(read('skills/alera-setup/SKILL.md')).toContain('Do not');
      expect(read('skills/alera-setup/SKILL.md')).toContain('insufficient_scope');
    });

    test('extracts one complete plugin folder with deterministic bytes and checksum across time zones', () => {
      const extracted = unzipSync(bundle.bytes);
      const folder = manifest.name;
      expect(Object.keys(extracted).length).toBe(Object.keys(bundle.files).length);
      for (const [path, bytes] of Object.entries(bundle.files)) expect(extracted[`${folder}/${path}`], path).toEqual(new Uint8Array(bytes));
      expect(bundle.checksum).toBe(`${createHash('sha256').update(bundle.bytes).digest('hex')}  ${distribution.archive}\n`);
      expect(distribution.build(root).bytes).toEqual(bundle.bytes);
      const script = `import { clientPluginDistributions } from './config/client-plugin-downloads.ts'; console.log(clientPluginDistributions.find(d => d.channel === '${distribution.channel}').build(process.cwd()).sha256);`;
      for (const tz of ['UTC', 'America/Mexico_City', 'Asia/Tokyo']) expect(execFileSync(process.execPath, ['-e', script], { cwd: root, env: { ...process.env, TZ: tz }, encoding: 'utf8' }).trim()).toBe(bundle.sha256);
    });
  });
}

test('pinned official schemas reject provider inventions and invalid standard remote transports', () => {
  const manifest = JSON.parse(readFileSync(new URL('../../agent-plugin/plugin.json', import.meta.url), 'utf8'));
  const mcp = JSON.parse(readFileSync(new URL('../../agent-plugin/mcp.json', import.meta.url), 'utf8'));
  for (const field of ['logo', 'icon', 'interface', 'displayName', 'mcpServers']) expect(validateAgentPluginManifest({ ...manifest, [field]: {} })).toBe(false);
  for (const name of ['Wrong-Name', 'a--b', 'a..b', '-a', 'a'.repeat(65)]) expect(validateAgentPluginManifest({ ...manifest, name })).toBe(false);
  expect(validateAgentPluginManifest({ ...manifest, extensions: { 'com.github.copilot': {} } })).toBe(true);
  expect(() => assertPureAgentPlugin({ ...manifest, extensions: { 'com.github.copilot': {} } }, mcp)).toThrow('cannot contain extensions');
  for (const server of [{ type: 'http', url: 'https://api.alera.build/v1/mcp' }, { url: 'https://api.alera.build/v1/mcp' }, { ...mcp.mcpServers.alera, extensions: { 'com.openai': {} } }, { ...mcp.mcpServers.alera, oauth: {} }]) expect(validateAgentPluginMcp({ ...mcp, mcpServers: { alera: server } })).toBe(false);
  expect(() => assertPureAgentPlugin(manifest, { ...mcp, mcpServers: { alera: { ...mcp.mcpServers.alera, headers: { Authorization: 'test-only' } } } })).toThrow('credential-free');
  for (const [file, expected] of [['plugin.schema.json', '0a4aad95ce337878ad38802ebf0daa3fde76abe3f65400c86bcbb1ec0b3ab883'], ['mcp.schema.json', '6539175bfcdf43085855183e86da40ea94b166547a72b47ae9a0a390516d3acb']]) expect(createHash('sha256').update(readFileSync(new URL(`../../config/schemas/agent-plugins-1.0.0/${file}`, import.meta.url))).digest('hex')).toBe(expected);
});

test('archive boundaries reject traversal and preserve original ChatGPT and Claude bytes', () => {
  for (const path of ['/absolute', '../escape', './dot', 'a//b', 'a\\b']) expect(() => buildPluginArchive({ [path]: new Uint8Array() }, 'alera-test', 'test.zip')).toThrow('Unsafe plugin path');
  expect(CURSOR_PLUGIN_LABEL).toBe('GrokBot Cursor');
  expect(AGENT_PLUGIN_LABEL).toBe('Agent Plugin');
  expect(buildPluginBundle(root).sha256).toBe('4f1fedc3116746ebdc0dc006bab198520bc205660b0fb6242bd0f80305811b91');
  expect(buildClaudePluginBundle(root).sha256).toBe('696bd234f1ce0d731a4abecae67f3171910f8b2064cd2af7c16646aaf1b044e4');
  const names = [buildPluginBundle(root), buildClaudePluginBundle(root), ...clientPluginDistributions.map(({ build }) => build(root))].map(({ sha256 }) => sha256);
  expect(new Set(names).size).toBe(5);
});
