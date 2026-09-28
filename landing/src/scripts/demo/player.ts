import { createSceneBinding, type SceneBinding } from './scene-binding';
import { compileStoryboard, type CompiledTimeline, type Storyboard, type StageLayout } from './timeline';

/**
 * Drives the demo: a clock, the controls, and the rules for when it may move.
 * It autoplays only when most of it is on screen and motion is not reduced,
 * pauses when scrolled away or when the tab is hidden, and never loops: it
 * ends on a card with Replay. `?demo=capture` exposes an exact `seek` for the
 * README media script instead of playing.
 */
export type PauseReason = 'user' | 'offscreen' | 'hidden' | 'ended';

export interface DemoPlayer {
  readonly timeline: CompiledTimeline;
  readonly time: number;
  play(): void;
  pause(reason: PauseReason): void;
  seek(t: number): void;
}

declare global {
  interface Window {
    __aleraDemo?: {
      duration: number;
      chapters: CompiledTimeline['chapters'];
      seek(t: number): Promise<void>;
    };
  }
}

const MAX_STEP_MS = 100;
const PLAY_RATIO = 0.35;
const PAUSE_RATIO = 0.2;

function formatTime(ms: number): string {
  const seconds = Math.floor(ms / 1000);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

const nextFrames = () => new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));

export async function mountDemo(root: HTMLElement, board: Storyboard): Promise<DemoPlayer> {
  const timeline = compileStoryboard(board);
  const binding: SceneBinding = createSceneBinding(root, timeline);
  if (binding.missing.length > 0) console.warn(`Demo nodes missing from the scene: ${binding.missing.join(', ')}`);

  const capture = new URLSearchParams(window.location.search).get('demo') === 'capture';
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const toggle = root.querySelector<HTMLButtonElement>('[data-demo-toggle]');
  const toggleLabel = toggle?.querySelector<HTMLElement>('[data-demo-toggle-label]');
  const scrub = root.querySelector<HTMLInputElement>('[data-demo-scrub]');
  const clock = root.querySelector<HTMLElement>('[data-demo-time]');
  const chapterButtons = [...root.querySelectorAll<HTMLButtonElement>('[data-demo-chapter]')];
  const replayButtons = [...root.querySelectorAll<HTMLButtonElement>('[data-demo-replay]')];

  // Every face the stage draws with must be loaded before layout is measured:
  // a late font changes text widths and would move the pointer's targets.
  await Promise.all(
    [
      '400 13px Inter',
      '500 13px Inter',
      '600 13px Inter',
      '400 13px "JetBrains Mono"',
      '600 13px "JetBrains Mono"',
    ].map((font) => document.fonts.load(font, 'Aa ─│●❯⌘⇧→').catch(() => [])),
  );
  await document.fonts.ready;
  const layout: StageLayout = binding.measure(timeline);

  let time = 0;
  let playing = false;
  let userPaused = false;
  let inView = false;
  let frameRequest = 0;
  let lastTick = 0;
  let renderedChapter = -1;

  const render = () => {
    const frame = timeline.frameAt(time, layout);
    binding.apply(frame);
    root.dataset.state = playing ? 'playing' : time >= timeline.duration ? 'ended' : 'paused';
    if (scrub) {
      scrub.value = String(Math.round(time));
      scrub.setAttribute(
        'aria-valuetext',
        `Chapter ${frame.chapter + 1} of ${timeline.chapters.length}, ${formatTime(time)} of ${formatTime(timeline.duration)}`,
      );
    }
    if (clock) clock.textContent = `${formatTime(time)} / ${formatTime(timeline.duration)}`;
    if (frame.chapter !== renderedChapter) {
      chapterButtons.forEach((button, index) => {
        if (index === frame.chapter) button.setAttribute('aria-current', 'step');
        else button.removeAttribute('aria-current');
      });
      renderedChapter = frame.chapter;
    }
  };

  const setToggle = () => {
    if (!toggle || !toggleLabel) return;
    const label = playing ? 'Pause' : time >= timeline.duration ? 'Replay' : 'Play';
    toggleLabel.textContent = label;
    toggle.setAttribute('aria-label', `${label} Demo`);
    toggle.dataset.action = label.toLowerCase();
  };

  const tick = (now: number) => {
    const step = Math.min(now - lastTick, MAX_STEP_MS);
    lastTick = now;
    time = Math.min(timeline.duration, time + step);
    if (time >= timeline.duration) {
      playing = false;
      setToggle();
    }
    render();
    if (playing) frameRequest = requestAnimationFrame(tick);
  };

  const play = () => {
    if (playing) return;
    if (time >= timeline.duration) time = 0;
    playing = true;
    lastTick = performance.now();
    setToggle();
    frameRequest = requestAnimationFrame(tick);
  };

  const pause = (reason: PauseReason) => {
    if (reason === 'user') userPaused = true;
    if (!playing) return;
    playing = false;
    cancelAnimationFrame(frameRequest);
    setToggle();
    render();
  };

  const seek = (t: number) => {
    time = Math.min(Math.max(t, 0), timeline.duration);
    render();
    setToggle();
  };

  const maybeAutoplay = () => {
    if (capture || reducedMotion.matches || userPaused || !inView || document.hidden) return;
    if (time >= timeline.duration) return;
    play();
  };

  toggle?.addEventListener('click', () => {
    if (playing) {
      pause('user');
    } else {
      userPaused = false;
      play();
    }
  });
  replayButtons.forEach((button) =>
    button.addEventListener('click', () => {
      userPaused = false;
      seek(0);
      play();
    }),
  );
  scrub?.addEventListener('input', () => {
    pause('user');
    seek(Number(scrub.value));
  });
  chapterButtons.forEach((button, index) => {
    button.addEventListener('click', () => {
      const chapter = timeline.chapters[index]!;
      // With motion reduced a chapter is its poster frame; otherwise it plays from the start.
      seek(reducedMotion.matches ? chapter.poster : chapter.start);
      if (!reducedMotion.matches && !capture) {
        userPaused = false;
        play();
      }
    });
  });

  const observer = new IntersectionObserver(
    ([entry]) => {
      const ratio = entry?.intersectionRatio ?? 0;
      if (ratio >= PLAY_RATIO) {
        inView = true;
        maybeAutoplay();
      } else if (ratio < PAUSE_RATIO) {
        inView = false;
        pause('offscreen');
      }
    },
    { threshold: [0, PAUSE_RATIO, PLAY_RATIO, 0.6] },
  );
  observer.observe(root);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) pause('hidden');
    else maybeAutoplay();
  });
  new ResizeObserver(() => render()).observe(root);

  if (scrub) scrub.max = String(timeline.duration);
  if (reducedMotion.matches) time = timeline.chapters[0]!.poster;
  render();
  setToggle();
  root.dataset.ready = '';

  if (capture) {
    root.dataset.capture = '';
    window.__aleraDemo = {
      duration: timeline.duration,
      chapters: timeline.chapters,
      seek: async (t: number) => {
        pause('user');
        seek(t);
        await document.fonts.ready;
        await nextFrames();
      },
    };
  }

  return {
    timeline,
    get time() {
      return time;
    },
    play,
    pause,
    seek,
  };
}
