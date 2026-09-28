import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';

test('answers unknown URLs with the site 404 page', async ({ page }) => {
  const response = await page.goto('/this-page-does-not-exist');
  expect(response?.status()).toBe(404);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Page Not Found');
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute('content', /noindex/);
});

test('keeps the sitemap to public pages with canonical URLs', async ({ request }) => {
  const sitemap = await (await request.get('/sitemap-0.xml')).text();
  const urls = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1]!);
  expect(urls).toContain('https://alera.build/docs/install');
  expect(urls.some((url) => url.endsWith('/404') || url.includes('/signed-in'))).toBe(false);
  expect(urls.filter((url) => url !== 'https://alera.build/' && url.endsWith('/'))).toEqual([]);
});

test('gives every page one h1 and a canonical link to itself', async ({ page }) => {
  for (const path of ['/', '/download', '/docs', '/docs/install', '/blog', '/privacy']) {
    await page.goto(path);
    await expect(page.locator('h1'), path).toHaveCount(1);
    const canonical = await page.locator('link[rel="canonical"]').getAttribute('href');
    expect(canonical, path).toBe(new URL(path, 'https://alera.build').toString());
  }
});

test('has no serious accessibility violations on the docs', async ({ page }) => {
  for (const path of ['/docs', '/docs/install', '/404']) {
    await page.goto(path);
    const results = await new AxeBuilder({ page }).analyze();
    const serious = results.violations.filter((violation) => ['serious', 'critical'].includes(violation.impact ?? ''));
    expect(serious.map((violation) => `${violation.id}: ${violation.help}`), path).toEqual([]);
  }
});
