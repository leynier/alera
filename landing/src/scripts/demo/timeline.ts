import { ease, mix, progress, type EaseName } from './motion-curves';

/**
 * The product demo as data: every change on screen is a key at a time, and
 * `frameAt(t)` folds the keys into what the scene looks like at `t`. It reads
 * no clock, no DOM and no randomness, so seeking backwards, playing forwards
 * and rendering one frame for the README all produce the same picture.
 */
export type Ms = number;
export type Rect = readonly [x: number, y: number, width: number, height: number];
/** A node id in the scene, or a rectangle in stage coordinates. */
export type Target = string | Rect;

export interface Chapter {
  id: string;
  title: string;
  caption: string;
  start: Ms;
  end: Ms;
  /** The frame that stands for the chapter when motion is reduced. */
  poster: Ms;
}
export interface Beat {
  at: Ms;
  caption: string;
}
/** Sets `data-state` on a node. */
export interface StateKey {
  at: Ms;
  node: string;
  state: string;
}
/** Shows or hides a node with a fade; `collapse` takes it out of the layout while hidden. */
export interface ShowKey {
  at: Ms;
  node: string;
  show: boolean;
  fadeMs?: Ms;
  lift?: number;
  collapse?: boolean;
}
/** Replaces a node's text at once. */
export interface TextKey {
  at: Ms;
  node: string;
  text: string;
}
/** Types text into a node, one character at a time. */
export interface TypeRun {
  node: string;
  start: Ms;
  text: string;
  /** Characters per second. */
  cps?: number;
}
/** Reveals a node's children one by one, like lines arriving in a terminal. */
export interface RevealRun {
  node: string;
  start: Ms;
  /** Delay between children: one value for all, or one per child after the first. */
  step: Ms | readonly Ms[];
}
/** Animates a numeric CSS custom property (`--<prop>`) between keyed values. */
export interface TweenRun {
  node: string;
  prop: string;
  keys: readonly { at: Ms; value: number; ease?: EaseName }[];
}
export interface CameraKey {
  at: Ms;
  wide: Target;
  compact?: Target;
  ms?: Ms;
}
export interface PointerKey {
  at: Ms;
  device: 'mouse' | 'touch';
  target?: Target;
  press?: boolean;
  hide?: boolean;
  moveMs?: Ms;
}
export interface HudKey {
  at: Ms;
  until: Ms;
  keys: string;
  label: string;
}

export interface Storyboard {
  duration: Ms;
  chapters: readonly Chapter[];
  beats?: readonly Beat[];
  states?: readonly StateKey[];
  shows?: readonly ShowKey[];
  texts?: readonly TextKey[];
  typing?: readonly TypeRun[];
  reveals?: readonly RevealRun[];
  tweens?: readonly TweenRun[];
  camera: readonly CameraKey[];
  pointer?: readonly PointerKey[];
  hud?: readonly HudKey[];
}

export interface ShowState {
  opacity: number;
  lift: number;
  collapsed: boolean;
}
export interface PointerState {
  device: 'mouse' | 'touch';
  x: number;
  y: number;
  pressed: number;
  visible: boolean;
}
export interface DemoFrame {
  t: Ms;
  chapter: number;
  caption: string;
  /** Only nodes some key has touched by `t`; everything else keeps its markup. */
  states: ReadonlyMap<string, string>;
  shows: ReadonlyMap<string, ShowState>;
  texts: ReadonlyMap<string, string>;
  typing: ReadonlySet<string>;
  reveals: ReadonlyMap<string, number>;
  vars: ReadonlyMap<string, number>;
  camera: { wide: Rect; compact: Rect };
  pointers: readonly PointerState[];
  hud: HudKey | null;
}

/** Where layout-dependent keys point, measured from the rendered scene. */
export type StageLayout = ReadonlyMap<string, Rect>;
export interface LayoutRequest {
  id: string;
  at: Ms;
  node: string;
}

const DEFAULT_FADE_MS = 180;
const DEFAULT_CAMERA_MS = 700;
const DEFAULT_MOVE_MS = 520;
const DEFAULT_CPS = 30;
const PRESS_MS = 160;
const NODE_PADDING = 24;
const EMPTY_RECT: Rect = [0, 0, 0, 0];

