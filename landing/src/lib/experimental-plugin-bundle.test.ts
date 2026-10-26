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
  expect(bundle.sha256).toBe('a5edffff4d379188a362065dd66af655008a24e247730803bde30dfedc431837');
  expect(strFromU8(bundle.files['README.md']!)).toContain('Experimental only');
  expect(strFromU8(bundle.files['README.md']!)).toContain('OAuth');
});

test('combined experiment leaves all five production archives and publishing inputs unchanged', () => {
  const production = [buildPluginBundle, buildClaudePluginBundle, ...clientPluginDistributions.map(({ build }) => build)];
  const before = production.map((build) => build(root).sha256);
  expect(before).toEqual([
    '457fe4f25ad9243b05644d23842d00e24d0ba02b2269437f46ec5fe2ea7796fe',
    '6de8d974c1f3dd96e3615333bc7f8e4cc61be378e8fe639e5bb6399a5f338532',
    'eafa30b55ba944f6d977cf8b16025e0121d854667e9e44d30836b5666e563ef6',
    'dd62fe0af8b0f7ce092780bbfc91ceb85bdd41fb57678e7ba994ac5cd5b5749b',
    '551c4ca89d3ef38e75d17cd8dfcd379061b578c442dcffd383b357e1fdb164b7',
  ]);
  const experimental = buildExperimentalPluginBundle(root);
  expect(production.map((build) => build(root).sha256)).toEqual(before);
  expect(before.includes(experimental.sha256)).toBe(false);
  expect(clientPluginDistributions.some(({ archive }) => archive.includes('experimental'))).toBe(false);
});
