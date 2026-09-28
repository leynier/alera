import { describe, expect, test } from 'bun:test';
import { readingMinutes } from './reading-time';

const words = (count: number) => Array.from({ length: count }, (_, index) => `word${index}`).join(' ');

describe('readingMinutes', () => {
  test('rounds to whole minutes and never says zero', () => {
    expect(readingMinutes('')).toBe(1);
    expect(readingMinutes(words(230))).toBe(1);
    expect(readingMinutes(words(690))).toBe(3);
  });

  test('ignores front matter, link targets and markup', () => {
    const body = `---\ntitle: ${words(500)}\n---\n${words(230)} [a link](https://example.com/${words(200).replaceAll(' ', '/')}) ## ** __`;
    expect(readingMinutes(body)).toBe(1);
  });

  test('counts code at half weight', () => {
    expect(readingMinutes(`${words(230)}\n\`\`\`ts\n${words(460)}\n\`\`\`\n`)).toBe(2);
  });
});
