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
  expect(bundle.sha256).toBe('9b71c90842f952440617b84bd24334de9bec24c3549753023b35ac2233ebda29');
  expect(strFromU8(bundle.files['README.md']!)).toContain('Experimental only');
  expect(strFromU8(bundle.files['README.md']!)).toContain('OAuth');
});

test('combined experiment leaves all five production archives and publishing inputs unchanged', () => {
  const production = [buildPluginBundle, buildClaudePluginBundle, ...clientPluginDistributions.map(({ build }) => build)];
  const before = production.map((build) => build(root).sha256);
  expect(before).toEqual([
    '2664cc0b9fe80cf6498b55be58c5c8a7d534d29384e14fc0cf446f56a4f0a66a',
    '8d14c3a88ecbef19d568cba87b564dba0d6b79f426c9ace7e7ee897b9862c725',
    'a32fd889cf0d3f5741b2ef74c75639353d87c82405e2d769bd690e2408831348',
    '23f160fd4b5bee0137182e7ebab8694949d91211a17f4738f12a7bb25cc757d5',
    'f92bd5d93bfceb8bdb893fb846d002e652391db369f2d5a6fe178d9486266a0a',
  ]);
  const experimental = buildExperimentalPluginBundle(root);
  expect(production.map((build) => build(root).sha256)).toEqual(before);
  expect(before.includes(experimental.sha256)).toBe(false);
  expect(clientPluginDistributions.some(({ archive }) => archive.includes('experimental'))).toBe(false);
});
