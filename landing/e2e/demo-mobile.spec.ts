import { expect, test } from '@playwright/test';

test('frames the demo for a phone and keeps its controls usable', async ({ page }) => {
  await page.goto('/');
  const demo = page.locator('[data-demo-root]');
  await demo.scrollIntoViewIfNeeded();
  await expect(demo).toHaveAttribute('data-ready', '');
  const viewport = demo.locator('[data-demo-viewport]');
  await expect(viewport).toHaveAttribute('data-tier', 'compact');
  const box = (await viewport.boundingBox())!;
  expect(box.width / box.height).toBeCloseTo(4 / 5, 1);
  await expect(demo).toHaveAttribute('data-state', 'playing');
  await demo.getByRole('button', { name: 'Pause Demo' }).tap();
  await expect(demo).toHaveAttribute('data-state', 'paused');
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow).toBeLessThanOrEqual(0);
});
