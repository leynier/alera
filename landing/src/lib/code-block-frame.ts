/**
 * Wraps each highlighted code block in a frame with a language label and a
 * copy button. Done on the rendered HTML at build time, so the frame is part
 * of the first paint instead of being injected by a script after it.
 */
const LANGUAGE_LABELS: Record<string, string> = {
  bash: 'Terminal',
  sh: 'Terminal',
  shell: 'Terminal',
  zsh: 'Terminal',
  powershell: 'PowerShell',
  ps1: 'PowerShell',
  toml: 'TOML',
  json: 'JSON',
  jsonc: 'JSON',
  yaml: 'YAML',
  yml: 'YAML',
  ts: 'TypeScript',
  typescript: 'TypeScript',
  js: 'JavaScript',
  javascript: 'JavaScript',
  dart: 'Dart',
  rust: 'Rust',
  diff: 'Diff',
  plaintext: 'Text',
  text: 'Text',
  txt: 'Text',
};

const PRE_PATTERN = /<pre\b([^>]*\bclass="[^"]*\bastro-code\b[^"]*"[^>]*)>([\s\S]*?)<\/pre>/g;
const LANGUAGE_PATTERN = /\bdata-language="([^"]*)"/;

export function codeLanguageLabel(language: string | undefined): string {
  if (!language) return 'Text';
  return LANGUAGE_LABELS[language.toLowerCase()] ?? language.toUpperCase();
}

export function frameCodeBlocks(html: string): string {
  return html.replace(PRE_PATTERN, (match, attributes: string) => {
    const language = LANGUAGE_PATTERN.exec(attributes)?.[1];
    const label = codeLanguageLabel(language);
    return [
      `<div class="code-block" data-code-block>`,
      `<div class="code-block-bar" data-pagefind-ignore>`,
      `<span class="code-block-language">${label}</span>`,
      `<button type="button" class="code-block-copy" data-code-copy>Copy</button>`,
      `</div>`,
      match,
      `</div>`,
    ].join('');
  });
}