/** Last index whose `at` is at or before `t`, or -1. */
function lastAtOrBefore<T extends { at: Ms }>(keys: readonly T[], t: Ms): number {
  let low = 0;
  let high = keys.length - 1;
  let found = -1;
  while (low <= high) {
    const mid = (low + high) >> 1;
    if (keys[mid]!.at <= t) {
      found = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return found;
}

function groupByNode<T extends { node: string; at: Ms }>(keys: readonly T[] = []): Map<string, T[]> {
  const groups = new Map<string, T[]>();
  for (const key of keys) {
    const group = groups.get(key.node) ?? [];
    group.push(key);
    groups.set(key.node, group);
  }
  for (const group of groups.values()) group.sort((a, b) => a.at - b.at);
  return groups;
}

/** Per-character arrival times, with a fixed, repeatable unevenness. */
export function typingSchedule(text: string, cps = DEFAULT_CPS): Ms[] {
  const base = 1000 / cps;
  const times: Ms[] = [];
  let elapsed = 0;
  for (let i = 0; i < text.length; i += 1) {
    elapsed += Math.max(base * 0.4, base + (((i * 7919) % 13) - 6) * base * 0.06);
    times.push(elapsed);
  }
  return times;
}

function countArrived(times: readonly Ms[], elapsed: Ms): number {
  let count = 0;
  while (count < times.length && times[count]! <= elapsed) count += 1;
  return count;
}

function padded(rect: Rect, pad = NODE_PADDING): Rect {
  return [rect[0] - pad, rect[1] - pad, rect[2] + pad * 2, rect[3] + pad * 2];
}

function mixRect(from: Rect, to: Rect, amount: number): Rect {
  return [mix(from[0], to[0], amount), mix(from[1], to[1], amount), mix(from[2], to[2], amount), mix(from[3], to[3], amount)];
}

export interface CompiledTimeline {
  duration: Ms;
  chapters: readonly Chapter[];
  /** Every node id the storyboard touches, to check against the scene. */
  nodes: ReadonlySet<string>;
  /** Positions the scene must measure before layout-dependent keys resolve. */
  layoutRequests: readonly LayoutRequest[];
  chapterAt(t: Ms): number;
  frameAt(t: Ms, layout?: StageLayout): DemoFrame;
}

export function compileStoryboard(board: Storyboard): CompiledTimeline {
  const problems: string[] = [];
  const inRange = (at: Ms, what: string) => {
    if (!(at >= 0 && at <= board.duration)) problems.push(`${what} at ${at} is outside 0..${board.duration}`);
  };

  const chapters = [...board.chapters].sort((a, b) => a.start - b.start);
  chapters.forEach((chapter, index) => {
    if (chapter.end <= chapter.start) problems.push(`chapter ${chapter.id} ends before it starts`);
    if (chapter.poster < chapter.start || chapter.poster >= chapter.end) problems.push(`chapter ${chapter.id} poster is outside it`);
    const next = chapters[index + 1];
    if (next && next.start < chapter.end) problems.push(`chapters ${chapter.id} and ${next.id} overlap`);
  });
  if (chapters.length === 0) problems.push('a storyboard needs at least one chapter');

  const states = groupByNode(board.states);
  const shows = groupByNode(board.shows);
  const texts = groupByNode(
    [
      ...(board.texts ?? []).map((key) => ({ ...key, typed: null as Ms[] | null })),
      ...(board.typing ?? []).map((run) => ({ at: run.start, node: run.node, text: run.text, typed: typingSchedule(run.text, run.cps) })),
    ],
  );
  const reveals = [...(board.reveals ?? [])];
  const tweens = (board.tweens ?? []).map((run) => ({ ...run, keys: [...run.keys].sort((a, b) => a.at - b.at) }));
  const beats = [...(board.beats ?? [])].sort((a, b) => a.at - b.at);
  const camera = [...board.camera].sort((a, b) => a.at - b.at);
  const hud = [...(board.hud ?? [])].sort((a, b) => a.at - b.at);
  const pointerDevices = (['mouse', 'touch'] as const).map((device) =>
    (board.pointer ?? []).filter((key) => key.device === device).sort((a, b) => a.at - b.at),
  );

  for (const group of [...states.values(), ...shows.values(), ...texts.values()]) for (const key of group) inRange(key.at, key.node);
  for (const run of reveals) inRange(run.start, run.node);
  for (const run of tweens) for (const key of run.keys) inRange(key.at, `${run.node} --${run.prop}`);
  for (const key of camera) inRange(key.at, 'camera');
  for (const keys of pointerDevices) for (const key of keys) inRange(key.at, `${key.device} pointer`);
  if (camera.length === 0) problems.push('a storyboard needs at least one camera key');
  else if (typeof camera[0]!.wide === 'string' || typeof camera[0]!.compact === 'string') {
    // Later keys fall back to the previous framing when a node cannot be
    // measured, so the chain has to start from a fixed rectangle.
    problems.push('the first camera key must frame explicit rectangles');
  }
  if (problems.length > 0) throw new Error(`Invalid storyboard:\n- ${problems.join('\n- ')}`);

  const nodes = new Set<string>([
    ...states.keys(),
    ...shows.keys(),
    ...texts.keys(),
    ...reveals.map((run) => run.node),
    ...tweens.map((run) => run.node),
  ]);

  const layoutRequests: LayoutRequest[] = [];
  camera.forEach((key, index) => {
    if (typeof key.wide === 'string') layoutRequests.push({ id: `camera:${index}:wide`, at: key.at, node: key.wide });
    if (typeof key.compact === 'string') layoutRequests.push({ id: `camera:${index}:compact`, at: key.at, node: key.compact });
  });
  pointerDevices.forEach((keys) =>
    keys.forEach((key, index) => {
      if (typeof key.target === 'string') layoutRequests.push({ id: `${key.device}:${index}`, at: key.at, node: key.target });
    }),
  );
  for (const request of layoutRequests) nodes.add(request.node);

  const chapterAt = (t: Ms) => {
    let index = 0;
    chapters.forEach((chapter, i) => {
      if (t >= chapter.start) index = i;
    });
    return index;
  };

  const resolve = (target: Target | undefined, id: string, layout: StageLayout | undefined, pad: boolean): Rect | null => {
    if (target === undefined) return null;
    if (typeof target !== 'string') return target;
    const rect = layout?.get(id);
    if (!rect) return null;
    return pad ? padded(rect) : rect;
  };

  const cameraAt = (t: Ms, layout: StageLayout | undefined) => {
    const rectFor = (index: number, tier: 'wide' | 'compact'): Rect => {
      const key = camera[index]!;
      const target = tier === 'compact' ? (key.compact ?? key.wide) : key.wide;
      const tierId = tier === 'compact' && key.compact !== undefined ? 'compact' : 'wide';
      return resolve(target, `camera:${index}:${tierId}`, layout, true) ?? (index > 0 ? rectFor(index - 1, tier) : EMPTY_RECT);
    };
    const current = Math.max(0, lastAtOrBefore(camera, t));
    const key = camera[current]!;
    const amount = current === 0 ? 1 : ease('camera', progress(t, key.at, key.ms ?? DEFAULT_CAMERA_MS));
    const frame = (tier: 'wide' | 'compact') =>
      amount >= 1 || current === 0 ? rectFor(current, tier) : mixRect(rectFor(current - 1, tier), rectFor(current, tier), amount);
    return { wide: frame('wide'), compact: frame('compact') };
  };

  const pointerAt = (keys: readonly PointerKey[], t: Ms, layout: StageLayout | undefined): PointerState | null => {
    if (keys.length === 0) return null;
    const device = keys[0]!.device;
    const centre = (index: number): [number, number] | null => {
      const rect = resolve(keys[index]!.target, `${device}:${index}`, layout, false);
      return rect ? [rect[0] + rect[2] / 2, rect[1] + rect[3] / 2] : null;
    };
    const nextIndex = keys.findIndex((key) => key.at >= t);
    const previousIndex = nextIndex === -1 ? keys.length - 1 : nextIndex - 1;
    const previous = previousIndex >= 0 ? keys[previousIndex]! : null;
    if (previous?.hide) return { device, x: 0, y: 0, pressed: 0, visible: false };

    const next = nextIndex === -1 ? null : keys[nextIndex]!;
    const from = previousIndex >= 0 ? centre(previousIndex) : null;
    const to = next ? centre(nextIndex) : null;
    let position = from;
    let visible = from !== null;
    if (next && to && !next.hide) {
      const moveMs = next.moveMs ?? DEFAULT_MOVE_MS;
      const amount = ease('easeInOut', progress(t, next.at - moveMs, moveMs));
      if (!from) {
        visible = t >= next.at - moveMs;
        position = to;
      } else if (amount > 0) {
        // A shallow arc reads as a hand on a mouse; a straight line reads as a robot.
        const [fx, fy] = from;
        const [tx, ty] = to;
        const length = Math.hypot(tx - fx, ty - fy) || 1;
        const bend = length * 0.12;
        const cx = (fx + tx) / 2 + ((ty - fy) / length) * bend;
        const cy = (fy + ty) / 2 - ((tx - fx) / length) * bend;
        const inverse = 1 - amount;
        position = [
          inverse * inverse * fx + 2 * inverse * amount * cx + amount * amount * tx,
          inverse * inverse * fy + 2 * inverse * amount * cy + amount * amount * ty,
        ];
      }
    }
    if (!position) return { device, x: 0, y: 0, pressed: 0, visible: false };

    let pressed = 0;
    if (previous?.press && t - previous.at < PRESS_MS) pressed = Math.sin(Math.PI * progress(t, previous.at, PRESS_MS));
    return { device, x: position[0], y: position[1], pressed, visible };
  };

  const frameAt = (rawT: Ms, layout?: StageLayout): DemoFrame => {
    const t = Math.min(Math.max(rawT, 0), board.duration);
    const chapter = chapterAt(t);
    const beatIndex = lastAtOrBefore(beats, t);
    const beat = beatIndex >= 0 && beats[beatIndex]!.at >= chapters[chapter]!.start ? beats[beatIndex]! : null;

    const stateMap = new Map<string, string>();
    for (const [node, keys] of states) {
      const index = lastAtOrBefore(keys, t);
      if (index >= 0) stateMap.set(node, keys[index]!.state);
    }

    const showMap = new Map<string, ShowState>();
    for (const [node, keys] of shows) {
      const index = lastAtOrBefore(keys, t);
      if (index < 0) continue;
      const key = keys[index]!;
      const amount = ease('easeOut', progress(t, key.at, key.fadeMs ?? DEFAULT_FADE_MS));
      const opacity = key.show ? amount : 1 - amount;
      showMap.set(node, {
        opacity,
        lift: key.show ? (1 - amount) * (key.lift ?? 0) : 0,
        collapsed: !key.show && opacity <= 0 && key.collapse === true,
      });
    }

    const textMap = new Map<string, string>();
    const typingSet = new Set<string>();
    for (const [node, keys] of texts) {
      const index = lastAtOrBefore(keys, t);
      if (index < 0) continue;
      const key = keys[index]!;
      if (key.typed) {
        const count = countArrived(key.typed, t - key.at);
        textMap.set(node, key.text.slice(0, count));
        if (count < key.text.length) typingSet.add(node);
      } else {
        textMap.set(node, key.text);
      }
    }

    const revealMap = new Map<string, number>();
    for (const run of reveals) {
      if (t < run.start) {
        revealMap.set(run.node, 0);
        continue;
      }
      const elapsed = t - run.start;
      if (Array.isArray(run.step)) {
        let count = 1;
        let at = 0;
        for (const gap of run.step as readonly Ms[]) {
          at += gap;
          if (at > elapsed) break;
          count += 1;
        }
        revealMap.set(run.node, count);
      } else {
        revealMap.set(run.node, 1 + Math.floor(elapsed / (run.step as Ms)));
      }
    }

    const varMap = new Map<string, number>();
    for (const run of tweens) {
      const keys = run.keys;
      if (keys.length === 0) continue;
      const index = lastAtOrBefore(keys, t);
      let value: number;
      if (index < 0) value = keys[0]!.value;
      else if (index === keys.length - 1) value = keys[index]!.value;
      else {
        const from = keys[index]!;
        const to = keys[index + 1]!;
        value = mix(from.value, to.value, ease(to.ease ?? 'linear', progress(t, from.at, to.at - from.at)));
      }
      varMap.set(`${run.node}|${run.prop}`, value);
    }

    const hudIndex = lastAtOrBefore(hud, t);
    const hudKey = hudIndex >= 0 && t < hud[hudIndex]!.until ? hud[hudIndex]! : null;

    return {
      t,
      chapter,
      caption: beat?.caption ?? chapters[chapter]!.caption,
      states: stateMap,
      shows: showMap,
      texts: textMap,
      typing: typingSet,
      reveals: revealMap,
      vars: varMap,
      camera: cameraAt(t, layout),
      pointers: pointerDevices.map((keys) => pointerAt(keys, t, layout)).filter((state): state is PointerState => state !== null),
      hud: hudKey,
    };
  };

  return { duration: board.duration, chapters, nodes, layoutRequests, chapterAt, frameAt };
}
