/**
 * Easing for the product demo. `easeOut` and `easeInOut` match the Flutter
 * curves the app animates with (`Curves.easeOut`, `Curves.easeInOut`), so a
 * dialog or toast moves in the demo the way it moves in Alera. `camera` is
 * slower in and out, for moves the app itself never makes.
 */
export type EaseName = 'linear' | 'easeOut' | 'easeInOut' | 'camera';

function cubicBezier(x1: number, y1: number, x2: number, y2: number): (t: number) => number {
  const sample = (a: number, b: number, t: number) => 3 * a * (1 - t) ** 2 * t + 3 * b * (1 - t) * t ** 2 + t ** 3;
  return (x: number) => {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    // Bisection is plenty for a curve drawn at 60 frames per second.
    let low = 0;
    let high = 1;
    for (let i = 0; i < 24; i += 1) {
      const mid = (low + high) / 2;
      if (sample(x1, x2, mid) < x) low = mid;
      else high = mid;
    }
    return sample(y1, y2, (low + high) / 2);
  };
}

const curves: Record<EaseName, (t: number) => number> = {
  linear: (t) => Math.min(1, Math.max(0, t)),
  easeOut: cubicBezier(0, 0, 0.58, 1),
  easeInOut: cubicBezier(0.42, 0, 0.58, 1),
  camera: cubicBezier(0.65, 0, 0.35, 1),
};

export function ease(name: EaseName, t: number): number {
  return curves[name](t);
}

/** Progress of `t` through `[start, start + duration]`, clamped to 0..1. */
export function progress(t: number, start: number, duration: number): number {
  if (duration <= 0) return t >= start ? 1 : 0;
  return Math.min(1, Math.max(0, (t - start) / duration));
}

export function mix(from: number, to: number, amount: number): number {
  return from + (to - from) * amount;
}
