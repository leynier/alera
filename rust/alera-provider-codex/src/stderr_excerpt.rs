//! A Codex exit error that quotes the line explaining it, as T3 Code's
//! stderr excerpt: the last error-looking line of the stderr tail, else its
//! last line, without terminal controls and at most 512 characters.

use alera_agent_transport::{JsonLineProcess, JsonTransport, TransportError};
use async_trait::async_trait;
use serde_json::Value;

const EXCERPT_MAX_CHARS: usize = 512;

/// The Codex app-server process, whose exit error names its stderr line.
pub struct CodexProcess(pub(crate) JsonLineProcess);

#[async_trait]
impl JsonTransport for CodexProcess {
    async fn send(&mut self, message: Value) -> Result<(), TransportError> {
        self.0.send(message).await.map_err(excerpted)
    }

    async fn recv(&mut self) -> Result<Option<Value>, TransportError> {
        self.0.recv().await.map_err(excerpted)
    }

    async fn close(&mut self) -> Result<(), TransportError> {
        self.0.close().await.map_err(excerpted)
    }
}

fn excerpted(error: TransportError) -> TransportError {
    match error {
        TransportError::ProcessExited { code, stderr } => TransportError::ProcessExited {
            code,
            stderr: stderr_excerpt(&stderr).unwrap_or_default(),
        },
        other => other,
    }
}

/// The line of [tail] that explains the exit, or None when it has none.
pub(crate) fn stderr_excerpt(tail: &str) -> Option<String> {
    let text = strip_controls(tail);
    let lines = text
        .split('\n')
        .map(|line| line.split_whitespace().collect::<Vec<_>>().join(" "))
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>();
    let line = lines
        .iter()
        .rev()
        .find(|line| is_error_line(line))
        .or_else(|| lines.last())?;
    Some(if line.chars().count() > EXCERPT_MAX_CHARS {
        let mut clipped = line.chars().take(EXCERPT_MAX_CHARS - 1).collect::<String>();
        clipped.push('…');
        clipped
    } else {
        line.clone()
    })
}

/// `Error: …`, `TypeError [CODE]: …`, `fatal: …`, or a tracing line whose
/// first or second word is `ERROR`.
fn is_error_line(line: &str) -> bool {
    let words = line.split(' ').take(2).collect::<Vec<_>>();
    if words.contains(&"ERROR") {
        return true;
    }
    let word_len = line.bytes().take_while(u8::is_ascii_alphabetic).count();
    let word = line[..word_len].to_ascii_lowercase();
    if word_len == 0 || !(word.ends_with("error") || word == "fatal") {
        return false;
    }
    let mut rest = &line[word_len..];
    if let Some(code) = rest.strip_prefix(" [").or_else(|| rest.strip_prefix('[')) {
        let Some(end) = code.find(']') else {
            return false;
        };
        rest = &code[end + 1..];
    }
    rest.strip_prefix(':')
        .is_some_and(|message| !message.trim_start().is_empty())
}

/// Drops CSI and OSC sequences and other control characters, keeping
/// newlines, carriage returns and tabs.
fn strip_controls(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        let csi = match c {
            '\u{1b}' => match chars.peek() {
                Some('[') => {
                    chars.next();
                    true
                }
                Some(']') => {
                    chars.next();
                    skip_osc(&mut chars);
                    continue;
                }
                _ => {
                    chars.next();
                    continue;
                }
            },
            '\u{9b}' => true,
            '\u{9d}' => {
                skip_osc(&mut chars);
                continue;
            }
            '\n' | '\r' | '\t' => {
                out.push(c);
                continue;
            }
            c if c.is_control() => continue,
            c => {
                out.push(c);
                continue;
            }
        };
        if csi {
            for c in chars.by_ref() {
                if ('\u{40}'..='\u{7e}').contains(&c) {
                    break;
                }
            }
        }
    }
    out
}

fn skip_osc(chars: &mut std::iter::Peekable<std::str::Chars<'_>>) {
    while let Some(c) = chars.next() {
        if c == '\u{7}' || c == '\u{9c}' || (c == '\u{1b}' && chars.next_if_eq(&'\\').is_some()) {
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::stderr_excerpt as excerpt;

    #[test]
    fn the_error_line_explains_the_exit() {
        let node = "node:internal/modules/cjs/loader:1228\n  throw err;\n  ^\n\nError: Missing optional dependency @openai/codex-darwin-arm64. Reinstall Codex: npm install -g @openai/codex@latest\n    at Object.<anonymous> (/usr/lib/node_modules/@openai/codex/bin/codex.js:70:11)\n\nNode.js v22.0.0\n";
        assert_eq!(
            excerpt(node).as_deref(),
            Some("Error: Missing optional dependency @openai/codex-darwin-arm64. Reinstall Codex: npm install -g @openai/codex@latest")
        );
        assert_eq!(
            excerpt("x\nError [ERR_MODULE_NOT_FOUND]: Cannot find package 'x'\n    at y\n")
                .as_deref(),
            Some("Error [ERR_MODULE_NOT_FOUND]: Cannot find package 'x'")
        );
        assert_eq!(
            excerpt("error: unexpected argument 'app-server' found\n\nUsage: codex [OPTIONS]\n")
                .as_deref(),
            Some("error: unexpected argument 'app-server' found")
        );
        assert_eq!(
            excerpt("ERROR: Missing dependency\n").as_deref(),
            Some("ERROR: Missing dependency")
        );
        assert_eq!(
            excerpt("WARNING: proxy ignored\nMissing OpenAI API key.\n").as_deref(),
            Some("Missing OpenAI API key.")
        );
        assert_eq!(
            excerpt("2026-10-31T10:00:00Z ERROR codex_core: failed to load config\n2026-10-31T10:00:01Z WARN later\n").as_deref(),
            Some("2026-10-31T10:00:00Z ERROR codex_core: failed to load config")
        );
    }

    #[test]
    fn terminal_controls_and_long_lines_are_cleaned() {
        assert_eq!(
            excerpt("\u{1b}[31mError:\u{1b}[0m config.toml\tis invalid\r\n").as_deref(),
            Some("Error: config.toml is invalid")
        );
        assert_eq!(
            excerpt("\u{9b}31mError: invalid config\u{9b}0m").as_deref(),
            Some("Error: invalid config")
        );
        let long = excerpt(&format!("Error: {}", "x".repeat(600))).unwrap();
        assert_eq!(long.chars().count(), 512);
        assert!(long.ends_with('…'));
        assert_eq!(excerpt(" \n\u{1b}[0m\n"), None);
    }
}
