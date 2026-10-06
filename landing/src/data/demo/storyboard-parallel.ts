import { SAMPLE } from './sample-workspace';
import { SHORTCUTS } from './shortcuts';
import { at, beat, camera, click, hide, point, script, shortcut, show, state, swap, text } from './storyboard-keys';

/**
 * Chapter 2, 19 to 40 s: Split Right, Codex typed into the new terminal,
 * the sidebar switching from the merged run to the agent summary once two
 * agents share the main panel, quotas and Resource Manager, and Claude
 * stopping to ask for permission, which is what sends the push.
 */
const FULL = [0, 0, 1720, 900] as const;
const WORKBENCH = [0, 48, 1228, 642] as const;

export const PARALLEL_CHAPTER = script([
  {
    beats: [
      beat(24.9, 'The sidebar follows every agent run in the workspace and what each one is doing right now.'),
      beat(26.3, "Each provider's remaining quota stays in the status bar."),
      beat(27.6, 'Resource Manager shows what every terminal costs in CPU and memory.'),
      beat(32.0, 'Claude asks before running the tests. The tab, the sidebar and the phone all show it is waiting.'),
    ],
    camera: [
      camera(19.0, [300, 48, 928, 560], [300, 48, 480, 600]),
      camera(22.2, [300, 48, 928, 560], [770, 48, 480, 600]),
      camera(24.6, WORKBENCH, [0, 150, 420, 525]),
      camera(26.3, [0, 560, 720, 340], [0, 470, 420, 525]),
      camera(27.5, [760, 360, 540, 520], [790, 380, 440, 550]),
      camera(31.6, WORKBENCH, [300, 250, 460, 575]),
      camera(33.2, FULL, [1310, 18, 410, 512]),
      camera(36.4, FULL, [770, 48, 480, 600]),
    ],
    hud: [shortcut(19.0, SHORTCUTS.splitRight.keys, SHORTCUTS.splitRight.label)],
    pointer: [
      point(21.0, [1000, 560, 0, 0], 900),
      click(24.9, 'd-row-webhooks-tray', 850),
      point(27.4, 'd-resource-chip', 900),
      point(31.3, [700, 600, 0, 0], 700),
    ],
  },
  {
    // Split Right, then Codex in the new pane.
    states: [
      state(19.3, 'd-panes', 'split'),
      state(23.3, 'd-chip-codex-dot', 'working'),
    ],
    typing: [{ node: 'codex-command', start: at(20.0), text: `codex "${SAMPLE.codexPrompt}"`, cps: 24 }],
    shows: [
      show(22.9, 'codex-ui', 0),
      show(23.3, 'd-chip-codex-generating', 0),
      hide(25.4, 'd-chip-codex-generating', 0),
    ],
    texts: [
      text(25.4, 'd-chip-codex-title', 'Duplicate Delivery Test'),
      text(19.5, 'd-res-sessions', '4'),
      text(19.5, 'd-res-memory', '1.21 GB'),
      text(25.5, 'd-res-memory', '1.37 GB'),
    ],
    reveals: [
      {
        node: 'codex-work',
        start: at(23.6),
        step: [250, 1400, 250, 250, 250, 1800, 250, 2200, 250, 250, 5600, 50, 150, 50],
      },
    ],
  },
  {
    // Two agents in the main panel: the row drops the merged run for the summary.
    states: [
      state(23.3, 'd-row-webhooks-glyph', 'idle-active'),
      state(23.5, 'p-row-webhooks-glyph', 'idle-active'),
      state(25.0, 'd-row-webhooks-tray', 'expanded'),
    ],
    shows: [
      hide(23.3, 'd-row-webhooks-logo', 0),
      show(23.3, 'd-row-webhooks-tray', 0),
      hide(23.5, 'p-row-webhooks-logo', 0),
      show(23.5, 'p-row-webhooks-tray', 0),
      show(25.0, 'd-row-webhooks-runs', 120),
    ],
    texts: [text(29.6, 'd-run-claude-label', 'Bash: bun test src/webhooks')],
  },
  {
    // Resource Manager opens on hover and closes when the pointer leaves.
    shows: [show(27.8, 'd-resource-card', 100), hide(31.5, 'd-resource-card', 100)],
    texts: [
      text(29.6, 'd-res-total-cpu', '13.2%'),
      text(29.6, 'd-res-claude-cpu', '5.1%'),
      text(29.6, 'd-res-codex-cpu', '4.4%'),
    ],
  },
  {
    // Claude waits for permission to run the tests. The workspace badge sums
    // up both agents, so it asks for input with no merged run on the row.
    shows: [
      hide(32.0, 'claude-thinking', 0),
      show(32.0, 'claude-permission', 0),
      show(32.0, 'p-claude-permission', 0),
      ...swap(32.0, 'd-tray-working-both', 'd-tray-waiting-working'),
      ...swap(32.2, 'p-tray-working-both', 'p-tray-waiting-working'),
      show(33.4, 'p-notification', 220, -18),
    ],
    states: [
      state(32.0, 'd-chip-claude-dot', 'waiting'),
      state(32.0, 'd-run-claude-glyph', 'waiting'),
      state(32.0, 'd-row-webhooks-badge', 'waiting'),
      state(32.2, 'p-row-webhooks-badge', 'waiting'),
    ],
  },
  {
    // Codex finishes its test beside it.
    shows: [
      hide(36.6, 'codex-status', 0),
      ...swap(36.6, 'd-tray-waiting-working', 'd-tray-waiting-done'),
      ...swap(36.8, 'p-tray-waiting-working', 'p-tray-waiting-done'),
    ],
    states: [state(36.6, 'd-chip-codex-dot', 'done'), state(36.6, 'd-run-codex-glyph', 'done')],
    texts: [
      text(36.6, 'd-run-codex-label', 'Added a regression test: a second delivery with the same event id is acknowledged without charging again.'),
    ],
  },
]);
