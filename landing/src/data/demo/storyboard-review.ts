import { SAMPLE } from './sample-workspace';
import { SHORTCUTS } from './shortcuts';
import { at, beat, camera, click, hide, point, script, shortcut, show, state, swap, text } from './storyboard-keys';

/**
 * Chapter 4, 60 to 89 s: Close Split, Show Source Control, a wider panel so
 * the AI Assist button is in view (at 280 px it scrolls out,
 * workspace_git_diff_panel_toolbar.dart), stage, generate, commit, publish;
 * then the Pull Request tool, its checks, and Watch and Fix dispatching the
 * failure to Claude.
 */
const FULL = [0, 0, 1720, 900] as const;
const PANEL = [700, 48, 590, 470] as const;
const PANEL_COMPACT = [880, 48, 410, 512] as const;
// The panel's resize handle before and after dragging it 100 px wider.
const HANDLE_START = [997, 330, 0, 0] as const;
const HANDLE_END = [897, 330, 0, 0] as const;

export const REVIEW_CHAPTER = script([
  {
    beats: [
      beat(72.6, 'Open the pull request from the same panel. AI Assist drafts its title and description too.'),
      beat(77.6, 'Checks run right under the pull request. When one fails, Watch and Fix hands it back to the agent.'),
      beat(86.2, 'The agent pushes a fix and Watch and Fix keeps watching until the checks pass.'),
    ],
    camera: [
      camera(60.0, [0, 20, 1290, 860], [300, 48, 460, 575]),
      camera(61.9, PANEL, PANEL_COMPACT),
      camera(77.6, [700, 60, 590, 500], [880, 100, 410, 512]),
      camera(81.7, [300, 350, 594, 480], [300, 360, 460, 575]),
      camera(86.3, [700, 60, 590, 500], [880, 150, 410, 512]),
    ],
    hud: [
      shortcut(60.2, SHORTCUTS.closeSplit.keys, SHORTCUTS.closeSplit.label, 1.2),
      shortcut(61.6, SHORTCUTS.showSourceControl.keys, SHORTCUTS.showSourceControl.label, 1.3),
    ],
    pointer: [
      point(60.0, [1080, 420, 0, 0], 700),
      click(62.7, HANDLE_START, 700),
      point(63.3, HANDLE_END, 600),
      click(64.0, 'd-sc-stage-unstaged', 700),
      click(65.0, 'd-sc-ai', 600),
      click(68.3, 'd-sc-primary', 650),
      click(69.9, 'd-sc-primary', 300),
      click(71.8, 'd-rp-add', 700),
      click(72.5, 'd-add-menu-pr', 500),
      click(73.5, 'd-pr-ai', 700),
      click(76.6, 'd-pr-create', 700),
      click(80.8, 'd-pr-ask', 800),
      click(81.5, 'd-menu-watch-fix', 500),
      point(83.0, [620, 700, 0, 0], 900),
    ],
  },
  {
    // Close Split, Show Source Control, and the wider panel.
    states: [
      state(60.5, 'd-panes', 'merged'),
      state(61.9, 'd-rp', 'expanded'),
      state(62.7, 'd-rp-handle', 'drag'),
      state(63.35, 'd-rp-handle', ''),
    ],
    tweens: [{ node: 'd-rp', prop: 'panel-w', keys: [{ at: at(62.7), value: 280 }, { at: at(63.3), value: 380, ease: 'easeInOut' }] }],
  },
  {
    // Stage, generate the message, commit, publish.
    states: [
      state(64.0, 'd-sc-files', 'staged'),
      state(65.0, 'd-sc-ai', 'generating'),
      state(67.0, 'd-sc-ai', 'idle'),
      state(67.0, 'd-sc-message-box', 'filled'),
      state(67.0, 'd-sc-primary', 'commit'),
      state(68.3, 'd-sc-primary', 'busy'),
      state(68.9, 'd-sc-primary', 'publish'),
      state(68.9, 'd-sc-message-box', 'empty'),
      state(68.9, 'd-sc-files', 'clean'),
      state(69.9, 'd-sc-primary', 'busy'),
      state(70.9, 'd-sc-primary', 'fetch'),
    ],
    shows: [show(65.0, 'd-sc-generating', 100), hide(67.0, 'd-sc-generating', 100)],
    texts: [
      text(67.0, 'd-sc-message', SAMPLE.commitMessage),
      text(68.9, 'd-sc-message', ''),
      text(68.3, 'd-sc-branch-details', 'committing'),
      text(68.9, 'd-sc-branch-details', ''),
      text(68.9, 'd-sc-commit-count', '13'),
      text(69.9, 'd-sc-branch-details', 'pushing'),
      text(70.9, 'd-sc-branch-details', `origin/${SAMPLE.workspaces.webhooks.branch}`),
    ],
  },
  {
    // The Pull Request tool: generate, create, checks.
    shows: [
      show(71.8, 'd-add-menu', 100),
      hide(72.6, 'd-add-menu', 100),
      show(72.6, 'd-rp-chip-pr', 0),
      hide(72.6, 'd-tool-sc', 0),
      show(72.6, 'd-tool-pr', 0),
      show(73.5, 'd-pr-title-generating', 100),
      show(73.5, 'd-pr-generating', 100),
      hide(75.6, 'd-pr-title-generating', 100),
      hide(75.6, 'd-pr-generating', 100),
      hide(75.6, 'd-pr-description-hint', 0),
      hide(77.6, 'd-pr-form', 0),
      show(77.6, 'd-pr-summary', 0),
      show(77.6, 'd-row-webhooks-pr', 0),
      show(77.8, 'p-row-webhooks-pr', 0),
      show(79.0, 'd-pr-fix-failed', 0),
    ],
    states: [
      state(72.6, 'd-rp-chip-pr', 'active'),
      state(72.6, 'd-rp-chip-sc', 'idle'),
      state(73.5, 'd-pr-ai', 'generating'),
      state(75.6, 'd-pr-ai', 'idle'),
      state(76.6, 'd-pr-create', 'busy'),
      state(79.0, 'd-pr-checks', 'failing'),
      state(80.0, 'd-pr-checks', 'failed'),
      state(86.2, 'd-pr-checks', 'pending'),
      state(87.5, 'd-pr-checks', 'passed'),
    ],
    texts: [
      text(75.6, 'd-pr-title', SAMPLE.pullRequestTitle),
      text(75.6, 'd-pr-description', SAMPLE.pullRequestDescription),
    ],
  },
  {
    // Watch and Fix sends the failure to Claude.
    shows: [
      show(80.8, 'd-ask-menu', 100),
      hide(81.6, 'd-ask-menu', 100),
      show(81.6, 'd-pr-watching', 0),
      hide(81.6, 'd-pr-fix-failed', 0),
      show(81.6, 'd-row-webhooks-watch', 0),
      show(81.8, 'p-row-webhooks-watch', 0),
      show(81.9, 'claude-thinking', 0),
      hide(86.4, 'claude-thinking', 0),
      ...swap(81.9, 'd-tray-done-both', 'd-tray-working-done'),
      ...swap(82.0, 'p-tray-done-both', 'p-tray-working-done'),
      ...swap(86.4, 'd-tray-working-done', 'd-tray-done-both'),
      ...swap(86.5, 'p-tray-working-done', 'p-tray-done-both'),
    ],
    states: [
      state(81.6, 'd-pr-ask', 'watching'),
      state(81.9, 'd-chip-claude-dot', 'working'),
      state(81.9, 'd-run-claude-glyph', 'working'),
      state(82.0, 'p-row-webhooks-glyph', 'working'),
      state(86.4, 'd-chip-claude-dot', 'done'),
      state(86.4, 'd-run-claude-glyph', 'done'),
      state(86.5, 'p-row-webhooks-glyph', 'done'),
    ],
    texts: [
      text(82.9, 'd-run-claude-label', 'Bash: gh pr checks 128'),
      text(84.1, 'd-run-claude-label', 'Update: src/webhooks/retry.ts'),
      text(85.5, 'd-run-claude-label', 'Bash: git commit -am "fix: await the parked event write" && git push'),
      text(86.4, 'd-run-claude-label', 'Fixed the lint failure and pushed. The checks are running again.'),
    ],
    reveals: [{ node: 'claude-fix', start: at(81.8), step: [250, 900, 250, 250, 1100, 250, 250, 1200, 250, 250] }],
  },
]);
