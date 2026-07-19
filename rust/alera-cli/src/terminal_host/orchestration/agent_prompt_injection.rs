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

/// Interactive shells known to enable bracketed paste for their line editor.
pub fn shell_supports_bracketed_paste(shell: &str) -> bool {
    let executable = shell
        .replace('\\', "/")
        .rsplit('/')
        .next()
        .unwrap_or_default()
        .to_ascii_lowercase();
    matches!(executable.as_str(), "bash" | "zsh" | "fish")
}

/// Multiline, control-heavy, and long startup commands need paste delivery.
pub fn should_use_bracketed_paste_for_startup(command: &str) -> bool {
    command
        .chars()
        .any(|character| (character as u32) < 0x20 || character as u32 == 0x7f)
        || command.len() > 512
}

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

/// Build shell-neutral startup input without executable terminal controls.
pub fn build_plain_startup_command_bytes(command: &str) -> Vec<u8> {
    let single_line = sanitize_agent_prompt_text(command)
        .replace('\n', "<LF>")
        .replace('\t', "<TAB>");
    format!("{single_line}\r").into_bytes()
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
    fn startup_delivery_matches_shell_capabilities_and_sanitizes_plain_input() {
        assert!(shell_supports_bracketed_paste("/bin/zsh"));
        assert!(shell_supports_bracketed_paste(r"C:\tools\fish"));
        assert!(!shell_supports_bracketed_paste("pwsh"));
        assert!(should_use_bracketed_paste_for_startup("line one\nline two"));
        assert!(should_use_bracketed_paste_for_startup(&"x".repeat(513)));
        assert!(!should_use_bracketed_paste_for_startup("codex"));
        assert_eq!(
            build_plain_startup_command_bytes("hello\x1b\nworld"),
            b"hello<0x1B><LF>world\r"
        );
    }
}
