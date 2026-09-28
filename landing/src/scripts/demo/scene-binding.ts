import { STAGE_WIDTH, TIER_ASPECT, fitCamera, tierFor, type DemoTier } from './camera';
import type { CompiledTimeline, DemoFrame, Rect, StageLayout } from './timeline';

/**
 * Writes a frame into the demo's DOM. Nodes are the elements marked
 * `data-demo-node`; anything a frame does not mention goes back to how the
 * markup rendered it, which is what makes seeking backwards exact.
 */
interface InitialState {
  state: string | null;
  text: string;
  hidden: boolean;
  concealed: boolean;
}

export interface SceneBinding {
  readonly root: HTMLElement;
  readonly missing: readonly string[];
  apply(frame: DemoFrame): void;
  /** Measures every layout-dependent key by showing its frame; call while the stage is not visible. */
  measure(timeline: CompiledTimeline): StageLayout;
  tier(): DemoTier;
}

export function createSceneBinding(root: HTMLElement, timeline: CompiledTimeline): SceneBinding {
  const viewport = root.querySelector<HTMLElement>('[data-demo-viewport]')!;
  const stage = root.querySelector<HTMLElement>('[data-demo-stage]')!;
  const caption = root.querySelector<HTMLElement>('[data-demo-caption]');
  const hud = root.querySelector<HTMLElement>('[data-demo-hud]');
  const hudKeys = hud?.querySelector<HTMLElement>('[data-demo-hud-keys]');
  const hudLabel = hud?.querySelector<HTMLElement>('[data-demo-hud-label]');
  const pointers = new Map(
    [...root.querySelectorAll<HTMLElement>('[data-demo-pointer]')].map((element) => [element.dataset.demoPointer!, element]),
  );

  const nodes = new Map<string, HTMLElement>();
  for (const element of stage.querySelectorAll<HTMLElement>('[data-demo-node]')) nodes.set(element.dataset.demoNode!, element);
  const missing = [...timeline.nodes].filter((id) => !nodes.has(id));

  const initial = new Map<string, InitialState>();
  for (const [id, element] of nodes) {
    initial.set(id, {
      state: element.getAttribute('data-state'),
      text: element.textContent ?? '',
      hidden: element.hidden === true,
      concealed: element.hasAttribute('data-demo-concealed'),
    });
  }

  let lastCaption = '';
  let lastTier: DemoTier | null = null;
  const touched = { states: new Set<string>(), shows: new Set<string>(), texts: new Set<string>(), reveals: new Set<string>() };

  const screenOf = (element: HTMLElement) => element.closest<HTMLElement>('[data-demo-screen]');

  const apply = (frame: DemoFrame) => {
    const dirtyScreens = new Set<HTMLElement>();

    for (const id of new Set([...touched.states, ...frame.states.keys()])) {
      const element = nodes.get(id);
      if (!element) continue;
      const state = frame.states.get(id) ?? initial.get(id)!.state;
      if (element.getAttribute('data-state') !== state) {
        if (state === null) element.removeAttribute('data-state');
        else element.setAttribute('data-state', state);
      }
    }
    touched.states = new Set(frame.states.keys());

    for (const id of new Set([...touched.shows, ...frame.shows.keys()])) {
      const element = nodes.get(id);
      if (!element) continue;
      const show = frame.shows.get(id);
      const start = initial.get(id)!;
      const opacity = show ? show.opacity : start.concealed ? 0 : 1;
      const collapsed = show ? show.collapsed : start.hidden;
      element.hidden = collapsed;
      element.style.opacity = opacity >= 1 ? '' : String(opacity);
      element.style.visibility = opacity <= 0 ? 'hidden' : '';
      element.style.translate = show && show.lift ? `0 ${show.lift}px` : '';
      const screen = screenOf(element);
      if (screen) dirtyScreens.add(screen);
    }
    touched.shows = new Set(frame.shows.keys());

    for (const id of new Set([...touched.texts, ...frame.texts.keys()])) {
      const element = nodes.get(id);
      if (!element) continue;
      const text = frame.texts.get(id) ?? initial.get(id)!.text;
      if (element.textContent !== text) {
        element.textContent = text;
        const screen = screenOf(element);
        if (screen) dirtyScreens.add(screen);
      }
      element.toggleAttribute('data-typing', frame.typing.has(id));
    }
    touched.texts = new Set(frame.texts.keys());

    for (const [id, count] of frame.reveals) {
      const element = nodes.get(id);
      if (!element) continue;
      let changed = false;
      [...element.children].forEach((child, index) => {
        const hidden = index >= count;
        if ((child as HTMLElement).hidden !== hidden) {
          (child as HTMLElement).hidden = hidden;
          changed = true;
        }
      });
      const screen = screenOf(element);
      if (changed && screen) dirtyScreens.add(screen);
    }

    for (const [key, value] of frame.vars) {
      const [id, prop] = key.split('|') as [string, string];
      nodes.get(id)?.style.setProperty(`--${prop}`, String(value));
    }

    // Terminals keep their newest line on screen once they fill up, the way
    // a real terminal scrolls. Reads come after every write above.
    const offsets = [...dirtyScreens].map((screen) => {
      const content = screen.firstElementChild as HTMLElement | null;
      return [content, content ? Math.min(0, screen.clientHeight - content.scrollHeight) : 0] as const;
    });
    for (const [content, offset] of offsets) if (content) content.style.translate = offset ? `0 ${offset}px` : '';

    root.style.setProperty('--demo-t', String(Math.round(frame.t)));

    const tier = tierFor(viewport.clientWidth);
    if (tier !== lastTier) {
      viewport.dataset.tier = tier;
      lastTier = tier;
    }
    const rect: Rect = tier === 'compact' ? frame.camera.compact : frame.camera.wide;
    const width = viewport.clientWidth;
    const camera = fitCamera(rect, width, width / TIER_ASPECT[tier]);
    stage.style.transform = `translate(${camera.x}px, ${camera.y}px) scale(${camera.scale})`;

    for (const [device, element] of pointers) {
      const pointer = frame.pointers.find((candidate) => candidate.device === device);
      const visible = pointer?.visible ?? false;
      element.style.opacity = visible ? '1' : '0';
      if (pointer && visible) {
        element.style.translate = `${pointer.x}px ${pointer.y}px`;
        element.style.setProperty('--press', pointer.pressed.toFixed(3));
      }
    }

    if (hud && hudKeys && hudLabel) {
      hud.hidden = frame.hud === null;
      if (frame.hud) {
        hudKeys.textContent = frame.hud.keys;
        hudLabel.textContent = frame.hud.label;
      }
    }

    if (caption && frame.caption !== lastCaption) {
      caption.textContent = frame.caption;
      lastCaption = frame.caption;
    }
  };

  const measure = (compiled: CompiledTimeline): StageLayout => {
    const layout = new Map<string, Rect>();
    const previousTransform = stage.style.transform;
    stage.style.transform = 'none';
    for (const request of compiled.layoutRequests) {
      apply(compiled.frameAt(request.at));
      stage.style.transform = 'none';
      const element = nodes.get(request.node);
      if (!element) continue;
      const stageBox = stage.getBoundingClientRect();
      const box = element.getBoundingClientRect();
      if (box.width === 0 && box.height === 0) continue;
      const scale = stageBox.width / STAGE_WIDTH || 1;
      layout.set(request.id, [
        (box.left - stageBox.left) / scale,
        (box.top - stageBox.top) / scale,
        box.width / scale,
        box.height / scale,
      ]);
    }
    stage.style.transform = previousTransform;
    return layout;
  };

  return { root, missing, apply, measure, tier: () => tierFor(viewport.clientWidth) };
}
