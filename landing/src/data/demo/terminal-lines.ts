/**
 * Terminal content as data. A line is a list of spans; a span is plain text
 * or text with tones. Tones name the terminal's ANSI roles (`red`, `dim`) or a
 * true color an agent CLI uses on its own (`claude` is Claude Code's orange),
 * and src/styles/demo/terminal.css paints them with the app's Alera Dark
 * terminal theme.
 */
export type Tone =
  | 'bold'
  | 'dim'
  | 'italic'
  | 'inverse'
  | 'cursor'
  | 'black'
  | 'red'
  | 'green'
  | 'yellow'
  | 'blue'
  | 'magenta'
  | 'cyan'
  | 'white'
  | 'bright-black'
  | 'claude'
  | 'claude-prompt'
  | 'diff-add'
  | 'diff-del'
  | 'codex-prompt';

/** `node` makes the span a storyboard target, such as a command being typed. */
export type Span = string | { text: string; tone?: Tone | readonly Tone[]; node?: string };
export type Line = readonly Span[];

/** A run of lines the storyboard can reveal one by one or show and hide as a unit. */
export interface Block {
  node?: string;
  lines: readonly Line[];
  /** Starts hidden; the storyboard shows it. */
  concealed?: boolean;
  /** Block-element art drawn beside the lines, such as Claude Code's mascot. */
  art?: readonly string[];
  /** Extra class for block-level chrome such as a permission prompt. */
  kind?: 'plain' | 'claude-input' | 'claude-permission' | 'codex-header' | 'codex-composer' | 'claude-header';
}

export function spanText(span: Span): string {
  return typeof span === 'string' ? span : span.text;
}

export function lineText(line: Line): string {
  return line.map(spanText).join('');
}

export function spanTones(span: Span): readonly Tone[] {
  if (typeof span === 'string' || span.tone === undefined) return [];
  return typeof span.tone === 'string' ? [span.tone] : span.tone;
}
