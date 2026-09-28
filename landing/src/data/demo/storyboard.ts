import type { Chapter, Storyboard } from '../../scripts/demo/timeline';
import { APP_COPY } from './app-copy';
import { PARALLEL_CHAPTER } from './storyboard-parallel';
import { PHONE_CHAPTER } from './storyboard-phone';
import { PROMPT_CHAPTER } from './storyboard-prompt';
import { REVIEW_CHAPTER } from './storyboard-review';
import { at, script, toasts } from './storyboard-keys';

/**
 * The whole product demo: four chapters on one clock. Chapter captions carry
 * the story when nothing inside a chapter replaces them; the transcript on
 * the page is built from the same text.
 */
const CHAPTERS: readonly Chapter[] = [
  {
    id: 'prompt',
    title: 'Start From A Prompt',
    caption: 'Describe a task once. Alera names the workspace, creates its Git worktree and starts the agent there.',
    start: 0,
    end: at(19),
    poster: at(15.5),
  },
  {
    id: 'parallel',
    title: 'Agents In Parallel',
    caption: 'Split the pane and start a second agent beside the first, in the same worktree.',
    start: at(19),
    end: at(40),
    poster: at(33.6),
  },
  {
    id: 'phone',
    title: 'Answer From Your Phone',
    caption: 'The paired Android phone gets the push. One tap opens the same terminal, live.',
    start: at(40),
    end: at(60),
    poster: at(44.4),
  },
  {
    id: 'review',
    title: 'Review And Ship',
    caption: 'Review the changes in Source Control, let AI Assist write the commit message, and publish the branch.',
    start: at(60),
    end: at(89),
    poster: at(82.5),
  },
];

// Toasts share three slots across chapters, so they are laid out in one pass.
const TOASTS = toasts([
  { at: 12.8, message: APP_COPY.workspaceCreated.text },
  { at: 64.1, message: APP_COPY.staged.text },
  { at: 67.0, message: APP_COPY.commitMessageGenerated.text },
  { at: 68.9, message: APP_COPY.committed.text },
  { at: 70.9, message: APP_COPY.branchPublished.text },
  { at: 75.6, message: APP_COPY.pullRequestDetailsGenerated.text },
]);

const SCRIPT = script([PROMPT_CHAPTER, PARALLEL_CHAPTER, PHONE_CHAPTER, REVIEW_CHAPTER, TOASTS]);

export const STORYBOARD: Storyboard = {
  duration: at(89),
  chapters: CHAPTERS,
  ...SCRIPT,
};
