import { expect, test } from 'bun:test';
import { fileURLToPath } from 'node:url';
import { strFromU8, unzipSync } from 'fflate';
import { clientPluginDistributions } from '../../config/client-plugin-downloads';
import { validateAgentPluginManifest, validateAgentPluginMcp } from './agent-plugin-validation';
import { buildExperimentalPluginBundle, EXPERIMENTAL_PLUGIN_NAME } from './experimental-plugin-bundle';
import { buildPluginBundle } from './plugin-bundle';
import { buildClaudePluginBundle } from './claude-plugin-bundle';

const root = fileURLToPath(new URL('../../', import.meta.url));

test('experimental example shares one skill set and carries native manifests beside a valid core', () => {
  const bundle = buildExperimentalPluginBundle(root);
  const json = (path: string) => JSON.parse(strFromU8(bundle.files[path]!));
  expect(validateAgentPluginManifest(json('plugin.json'))).toBe(true);
  expect(validateAgentPluginMcp(json('mcp.json'))).toBe(true);
  expect(json('plugin.json').extensions['com.openai']).toBeDefined();
  for (const path of ['plugin.json', '.codex-plugin/plugin.json', '.claude-plugin/plugin.json', '.cursor-plugin/plugin.json']) expect(json(path).name).toBe(EXPERIMENTAL_PLUGIN_NAME);
  expect(Object.keys(bundle.files).filter((path) => path.endsWith('/SKILL.md')).length).toBe(5);
  expect(json('.mcp.json')).toEqual({ mcpServers: { alera: { type: 'http', url: 'https://api.alera.build/v1/mcp' } } });
  expect(json('mcp.json').mcpServers.alera).toEqual({ type: 'streamable-http', url: 'https://api.alera.build/v1/mcp' });
  const extracted = unzipSync(bundle.bytes);
  for (const [path, bytes] of Object.entries(bundle.files)) expect(extracted[`${EXPERIMENTAL_PLUGIN_NAME}/${path}`]).toEqual(new Uint8Array(bytes));
  expect(buildExperimentalPluginBundle(root).bytes).toEqual(bundle.bytes);
  expect(bundle.sha256).toBe('4cc988f076afb2427fa98f9252cb9277d324c0ec52658ddf0097c8e38aca3c3a');
  expect(strFromU8(bundle.files['README.md']!)).toContain('Experimental only');
  expect(strFromU8(bundle.files['README.md']!)).toContain('OAuth');
});

test('combined experiment leaves all five production archives and publishing inputs unchanged', () => {
  const production = [buildPluginBundle, buildClaudePluginBundle, ...clientPluginDistributions.map(({ build }) => build)];
  const before = production.map((build) => build(root).sha256);
  expect(before).toEqual([
    '11c3462653b31974af7844f2c58c0949ab8a0d3a4067a84353f0eff051ab3166',
    '4e2765f33ba5e872b1aac3570b45083f044a7945afebc1c36b73f1e870356f63',
    '624dd8ffd789d826bf10189a65eb70b2b295bdc47cb799edd9134218b1208441',
    '46cb12a2a19804cfe3c2862443415f0259de0db338f6b6eaa4084e24f2e9bce7',
    '89f0b01584b213cd6850bb63d8bde30cb9caedb69e5eb0ac4f9de880f529e2b4',
  ]);
  const experimental = buildExperimentalPluginBundle(root);
  expect(production.map((build) => build(root).sha256)).toEqual(before);
  expect(before.includes(experimental.sha256)).toBe(false);
  expect(clientPluginDistributions.some(({ archive }) => archive.includes('experimental'))).toBe(false);
});
