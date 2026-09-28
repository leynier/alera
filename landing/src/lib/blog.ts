import { getCollection, type CollectionEntry } from 'astro:content';
import { newestFirst } from './blog-listing';
import { readingMinutes } from './reading-time';

export type BlogPost = CollectionEntry<'blog'>;

/** Published posts in production, newest first; drafts stay visible in local/dev builds. */
export async function getPublishedBlogPosts(): Promise<BlogPost[]> {
  const posts = await getCollection('blog', ({ data }) => (import.meta.env.PROD ? data.draft !== true : true));
  return newestFirst(posts);
}

export const postHref = (post: BlogPost) => `/blog/${post.id}`;

/** "5 Min Read", from the post's Markdown source. */
export const readingTimeLabel = (post: BlogPost) => `${readingMinutes(post.body ?? '')} Min Read`;

export function formatBlogDate(date: Date): string {
  return date.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    timeZone: 'UTC',
  });
}
