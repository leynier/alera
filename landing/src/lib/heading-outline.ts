/**
 * Reads the outline of a rendered page back out of its h2/h3 elements and
 * gives each one a self-link. The docs and the blog share it, so "On This
 * Page" always lists the headings the reader actually sees, whichever
 * Markdown pipeline produced them.
 */
export interface OutlineHeading {
  id: string;
  depth: 2 | 3;
  /** Plain text, for labels and matching. */
  text: string;
  /** Inner markup (inline code kept), for display in the outline. */
  html: string;
}

const HEADING_PATTERN = /<h([23])(\s[^>]*)?>([\s\S]*?)<\/h\1>/gi;
const ID_PATTERN = /\sid\s*=\s*"([^"]*)"/i;

const NAMED_ENTITIES: Record<string, string> = {
  amp: '&',
  lt: '<',
  gt: '>',
  quot: '"',
  apos: "'",
  nbsp: ' ',
};

function decodeEntities(value: string): string {
  return value.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (match, body: string) => {
    if (body[0] === '#') {
      const code = body[1]?.toLowerCase() === 'x' ? Number.parseInt(body.slice(2), 16) : Number(body.slice(1));
      return Number.isFinite(code) ? String.fromCodePoint(code) : match;
    }
    return NAMED_ENTITIES[body.toLowerCase()] ?? match;
  });
}

/** Text content of a fragment of markup; never inserted back as HTML. */
export function markupText(markup: string): string {
  let text = markup;
  let previous: string;
  do {
    previous = text;
    text = text.replace(/<[^>]*>/g, '');
  } while (text !== previous);
  return decodeEntities(text.replace(/[<>]/g, '')).replace(/\s+/g, ' ').trim();
}

export function slugify(text: string): string {
  const slug = text
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .trim()
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-');
  return slug || 'section';
}

function selfLink(id: string): string {
  return `<a class="heading-anchor" href="#${id}" aria-label="Link To This Section" data-pagefind-ignore>#</a>`;
}

export function outlineHtml(source: string): { html: string; headings: OutlineHeading[] } {
  const taken = new Set<string>();
  for (const match of source.matchAll(HEADING_PATTERN)) {
    const id = ID_PATTERN.exec(match[2] ?? '')?.[1];
    if (id) taken.add(id);
  }

  const headings: OutlineHeading[] = [];
  const html = source.replace(HEADING_PATTERN, (_match, level: string, attributes = '', inner: string) => {
    let id = ID_PATTERN.exec(attributes)?.[1];
    let nextAttributes = attributes;
    if (!id) {
      const base = slugify(markupText(inner));
      id = base;
      for (let n = 1; taken.has(id); n += 1) id = `${base}-${n}`;
      taken.add(id);
      nextAttributes = ` id="${id}"${attributes}`;
    }
    headings.push({ id, depth: level === '2' ? 2 : 3, text: markupText(inner), html: inner.trim() });
    return `<h${level}${nextAttributes}>${inner}${selfLink(id)}</h${level}>`;
  });

  return { html, headings };
}
