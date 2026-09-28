import { describe, expect, test } from 'bun:test';
import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  DOC_PAGES,
  DOC_SECTIONS,
  adjacentDocs,
  docHref,
  docSectionTitle,
  navigationDrift,
} from './docs-navigation';

const docsDir = fileURLToPath(new URL('../content/docs/', import.meta.url));

describe('docs navigation', () => {
  test('lists every page exactly once', () => {
    const ids = DOC_PAGES.map((page) => page.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  test('matches the MDX files on disk', () => {
    const entryIds = readdirSync(docsDir)
      .filter((file) => file.endsWith('.mdx'))
      .map((file) => file.replace(/\.mdx$/, ''));
    expect(navigationDrift(entryIds)).toEqual([]);
  });

  test('starts with the getting started page at /docs', () => {
    expect(DOC_PAGES[0]?.id).toBe('index');
    expect(docHref('index')).toBe('/docs');
    expect(docHref('install')).toBe('/docs/install');
  });

  test('keeps sections non-empty with Title Case headers', () => {
    for (const section of DOC_SECTIONS) {
      expect(section.pages.length).toBeGreaterThan(0);
      for (const word of section.title.split(' ')) {
        expect(word[0]).toBe(word[0]?.toUpperCase());
      }
    }
  });

  test('walks neighbours in reading order', () => {
    expect(adjacentDocs('index')).toEqual({ previous: undefined, next: DOC_PAGES[1] });
    const last = DOC_PAGES[DOC_PAGES.length - 1]!;
    expect(adjacentDocs(last.id).next).toBeUndefined();
    expect(adjacentDocs('missing')).toEqual({});
  });

  test('names the section a page belongs to', () => {
    expect(docSectionTitle('install')).toBe('Start');
    expect(docSectionTitle('missing')).toBeUndefined();
  });

  test('reports drift in both directions', () => {
    const ids = DOC_PAGES.map((page) => page.id).filter((id) => id !== 'install');
    const problems = navigationDrift([...ids, 'orphan']);
    expect(problems).toHaveLength(2);
    expect(problems.join('\n')).toContain('install');
    expect(problems.join('\n')).toContain('orphan');
  });
});
