import { expect, test, type Page } from '@playwright/test';

const demo = (page: Page) => page.locator('[data-demo-root]');
const clock = (page: Page) => demo(page).locator('[data-demo-time]');

/** The demo mounts lazily, so tests bring it into view instead of trusting the URL hash. */
async function openDemo(page: Page, path = '/') {
  await page.goto(path);
  await demo(page).scrollIntoViewIfNeeded();
  await expect(demo(page)).toHaveAttribute('data-ready', '');
}

async function elapsedSeconds(page: Page): Promise<number> {
  const text = (await clock(page).textContent()) ?? '';
  const [minutes, seconds] = text.split('/')[0]!.trim().split(':').map(Number);
  return minutes! * 60 + seconds!;
}

test('mounts every node the storyboard drives without console errors', async ({ page }) => {
  const problems: string[] = [];
  page.on('console', (message) => {
    // Vercel serves its analytics script only in production.
    if (message.location().url.includes('/_vercel/')) return;
    if (message.type() === 'error' || message.type() === 'warning') problems.push(message.text());
  });
  page.on('response', (response) => {
    if (response.status() >= 400 && !response.url().includes('/_vercel/')) problems.push(`${response.status()} ${response.url()}`);
  });
  page.on('pageerror', (error) => problems.push(error.message));
  await openDemo(page);
  expect(problems.filter((problem) => !problem.startsWith('Failed to load resource'))).toEqual([]);
});

test('plays once it is on screen and pauses from its control', async ({ page }) => {
  await page.goto('/');
  await expect(demo(page)).not.toHaveAttribute('data-state', 'playing');

  await demo(page).scrollIntoViewIfNeeded();
  await expect(demo(page)).toHaveAttribute('data-state', 'playing');
  await expect.poll(() => elapsedSeconds(page)).toBeGreaterThanOrEqual(1);

  await demo(page).getByRole('button', { name: 'Pause Demo' }).click();
  await expect(demo(page)).toHaveAttribute('data-state', 'paused');
  const pausedAt = await clock(page).textContent();
  await page.waitForTimeout(1_200);
  await expect(clock(page)).toHaveText(pausedAt!);

  await demo(page).getByRole('button', { name: 'Play Demo' }).click();
  await expect(demo(page)).toHaveAttribute('data-state', 'playing');
});

test('pauses when scrolled away and resumes when it comes back', async ({ page }) => {
  await openDemo(page);
  await expect(demo(page)).toHaveAttribute('data-state', 'playing');
  await page.locator('#faq').scrollIntoViewIfNeeded();
  await expect(demo(page)).toHaveAttribute('data-state', 'paused');
  await demo(page).scrollIntoViewIfNeeded();
  await expect(demo(page)).toHaveAttribute('data-state', 'playing');
});

test('jumps between chapters', async ({ page }) => {
  await openDemo(page);
  const chapters = demo(page).getByRole('list', { name: 'Demo Chapters' }).getByRole('button');
  await expect(chapters).toHaveCount(4);
  await chapters.nth(2).click();
  await expect(chapters.nth(2)).toHaveAttribute('aria-current', 'step');
  await expect(demo(page)).toHaveAttribute('data-state', 'playing');
  await chapters.nth(0).focus();
  await page.keyboard.press('Enter');
  await expect(chapters.nth(0)).toHaveAttribute('aria-current', 'step');
});

test('keeps the stage out of the accessibility tree and offers a transcript', async ({ page }) => {
  await openDemo(page);
  const viewport = demo(page).locator('[data-demo-viewport]');
  await expect(viewport).toHaveAttribute('aria-hidden', 'true');
  await expect(viewport).toHaveAttribute('inert', '');
  await demo(page).getByText('Read The Demo As Text').click();
  const transcript = demo(page).locator('details[open]');
  for (const title of ['Start From A Prompt', 'Agents In Parallel', 'Answer From Your Phone', 'Review And Ship']) {
    await expect(transcript).toContainText(title);
  }
});

