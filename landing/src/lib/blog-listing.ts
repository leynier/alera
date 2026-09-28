import { BLOG_TAGS, type BlogTag } from './blog-tags';

/**
 * How posts are ordered and grouped on the blog index, the tag pages and the
 * post pager. Kept apart from `blog.ts`, which reads the content collection,
 * so the rules can be tested without Astro.
 */
export interface ListedPost {
  id: string;
  data: { pubDate: Date; featured: boolean; tags: readonly BlogTag[] };
}

/** Newest first; posts published at the same instant fall back to their id. */
export function newestFirst<T extends ListedPost>(posts: readonly T[]): T[] {
  return [...posts].sort((a, b) => b.data.pubDate.valueOf() - a.data.pubDate.valueOf() || a.id.localeCompare(b.id));
}

/** The post the index leads with: the newest one marked `featured`, else the newest. */
export function featuredPost<T extends ListedPost>(posts: readonly T[]): T | undefined {
  const ordered = newestFirst(posts);
  return ordered.find((post) => post.data.featured) ?? ordered[0];
}

/** Tags in use, in vocabulary order, with how many posts carry each. */
export function tagCounts(posts: readonly ListedPost[]): { tag: BlogTag; count: number }[] {
  return BLOG_TAGS.map((tag) => ({ tag, count: posts.filter((post) => post.data.tags.includes(tag)).length })).filter(
    ({ count }) => count > 0,
  );
}

/** The posts either side of `id` in reading order: newer above, older below. */
export function adjacentPosts<T extends ListedPost>(posts: readonly T[], id: string): { newer?: T; older?: T } {
  const ordered = newestFirst(posts);
  const index = ordered.findIndex((post) => post.id === id);
  if (index < 0) return {};
  return { newer: ordered[index - 1], older: ordered[index + 1] };
}
