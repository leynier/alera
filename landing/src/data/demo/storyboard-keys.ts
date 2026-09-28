import type {
  Beat,
  CameraKey,
  HudKey,
  Ms,
  PointerKey,
  RevealRun,
  ShowKey,
  StateKey,
  Target,
  TextKey,
  TweenRun,
  TypeRun,
} from '../../scripts/demo/timeline';

/**
 * The vocabulary the chapter scripts are written in: seconds instead of
 * milliseconds, and one call per thing that happens on screen (a click, a
 * toast, a view swap) instead of the raw keys it takes.
 */
export interface Script {
  beats: Beat[];
  states: StateKey[];
  shows: ShowKey[];
  texts: TextKey[];
  typing: TypeRun[];
  reveals: RevealRun[];
  tweens: TweenRun[];
  camera: CameraKey[];
  pointer: PointerKey[];
  hud: HudKey[];
}

export const at = (seconds: number): Ms => Math.round(seconds * 1000);

export function script(parts: Partial<Script>[]): Script {
  const merged: Script = { beats: [], states: [], shows: [], texts: [], typing: [], reveals: [], tweens: [], camera: [], pointer: [], hud: [] };
  for (const part of parts) {
    for (const key of Object.keys(merged) as (keyof Script)[]) {
      (merged[key] as unknown[]).push(...((part[key] as unknown[] | undefined) ?? []));
    }
  }
  return merged;
}

export const state = (seconds: number, node: string, value: string): StateKey => ({ at: at(seconds), node, state: value });
export const text = (seconds: number, node: string, value: string): TextKey => ({ at: at(seconds), node, text: value });

export function show(seconds: number, node: string, fadeMs = 180, lift = 0): ShowKey {
  return { at: at(seconds), node, show: true, fadeMs, lift };
}

export function hide(seconds: number, node: string, fadeMs = 180): ShowKey {
  return { at: at(seconds), node, show: false, fadeMs, collapse: true };
}

/** Replaces one visible variant with another in the same frame. */
export function swap(seconds: number, from: string, to: string): ShowKey[] {
  return [hide(seconds, from, 0), show(seconds, to, 0)];
}

export const beat = (seconds: number, caption: string): Beat => ({ at: at(seconds), caption });

export function camera(seconds: number, wide: Target, compact: Target, ms = 800): CameraKey {
  return { at: at(seconds), wide, compact, ms };
}

/** The mouse travels to a target and presses on arrival. */
export function click(seconds: number, target: Target, moveMs = 650): PointerKey {
  return { at: at(seconds), device: 'mouse', target, press: true, moveMs };
}

export function point(seconds: number, target: Target, moveMs = 650): PointerKey {
  return { at: at(seconds), device: 'mouse', target, moveMs };
}

/** A finger lands on a target, taps, and lifts. */
export function tap(seconds: number, target: Target): PointerKey[] {
  return [
    { at: at(seconds), device: 'touch', target, press: true, moveMs: 350 },
    { at: at(seconds + 0.35), device: 'touch', hide: true },
  ];
}

export function shortcut(seconds: number, keys: string, label: string, holdSeconds = 1.3): HudKey {
  return { at: at(seconds), until: at(seconds + holdSeconds), keys, label };
}

const TOAST_MS = 4_000;
const TOAST_EXIT_MS = 180;

/**
 * Toasts as the app shows them: in at once, out after four seconds with a
 * short fade and slide. Slots are reused in turn, so a script must not keep
 * more than three on screen.
 */
export function toasts(list: readonly { at: number; message: string }[]): Partial<Script> {
  const slots = ['d-toast-a', 'd-toast-b', 'd-toast-c'];
  const busyUntil = new Map(slots.map((slot) => [slot, -Infinity]));
  const exits = new Map<string, { at: Ms; value: number }[]>(slots.map((slot) => [slot, [{ at: 0, value: 0 }]]));
  const part: Partial<Script> = { texts: [], shows: [] };
  for (const toast of list) {
    const start = at(toast.at);
    const slot = slots.find((candidate) => busyUntil.get(candidate)! <= start);
    if (!slot) throw new Error(`No free toast slot at ${toast.at}s`);
    const end = start + TOAST_MS;
    busyUntil.set(slot, end + TOAST_EXIT_MS);
    part.texts!.push({ at: start, node: `${slot}-text`, text: toast.message });
    part.shows!.push({ at: start, node: slot, show: true, fadeMs: 0 });
    part.shows!.push({ at: end + TOAST_EXIT_MS, node: slot, show: false, fadeMs: 0, collapse: true });
    exits.get(slot)!.push({ at: start, value: 0 }, { at: end, value: 0 }, { at: end + TOAST_EXIT_MS, value: 1 });
  }
  part.tweens = slots.map((slot) => ({ node: slot, prop: 'exit', keys: exits.get(slot)! }));
  return part;
}
