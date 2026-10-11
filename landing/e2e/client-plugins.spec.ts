import { createHash } from 'node:crypto';
import { strFromU8, unzipSync } from 'fflate';
import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';
import { clientPluginDistributions } from '../config/client-plugin-downloads';

const guides = [
  { id: 'grokbot-cursor-plugin', label: 'GrokBot Cursor', button: 'Download GrokBot Cursor ZIP', limit: 'this ZIP does not provide a documented Grok Bot installation route' },
  { id: 'agent-plugin', label: 'Agent Plugin', button: 'Download Agent Plugin ZIP', limit: 'Agent Plugins 1.0 defines no OAuth settings' },
  { id: 'copilot-plugin', label: 'GitHub Copilot', button: 'Download Copilot Plugin ZIP', limit: 'no supported image field inside com.github.copilot' },
];

test('serves all five independent plugin downloads with valid checksums and existing aliases', async ({ page, request }) => {
  await page.goto('/download');
  const previous = [
    ['Download Plugin ZIP', 'alera-plugin.zip', '4f1fedc3116746ebdc0dc006bab198520bc205660b0fb6242bd0f80305811b91'],
    ['Download Claude Plugin ZIP', 'alera-claude-plugin.zip', '696bd234f1ce0d731a4abecae67f3171910f8b2064cd2af7c16646aaf1b044e4'],
  ] as const;
  for (const [button, archive, checksum] of previous) {
    await expect(page.getByRole('link', { name: button, exact: true })).toHaveAttribute('href', `/downloads/${archive}`);
    const response = await request.get(`/downloads/${archive}`);
    expect(response.status()).toBe(200);
    expect(createHash('sha256').update(await response.body()).digest('hex')).toBe(checksum);
  }
  for (const distribution of clientPluginDistributions) {
    const guide = guides.find(({ id }) => id.includes(distribution.channel === 'cursor' ? 'cursor' : distribution.channel))!;
    const link = page.getByRole('link', { name: guide.button, exact: true });
    await expect(link).toHaveAttribute('href', `/downloads/${distribution.archive}`);
    const pending = page.waitForEvent('download');
    await link.click();
    expect((await pending).suggestedFilename()).toBe(distribution.archive);
    const response = await request.get(`/downloads/${distribution.archive}`);
    expect(response.status()).toBe(200);
    const bytes = await response.body();
    const checksum = await request.get(`/downloads/${distribution.archive}.sha256`);
    expect(checksum.status()).toBe(200);
    expect(await checksum.text()).toBe(`${createHash('sha256').update(bytes).digest('hex')}  ${distribution.archive}\n`);
    const files = unzipSync(bytes);
    const manifestPath = Object.keys(files).find((path) => path.endsWith('/plugin.json'))!;
    const manifest = JSON.parse(strFromU8(files[manifestPath]!));
    expect(manifest.version).toBe('1.0.0');
    expect(files[`${manifest.name}/skills/alera-setup/SKILL.md`]).toBeDefined();
    expect(files[`${manifest.name}/skills/alera-mcp/references/workspaces.md`]).toBeDefined();
  }
  await expect(page.getByRole('link', { name: 'Download .plugin', exact: true })).toHaveAttribute('href', '/downloads/alera-claude.plugin');
  expect((await request.get('/downloads/alera-combined-experimental.zip')).status()).toBe(404);
});

for (const width of [1440, 390]) {
  test(`shows all five compatibility notices before download actions at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.goto('/download');
    const cards = [
      { id: 'plugin', terms: [/desktop.only/i, /remote HTTPS/i, /without registering the MCP URL manually/i, /OAuth/i] },
      { id: 'claude-plugin', terms: [/paid Claude plan/i, /Connectors Tab/i, /unidentified experimental ZIP/i, /does not verify every package/i] },
      { id: 'grokbot-cursor-plugin', terms: [/Cursor:/i, /plugins\/local\//i, /Grok Bot:/i, /arbitrary ZIP import/i] },
      { id: 'agent-plugin', terms: [/Agent Plugins 1\.0/i, /does not define a universal ZIP installer/i, /authorization flow/i] },
      { id: 'copilot-plugin', terms: [/Copilot CLI:/i, /VS Code:/i, /GitHub Copilot App:/i, /shared OAuth grant/i] },
    ];
    for (const { id, terms } of cards) {
      const card = page.locator(`#${id}`);
      const notice = card.locator('[data-plugin-installation]');
      await expect(notice).toBeVisible();
      for (const term of terms) await expect(notice).toContainText(term);
      const actions = card.locator('a[download]');
      for (const action of await actions.all()) {
        expect(await notice.evaluate((node, link) => Boolean(node.compareDocumentPosition(link as Node) & Node.DOCUMENT_POSITION_FOLLOWING), await action.elementHandle())).toBe(true);
        const noticeBox = await notice.boundingBox();
        const actionBox = await action.boundingBox();
        expect(noticeBox!.y + noticeBox!.height).toBeLessThanOrEqual(actionBox!.y);
      }
      await card.scrollIntoViewIfNeeded();
      if (!process.env.CI) await card.screenshot({ path: `../build/plugin-distributions/before-download-${id}-${width}.png` });
    }
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    const violations = (await new AxeBuilder({ page }).analyze()).violations.filter(({ impact }) => ['serious', 'critical'].includes(impact ?? ''));
    expect(violations.map(({ id, help }) => `${id}: ${help}`)).toEqual([]);
    await page.goto('/#install');
    const compatibility = page.getByRole('link', { name: 'Compare Plugin Compatibility And Installation', exact: true });
    await expect(compatibility).toBeVisible();
    await expect(compatibility).toHaveAttribute('href', '/download#plugin');
    await compatibility.scrollIntoViewIfNeeded();
    const summaryBox = await compatibility.locator('..').boundingBox();
    const homeActionBox = await page.locator('#install [role="tabpanel"]:not([hidden]) a').first().boundingBox();
    expect(summaryBox!.y + summaryBox!.height).toBeLessThanOrEqual(homeActionBox!.y);
    if (!process.env.CI) await page.locator('#install').screenshot({ path: `../build/plugin-distributions/before-download-home-${width}.png` });
  });

  test(`shows three new setup guides with honest compatibility limits at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 900 });
    await page.emulateMedia({ reducedMotion: 'reduce' });
    for (const guide of guides) {
      await page.goto(`/download#${guide.id}`);
      await expect(page.getByRole('heading', { name: guide.label, exact: true })).toBeVisible();
      await page.getByRole('link', { name: `${guide.label} Setup`, exact: true }).click();
      await expect(page).toHaveURL(new RegExp(`/docs/${guide.id}$`));
      await expect(page.getByRole('heading', { level: 1 })).toHaveText(guide.label);
      await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', `https://alera.build/docs/${guide.id}`);
      await expect(page.getByRole('link', { name: guide.button, exact: true })).toBeVisible();
      await expect(page.getByText(guide.limit, { exact: false })).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
      const violations = (await new AxeBuilder({ page }).analyze()).violations.filter(({ impact }) => ['serious', 'critical'].includes(impact ?? ''));
      expect(violations.map(({ id, help }) => `${id}: ${help}`)).toEqual([]);
      if (!process.env.CI) await page.screenshot({ path: `../build/plugin-distributions/${guide.id}-${width}.png`, fullPage: true });
    }
  });
}
