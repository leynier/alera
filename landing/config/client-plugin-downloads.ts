import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { AstroIntegration } from 'astro';
import { AGENT_PLUGIN_ARCHIVE } from '../src/data/agent-plugin';
import { COPILOT_PLUGIN_ARCHIVE } from '../src/data/copilot-plugin';
import { CURSOR_PLUGIN_ARCHIVE } from '../src/data/cursor-plugin';
import { buildAgentPluginBundle } from '../src/lib/agent-plugin-bundle';
import { buildCopilotPluginBundle } from '../src/lib/copilot-plugin-bundle';
import { buildCursorPluginBundle } from '../src/lib/cursor-plugin-bundle';

export const clientPluginDistributions = [
  { channel: 'agent', archive: AGENT_PLUGIN_ARCHIVE, build: buildAgentPluginBundle },
  { channel: 'copilot', archive: COPILOT_PLUGIN_ARCHIVE, build: buildCopilotPluginBundle },
  { channel: 'cursor', archive: CURSOR_PLUGIN_ARCHIVE, build: buildCursorPluginBundle },
] as const;

export function clientPluginDownloads(): AstroIntegration {
  let root: string;
  return {
    name: 'alera-client-plugin-downloads',
    hooks: {
      'astro:config:done': ({ config }) => { root = fileURLToPath(config.root); },
      'astro:build:done': ({ dir, logger }) => {
        const downloads = new URL('downloads/', dir);
        mkdirSync(downloads, { recursive: true });
        for (const distribution of clientPluginDistributions) {
          const bundle = distribution.build(root);
          writeFileSync(new URL(distribution.archive, downloads), bundle.bytes);
          writeFileSync(new URL(`${distribution.archive}.sha256`, downloads), bundle.checksum);
          logger.info(`packaged ${distribution.channel} plugin ${bundle.version} (${bundle.bytes.length} bytes)`);
        }
      },
      'astro:server:setup': ({ server }) => {
        server.middlewares.use((request, response, next) => {
          const path = request.url?.split('?')[0];
          const distribution = clientPluginDistributions.find(({ archive }) => path === `/downloads/${archive}` || path === `/downloads/${archive}.sha256`);
          if (!distribution) return next();
          const bundle = distribution.build(root);
          const archive = path === `/downloads/${distribution.archive}`;
          response.setHeader('Content-Type', archive ? 'application/zip' : 'text/plain; charset=utf-8');
          if (archive) response.setHeader('Content-Disposition', `attachment; filename="${distribution.archive}"`);
          response.end(archive ? bundle.bytes : bundle.checksum);
        });
      },
    },
  };
}
