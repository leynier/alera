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

test('links only to pages and anchors that exist', async ({ request }) => {
  const sitemap = await (await request.get('/sitemap-0.xml')).text();
  const pages = [...sitemap.matchAll(/<loc>https:\/\/alera\.build([^<]*)<\/loc>/g)].map((match) => match[1] || '/');
  const html = new Map<string, string>();
  const load = async (path: string) => {
    if (!html.has(path)) {
      const response = await request.get(path);
      expect(response.status(), path).toBeLessThan(400);
      html.set(path, await response.text());
    }
    return html.get(path)!;
  };
  const statuses = new Map<string, number>();
  const status = async (path: string) => {
    if (!statuses.has(path)) statuses.set(path, (await request.get(path)).status());
    return statuses.get(path)!;
  };
  const broken: string[] = [];
  for (const page of pages) {
    const body = await load(page);
    for (const [, href] of body.matchAll(/href="(\/(?!\/)[^"]*)"/g)) {
      const [path, anchor] = href!.replace(/&amp;/g, '&').split('#');
      if (!path || /\.(xml|png|svg|webp|jpg|ico|txt|sh|asc|json|webmanifest|css|js|woff2)$/.test(path)) continue;
      const code = await status(path);
      if (code >= 400) {
        broken.push(`${page} -> ${href} (${code})`);
        continue;
      }
      if (anchor && !(await load(path)).includes(`id="${anchor}"`)) broken.push(`${page} -> ${href} (no #${anchor})`);
    }
  }
  expect(broken).toEqual([]);
});

test('gives every page one h1 and a canonical link to itself', async ({ page }) => {
  for (const path of ['/', '/download', '/docs', '/docs/install', '/blog', '/privacy']) {
    await page.goto(path);
    await expect(page.locator('h1'), path).toHaveCount(1);
    const canonical = await page.locator('link[rel="canonical"]').getAttribute('href');
    expect(canonical, path).toBe(new URL(path, 'https://alera.build').toString());
  }
});

test('has no serious accessibility violations on the key pages', async ({ page }) => {
  // Entrance animations fade text in, and axe would measure contrast mid-fade.
  await page.emulateMedia({ reducedMotion: 'reduce' });
  // Commands and tables only overflow on a phone, so both widths are checked.
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 900 });
    for (const path of ['/', '/download', '/blog', '/docs', '/docs/install', '/docs/keyboard-shortcuts', '/docs/pull-requests', '/404']) {
      await page.goto(path);
      const results = await new AxeBuilder({ page }).analyze();
      const serious = results.violations.filter((violation) => ['serious', 'critical'].includes(violation.impact ?? ''));
      expect(serious.map((violation) => `${violation.id}: ${violation.help}`), `${path} at ${width}px`).toEqual([]);
    }
  }
});
