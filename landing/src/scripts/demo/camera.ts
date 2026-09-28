import type { Rect } from './timeline';

/**
 * The demo stage is drawn at the app's logical size and framed by a virtual
 * camera. Wide viewports see the whole stage; phones get a portrait frame that
 * follows the action closely enough for the app's 13 px text to stay legible.
 */
export const STAGE_WIDTH = 1720;
export const STAGE_HEIGHT = 900;

export type DemoTier = 'wide' | 'medium' | 'compact';

export const TIER_ASPECT: Record<DemoTier, number> = {
  wide: STAGE_WIDTH / STAGE_HEIGHT,
  medium: 16 / 10,
  compact: 4 / 5,
};

/** Never magnify past the app's own size: at 1:1 the demo is as sharp as the app. */
const MAX_SCALE = 1.1;

export function tierFor(width: number): DemoTier {
  if (width >= 1100) return 'wide';
  if (width >= 720) return 'medium';
  return 'compact';
}

export interface CameraTransform {
  scale: number;
  x: number;
  y: number;
}

/** Scale and offset that fit `rect` in the viewport without showing past the stage edges. */
export function fitCamera(rect: Rect, viewportWidth: number, viewportHeight: number): CameraTransform {
  const [rx, ry, rw, rh] = rect;
  const scale = Math.min(MAX_SCALE, viewportWidth / Math.max(rw, 1), viewportHeight / Math.max(rh, 1));
  const clampAxis = (offset: number, viewport: number, stage: number) => {
    const scaled = stage * scale;
    if (scaled <= viewport) return (viewport - scaled) / 2;
    return Math.min(0, Math.max(viewport - scaled, offset));
  };
  return {
    scale,
    x: clampAxis(viewportWidth / 2 - (rx + rw / 2) * scale, viewportWidth, STAGE_WIDTH),
    y: clampAxis(viewportHeight / 2 - (ry + rh / 2) * scale, viewportHeight, STAGE_HEIGHT),
  };
}
