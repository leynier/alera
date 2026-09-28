import { expect, test } from '@playwright/test';

test('opens the page index from the bar under the navbar', async ({ page }) => {
  await page.goto('/docs/quotas');
  const toggle = page.locator('#docs-menu-toggle');
  await expect(toggle).toContainText('Quotas And Resources');

  await toggle.click();
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  await page.keyboard.press('Escape');
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  await expect(toggle).toBeFocused();

  await toggle.click();
  await page.locator('#docs-menu').getByRole('link', { name: 'Mobile Companion' }).click();
  await expect(page).toHaveURL(/\/docs\/mobile$/);
});

test('searches from the mobile bar', async ({ page }) => {
  await page.goto('/docs');
  await page.locator('#docs-mobile-bar').getByRole('button', { name: 'Search The Docs' }).click();
  await expect(page.getByRole('dialog', { name: 'Search The Docs' })).toBeVisible();
});

test('shows the outline as a collapsible block', async ({ page }) => {
  await page.goto('/docs/install');
  const outline = page.locator('details').filter({ hasText: 'On This Page' });
  await outline.locator('summary').click();
  await expect(outline.getByRole('link', { name: 'Updating' })).toBeVisible();
});

test('never scrolls sideways', async ({ page }) => {
  for (const path of ['/docs', '/docs/install', '/docs/alera-toml']) {
    await page.goto(path);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow, path).toBeLessThanOrEqual(0);
  }
});
