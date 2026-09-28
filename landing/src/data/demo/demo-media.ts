import { createHash } from 'node:crypto';
import type { Ms } from '../../scripts/demo/timeline';
import { STORYBOARD } from './storyboard';

/**
 * The media the repository README shows, rendered from the demo by
 * `bun run media:demo` (scripts/render-demo-media.ts) into `assets/product/`:
 * an animated cut of the story and one poster per chapter. Nothing here is a
 * screen recording; every frame is the demo seeked to an exact time.
 *
 * The size keeps the stage's aspect ratio on whole pixels (1720:900 is 86:45),
 * because the camera derives the viewport height from its width, and stays
 * at or above 1100 px so the camera frames it like the wide tier on the site.
 */
export const DEMO_MEDIA = {
  width: 1376,
  height: 720,
  fps: 10,
  animationQuality: 72,
  posterQuality: 84,
  maxAnimationBytes: 4 * 1024 * 1024,
  animationFile: 'alera-demo.webp',
  manifestFile: 'demo-media.json',
  /** Stretches of the demo clock the animation plays back to back, in ms. */
  cuts: [
    [1_000, 4_600],
    [7_700, 13_500],
    [19_000, 23_800],
    [40_600, 45_800],
    [63_800, 70_400],
    [76_500, 82_000],
  ] as readonly (readonly [Ms, Ms])[],
} as const;

export const posterFile = (chapterId: string) => `demo-${chapterId}.webp`;

/**
 * A digest of everything the media draw: the storyboard's keys and chapter
 * timing plus the render settings. Captions are left out because the media
 * do not show them, so rewording one does not force a render.
 */
export function demoMediaFingerprint(): string {
  const { beats: _beats, chapters, ...keys } = STORYBOARD;
  const story = {
    keys,
    chapters: chapters.map(({ id, start, end, poster }) => ({ id, start, end, poster })),
    media: { width: DEMO_MEDIA.width, height: DEMO_MEDIA.height, fps: DEMO_MEDIA.fps, cuts: DEMO_MEDIA.cuts },
  };
  return createHash('sha256').update(JSON.stringify(story)).digest('hex');
}

export interface DemoMediaManifest {
  fingerprint: string;
  animation: { file: string; width: number; height: number; frames: number; durationMs: number; bytes: number };
  posters: { chapter: string; title: string; file: string; at: Ms; bytes: number }[];
}
