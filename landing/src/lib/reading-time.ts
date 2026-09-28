/**
 * Minutes to read a Markdown body at 230 words per minute, the usual figure
 * for technical prose. Code blocks count at half weight, since readers skim
 * them, and front matter, markup and URLs are not words.
 */
const WORDS_PER_MINUTE = 230;

export function readingMinutes(markdown: string): number {
  const body = markdown.replace(/^---\n[\s\S]*?\n---\n/, '');
  let codeWords = 0;
  const prose = body.replace(/```[\s\S]*?```/g, (block) => {
    codeWords += countWords(block.replace(/^```.*$/gm, ''));
    return ' ';
  });
  const text = prose
    .replace(/!\[[^\]]*\]\([^)]*\)/g, ' ')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/<[^>]+>/g, ' ')
    .replace(/[#>*_`|~-]+/g, ' ');
  const words = countWords(text) + codeWords / 2;
  return Math.max(1, Math.round(words / WORDS_PER_MINUTE));
}

function countWords(text: string): number {
  return text.split(/\s+/).filter((word) => /[\p{L}\p{N}]/u.test(word)).length;
}
