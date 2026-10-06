import { beat, camera, click, hide, point, script, show, state, swap, tap, text } from './storyboard-keys';

/**
 * Chapter 3, 40 to 60 s: the push opens the workspace on the phone, the
 * phone takes the driver seat (terminal_driver.rs), so the desktop pane
 * narrows to the phone's columns under the driver banner, Enter answers
 * Claude, and the desktop takes the terminal back, which sends the phone
 * back to its list with a snack bar.
 */
const FULL = [0, 0, 1720, 900] as const;
const PHONE_TOP = [1310, 18, 410, 512] as const;
const CLAUDE_PANE = [300, 48, 460, 575] as const;
const TESTS_STEPS = [1800, 250, 250, 1400, 250, 250];

export const PHONE_CHAPTER = script([
  {
    beats: [
      beat(42.0, 'While the phone drives the terminal, the desktop keyboard is paused so no one types over anyone.'),
      beat(45.3, 'Enter on the phone reaches the real terminal, and Claude runs the tests.'),
      beat(53.7, 'Take the terminal back from the desktop whenever you want. Pushes for finished agents are off by default.'),
    ],
    camera: [
      camera(40.0, FULL, PHONE_TOP),
      camera(41.6, FULL, [1310, 120, 410, 512]),
      camera(42.3, FULL, CLAUDE_PANE),
      camera(44.2, FULL, [1310, 390, 410, 512], 700),
      camera(46.0, FULL, [1310, 200, 410, 512]),
      camera(51.0, FULL, [300, 250, 460, 575]),
      camera(52.8, FULL, CLAUDE_PANE),
      camera(53.9, FULL, [1310, 380, 410, 512]),
      camera(56.6, FULL, [0, 150, 420, 525]),
    ],
    pointer: [...tap(41.2, 'p-notification'), ...tap(45.0, 'p-key-enter'), point(50.0, [620, 560, 0, 0], 900), click(53.6, 'd-driver-take-back', 900)],
  },
  {
    // The push opens the workspace; the phone takes the driver seat.
    shows: [hide(41.4, 'p-notification', 150), show(41.5, 'p-workspace', 200, 16), show(42.0, 'd-driver', 180, 6)],
    states: [state(42.0, 'd-pane-claude', 'driven')],
  },
  {
    // Enter from the quick keys accepts the prompt on the desktop's PTY.
    states: [
      state(45.0, 'p-key-enter', 'pressed'),
      state(45.25, 'p-key-enter', ''),
      state(45.3, 'd-chip-claude-dot', 'working'),
      state(45.3, 'd-run-claude-glyph', 'working'),
      state(45.3, 'p-chip-claude-glyph', 'working'),
      state(45.3, 'd-row-webhooks-badge', 'none'),
      state(45.4, 'p-row-webhooks-badge', 'none'),
    ],
    shows: [
      hide(45.3, 'claude-permission', 0),
      hide(45.3, 'p-claude-permission', 0),
      show(45.3, 'claude-thinking', 0),
      show(45.3, 'p-claude-thinking', 0),
      ...swap(45.3, 'd-tray-waiting-done', 'd-tray-working-done'),
      ...swap(45.4, 'p-tray-waiting-done', 'p-tray-working-done'),
    ],
    reveals: [
      { node: 'claude-tests', start: 45_600, step: TESTS_STEPS },
      { node: 'p-claude-tests', start: 45_600, step: TESTS_STEPS },
    ],
  },
  {
    // Claude is done, on both screens.
    shows: [
      hide(51.0, 'claude-thinking', 0),
      hide(51.0, 'p-claude-thinking', 0),
      ...swap(51.0, 'd-tray-working-done', 'd-tray-done-both'),
      ...swap(51.1, 'p-tray-working-done', 'p-tray-done-both'),
    ],
    states: [
      state(51.0, 'd-chip-claude-dot', 'done'),
      state(51.0, 'd-run-claude-glyph', 'done'),
      state(51.0, 'p-chip-claude-glyph', 'done'),
      state(51.0, 'd-row-webhooks-badge', 'done'),
      state(51.1, 'p-row-webhooks-badge', 'done'),
    ],
    texts: [text(51.0, 'd-run-claude-label', 'All webhook tests pass. Failed deliveries now retry with exponential backoff and jitter.')],
  },
  {
    // The desktop takes the terminal back.
    shows: [
      hide(53.7, 'd-driver', 150),
      hide(53.9, 'p-workspace', 200),
      show(53.9, 'p-snackbar', 150, 12),
      hide(57.9, 'p-snackbar', 150),
    ],
    // A floating SnackBar lifts the list's New Workspace button above it.
    states: [state(53.7, 'd-pane-claude', 'own'), state(53.9, 'p-list', 'snackbar'), state(58.05, 'p-list', '')],
  },
]);
