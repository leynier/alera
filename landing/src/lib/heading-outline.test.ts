import { describe, expect, test } from 'bun:test';
import { markupText, outlineHtml, slugify } from './heading-outline';

describe('outlineHtml', () => {
  test('keeps ids the Markdown pipeline assigned and links each heading to itself', () => {
    const { html, headings } = outlineHtml('<h2 id="linux">Linux</h2><p>Body</p><h3 id="tarball">Tarball</h3>');
    expect(headings).toEqual([
      { id: 'linux', depth: 2, text: 'Linux', html: 'Linux' },
      { id: 'tarball', depth: 3, text: 'Tarball', html: 'Tarball' },
    ]);
    expect(html).toContain('<h2 id="linux">Linux<a class="heading-anchor" href="#linux"');
    expect(html).toContain('<p>Body</p>');
  });

  test('ignores h1 and h4 so the outline stays two levels deep', () => {
    const { headings } = outlineHtml('<h1 id="a">A</h1><h4 id="b">B</h4><h2 id="c">C</h2>');
    expect(headings.map((heading) => heading.id)).toEqual(['c']);
  });

  test('derives a unique id when a heading has none', () => {
    const { html, headings } = outlineHtml('<h2 id="setup">Taken</h2><h2>Setup</h2><h2>Setup</h2>');
    expect(headings.map((heading) => heading.id)).toEqual(['setup', 'setup-1', 'setup-2']);
    expect(html).toContain('<h2 id="setup-1">Setup');
  });

  test('keeps inline code in the display markup but not in the text', () => {
    const { headings } = outlineHtml('<h2 id="toml">The <code>alera.toml</code> file</h2>');
    expect(headings[0]?.html).toBe('The <code>alera.toml</code> file');
    expect(headings[0]?.text).toBe('The alera.toml file');
  });

  test('leaves pages without headings untouched', () => {
    const source = '<p>No headings here.</p>';
    expect(outlineHtml(source)).toEqual({ html: source, headings: [] });
  });
});

describe('markupText', () => {
  test('strips nested tags and decodes entities', () => {
    expect(markupText('Fish &amp; <b>chips</b> &#x27;n&#39; &lt;tags&gt;')).toBe("Fish & chips 'n' <tags>");
    expect(markupText('<<b>b>still text')).toBe('bstill text');
  });
});

describe('slugify', () => {
  test('matches the shape Markdown heading ids use', () => {
    expect(slugify('Projects And Workspaces')).toBe('projects-and-workspaces');
    expect(slugify('What is "alera.toml"?')).toBe('what-is-aleratoml');
    expect(slugify('Déjà vu')).toBe('deja-vu');
    expect(slugify('!!!')).toBe('section');
  });
});
