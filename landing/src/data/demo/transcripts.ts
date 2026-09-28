import { SAMPLE } from './sample-workspace';
import type { Block, Line } from './terminal-lines';

/**
 * The staged agent sessions the demo's terminals show. They imitate what
 * Claude Code and Codex print in a real session, drawn only with glyphs the
 * bundled JetBrains Mono has (the fidelity tests check), so nothing falls back
 * to another font. Node ids are what the storyboard reveals or shows.
 */
const WORKTREE = `~/.alera/workspaces/storefront-4e1b7c9a-2d3f-4a8b-9c6e-0f5d2a7b3e81/${SAMPLE.workspaces.webhooks.slug}`;
const blank: Line = [''];

export const CLAUDE_SESSION: readonly Block[] = [
  {
    kind: 'claude-header',
    lines: [
      [{ text: ' ▐▛███▜▌ ', tone: 'claude' }, '  ', { text: 'Claude Code', tone: 'bold' }],
      [{ text: '▝▜█████▛▘', tone: 'claude' }, '  ', { text: WORKTREE, tone: 'dim' }],
      [{ text: '  ▘▘ ▝▝  ', tone: 'claude' }],
    ],
  },
  { lines: [blank] },
  {
    kind: 'plain',
    lines: [[{ text: `> ${SAMPLE.prompt}`, tone: 'claude-prompt' }], blank],
  },
  {
    node: 'claude-work',
    lines: [
      ['● ', "I'll read the webhook handler and the retry queue first."],
      blank,
      [{ text: '● ', tone: 'green' }, { text: 'Read', tone: 'bold' }, '(src/webhooks/handler.ts)'],
      [{ text: '  └ ', tone: 'dim' }, { text: 'Read 142 lines', tone: 'dim' }],
      blank,
      [{ text: '● ', tone: 'green' }, { text: 'Search', tone: 'bold' }, '(pattern: "deliverWebhook", path: "src")'],
      [{ text: '  └ ', tone: 'dim' }, { text: 'Found 3 files', tone: 'dim' }],
      blank,
      [{ text: '● ', tone: 'green' }, { text: 'Update', tone: 'bold' }, '(src/webhooks/retry.ts)'],
      [{ text: '  └ ', tone: 'dim' }, { text: 'Updated src/webhooks/retry.ts with 31 additions and 6 removals', tone: 'dim' }],
      [{ text: '     24 ', tone: 'dim' }, { text: '-    await sleep(1000);', tone: 'diff-del' }],
      [{ text: '     24 ', tone: 'dim' }, { text: '+    const delay = Math.min(baseMs * 2 ** attempt, maxMs);', tone: 'diff-add' }],
      [{ text: '     25 ', tone: 'dim' }, { text: '+    await sleep(delay + jitter(delay));', tone: 'diff-add' }],
      blank,
      [{ text: '● ', tone: 'green' }, { text: 'Write', tone: 'bold' }, '(src/webhooks/retry.test.ts)'],
      [{ text: '  └ ', tone: 'dim' }, { text: 'Wrote 58 lines to src/webhooks/retry.test.ts', tone: 'dim' }],
      blank,
    ],
  },
  {
    node: 'claude-permission',
    concealed: true,
    kind: 'claude-permission',
    lines: [
      [{ text: 'Bash command', tone: 'bold' }],
      blank,
      ['  bun test src/webhooks'],
      [{ text: '  Run the webhook tests', tone: 'dim' }],
      blank,
      ['Do you want to proceed?'],
      [{ text: '❯ 1. Yes', tone: 'claude' }],
      ['  2. Yes, and don\'t ask again for bun test commands in this project'],
      ['  3. No, and tell Claude what to do differently (esc)'],
    ],
  },
  {
    node: 'claude-tests',
    lines: [
      [{ text: '● ', tone: 'green' }, { text: 'Bash', tone: 'bold' }, '(bun test src/webhooks)'],
      [{ text: '  └ ', tone: 'dim' }, { text: ' 17 pass', tone: 'green' }],
      [{ text: '     0 fail', tone: 'dim' }],
      [{ text: '    Ran 17 tests across 3 files. [412.00ms]', tone: 'dim' }],
      blank,
      ['● ', 'All webhook tests pass. Failed deliveries now retry with'],
      ['  exponential backoff and jitter: 1s base, capped at 60s,'],
      ['  up to 6 attempts before the event is parked for review.'],
      blank,
    ],
  },
  {
    node: 'claude-fix',
    lines: [
      [{ text: `> Pull request #${SAMPLE.pullRequest} checks failed. Please fix them.`, tone: 'claude-prompt' }],
      blank,
      [{ text: '● ', tone: 'green' }, { text: 'Bash', tone: 'bold' }, '(gh pr checks 128)'],
      [{ text: '  └ ', tone: 'dim' }, { text: 'lint  fail  src/webhooks/retry.ts:31 no-floating-promises', tone: 'dim' }],
      blank,
      [{ text: '● ', tone: 'green' }, { text: 'Update', tone: 'bold' }, '(src/webhooks/retry.ts)'],
      [{ text: '  └ ', tone: 'dim' }, { text: 'Updated src/webhooks/retry.ts with 1 addition and 1 removal', tone: 'dim' }],
      blank,
      [{ text: '● ', tone: 'green' }, { text: 'Bash', tone: 'bold' }, '(git commit -am "fix: await the parked event write" && git push)'],
      [{ text: '  └ ', tone: 'dim' }, { text: 'feat/webhook-retry-backoff -> feat/webhook-retry-backoff', tone: 'dim' }],
      blank,
    ],
  },
  {
    node: 'claude-thinking',
    concealed: true,
    lines: [[{ text: '✶ Weaving… ', tone: 'claude' }, { text: '(esc to interrupt)', tone: 'dim' }], blank],
  },
  {
    kind: 'claude-input',
    lines: [['> ']],
  },
  {
    lines: [[{ text: '  ? for shortcuts', tone: 'dim' }]],
  },
];

