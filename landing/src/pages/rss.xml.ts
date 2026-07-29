import rss from '@astrojs/rss';
import type { APIContext } from 'astro';
import { getPublishedBlogPosts } from '../lib/blog';

export async function GET(context: APIContext) {
  const posts = await getPublishedBlogPosts();

  return rss({
    title: 'Alera Blog',
    description:
      'Notes from the team building Alera, a native workbench for CLI coding agents.',
    site: context.site!,
    items: posts.map((post) => ({
      title: post.data.title,
      description: post.data.description,
      pubDate: post.data.pubDate,
      link: `/blog/${post.id}`,
    })),
  });
}
