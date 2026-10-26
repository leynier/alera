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
  expect(bundle.sha256).toBe('e6dc6db58b9de08a54b95de9a7ed353861b93f1ea188b3bf88ad769e44133640');
  expect(strFromU8(bundle.files['README.md']!)).toContain('Experimental only');
  expect(strFromU8(bundle.files['README.md']!)).toContain('OAuth');
});

test('combined experiment leaves all five production archives and publishing inputs unchanged', () => {
  const production = [buildPluginBundle, buildClaudePluginBundle, ...clientPluginDistributions.map(({ build }) => build)];
  const before = production.map((build) => build(root).sha256);
  expect(before).toEqual([
    'e8d46d07516054659b60d877f06937c13418e00537766e9d0be7a844927818bf',
    '84fe65a7fa6587a47febee3778f1f2680b22d1a460c72d549ee6cbf5775c7a7d',
    '96b5fb47aac4f1c47a315f0dc6176510eedda61d7cd42d3adf194495ad279c85',
    '1abc4b3b670b0d201d295f65c96497f79380adb29c6c923c5c1e7316916f4f45',
    '300c125c892af9ad196d50171fcbbffeada832968f3c273da4ad059ff43d2bfc',
  ]);
  const experimental = buildExperimentalPluginBundle(root);
  expect(production.map((build) => build(root).sha256)).toEqual(before);
  expect(before.includes(experimental.sha256)).toBe(false);
  expect(clientPluginDistributions.some(({ archive }) => archive.includes('experimental'))).toBe(false);
});
