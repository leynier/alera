import { describe, expect, test } from 'bun:test';
import { readFileSync, statSync } from 'node:fs';
import { STAGE_HEIGHT, STAGE_WIDTH, tierFor } from '../../scripts/demo/camera';
import { compileStoryboard } from '../../scripts/demo/timeline';
import { DEMO_MEDIA, demoMediaFingerprint, posterFile, type DemoMediaManifest } from './demo-media';
import { STORYBOARD } from './storyboard';

const product = (file: string) => new URL(`../../../../assets/product/${file}`, import.meta.url);
const manifest = JSON.parse(readFileSync(product(DEMO_MEDIA.manifestFile), 'utf8')) as DemoMediaManifest;
const chapters = compileStoryboard(STORYBOARD).chapters;

describe('README media', () => {
  test('show the current storyboard', () => {
    // When this fails, render them again: `bun run build && bun run media:demo`.
    expect(manifest.fingerprint).toBe(demoMediaFingerprint());
  });

  test('are framed like the wide demo, on whole pixels', () => {
    expect(tierFor(DEMO_MEDIA.width)).toBe('wide');
    expect((DEMO_MEDIA.width * STAGE_HEIGHT) / STAGE_WIDTH).toBe(DEMO_MEDIA.height);
  });

  test('play only stretches of the demo, in order', () => {
    let previousEnd = 0;
    for (const [start, end] of DEMO_MEDIA.cuts) {
      expect(start).toBeGreaterThanOrEqual(previousEnd);
      expect(end).toBeGreaterThan(start);
      previousEnd = end;
    }
    expect(previousEnd).toBeLessThanOrEqual(STORYBOARD.duration);
  });

  test('stay within the size budget and exist on disk', () => {
    expect(statSync(product(manifest.animation.file)).size).toBe(manifest.animation.bytes);
    expect(manifest.animation.bytes).toBeLessThanOrEqual(DEMO_MEDIA.maxAnimationBytes);
    for (const poster of manifest.posters) expect(statSync(product(poster.file)).size).toBe(poster.bytes);
  });

  test('are all shown in the repository README', () => {
    const readme = readFileSync(new URL('../../../../readme.md', import.meta.url), 'utf8');
    for (const file of [manifest.animation.file, ...manifest.posters.map((poster) => poster.file)]) {
      expect({ file, shown: readme.includes(`assets/product/${file}`) }).toEqual({ file, shown: true });
    }
  });

  test('have one poster per chapter', () => {
    expect(manifest.posters.map(({ chapter, file }) => ({ chapter, file }))).toEqual(
      chapters.map((chapter) => ({ chapter: chapter.id, file: posterFile(chapter.id) })),
    );
  });
});
