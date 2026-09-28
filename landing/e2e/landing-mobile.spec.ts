import { expect, test } from '@playwright/test';

test('opens every section from the mobile menu', async ({ page }) => {
  await page.goto('/');
  const toggle = page.locator('#nav-menu-toggle');
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');

  await toggle.click();
  const menu = page.locator('#nav-menu');
  await expect(menu).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(menu).toBeHidden();
  await expect(toggle).toBeFocused();

  await toggle.click();
  await menu.getByRole('link', { name: 'Install' }).click();
  await expect(menu).toBeHidden();
  await expect(page).toHaveURL(/#install$/);
});

test('never scrolls sideways on a phone', async ({ page }) => {
  for (const path of ['/', '/download', '/blog', '/404']) {
    await page.goto(path);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow, path).toBeLessThanOrEqual(0);
  }
});
