import { createHash } from 'node:crypto';
import { strFromU8, unzipSync } from 'fflate';
import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';
import { CLAUDE_PLUGIN_ALIAS, CLAUDE_PLUGIN_ALIAS_URL, CLAUDE_PLUGIN_ARCHIVE, CLAUDE_PLUGIN_DOWNLOAD_URL, CLAUDE_PLUGIN_VERSION } from '../src/data/claude-plugin';

test('downloads identical Claude web ZIP and .plugin archives with matching checksums', async ({ page, request }) => {
  await page.goto('/download');
  let first: Buffer | undefined;
  for (const [label, url, name] of [
    ['Download Claude Plugin ZIP', CLAUDE_PLUGIN_DOWNLOAD_URL, CLAUDE_PLUGIN_ARCHIVE],
    ['Download .plugin', CLAUDE_PLUGIN_ALIAS_URL, CLAUDE_PLUGIN_ALIAS],
  ] as const) {
    const button = page.getByRole('link', { name: label, exact: true });
    await expect(button).toHaveAttribute('href', url);
    const pending = page.waitForEvent('download');
    await button.click();
    expect((await pending).suggestedFilename()).toBe(name);
    const response = await request.get(url);
    expect(response.status()).toBe(200);
    const bytes = await response.body();
    if (first) expect(bytes).toEqual(first); else first = bytes;
    const files = unzipSync(bytes);
    expect(JSON.parse(strFromU8(files['.claude-plugin/plugin.json']!)).version).toBe(CLAUDE_PLUGIN_VERSION);
    expect(files['skills/alera-setup/SKILL.md']).toBeDefined();
    expect(files['skills/alera-mcp/references/workspaces.md']).toBeDefined();
    expect(files['.codex-plugin/plugin.json']).toBeUndefined();
    const checksum = await request.get(`${url}.sha256`);
    expect(checksum.status()).toBe(200);
    expect(await checksum.text()).toBe(`${createHash('sha256').update(bytes).digest('hex')}  ${name}\n`);
  }
  await expect(page.getByRole('link', { name: 'Download Plugin ZIP', exact: true })).toHaveAttribute('href', '/downloads/alera-plugin.zip');
});

for (const width of [1440, 390]) {
  test(`shows Claude web upload and OAuth guidance at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto('/download#claude-plugin');
    await expect(page.getByRole('link', { name: 'Download Claude Plugin ZIP', exact: true })).toBeVisible();
    await page.getByRole('link', { name: 'Claude Web Setup' }).click();
    await expect(page).toHaveURL(/\/docs\/claude-plugin$/);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Alera For Claude Web');
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', 'https://alera.build/docs/claude-plugin');
    await expect(page.getByRole('link', { name: 'Download Claude Plugin ZIP' })).toHaveAttribute('href', CLAUDE_PLUGIN_DOWNLOAD_URL);
    await expect(page.getByRole('link', { name: 'Download .plugin', exact: true })).toHaveAttribute('href', CLAUDE_PLUGIN_ALIAS_URL);
    await expect(page.getByText('This package does not pin the web scope request to read and execute.', { exact: false })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    const violations = (await new AxeBuilder({ page }).analyze()).violations.filter((item) => ['serious', 'critical'].includes(item.impact ?? ''));
    expect(violations.map((item) => `${item.id}: ${item.help}`)).toEqual([]);
  });
}
