import { defineConfig } from 'astro/config';
import mdx from '@astrojs/mdx';
import sitemap from '@astrojs/sitemap';
import tailwindcss from '@tailwindcss/vite';
import { aleraCodeTheme } from './config/alera-code-theme.mjs';
import { docsSearchIndex } from './config/docs-search-index.mjs';
import { pluginDownload } from './config/plugin-download.ts';
import { claudePluginDownload } from './config/claude-plugin-download.ts';

const unlistedPaths = new Set(['/404', '/signed-in']);

// Canonical URLs on this site carry no trailing slash, so the sitemap drops
// it too; otherwise search engines see two spellings of every page.
function withoutTrailingSlash(url) {
  const parsed = new URL(url);
  if (parsed.pathname !== '/' && parsed.pathname.endsWith('/')) {
    parsed.pathname = parsed.pathname.slice(0, -1);
  }
  return parsed.toString();
}

export default defineConfig({
  site: 'https://alera.build',
  output: 'static',
  build: {
    inlineStylesheets: 'auto',
  },
  markdown: {
    shikiConfig: {
      theme: aleraCodeTheme,
    },
  },
  integrations: [
    mdx(),
    sitemap({
      filter: (page) => !unlistedPaths.has(new URL(withoutTrailingSlash(page)).pathname),
      serialize: (item) => ({ ...item, url: withoutTrailingSlash(item.url) }),
    }),
    docsSearchIndex(),
    pluginDownload(),
    claudePluginDownload(),
  ],
  vite: {
    plugins: [tailwindcss()],
  },
});
