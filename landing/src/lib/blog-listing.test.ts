import { describe, expect, test } from 'bun:test';
import { adjacentPosts, featuredPost, newestFirst, tagCounts, type ListedPost } from './blog-listing';
import { BLOG_TAGS, tagFromSlug, tagHref, tagSlug } from './blog-tags';

const post = (id: string, day: number, tags: ListedPost['data']['tags'], featured = false): ListedPost => ({
  id,
  data: { pubDate: new Date(Date.UTC(2026, 6, day)), featured, tags },
});

const posts = [
  post('old', 1, ['Product']),
  post('middle', 5, ['Agents', 'Terminals'], true),
  post('new', 9, ['Agents']),
  post('tie-b', 3, ['Worktrees']),
  post('tie-a', 3, ['Worktrees']),
];

describe('blog listing', () => {
  test('orders newest first and breaks ties by id', () => {
    expect(newestFirst(posts).map((entry) => entry.id)).toEqual(['new', 'middle', 'tie-a', 'tie-b', 'old']);
  });

  test('leads with the newest featured post, or the newest when none is featured', () => {
    expect(featuredPost(posts)?.id).toBe('middle');
    expect(featuredPost(posts.map((entry) => ({ ...entry, data: { ...entry.data, featured: false } })))?.id).toBe('new');
    expect(featuredPost([])).toBeUndefined();
  });

  test('counts only the tags in use, in vocabulary order', () => {
    expect(tagCounts(posts)).toEqual([
      { tag: 'Agents', count: 2 },
      { tag: 'Product', count: 1 },
      { tag: 'Terminals', count: 1 },
      { tag: 'Worktrees', count: 2 },
    ]);
  });

  test('pages to the newer and the older neighbour', () => {
    expect(adjacentPosts(posts, 'middle')).toEqual({ newer: posts[2], older: posts[4] });
    expect(adjacentPosts(posts, 'new').newer).toBeUndefined();
    expect(adjacentPosts(posts, 'old').older).toBeUndefined();
    expect(adjacentPosts(posts, 'missing')).toEqual({});
  });
});

describe('blog tags', () => {
  test('round-trip through their URL slug', () => {
    for (const tag of BLOG_TAGS) {
      expect(tagFromSlug(tagSlug(tag))).toBe(tag);
      expect(tagHref(tag)).toBe(`/blog/tags/${tagSlug(tag)}`);
    }
    expect(tagFromSlug('unknown')).toBeUndefined();
  });
});
