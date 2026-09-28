import { expect, test } from '@playwright/test';

const signingAttribution = 'Free code signing provided by SignPath.io, certificate by SignPath Foundation';

test('links every nav entry to a section that exists', async ({ page }) => {
  await page.goto('/');
  const hrefs = await page
    .getByRole('navigation', { name: 'Main' })
    .locator('a[href^="/#"]')
    .evaluateAll((links) => links.map((link) => link.getAttribute('href')!));
  expect(hrefs.length).toBeGreaterThan(0);
  for (const href of new Set(hrefs)) {
    await expect(page.locator(href.slice(1)), href).toHaveCount(1);
  }
});

test('keeps the #install anchor the Linux installer writes into package sources', async ({ page }) => {
  await page.goto('/#install');
  await expect(page.locator('#install')).toBeVisible();
  await expect(page.locator('#install').getByRole('tab', { name: 'Linux' })).toBeVisible();
});

test('switches install platforms with the mouse and the keyboard', async ({ page }) => {
  await page.goto('/#install');
  const install = page.locator('#install');
  await install.getByRole('tab', { name: 'Windows' }).click();
  const windows = install.getByRole('tabpanel', { name: 'Windows' });
  await expect(windows).toContainText('scoop install leynier/alera');
  await expect(windows).toContainText('choco install alera');

  await page.keyboard.press('ArrowRight');
  await expect(install.getByRole('tab', { name: 'Linux' })).toHaveAttribute('aria-selected', 'true');
  await expect(install.getByRole('tabpanel', { name: 'Linux' })).toContainText('curl -fsSL https://alera.build/install.sh | sh');
  await expect(windows).toBeHidden();
});

test('preselects the visitor platform', async ({ browser }) => {
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36',
  });
  const page = await context.newPage();
  await page.goto('/#install');
  await expect(page.locator('#install').getByRole('tab', { name: 'Windows' })).toHaveAttribute('aria-selected', 'true');
  await context.close();
});

test('copies the install command exactly', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('/#install');
  const install = page.locator('#install');
  await install.getByRole('tab', { name: 'Linux' }).click();
  const panel = install.getByRole('tabpanel', { name: 'Linux' });
  await panel.getByRole('button', { name: 'Copy' }).click();
  await expect(panel.getByRole('button', { name: 'Copied' })).toBeVisible();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe('curl -fsSL https://alera.build/install.sh | sh');
});

test('carries the SignPath attribution verbatim on the home and download pages', async ({ page }) => {
  for (const path of ['/', '/download']) {
    await page.goto(path);
    await expect(page.getByText(signingAttribution, { exact: false }).first(), path).toBeVisible();
  }
});

test('lists the pinned release assets and the key fingerprint on the download page', async ({ page }) => {
  await page.goto('/download');
  await expect(page.getByRole('link', { name: 'Download For macOS' })).toHaveAttribute(
    'href',
    /^https:\/\/github\.com\/leynier\/alera\/releases\/download\/v[\d.]+\/alera-[\d.]+-macos\.tar\.gz$/,
  );
  await expect(page.getByText('5DE97E7CFE234A1C5869EC54708DA940734CF23A')).toBeVisible();
});
