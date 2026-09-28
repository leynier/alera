import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

const blog = defineCollection({
  loader: glob({ base: './src/content/blog', pattern: '**/*.md' }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    pubDate: z.coerce.date(),
    updatedDate: z.coerce.date().optional(),
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
