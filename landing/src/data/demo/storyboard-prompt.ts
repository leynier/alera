import { APP_COPY } from './app-copy';
import { SAMPLE } from './sample-workspace';
import { SHORTCUTS } from './shortcuts';
import { at, beat, camera, click, hide, point, script, shortcut, show, state, text } from './storyboard-keys';

/**
 * Chapter 1, 0 to 19 s: New Workspace from a prompt. The sequence is the one
 * background_setup_jobs.dart runs: the dialog closes on Create, the job card
 * walks through its phases, the workspace appears in the sidebar without
 * being selected, and "Workspace created" comes once the agent has started.
 */
const FULL = [0, 0, 1720, 900] as const;
const SIDEBAR_COMPACT = [0, 20, 420, 525] as const;

export const PROMPT_CHAPTER = script([
  {
    beats: [
      beat(8.2, 'Creation runs as a background job while you keep working. Nothing takes over the screen.'),
      beat(14.3, 'Claude is already working in its own worktree by the time you open the workspace.'),
    ],
    camera: [
      camera(0, FULL, SIDEBAR_COMPACT, 0),
      camera(1.3, 'd-dialog', [330, 100, 440, 550], 700),
      camera(3.2, 'd-dialog', [330, 330, 440, 550], 600),
      camera(7.3, 'd-dialog', [560, 380, 440, 550], 500),
      camera(8.2, FULL, [860, 360, 420, 525]),
      camera(10.6, FULL, SIDEBAR_COMPACT),
      camera(12.8, FULL, [860, 360, 420, 525]),
      camera(14.5, [0, 20, 1000, 520], [300, 48, 420, 525], 900),
    ],
    hud: [shortcut(1.0, SHORTCUTS.newWorkspace.keys, SHORTCUTS.newWorkspace.label, 1.4)],
    pointer: [
      point(0.5, [880, 520, 0, 0], 0),
      click(2.5, 'd-dialog-new-worktree', 750),
      click(3.5, 'd-dialog-prompt', 600),
      click(7.9, 'd-dialog-create', 550),
      point(9.6, [760, 640, 0, 0], 900),
      click(14.4, 'd-row-webhooks', 950),
    ],
  },
  {
    // The dialog, filled in.
    shows: [
      show(1.2, 'd-dialog-barrier', 150),
      show(1.2, 'd-dialog', 150, 6),
      show(2.55, 'd-dialog-source-branch', 0),
      hide(8.05, 'd-dialog', 120),
      hide(8.05, 'd-dialog-barrier', 120),
    ],
    states: [
      state(2.55, 'd-dialog-location', 'worktree'),
      state(3.55, 'd-dialog-prompt', 'focused'),
      state(3.9, 'd-dialog-prompt', 'typing'),
    ],
    typing: [{ node: 'd-dialog-prompt-text', start: at(3.9), text: SAMPLE.prompt, cps: 27 }],
    tweens: [{ node: 'd-dialog-form', prop: 'scroll', keys: [{ at: at(7.0), value: 0 }, { at: at(7.35), value: 18, ease: 'easeOut' }] }],
  },
  {
    // The job card and the workspace arriving on both screens.
    shows: [
      show(8.2, 'd-job', 180, 8),
      hide(12.8, 'd-job', 150),
      show(10.8, 'd-row-webhooks', 180),
      show(11.0, 'p-row-webhooks', 180),
      show(12.4, 'd-row-webhooks-logo', 0),
      show(12.6, 'p-row-webhooks-logo', 0),
    ],
    texts: [
      text(9.4, 'd-job-phase', APP_COPY.phaseBranch.text),
      text(10.0, 'd-job-phase', APP_COPY.phaseCreating.text),
      text(11.0, 'd-job-title', APP_COPY.phaseStartingAgent.text),
      text(11.0, 'd-job-phase', APP_COPY.phaseStartingAgent.text),
      text(10.8, 'd-storefront-count', '3'),
      text(10.8, 'd-projects-count', '5'),
      text(11.0, 'p-storefront-count', '3'),
      text(12.4, 'd-res-sessions', '3'),
      text(12.4, 'd-res-memory', '1.08 GB'),
    ],
    states: [
      state(11.6, 'd-row-webhooks-glyph', 'idle-active'),
      state(12.4, 'd-row-webhooks-glyph', 'working'),
      state(11.8, 'p-row-webhooks-glyph', 'idle-active'),
      state(12.6, 'p-row-webhooks-glyph', 'working'),
    ],
  },
  {
    // Opening the new workspace, where Claude is already working.
    states: [
      state(14.0, 'd-row-webhooks', 'hover'),
      state(14.4, 'd-row-webhooks', 'active'),
      state(14.4, 'd-row-release', 'idle'),
    ],
    shows: [
      hide(14.4, 'd-view-release', 0),
      show(14.4, 'd-view-webhooks', 0),
      show(12.6, 'claude-thinking', 0),
    ],
    reveals: [
      {
        node: 'claude-work',
        start: at(12.9),
        // One entry per line after the first: tool calls land with their
        // results, and the gaps are the agent thinking.
        step: [700, 1200, 250, 250, 1500, 250, 250, 1700, 250, 250, 250, 250, 900, 2600, 250, 250],
      },
    ],
  },
]);