test('ends on a card that replays from the start', async ({ page }) => {
  await openDemo(page, '/?demo=capture');
  await page.evaluate(() => window.__aleraDemo!.seek(window.__aleraDemo!.duration));
  await demo(page).evaluate((element) => element.removeAttribute('data-capture'));
  await expect(demo(page)).toHaveAttribute('data-state', 'ended');
  await expect(demo(page).getByRole('link', { name: 'Download' })).toBeVisible();
  await demo(page).getByRole('button', { name: 'Replay', exact: true }).click();
  await expect(demo(page)).toHaveAttribute('data-state', 'playing');
  await expect(clock(page)).toContainText('0:0');
});

test('respects reduced motion', async ({ browser }) => {
  const context = await browser.newContext({ reducedMotion: 'reduce', viewport: { width: 1440, height: 900 } });
  const page = await context.newPage();
  await openDemo(page);
  await page.waitForTimeout(800);
  await expect(demo(page)).toHaveAttribute('data-state', 'paused');
  const chapters = demo(page).getByRole('list', { name: 'Demo Chapters' }).getByRole('button');
  await chapters.nth(1).click();
  await expect(chapters.nth(1)).toHaveAttribute('aria-current', 'step');
  await expect(demo(page)).toHaveAttribute('data-state', 'paused');
  await context.close();
});

test('pauses when reduced motion is enabled after playback starts', async ({ page }) => {
  await openDemo(page);
  await expect(demo(page)).toHaveAttribute('data-state', 'playing');
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await expect(demo(page)).toHaveAttribute('data-state', 'paused');
  const pausedAt = await demo(page).evaluate((element) => element.style.getPropertyValue('--demo-t'));
  await page.waitForTimeout(500);
  await expect(demo(page)).toHaveAttribute('data-state', 'paused');
  expect(await demo(page).evaluate((element) => element.style.getPropertyValue('--demo-t'))).toBe(pausedAt);
});

test('draws the same frame for the same time in capture mode', async ({ page }) => {
  await openDemo(page, '/?demo=capture');
  await expect(demo(page)).toHaveAttribute('data-capture', '');
  // The fixed navbar would overlap the frame's top edge in a screenshot.
  await page.locator('header').evaluateAll((headers) => headers.forEach((header) => ((header as HTMLElement).style.display = 'none')));
  const viewport = demo(page).locator('[data-demo-viewport]');
  const shoot = async (t: number) => {
    await page.evaluate((time) => window.__aleraDemo!.seek(time), t);
    return viewport.screenshot({ animations: 'allow' });
  };
  const first = await shoot(31_500);
  const elsewhere = await shoot(70_000);
  const again = await shoot(31_500);
  // Chrome may raster the scaled stage at a slightly different scale after
  // the camera moves, which shifts antialiasing by a few levels; the content
  // must match, so only pixels that change by more than that count.
  const changed = (a: Buffer, b: Buffer) =>
    page.evaluate(
      async ([left, right]) => {
        const load = (data: string) =>
          new Promise<HTMLImageElement>((resolve) => {
            const image = new Image();
            image.onload = () => resolve(image);
            image.src = `data:image/png;base64,${data}`;
          });
        const [a, b] = await Promise.all([load(left!), load(right!)]);
        const canvas = document.createElement('canvas');
        canvas.width = a.width;
        canvas.height = a.height;
        const context = canvas.getContext('2d')!;
        context.drawImage(a, 0, 0);
        const pixelsA = context.getImageData(0, 0, a.width, a.height).data;
        context.drawImage(b, 0, 0);
        const pixelsB = context.getImageData(0, 0, a.width, a.height).data;
        let count = 0;
        for (let i = 0; i < pixelsA.length; i += 4) {
          const delta = Math.max(
            Math.abs(pixelsA[i]! - pixelsB[i]!),
            Math.abs(pixelsA[i + 1]! - pixelsB[i + 1]!),
            Math.abs(pixelsA[i + 2]! - pixelsB[i + 2]!),
          );
          if (delta > 48) count += 1;
        }
        return count / (a.width * a.height);
      },
      [a.toString('base64'), b.toString('base64')],
    );
  expect(await changed(first, again)).toBeLessThan(0.001);
  expect(await changed(first, elsewhere)).toBeGreaterThan(0.05);
});
