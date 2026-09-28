import { describe, expect, test } from 'bun:test';
import { STAGE_HEIGHT, STAGE_WIDTH, TIER_ASPECT, fitCamera, tierFor } from './camera';

describe('camera', () => {
  test('picks a tier from the container width', () => {
    expect(tierFor(360)).toBe('compact');
    expect(tierFor(719)).toBe('compact');
    expect(tierFor(720)).toBe('medium');
    expect(tierFor(1099)).toBe('medium');
    expect(tierFor(1100)).toBe('wide');
  });

  test('fits the whole stage exactly in the wide tier', () => {
    const width = 1152;
    const height = width / TIER_ASPECT.wide;
    const camera = fitCamera([0, 0, STAGE_WIDTH, STAGE_HEIGHT], width, height);
    expect(camera.scale).toBeCloseTo(width / STAGE_WIDTH, 6);
    expect(camera.x).toBeCloseTo(0, 6);
    expect(camera.y).toBeCloseTo(0, 6);
  });

  test('frames a region on a phone at a legible scale', () => {
    const width = 342;
    const height = width / TIER_ASPECT.compact;
    const camera = fitCamera([300, 60, 420, 525], width, height);
    expect(camera.scale).toBeGreaterThan(0.75);
    const centreX = (300 + 210) * camera.scale + camera.x;
    expect(centreX).toBeCloseTo(width / 2, 0);
  });

  test('never magnifies past the app size', () => {
    const camera = fitCamera([100, 100, 200, 100], 1400, 1400 / TIER_ASPECT.wide);
    expect(camera.scale).toBeCloseTo(1.1, 6);
  });

  test('keeps the stage edges in view instead of empty space', () => {
    const width = 342;
    const height = width / TIER_ASPECT.compact;
    const camera = fitCamera([0, 0, 420, 525], width, height);
    expect(camera.x).toBeLessThanOrEqual(0);
    expect(camera.x).toBeGreaterThanOrEqual(width - STAGE_WIDTH * camera.scale);
    expect(camera.y).toBeLessThanOrEqual(0);
  });
});
