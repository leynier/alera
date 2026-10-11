import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { AstroIntegration } from 'astro';
import { CLAUDE_PLUGIN_ALIAS, CLAUDE_PLUGIN_ARCHIVE } from '../src/data/claude-plugin';
import { buildClaudePluginBundle } from '../src/lib/claude-plugin-bundle';

export function claudePluginDownload(): AstroIntegration {
  let root: string;
  const names = [CLAUDE_PLUGIN_ARCHIVE, CLAUDE_PLUGIN_ALIAS] as const;
  return {
    name: 'alera-claude-plugin-download',
    hooks: {
      'astro:config:done': ({ config }) => { root = fileURLToPath(config.root); },
      'astro:build:done': ({ dir, logger }) => {
        const bundle = buildClaudePluginBundle(root);
        const downloads = new URL('downloads/', dir);
        mkdirSync(downloads, { recursive: true });
        for (const name of names) {
          writeFileSync(new URL(name, downloads), bundle.bytes);
          writeFileSync(new URL(`${name}.sha256`, downloads), bundle.checksums[name]!);
        }
        logger.info(`packaged Alera for Claude ${bundle.version} (${bundle.bytes.length} bytes)`);
      },
      'astro:server:setup': ({ server }) => {
        server.middlewares.use((request, response, next) => {
          const path = request.url?.split('?')[0];
          const name = names.find((name) => path === `/downloads/${name}` || path === `/downloads/${name}.sha256`);
          if (!name) return next();
          const bundle = buildClaudePluginBundle(root);
          const archive = path === `/downloads/${name}`;
          response.setHeader('Content-Type', archive ? 'application/zip' : 'text/plain; charset=utf-8');
          if (archive) response.setHeader('Content-Disposition', `attachment; filename="${name}"`);
          response.end(archive ? bundle.bytes : bundle.checksums[name]);
        });
      },
    },
  };
}
