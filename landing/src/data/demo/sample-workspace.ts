/**
 * The staged project the demo works in. Everything here is sample data and
 * the page says so; names follow the rules the app applies to real ones
 * (a generated workspace name is 2 to 6 words in title case and its branch
 * starts with `feat/`, see ai_assist_workspace_identity.rs).
 */
export const SAMPLE = {
  host: 'Studio',
  phone: 'Pixel 7a',
  project: 'storefront',
  user: 'dev',
  sourceBranch: 'main',
  pullRequest: 128,
  prompt: 'Retry failed payment webhooks with exponential backoff and add tests',
  codexPrompt: 'add a regression test for duplicate webhook deliveries',
  workspaces: {
    main: { name: 'storefront', branch: 'main' },
    releaseNotes: { name: 'Release Notes', branch: 'docs/release-notes' },
    searchPagination: { name: 'Search Pagination', branch: 'feat/search-pagination' },
    webhooks: { name: 'Webhook Retry Backoff', branch: 'feat/webhook-retry-backoff', slug: 'webhook-retry-backoff' },
  },
  commitMessage:
    'feat: retry failed payment webhooks with backoff\n\nRetry failed deliveries with exponential backoff and jitter, park events after the last attempt, and cover duplicate deliveries with a regression test.',
  pullRequestTitle: 'Retry failed payment webhooks with exponential backoff',
  pullRequestDescription:
    '## Summary\n- Retry failed payment webhook deliveries with exponential backoff and jitter\n- Park an event for review after six failed attempts\n- Add a regression test for duplicate deliveries\n\n## Testing\n- bun test src/webhooks',
} as const;
