import { createHash } from 'node:crypto';
import { strFromU8, unzipSync } from 'fflate';
import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';
import { PLUGIN_ARCHIVE, PLUGIN_CHECKSUM_URL, PLUGIN_DOWNLOAD_URL, PLUGIN_VERSION } from '../src/data/plugin';

test('downloads the complete plugin from the download page', async ({ page, request }) => {
  await page.goto('/download');
  const button = page.getByRole('link', { name: 'Download Plugin ZIP' });
  await expect(button).toHaveAttribute('href', PLUGIN_DOWNLOAD_URL);
  const pending = page.waitForEvent('download');
  await button.click();
  expect((await pending).suggestedFilename()).toBe(PLUGIN_ARCHIVE);

  const response = await request.get(PLUGIN_DOWNLOAD_URL);
  expect(response.status()).toBe(200);
  const bytes = await response.body();
  const files = unzipSync(bytes);
  const manifest = JSON.parse(strFromU8(files['alera/plugin.json']!));
  expect(manifest.version).toBe(PLUGIN_VERSION);
  expect(files['alera/.codex-plugin/plugin.json']).toBeDefined();
  expect(files['alera/skills/alera-mcp/references/workspaces.md']).toBeDefined();
  expect(files['alera/skills/alera-setup/SKILL.md']).toBeDefined();
  expect(files['alera/assets/logo.png']).toBeDefined();
  const checksum = await request.get(PLUGIN_CHECKSUM_URL);
  expect(checksum.status()).toBe(200);
  expect(await checksum.text()).toBe(`${createHash('sha256').update(bytes).digest('hex')}  ${PLUGIN_ARCHIVE}\n`);
});

for (const width of [1440, 390]) {
  test(`shows usable plugin installation and download at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto('/download#plugin');
    await expect(page.getByRole('link', { name: 'Download Plugin ZIP' })).toBeVisible();
    await page.getByRole('link', { name: 'Installation Guide' }).click();
    await expect(page).toHaveURL(/\/docs\/plugin$/);
    await expect(page.getByRole('heading', { level: 1 })).toHaveText('Alera Plugin');
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', 'https://alera.build/docs/plugin');
    await expect(page.getByRole('link', { name: 'Download Plugin ZIP' })).toHaveAttribute('href', PLUGIN_DOWNLOAD_URL);
    await expect(page.getByRole('link', { name: 'SHA-256 Checksum' })).toHaveAttribute('href', PLUGIN_CHECKSUM_URL);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    const violations = (await new AxeBuilder({ page }).analyze()).violations.filter((item) => ['serious', 'critical'].includes(item.impact ?? ''));
    expect(violations.map((item) => `${item.id}: ${item.help}`)).toEqual([]);
  });
}
