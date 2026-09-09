//! Workspace display-name slug helper shared by local and remote create.

use anyhow::{bail, Result};

pub(crate) fn slugify(input: &str) -> Result<String> {
    let mut output = String::new();
    let mut last_dash = false;
    for ch in input.trim().to_lowercase().chars() {
        let next = if ch.is_ascii_alphanumeric() {
            last_dash = false;
            Some(ch)
        } else if ch.is_whitespace() || ch == '_' || ch == '/' || ch == '-' {
            if last_dash {
                None
            } else {
                last_dash = true;
                Some('-')
            }
        } else if last_dash {
            None
        } else {
            last_dash = true;
            Some('-')
        };
        if let Some(next) = next {
            output.push(next);
        }
    }
    let trimmed = output.trim_matches('-').to_string();
    if trimmed.is_empty() {
        bail!("Workspace name must contain a letter or digit");
    }
    Ok(trimmed)
}
