import { describe, expect, test } from 'bun:test';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { strFromU8, unzipSync } from 'fflate';
import { buildSkillCatalog } from '../../../edge/tool/skill_catalog';
import { PLUGIN_ARCHIVE, PLUGIN_MCP_URL, PLUGIN_NAME, PLUGIN_SKILLS } from '../data/plugin';
import { buildPluginBundle } from './plugin-bundle';

const root = fileURLToPath(new URL('../../', import.meta.url));
const bundle = buildPluginBundle(root);
const extracted = unzipSync(bundle.bytes);
const read = (path: string) => strFromU8(extracted[`${PLUGIN_NAME}/${path}`]!);
const json = (path: string) => JSON.parse(read(path));

describe('downloadable Alera plugin', () => {
  test('produces an extractable, deterministic ZIP with a matching checksum', () => {
    expect(buildPluginBundle(root).bytes).toEqual(bundle.bytes);
    expect(Object.keys(extracted).length).toBe(Object.keys(bundle.files).length);
    expect(bundle.checksum).toBe(`${createHash('sha256').update(bundle.bytes).digest('hex')}  ${PLUGIN_ARCHIVE}\n`);
    for (const [path, bytes] of Object.entries(bundle.files)) {
      expect(extracted[`${PLUGIN_NAME}/${path}`], path).toEqual(new Uint8Array(bytes));
    }
  });

  test('produces the same archive in different build host time zones', () => {
    const script = `import { buildPluginBundle } from './src/lib/plugin-bundle.ts'; console.log(buildPluginBundle(process.cwd()).sha256);`;
    for (const tz of ['UTC', 'America/Mexico_City', 'Asia/Tokyo']) {
      const digest = execFileSync(process.execPath, ['-e', script], { cwd: root, env: { ...process.env, TZ: tz }, encoding: 'utf8' });
      expect(digest.trim(), tz).toBe(bundle.sha256);
    }
  });

  test('includes every maintained MCP skill and reference without changing the instructions', () => {
    const catalog = buildSkillCatalog(fileURLToPath(new URL('../../../edge/skills/', import.meta.url)));
    expect(catalog.skills.map((skill) => skill.name).sort()).toEqual(PLUGIN_SKILLS.map((skill) => skill.name).sort());
    for (const skill of catalog.skills) {
      for (const file of skill.files) expect(read(`skills/${skill.name}/${file.path}`)).toBe(file.text);
      const metadata = Bun.YAML.parse(read(`skills/${skill.name}/agents/openai.yaml`)) as any;
      expect(metadata.interface.short_description.length).toBeGreaterThanOrEqual(25);
      expect(metadata.interface.short_description.length).toBeLessThanOrEqual(64);
      expect(metadata.dependencies.tools).toEqual([{
        type: 'mcp', value: 'alera', description: 'Connect to your Alera runtimes', transport: 'streamable_http', url: PLUGIN_MCP_URL,
      }]);
    }
  });

  test('declares one OAuth MCP connection with no embedded credentials', () => {
    const portable = json('mcp.json');
    expect(portable.$schema).toBe('https://agent-plugins.org/schemas/1.0.0/mcp.schema.json');
    expect(Object.keys(portable.mcpServers)).toEqual(['alera']);
    expect(portable.mcpServers.alera).toEqual({
      type: 'streamable-http', url: PLUGIN_MCP_URL,
      extensions: { 'com.openai': { auth: { type: 'oauth', client: { mode: 'cimd' }, baseScopes: ['mcp:read', 'mcp:execute'] } } },
    });
    const compatibility = json('.mcp.json');
    expect(compatibility.mcpServers.alera.url).toBe(PLUGIN_MCP_URL);
    expect(compatibility.mcpServers.alera.type).toBeUndefined();
    for (const config of ['plugin.json', 'mcp.json', '.mcp.json', '.codex-plugin/plugin.json']) {
      expect(read(config)).not.toMatch(/"(?:clientSecret|accessToken|refreshToken|Authorization|headers)"\s*:/);
    }
  });

  test('resolves presentation and onboarding paths in both manifest formats', () => {
    const portable = json('plugin.json');
    const compatibility = json('.codex-plugin/plugin.json');
    expect(portable.$schema).toBe('https://agent-plugins.org/schemas/1.0.0/plugin.schema.json');
    expect(compatibility.name).toBe(portable.name);
    expect(compatibility.version).toBe(portable.version);
    expect(compatibility.skills).toBe('./skills/');
    expect(compatibility.mcpServers).toBe('./.mcp.json');
    expect(compatibility.interface).toEqual(portable.extensions['com.openai'].interface);
    for (const manifest of [portable, compatibility]) {
      const openai = manifest.extensions['com.openai'];
      const presentation = openai.interface ?? manifest.interface;
      for (const path of [openai.onboardingSkill, presentation.composerIcon, presentation.composerIconDark, presentation.logo, presentation.logoDark]) {
        expect(path).toStartWith('./');
        expect(extracted[`${PLUGIN_NAME}/${path.slice(2)}`]?.byteLength).toBeGreaterThan(0);
      }
    }
    expect(extracted[`${PLUGIN_NAME}/assets/logo.png`]).toEqual(new Uint8Array(readFileSync(new URL('../../../assets/logo/alera-logo.png', import.meta.url))));
    expect(extracted[`${PLUGIN_NAME}/assets/logo-dark.png`]).toEqual(new Uint8Array(readFileSync(new URL('../../public/logo.png', import.meta.url))));
    for (const path of ['assets/logo.png', 'assets/logo-dark.png']) {
      const png = Buffer.from(extracted[`${PLUGIN_NAME}/${path}`]!);
      expect(png.subarray(0, 8)).toEqual(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
      const width = png.readUInt32BE(16);
      const height = png.readUInt32BE(20);
      expect(width).toBe(height);
      expect(width).toBeGreaterThanOrEqual(48);
      expect(width).toBeLessThanOrEqual(4096);
      expect(png.byteLength).toBeLessThanOrEqual(5 * 1024 * 1024);
    }
    const setup = Bun.YAML.parse(read('skills/alera-setup/agents/openai.yaml')) as any;
    expect(setup.dependencies.tools[0].url).toBe(PLUGIN_MCP_URL);
  });

  test('keeps the marketplace source inside the extracted folder', () => {
    const marketplace = json('.agents/plugins/marketplace.json');
    expect(marketplace.name).toBe(PLUGIN_NAME);
    expect(marketplace.plugins).toHaveLength(1);
    expect(marketplace.plugins[0].source).toEqual({ source: 'local', path: './' });
    expect(marketplace.plugins[0].policy).toEqual({ installation: 'AVAILABLE', authentication: 'ON_INSTALL' });
    expect(read('plugin.json')).toContain(`"name": "${marketplace.plugins[0].name}"`);
    for (const path of Object.keys(extracted)) {
      expect(path).toStartWith(`${PLUGIN_NAME}/`);
      expect(path.split('/')).not.toContain('..');
      expect(path).not.toContain('\\');
      expect(path).not.toMatch(/(?:^|\/)\.env(?:\.|$)/);
    }
  });
});
