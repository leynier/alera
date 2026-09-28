import { expect, test } from '@playwright/test';

// Published URLs are permanent: corrections add a dated note instead of moving a post.
const publishedPosts = [
  'automate-new-worktree-setup-with-alera-toml',
  'bring-your-own-cli-agent-to-alera',
  'how-alera-keeps-terminals-alive-after-you-quit',
  'inter-agent-orchestration-in-alera',
  'native-first-agent-workbench',
  'pair-a-phone-to-your-alera-runtime',
  'pull-requests-and-ci-checks-per-worktree',
  'run-cli-agents-in-parallel-with-git-worktrees',
  'see-which-agent-is-eating-your-cpu',
  'track-coding-agent-quotas-without-leaving-the-workbench',
  'welcome-to-alera',
  'why-alera-is-terminal-first-not-another-ai-ide',
  'why-terminal-output-performance-matters-for-agent-workbenches',
];

test('keeps every published post URL', async ({ request }) => {
  for (const id of publishedPosts) {
    const response = await request.get(`/blog/${id}`);
    expect(response.status(), id).toBe(200);
  }
});

test('leads the index with a featured post and gives every post a reading time', async ({ page }) => {
  await page.goto('/blog');
  await expect(page.getByRole('heading', { level: 1, name: 'Blog' })).toBeVisible();
  const cards = page.locator('main article');
  await expect(cards).toHaveCount(publishedPosts.length);
  await expect(cards.first()).toContainText('Featured');
  // innerText follows the uppercase styling of the meta line.
  for (const text of await cards.allInnerTexts()) expect(text).toMatch(/\d+ min read/i);
  await expect(page.getByRole('navigation', { name: 'Main' }).locator('[aria-current="page"]')).toHaveText('Blog');
});

test('filters posts by tag from the tag bar', async ({ page }) => {
  await page.goto('/blog');
  const tags = page.getByRole('navigation', { name: 'Blog Tags' });
  await expect(tags.getByRole('link', { name: /All Posts/ })).toHaveAttribute('aria-current', 'page');
  await tags.getByRole('link', { name: /^Agents/ }).click();
  await expect(page).toHaveURL(/\/blog\/tags\/agents$/);
  await expect(page.getByRole('heading', { level: 1, name: 'Agents' })).toBeVisible();
  await expect(tags.getByRole('link', { name: /^Agents/ })).toHaveAttribute('aria-current', 'page');
  const cards = page.locator('main article');
  expect(await cards.count()).toBeGreaterThan(0);
  for (const card of await cards.all()) {
    await expect(card.getByRole('link', { name: 'Agents', exact: true })).toHaveAttribute('href', '/blog/tags/agents');
  }
});

test('reads a post with its outline, related docs, and neighbours', async ({ page }) => {
  await page.goto('/blog/automate-new-worktree-setup-with-alera-toml');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
  await expect(page.locator('main header')).toContainText(/\d+ Min Read/);

  const outline = page.getByRole('complementary', { name: 'On This Page' });
  const links = outline.locator('a[data-outline-link]');
  expect(await links.count()).toBeGreaterThan(1);
  for (const href of await links.evaluateAll((all) => all.map((link) => link.getAttribute('href')))) {
    await expect(page.locator(`main ${href}`)).toHaveCount(1);
  }

  const related = page.getByRole('region', { name: 'Related Docs' });
  await expect(related.getByRole('link').first()).toHaveAttribute('href', /^\/docs/);
  await expect(page.getByRole('navigation', { name: 'Newer And Older Posts' }).getByRole('link').first()).toBeVisible();
});

test('publishes tags as RSS categories', async ({ request }) => {
  const feed = await (await request.get('/rss.xml')).text();
  expect(feed).toContain('<category>');
  expect(feed.match(/<item>/g)?.length).toBe(publishedPosts.length);
});
