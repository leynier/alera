//! The lines that name a turn's local attachments in the provider prompt, so
//! an agent that cannot take a file natively still learns where it is saved.
//! This is T3 Code's `providerMessageTextWithAttachmentPaths`.

use std::path::Path;

use crate::Attachment;

/// The name an attachment shows when its own name is blank or unknown.
const FALLBACK_NAME: &str = "Attachment";

impl Attachment {
    /// The person's file name when it is not blank, else the last segment of
    /// the saved path. A remote image has none.
    pub fn display_name(&self) -> Option<String> {
        let named = match self {
            Self::Image { .. } => return None,
            Self::File {
                name: Some(name), ..
            } if !name.trim().is_empty() => Some(name.clone()),
            _ => None,
        };
        Some(named.unwrap_or_else(|| {
            self.local_path()
                .and_then(Path::file_name)
                .map(|name| name.to_string_lossy().into_owned())
                .filter(|name| !name.trim().is_empty())
                .unwrap_or_else(|| FALLBACK_NAME.into())
        }))
    }

    /// Where the host saved the attachment. A remote image has no path.
    pub fn local_path(&self) -> Option<&Path> {
        match self {
            Self::Image { .. } => None,
            Self::LocalImage { path } | Self::File { path, .. } => Some(path),
        }
    }
}

/// `[Attached image|file "<name>" is saved at: <path>]`, or `None` for a
/// remote image, which the provider receives natively.
pub fn attachment_prompt_line(attachment: &Attachment) -> Option<String> {
    let kind = match attachment {
        Attachment::Image { .. } => return None,
        Attachment::LocalImage { .. } => "image",
        Attachment::File { .. } => "file",
    };
    let name = attachment.display_name()?;
    let path = attachment.local_path()?.to_string_lossy();
    Some(format!("[Attached {kind} \"{name}\" is saved at: {path}]"))
}

/// [text], then one line per local attachment, each after a blank line
/// unless the prompt is still empty. No length budget removes a line.
pub fn text_with_attachment_paths(text: &str, attachments: &[Attachment]) -> String {
    let mut prompt = text.to_owned();
    for line in attachments.iter().filter_map(attachment_prompt_line) {
        if !prompt.is_empty() {
            prompt.push_str("\n\n");
        }
        prompt.push_str(&line);
    }
    prompt
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn file(path: &str, name: Option<&str>) -> Attachment {
        Attachment::File {
            path: PathBuf::from(path),
            name: name.map(str::to_owned),
        }
    }

    #[test]
    fn every_local_attachment_is_named_after_the_text() {
        let attachments = [
            file("/rt/agent-chat-attachments/u.data.pdf", Some("spec.pdf")),
            Attachment::LocalImage {
                path: PathBuf::from("/w/shot.png"),
            },
        ];

        assert_eq!(
            text_with_attachment_paths("Read this.", &attachments),
            "Read this.\n\n[Attached file \"spec.pdf\" is saved at: /rt/agent-chat-attachments/u.data.pdf]\n\n[Attached image \"shot.png\" is saved at: /w/shot.png]"
        );
    }

    #[test]
    fn an_empty_text_starts_with_the_first_line() {
        let attachments = [file("/w/a.txt", Some("a.txt")), file("/w/b.txt", None)];

        assert_eq!(
            text_with_attachment_paths("", &attachments),
            "[Attached file \"a.txt\" is saved at: /w/a.txt]\n\n[Attached file \"b.txt\" is saved at: /w/b.txt]"
        );
    }

    #[test]
    fn a_full_length_text_still_keeps_every_path() {
        let attachments = [
            file("/w/one.pdf", Some("one.pdf")),
            file("/w/two.pdf", None),
        ];
        for length in [119_980, 120_000] {
            let text = "x".repeat(length);

            let prompt = text_with_attachment_paths(&text, &attachments);

            assert!(prompt.starts_with(&text));
            assert!(prompt.contains("is saved at: /w/one.pdf]"));
            assert!(prompt.ends_with("[Attached file \"two.pdf\" is saved at: /w/two.pdf]"));
        }
    }

    #[test]
    fn a_remote_image_adds_no_line() {
        let attachments = [Attachment::Image {
            url: "https://example.test/a.png".into(),
        }];

        assert_eq!(attachments[0].display_name(), None);
        assert_eq!(attachment_prompt_line(&attachments[0]), None);
        assert_eq!(text_with_attachment_paths("Look", &attachments), "Look");
    }

    #[test]
    fn a_blank_or_missing_name_falls_back_to_the_saved_file_name() {
        assert_eq!(
            file("/w/u.data.md", None).display_name().as_deref(),
            Some("u.data.md")
        );
        assert_eq!(
            file("/w/u.data.md", Some("  ")).display_name().as_deref(),
            Some("u.data.md")
        );
        assert_eq!(
            file("/", None).display_name().as_deref(),
            Some("Attachment")
        );
        assert_eq!(
            attachment_prompt_line(&file("/w/u.data.md", Some(""))).as_deref(),
            Some("[Attached file \"u.data.md\" is saved at: /w/u.data.md]")
        );
    }
}
