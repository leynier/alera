import { describe, expect, test } from 'bun:test';
import { codeLanguageLabel, frameCodeBlocks } from './code-block-frame';

describe('frameCodeBlocks', () => {
  test('frames highlighted blocks with a label and a copy button', () => {
    const block = '<pre class="astro-code alera-dark" data-language="bash"><code>brew install</code></pre>';
    const framed = frameCodeBlocks(`<p>Run:</p>${block}`);
    expect(framed).toContain('<div class="code-block" data-code-block>');
    expect(framed).toContain('<span class="code-block-language">Terminal</span>');
    expect(framed).toContain('<button type="button" class="code-block-copy" data-code-copy>Copy</button>');
    expect(framed).toContain(block);
    expect(framed.startsWith('<p>Run:</p>')).toBe(true);
  });

  test('frames every block independently', () => {
    const html = [
      '<pre class="astro-code" data-language="toml"><code>a = 1</code></pre>',
      '<pre class="astro-code" data-language="powershell"><code>scoop</code></pre>',
    ].join('');
    const framed = frameCodeBlocks(html);
    expect(framed.match(/data-code-block/g)).toHaveLength(2);
    expect(framed).toContain('>TOML<');
    expect(framed).toContain('>PowerShell<');
  });

  test('leaves plain pre elements alone', () => {
    const html = '<pre>ascii art</pre>';
    expect(frameCodeBlocks(html)).toBe(html);
  });
});

describe('codeLanguageLabel', () => {
  test('names shells as the terminal and falls back to the id', () => {
    expect(codeLanguageLabel('sh')).toBe('Terminal');
    expect(codeLanguageLabel(undefined)).toBe('Text');
    expect(codeLanguageLabel('kotlin')).toBe('KOTLIN');
  });
});
