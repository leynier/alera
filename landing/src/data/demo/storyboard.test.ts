import { describe, expect, test } from 'bun:test';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { compileStoryboard } from '../../scripts/demo/timeline';
import { STORYBOARD } from './storyboard';
import * as transcripts from './transcripts';

const timeline = compileStoryboard(STORYBOARD);

function sources(directory: URL): string {
  return readdirSync(fileURLToPath(directory), { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile() && /\.(astro|ts)$/.test(entry.name))
    .map((entry) => readFileSync(join(entry.parentPath, entry.name), 'utf8'))
    .join('\n');
}

describe('storyboard', () => {
  test('covers the whole clock with its chapters, in order', () => {
    const chapters = timeline.chapters;
    expect(chapters[0]!.start).toBe(0);
    expect(chapters.at(-1)!.end).toBe(timeline.duration);
    chapters.slice(1).forEach((chapter, index) => expect(chapter.start).toBe(chapters[index]!.end));
  });

  test('only touches nodes the scene declares', () => {
    const components = sources(new URL('../../components/demo/', import.meta.url));
    const blockNodes = Object.values(transcripts)
      .filter(Array.isArray)
      .flat()
      .flatMap((block) => [
        block.node,
        ...block.lines.flatMap((line: readonly unknown[]) =>
          line.map((span) => (typeof span === 'object' && span !== null && 'node' in span ? (span as { node?: string }).node : undefined)),
        ),
      ])
      .filter(Boolean);
    const declared = new Set(
      [
        ...components.matchAll(/['"`]((?:d|p)-[a-z0-9-]+)['"`]/g),
        ...components.matchAll(/data-demo-node="([a-z0-9-]+)"/g),
      ].map((match) => match[1]!),
    );
    for (const node of blockNodes) declared.add(node!);
    const missing = [...timeline.nodes].filter((node) => !declared.has(node));
    expect(missing).toEqual([]);
  });

  test('reveals every line of a terminal block, one step per line after the first', () => {
    const blocks = new Map(
      (Object.values(transcripts).filter(Array.isArray).flat() as { node?: string; lines: readonly unknown[] }[])
        .filter((block) => block.node)
        .map((block) => [block.node!, block.lines.length]),
    );
    for (const run of STORYBOARD.reveals ?? []) {
      if (!Array.isArray(run.step) || !blocks.has(run.node)) continue;
      expect({ node: run.node, steps: run.step.length + 1 }).toEqual({ node: run.node, steps: blocks.get(run.node)! });
    }
  });

  test('never writes an em dash', () => {
    const board = JSON.stringify(STORYBOARD);
    expect(board.includes('\u2014')).toBe(false);
  });
});