/** The shell in the new split, where the user types the Codex command. */
export const CODEX_SHELL: readonly Block[] = [
  {
    lines: [
      [
        `${SAMPLE.user}@${SAMPLE.host} ${SAMPLE.workspaces.webhooks.slug} % `,
        { text: '', node: 'codex-command' },
      ],
    ],
  },
];

/** Codex's own screen, shown below the shell line once the command runs. */
export const CODEX_UI: readonly Block[] = [
  {
    kind: 'codex-header',
    lines: [
      [{ text: '>_ ', tone: 'dim' }, { text: 'OpenAI Codex', tone: 'bold' }],
      blank,
      [{ text: 'directory: ', tone: 'dim' }, WORKTREE],
    ],
  },
  { lines: [blank] },
  {
    lines: [[{ text: `› ${SAMPLE.codexPrompt}`, tone: 'codex-prompt' }], blank],
  },
  {
    node: 'codex-work',
    lines: [
      ['• ', 'I\'ll add a test that sends the same event twice and'],
      ['  checks that only one charge is recorded.'],
      blank,
      [{ text: '• ', tone: 'green' }, { text: 'Explored', tone: 'bold' }],
      [{ text: '  └ ', tone: 'dim' }, 'Read handler.ts, idempotency.ts'],
      ['    Search deliveryId in src/webhooks'],
      blank,
      [{ text: '• ', tone: 'green' }, { text: 'Edited', tone: 'bold' }, ' src/webhooks/handler.test.ts ', { text: '(+28 -0)', tone: 'dim' }],
      blank,
      [{ text: '• ', tone: 'green' }, { text: 'Ran', tone: 'bold' }, ' bun test src/webhooks/handler.test.ts'],
      [{ text: '  └ ', tone: 'dim' }, { text: '4 pass, 0 fail', tone: 'dim' }],
      blank,
      [{ text: '─ Worked for 1m 12s ─────────────────────', tone: 'dim' }],
      blank,
      ['• ', 'Added a regression test: a second delivery with the'],
      ['  same event id is acknowledged without charging again.'],
      blank,
    ],
  },
  {
    node: 'codex-status',
    lines: [[{ text: '• ', tone: 'dim' }, { text: 'Working', tone: 'bold' }, { text: ' (esc to interrupt)', tone: 'dim' }], blank],
  },
  {
    kind: 'codex-composer',
    lines: [[{ text: '› ', tone: 'bold' }, { text: 'Ask Codex to do anything', tone: 'dim' }]],
  },
  {
    lines: [[{ text: '  ⏎ send   ⌃J newline   ⌃T transcript   ⌃C quit', tone: 'dim' }]],
  },
];
