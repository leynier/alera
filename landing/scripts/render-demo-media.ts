/**
 * Renders the README media from the built landing page into ../assets/product:
 * the animated cut, one poster per chapter, and demo-media.json. Run
 * `bun run build` first, then `bun run media:demo`. It serves dist/ itself,
 * opens the demo in capture mode (`?demo=capture`) and seeks every frame, so
 * the output depends only on the build, never on how fast the machine is.
 *
 * Set PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH to reuse an installed Chromium.
 */
import { chromium, type Page } from '@playwright/test';
import { mkdirSync, readdirSync, statSync, unlinkSync, writeFileSync } from 'node:fs';
import { join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { DEMO_MEDIA, demoMediaFingerprint, posterFile, type DemoMediaManifest } from '../src/data/demo/demo-media';
import { compileStoryboard } from '../src/scripts/demo/timeline';
import { STORYBOARD } from '../src/data/demo/storyboard';

const dist = fileURLToPath(new URL('../dist/', import.meta.url));
const output = fileURLToPath(new URL('../../assets/product/', import.meta.url));

function servedFile(pathname: string): string | null {
  const path = normalize(join(dist, decodeURIComponent(pathname)));
  if (!path.startsWith(dist)) return null;
  for (const candidate of [path, join(path, 'index.html')]) {
    try {
      if (statSync(candidate).isFile()) return candidate;
    } catch {
      // Try the next candidate.
    }
  }
  return null;
}

try {
  statSync(join(dist, 'index.html'));
} catch {
  console.error('dist/index.html is missing: run `bun run build` first.');
  process.exit(1);
}

const server = Bun.serve({
  port: 0,
  hostname: '127.0.0.1',
  fetch(request) {
    const file = servedFile(new URL(request.url).pathname);
    return file ? new Response(Bun.file(file)) : new Response('Not found', { status: 404 });
  },
});

const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;
const browser = await chromium.launch(executablePath ? { executablePath } : undefined);

async function openDemo(): Promise<{ page: Page; frame: () => Promise<Buffer> }> {
  const page = await browser.newPage({ viewport: { width: DEMO_MEDIA.width + 200, height: DEMO_MEDIA.height + 200 } });
  await page.goto(`${server.url}?demo=capture#product`);
  await page.waitForSelector('[data-demo-root][data-ready]');
  // Show the demo alone at the media size; the camera frames the stage for it.
  await page.evaluate(({ width, height }) => {
    const root = document.querySelector<HTMLElement>('[data-demo-root]')!;
    for (const child of [...document.body.children]) {
      if (child instanceof HTMLElement && !['STYLE', 'LINK', 'SCRIPT'].includes(child.tagName)) child.style.display = 'none';
    }
    document.body.prepend(root);
    root.style.display = 'block';
    Object.assign(document.body.style, { margin: '0', padding: '0' });
    Object.assign(root.style, { width: `${width}px`, margin: '0' });
    const viewport = root.querySelector<HTMLElement>('[data-demo-viewport]')!;
    Object.assign(viewport.style, { width: `${width}px`, height: `${height}px`, aspectRatio: 'auto', border: '0', borderRadius: '0' });
    window.scrollTo(0, 0);
  }, DEMO_MEDIA);
  const clip = await page.evaluate(() => {
    const box = document.querySelector('[data-demo-viewport]')!.getBoundingClientRect();
    return { x: box.x, y: box.y };
  });
  return {
    page,
    frame: () => page.screenshot({ type: 'png', clip: { ...clip, width: DEMO_MEDIA.width, height: DEMO_MEDIA.height } }),
  };
}

const seek = (page: Page, t: number) => page.evaluate((time) => window.__aleraDemo!.seek(time), t);

try {
  const { page, frame } = await openDemo();
  const timeline = compileStoryboard(STORYBOARD);
  mkdirSync(output, { recursive: true });

  // The animation: every cut at a fixed frame rate, identical frames merged.
  const step = 1000 / DEMO_MEDIA.fps;
  const frames: Buffer[] = [];
  const delays: number[] = [];
  for (const [start, end] of DEMO_MEDIA.cuts) {
    for (let t = start; t < end; t += step) {
      await seek(page, t);
      const image = await frame();
      if (frames.length > 0 && image.equals(frames.at(-1)!)) delays.push(delays.pop()! + step);
      else {
        frames.push(image);
        delays.push(step);
      }
    }
  }
  const animation = await sharp(frames, { join: { animated: true } })
    .webp({ quality: DEMO_MEDIA.animationQuality, effort: 6, loop: 0, delay: delays.map(Math.round) })
    .toBuffer();
  if (animation.length > DEMO_MEDIA.maxAnimationBytes) {
    throw new Error(
      `${DEMO_MEDIA.animationFile} is ${animation.length} bytes, over the ${DEMO_MEDIA.maxAnimationBytes} byte budget: shorten the cuts in src/data/demo/demo-media.ts.`,
    );
  }

  // One poster per chapter, at the chapter's poster time.
  const posters: DemoMediaManifest['posters'] = [];
  const posterBuffers = new Map<string, Buffer>();
  for (const chapter of timeline.chapters) {
    await seek(page, chapter.poster);
    const poster = await sharp(await frame()).webp({ quality: DEMO_MEDIA.posterQuality, effort: 6 }).toBuffer();
    const file = posterFile(chapter.id);
    posterBuffers.set(file, poster);
    posters.push({ chapter: chapter.id, title: chapter.title, file, at: chapter.poster, bytes: poster.length });
  }

  // Replace the previous render as a whole, so a renamed chapter leaves no stale poster behind.
  for (const name of readdirSync(output)) {
    if (name === DEMO_MEDIA.animationFile || /^demo-[\w-]+\.webp$/.test(name)) unlinkSync(join(output, name));
  }
  writeFileSync(join(output, DEMO_MEDIA.animationFile), animation);
  for (const [file, poster] of posterBuffers) writeFileSync(join(output, file), poster);
  const manifest: DemoMediaManifest = {
    fingerprint: demoMediaFingerprint(),
    animation: {
      file: DEMO_MEDIA.animationFile,
      width: DEMO_MEDIA.width,
      height: DEMO_MEDIA.height,
      frames: frames.length,
      durationMs: Math.round(delays.reduce((sum, delay) => sum + delay, 0)),
      bytes: animation.length,
    },
    posters,
  };
  writeFileSync(join(output, DEMO_MEDIA.manifestFile), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`${DEMO_MEDIA.animationFile}: ${frames.length} frames, ${animation.length} bytes`);
  for (const poster of posters) console.log(`${poster.file}: ${poster.bytes} bytes`);
} finally {
  await browser.close();
  server.stop(true);
}
