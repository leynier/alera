import { defineCollection, reference } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';
import { BLOG_TAGS } from './lib/blog-tags';

// A correction to a published post keeps its date and URL: the post gains an
// `updatedDate` and a dated note in the body instead of being rewritten.
const blog = defineCollection({
  loader: glob({ base: './src/content/blog', pattern: '**/*.{md,mdx}' }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    pubDate: z.coerce.date(),
    updatedDate: z.coerce.date().optional(),
    tags: z.array(z.enum(BLOG_TAGS)).min(1).max(3),
    featured: z.boolean().default(false),
    relatedDocs: z.array(reference('docs')).max(3).default([]),
    draft: z.boolean().default(false),
  }),
});

// Docs are flat MDX files; `index.mdx` is served at /docs and every other
// entry at /docs/<id>. Reading order and grouping live in
// `src/lib/docs-navigation.ts`, not in frontmatter.
const docs = defineCollection({
  loader: glob({ base: './src/content/docs', pattern: '*.mdx' }),
  schema: z.object({
    title: z.string(),
    description: z.string().max(200),
    updatedDate: z.coerce.date().optional(),
  }),
});

export const collections = { blog, docs };
