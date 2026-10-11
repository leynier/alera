import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CLAUDE_PLUGIN_ALIAS, CLAUDE_PLUGIN_ARCHIVE, CLAUDE_PLUGIN_NAME } from '../src/data/claude-plugin';
import { buildClaudePluginBundle } from '../src/lib/claude-plugin-bundle';

const root = fileURLToPath(new URL('../', import.meta.url));
const output = resolve(root, process.argv[2] ?? '../build/claude-plugin');
const bundle = buildClaudePluginBundle(root);
mkdirSync(output, { recursive: true });
for (const name of [CLAUDE_PLUGIN_ARCHIVE, CLAUDE_PLUGIN_ALIAS] as const) {
  writeFileSync(resolve(output, name), bundle.bytes);
  writeFileSync(resolve(output, `${name}.sha256`), bundle.checksums[name]!);
}
for (const [path, bytes] of Object.entries(bundle.files)) {
  const target = resolve(output, CLAUDE_PLUGIN_NAME, path);
  mkdirSync(resolve(target, '..'), { recursive: true });
  writeFileSync(target, bytes);
}
console.log(`Alera for Claude ${bundle.version}: ${resolve(output, CLAUDE_PLUGIN_ARCHIVE)}`);
console.log(`SHA-256: ${bundle.sha256}`);
