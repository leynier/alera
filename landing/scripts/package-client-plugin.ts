import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { clientPluginDistributions } from '../config/client-plugin-downloads';

const root = fileURLToPath(new URL('../', import.meta.url));
const distribution = clientPluginDistributions.find(({ channel }) => channel === process.argv[2]);
if (!distribution) throw new Error('Choose a plugin distribution: agent, copilot, cursor');
const output = resolve(root, process.argv[3] ?? `../build/${distribution.channel}-plugin`);
const bundle = distribution.build(root);
const manifest = JSON.parse(new TextDecoder().decode(bundle.files['plugin.json'] ?? bundle.files['.cursor-plugin/plugin.json']!));
mkdirSync(output, { recursive: true });
writeFileSync(resolve(output, distribution.archive), bundle.bytes);
writeFileSync(resolve(output, `${distribution.archive}.sha256`), bundle.checksum);
for (const [path, bytes] of Object.entries(bundle.files)) {
  const target = resolve(output, manifest.name, path);
  mkdirSync(resolve(target, '..'), { recursive: true });
  writeFileSync(target, bytes);
}
console.log(`${distribution.channel} ${bundle.version}: ${resolve(output, distribution.archive)}`);
console.log(`SHA-256: ${bundle.sha256}`);
