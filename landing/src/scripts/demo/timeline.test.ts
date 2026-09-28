import { describe, expect, test } from 'bun:test';
import { compileStoryboard, typingSchedule, type Storyboard } from './timeline';

const board: Storyboard = {
  duration: 10_000,
  chapters: [
    { id: 'one', title: 'One', caption: 'First chapter.', start: 0, end: 5_000, poster: 1_000 },
    { id: 'two', title: 'Two', caption: 'Second chapter.', start: 5_000, end: 10_000, poster: 6_000 },
  ],
  beats: [{ at: 2_000, caption: 'A beat inside chapter one.' }],
  states: [
    { at: 1_000, node: 'row', state: 'working' },
    { at: 3_000, node: 'row', state: 'waiting' },
  ],
  shows: [
    { at: 1_000, node: 'dialog', show: true, fadeMs: 200, lift: 8 },
    { at: 4_000, node: 'dialog', show: false, fadeMs: 200, collapse: true },
  ],
  texts: [{ at: 6_000, node: 'phase', text: 'Starting agent' }],
  typing: [{ node: 'prompt', start: 2_000, text: 'hello', cps: 10 }],
  reveals: [
    { node: 'lines', start: 2_000, step: 500 },
    { node: 'steps', start: 2_000, step: [100, 1_000] },
  ],
  tweens: [{ node: 'bar', prop: 'progress', keys: [{ at: 1_000, value: 0 }, { at: 2_000, value: 1 }] }],
  camera: [
    { at: 0, wide: [0, 0, 1720, 900] },
    { at: 5_000, wide: 'dialog', compact: [0, 0, 400, 500], ms: 1_000 },
  ],
  pointer: [
    { at: 2_000, device: 'mouse', target: [100, 100, 20, 20] },
    { at: 3_000, device: 'mouse', target: [500, 100, 20, 20], press: true, moveMs: 500 },
  ],
  hud: [{ at: 1_000, until: 2_000, keys: 'Mod+Shift+N', label: 'New Workspace' }],
};

const timeline = compileStoryboard(board);

describe('compileStoryboard', () => {
  test('rejects keys outside the storyboard and overlapping chapters', () => {
    expect(() =>
      compileStoryboard({ ...board, states: [{ at: 20_000, node: 'row', state: 'late' }] }),
    ).toThrow(/outside/);
    expect(() =>
      compileStoryboard({
        ...board,
        chapters: [
          { id: 'a', title: 'A', caption: '', start: 0, end: 6_000, poster: 0 },
          { id: 'b', title: 'B', caption: '', start: 5_000, end: 10_000, poster: 5_000 },
        ],
      }),
    ).toThrow(/overlap/);
  });

  test('lists the nodes it touches and the layout it needs', () => {
    expect([...timeline.nodes]).toEqual(expect.arrayContaining(['row', 'dialog', 'phase', 'prompt', 'lines', 'bar']));
    expect(timeline.layoutRequests).toEqual([{ id: 'camera:1:wide', at: 5_000, node: 'dialog' }]);
  });
});

describe('frameAt', () => {
  test('leaves untouched nodes out, so they keep their markup', () => {
    const frame = timeline.frameAt(500);
    expect(frame.states.has('row')).toBe(false);
    expect(frame.shows.has('dialog')).toBe(false);
    expect(frame.reveals.get('lines')).toBe(0);
  });

  test('folds discrete keys to the latest one', () => {
    expect(timeline.frameAt(1_500).states.get('row')).toBe('working');
    expect(timeline.frameAt(3_000).states.get('row')).toBe('waiting');
  });

  test('fades nodes in and collapses them after fading out', () => {
    expect(timeline.frameAt(1_000).shows.get('dialog')).toEqual({ opacity: 0, lift: 8, collapsed: false });
    expect(timeline.frameAt(1_200).shows.get('dialog')?.opacity).toBe(1);
    expect(timeline.frameAt(4_100).shows.get('dialog')?.collapsed).toBe(false);
    expect(timeline.frameAt(4_200).shows.get('dialog')?.collapsed).toBe(true);
  });

  test('types text on a fixed schedule and marks the node while it types', () => {
    const schedule = typingSchedule('hello', 10);
    expect(schedule).toHaveLength(5);
    const midway = timeline.frameAt(2_000 + schedule[1]!);
    expect(midway.texts.get('prompt')).toBe('he');
    expect(midway.typing.has('prompt')).toBe(true);
    const done = timeline.frameAt(2_000 + schedule[4]! + 1);
    expect(done.texts.get('prompt')).toBe('hello');
    expect(done.typing.has('prompt')).toBe(false);
  });

  test('reveals children on a uniform or per-child schedule', () => {
    expect(timeline.frameAt(2_000).reveals.get('lines')).toBe(1);
    expect(timeline.frameAt(3_100).reveals.get('lines')).toBe(3);
    expect(timeline.frameAt(2_050).reveals.get('steps')).toBe(1);
    expect(timeline.frameAt(2_150).reveals.get('steps')).toBe(2);
    expect(timeline.frameAt(3_200).reveals.get('steps')).toBe(3);
  });

  test('interpolates tweens between keys and holds the ends', () => {
    expect(timeline.frameAt(0).vars.get('bar|progress')).toBe(0);
    expect(timeline.frameAt(1_500).vars.get('bar|progress')).toBeCloseTo(0.5, 6);
    expect(timeline.frameAt(9_000).vars.get('bar|progress')).toBe(1);
  });

  test('moves the camera to measured nodes and uses the compact target on phones', () => {
    const layout = new Map([['camera:1:wide', [100, 100, 300, 200] as const]]);
    const settled = timeline.frameAt(7_000, layout);
    expect(settled.camera.wide).toEqual([76, 76, 348, 248]);
    expect(settled.camera.compact).toEqual([0, 0, 400, 500]);
    const halfway = timeline.frameAt(5_500, layout).camera.wide;
    expect(halfway[0]).toBeGreaterThan(0);
    expect(halfway[0]).toBeLessThan(76);
  });

  test('moves the pointer along an arc and presses on arrival', () => {
    const resting = timeline.frameAt(2_400).pointers[0]!;
    expect(resting).toMatchObject({ x: 110, y: 110, visible: true, pressed: 0 });
    const moving = timeline.frameAt(2_750).pointers[0]!;
    expect(moving.x).toBeGreaterThan(110);
    expect(moving.x).toBeLessThan(510);
    expect(moving.y).not.toBe(110);
    expect(timeline.frameAt(3_080).pointers[0]!.pressed).toBeGreaterThan(0.9);
    expect(timeline.frameAt(3_400).pointers[0]!.pressed).toBe(0);
  });

  test('uses chapter captions until a beat inside the chapter replaces them', () => {
    expect(timeline.frameAt(1_000).caption).toBe('First chapter.');
    expect(timeline.frameAt(2_500).caption).toBe('A beat inside chapter one.');
    expect(timeline.frameAt(6_000)).toMatchObject({ chapter: 1, caption: 'Second chapter.' });
  });

  test('shows a shortcut only for its window', () => {
    expect(timeline.frameAt(1_500).hud?.label).toBe('New Workspace');
    expect(timeline.frameAt(2_500).hud).toBeNull();
  });

  test('gives the same frame for the same time however it was reached', () => {
    const direct = timeline.frameAt(3_250);
    timeline.frameAt(9_999);
    timeline.frameAt(10);
    expect(timeline.frameAt(3_250)).toEqual(direct);
  });
});
