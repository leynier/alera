//! Safe delivery of orchestration prompts into agent terminals.
//!
//! Multiline preambles and banners with control characters corrupt interactive
//! shells when typed as raw keystrokes: readline/zle treat embedded LFs as
//! accept-line, and ESC sequences can reconfigure the TUI. Wrap the payload in
//! bracketed-paste markers, render terminal controls as inert text, and let the
//! caller fire a deferred Enter after the paste is rendered.

/// Bracketed paste start (DECSET 2004 content).
pub const BRACKETED_PASTE_START: &[u8] = b"\x1b[200~";
/// Bracketed paste end.
pub const BRACKETED_PASTE_END: &[u8] = b"\x1b[201~";
/// Submit after paste (carriage return, not LF).
pub const AGENT_PROMPT_SUBMIT: &[u8] = b"\r";

/// Max bytes per PTY write so large preambles do not monopolize the writer.
pub const TERMINAL_INPUT_CHUNK_MAX_BYTES: usize = 16 * 1024;

/// Preserve printable text, LF, and tab while rendering terminal controls as
/// inert ASCII markers.
pub fn sanitize_agent_prompt_text(text: &str) -> String {
    let mut sanitized = String::with_capacity(text.len());
    for character in text.chars() {
        let code_point = character as u32;
        if matches!(character, '\n' | '\t') {
            sanitized.push(character);
        } else if code_point <= 0x1f || code_point == 0x7f {
            sanitized.push_str(&format!("<0x{code_point:02X}>"));
        } else {
            sanitized.push(character);
        }
    }
    sanitized
}

/// Build bracketed-paste payload for an agent prompt (no trailing submit).
pub fn build_agent_prompt_paste_bytes(prompt: &str) -> Vec<u8> {
    let sanitized = sanitize_agent_prompt_text(prompt);
    let mut bytes = Vec::with_capacity(
        BRACKETED_PASTE_START.len() + sanitized.len() + BRACKETED_PASTE_END.len(),
    );
    bytes.extend_from_slice(BRACKETED_PASTE_START);
    bytes.extend_from_slice(sanitized.as_bytes());
    bytes.extend_from_slice(BRACKETED_PASTE_END);
    bytes
}

/// Split bytes into write-sized chunks (last chunk may be shorter).
pub fn iterate_terminal_input_chunks(
    bytes: &[u8],
    max_chunk_bytes: usize,
) -> impl Iterator<Item = &[u8]> {
    let max = max_chunk_bytes.max(1);
    (0..bytes.len().div_ceil(max)).map(move |i| {
        let start = i * max;
        let end = (start + max).min(bytes.len());
        &bytes[start..end]
    })
}

/// Write a sanitized bracketed-paste prompt to a PTY session in chunks.
pub fn write_agent_prompt_paste(
    session: &mut crate::terminal_host::session::Session,
    prompt: &str,
) {
    let paste = build_agent_prompt_paste_bytes(prompt);
    for chunk in iterate_terminal_input_chunks(&paste, TERMINAL_INPUT_CHUNK_MAX_BYTES) {
        session.write(chunk);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitizer_preserves_text_and_supported_whitespace() {
        assert_eq!(
            sanitize_agent_prompt_text("plain λ\n\ttext"),
            "plain λ\n\ttext"
        );
    }

    #[test]
    fn sanitizer_renders_every_unsafe_terminal_control() {
        for code_point in (0u8..=0x1f).chain(std::iter::once(0x7f)) {
            let input = String::from_utf8(vec![b'a', code_point, b'b']).unwrap();
            let sanitized = sanitize_agent_prompt_text(&input);
            if matches!(code_point, b'\n' | b'\t') {
                assert_eq!(sanitized.as_bytes(), input.as_bytes());
            } else {
                assert_eq!(sanitized, format!("a<0x{code_point:02X}>b"));
            }
        }
    }

    #[test]
    fn paste_wraps_sanitized_prompt() {
        let paste = build_agent_prompt_paste_bytes("hello\nworld");
        assert!(paste.starts_with(BRACKETED_PASTE_START));
        assert!(paste.ends_with(BRACKETED_PASTE_END));
        let inner = &paste[BRACKETED_PASTE_START.len()..paste.len() - BRACKETED_PASTE_END.len()];
        assert_eq!(inner, b"hello\nworld");
    }

    #[test]
    fn paste_sanitizes_esc_inside() {
        let paste = build_agent_prompt_paste_bytes("x\x1by");
        let as_str = String::from_utf8_lossy(&paste);
        assert!(as_str.contains("<0x1B>"));
        let inner = &paste[BRACKETED_PASTE_START.len()..paste.len() - BRACKETED_PASTE_END.len()];
        assert!(!inner.contains(&0x1b));
    }

    #[test]
    fn chunks_split_large_payloads() {
        let data = vec![b'a'; 40];
        let chunks: Vec<&[u8]> = iterate_terminal_input_chunks(&data, 16).collect();
        assert_eq!(chunks.len(), 3);
        assert_eq!(chunks[0].len(), 16);
        assert_eq!(chunks[1].len(), 16);
        assert_eq!(chunks[2].len(), 8);
    }

    #[test]
    fn empty_input_yields_no_chunks() {
        assert_eq!(iterate_terminal_input_chunks(b"", 16).count(), 0);
    }
}
