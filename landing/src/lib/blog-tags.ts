/**
 * The closed set of blog tags. A fixed vocabulary keeps tag pages worth
 * visiting: a typo in front matter fails the build instead of minting a tag
 * with one post.
 */
export const BLOG_TAGS = ['Agents', 'Mobile', 'Orchestration', 'Performance', 'Product', 'Review', 'Terminals', 'Worktrees'] as const;

export type BlogTag = (typeof BLOG_TAGS)[number];

/** One line under each tag page's title, in the same voice as the posts. */
export const TAG_DESCRIPTIONS: Record<BlogTag, string> = {
  Agents: 'Running CLI coding agents side by side: profiles, live states, and the hooks behind them.',
  Mobile: 'The Android companion: pairing, push, and answering an agent away from the desk.',
  Orchestration: 'Agents coordinating with each other: coordinators, task ownership, and decision gates.',
  Performance: 'Frame budgets, terminal throughput, and what the machine pays for every agent.',
  Product: 'Why Alera exists, what it bets on, and what it can do today.',
  Review: 'Source control, pull requests, and checks, next to the work that produced them.',
  Terminals: 'Real PTYs, sessions that outlive the window, and the runtime that owns them.',
  Worktrees: 'One Git worktree per task, and the setup that makes a new one ready to work in.',
};

export const tagSlug = (tag: BlogTag) => tag.toLowerCase();

export const tagHref = (tag: BlogTag) => `/blog/tags/${tagSlug(tag)}`;

export function tagFromSlug(slug: string): BlogTag | undefined {
  return BLOG_TAGS.find((tag) => tagSlug(tag) === slug);
}
