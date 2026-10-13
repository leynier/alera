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
  expect(bundle.sha256).toBe('f313bfbd86899cbe549b4f34f97171bba4b250d463e0acc6e8b7b8c33d769f9a');
  expect(strFromU8(bundle.files['README.md']!)).toContain('Experimental only');
  expect(strFromU8(bundle.files['README.md']!)).toContain('OAuth');
});

test('combined experiment leaves all five production archives and publishing inputs unchanged', () => {
  const production = [buildPluginBundle, buildClaudePluginBundle, ...clientPluginDistributions.map(({ build }) => build)];
  const before = production.map((build) => build(root).sha256);
  expect(before).toEqual([
    'd2f22c713d20b6140485884856fad162d3595c00f6c71d1b33019b2c8ba3c3ff',
    'd2b79707e99c35b4b86db4c964a62c31d3b21bfef485ee71f526657d4adeae13',
    '43b1517e0ef7beab0d263e5cbb3c4c690fc869008061ebd579acce2bc29cba56',
    '766090af8dbea45418c680ac086713f4abe6480580486bd98eb7f3dbb3460bde',
    'f1795bf5b922feb028f6a13c1214ccb18bc4479aaf6942b491191bf9889a3555',
  ]);
  const experimental = buildExperimentalPluginBundle(root);
  expect(production.map((build) => build(root).sha256)).toEqual(before);
  expect(before.includes(experimental.sha256)).toBe(false);
  expect(clientPluginDistributions.some(({ archive }) => archive.includes('experimental'))).toBe(false);
});
