import { expect, test } from '@playwright/test';

const legacyPages = ['', '/install', '/projects', '/agents', '/worktrees', '/alera-toml', '/orchestration', '/mobile', '/quotas'];

test('keeps every legacy docs URL, with and without a trailing slash', async ({ request }) => {
  for (const page of legacyPages) {
    for (const suffix of ['', '/']) {
      const path = `/docs${page}${suffix}`;
      const response = await request.get(path);
      expect(response.status(), path).toBe(200);
    }
  }
});

test('lists every page in the sidebar, grouped, with the current one marked', async ({ page }) => {
  await page.goto('/docs/worktrees');
  const sidebar = page.getByRole('navigation', { name: 'Documentation' }).last();
  await expect(sidebar.getByText('Workbench', { exact: true })).toBeVisible();
  await expect(sidebar.locator('[aria-current="page"]')).toHaveText('Worktrees');
  await expect(sidebar.getByRole('link', { name: 'Install' })).toHaveAttribute('href', '/docs/install');
  await expect(page.getByRole('navigation', { name: 'Previous And Next Page' }).getByRole('link')).toHaveCount(2);
});

test('outlines the page from its own headings', async ({ page }) => {
  await page.goto('/docs/install');
  const outline = page.getByRole('complementary', { name: 'On This Page' });
  const links = outline.locator('a[data-outline-link]');
  await expect(links.first()).toBeVisible();
  for (const href of await links.evaluateAll((all) => all.map((link) => link.getAttribute('href')))) {
    await expect(page.locator(`main ${href}`)).toHaveCount(1);
  }
  await outline.getByRole('link', { name: 'Windows' }).click();
  await expect(page).toHaveURL(/#windows$/);
  await expect(outline.locator('a[data-active]')).toHaveText('Windows');
});

test('keeps the anchors other pages link to', async ({ page }) => {
  await page.goto('/docs/install');
  for (const id of ['linux', 'macos', 'windows', 'updating', 'mobile', 'from-source']) {
    await expect(page.locator(`#${id}`)).toHaveCount(1);
  }
  await page.goto('/docs');
  await expect(page.locator('#first-session')).toHaveCount(1);
});

test('searches the docs from the keyboard', async ({ page }) => {
  await page.goto('/docs');
  await page.keyboard.press('Control+k');
  const dialog = page.getByRole('dialog', { name: 'Search The Docs' });
  await expect(dialog).toBeVisible();
  await dialog.getByRole('searchbox').fill('worktree');
  const results = dialog.locator('a[data-search-result]');
  await expect(results.first()).toBeVisible();
  await expect(results.first()).toHaveAttribute('href', /^\/docs/);
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();

  await page.keyboard.press('/');
  await expect(dialog).toBeVisible();
});

test('clears stale results when the query is emptied', async ({ page }) => {
  await page.goto('/docs');
  await page.getByRole('button', { name: /Search Docs/ }).click();
  const dialog = page.getByRole('dialog', { name: 'Search The Docs' });
  const box = dialog.getByRole('searchbox');
  await box.fill('agent');
  await box.fill('');
  await page.waitForTimeout(800);
  await expect(dialog.locator('a[data-search-result]')).toHaveCount(0);
  await expect(dialog.getByText('Type to search every page.')).toBeVisible();
});

test('copies a code block', async ({ page, context }) => {
  await context.grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.goto('/docs/install');
  const block = page.locator('[data-code-block]').first();
  await block.getByRole('button', { name: 'Copy' }).click();
  await expect(block.getByRole('button', { name: 'Copied' })).toBeVisible();
  const copied = await page.evaluate(() => navigator.clipboard.readText());
  expect(copied).toBe('curl -fsSL https://alera.build/install.sh | sh');
});

test('links each page to its source for editing', async ({ page }) => {
  await page.goto('/docs/alera-toml');
  await expect(page.getByRole('link', { name: 'Edit This Page' })).toHaveAttribute(
    'href',
    'https://github.com/leynier/alera/edit/main/landing/src/content/docs/alera-toml.mdx',
  );
  await expect(page).toHaveTitle('alera.toml - Alera Docs');
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', 'https://alera.build/docs/alera-toml');
});
