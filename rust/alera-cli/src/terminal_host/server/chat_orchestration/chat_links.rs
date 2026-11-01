//! Ready Markdown links to agent chats. Alera's apps open
//! `alera-chat://v1/<chatId>?workspace=<workspaceId>` as the chat; an agent
//! mentions a chat by pasting its `link` as is.

pub(super) const CHAT_LINK_SCHEME: &str = "alera-chat";

/// `[label](alera-chat://v1/<chatId>?workspace=<workspaceId>)`. The label
/// keeps to one line without brackets or backslashes, and falls back to the
/// chat id.
pub(super) fn chat_link(chat_id: &str, workspace_id: Option<&str>, label: Option<&str>) -> String {
    let cleaned = label
        .unwrap_or_default()
        .replace(['[', ']', '\\', '\r', '\n'], " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    let label = if cleaned.is_empty() {
        chat_id
    } else {
        &cleaned
    };
    let mut href = format!("{CHAT_LINK_SCHEME}://v1/{}", encode(chat_id));
    if let Some(workspace) = workspace_id.filter(|workspace| !workspace.is_empty()) {
        href.push_str(&format!("?workspace={}", encode(workspace)));
    }
    format!("[{label}]({href})")
}

/// Percent-encodes everything but unreserved characters.
fn encode(value: &str) -> String {
    value
        .bytes()
        .map(|byte| match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                (byte as char).to_string()
            }
            _ => format!("%{byte:02X}"),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::chat_link;

    #[test]
    fn a_link_names_the_chat_and_its_workspace() {
        assert_eq!(
            chat_link("chat-1", Some("ws-1"), Some("Fix the parser")),
            "[Fix the parser](alera-chat://v1/chat-1?workspace=ws-1)"
        );
    }

    #[test]
    fn a_label_stays_on_one_line_and_falls_back_to_the_id() {
        assert_eq!(
            chat_link("chat-1", None, Some(" [Plan]\n\\ the  work ")),
            "[Plan the work](alera-chat://v1/chat-1)"
        );
        assert_eq!(
            chat_link("chat-1", None, Some(" \n ")),
            "[chat-1](alera-chat://v1/chat-1)"
        );
        assert_eq!(
            chat_link("a b", Some("w/1"), None),
            "[a b](alera-chat://v1/a%20b?workspace=w%2F1)"
        );
    }
}
