//! Queued attachment copies must outlive picker files and upload TTLs.

use crate::terminal_host::host_error::{HostError, HostResult};
use alera_core::runtime::{open_private_runtime_file, prepare_private_runtime_directory};
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use uuid::Uuid;

pub(super) async fn retain_attachments(runtime_dir: &Path, payload: Value) -> HostResult<Value> {
    if payload
        .get("input")
        .and_then(Value::as_array)
        .is_none_or(Vec::is_empty)
    {
        return Err(HostError::format(
            "A message must contain text or attachments.",
        ));
    }
    let runtime_dir = runtime_dir.to_path_buf();
    tokio::task::spawn_blocking(move || retain(&runtime_dir, payload))
        .await
        .map_err(|error| HostError::state(error.to_string()))?
}

fn retain(runtime_dir: &Path, payload: Value) -> HostResult<Value> {
    let mut created = Vec::new();
    let result = retain_files(runtime_dir, payload, &mut created);
    if result.is_err() {
        for directory in created {
            let _ = std::fs::remove_dir_all(directory);
        }
    }
    result
}

fn retain_files(
    runtime_dir: &Path,
    mut payload: Value,
    created: &mut Vec<PathBuf>,
) -> HostResult<Value> {
    let root = runtime_dir.join("codex-attachments");
    let mut paths: Vec<_> = payload
        .pointer("/userMessage/attachments")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|attachment| {
            attachment.get("origin").and_then(Value::as_str) != Some("mention")
                && attachment.get("isDirectory").and_then(Value::as_bool) != Some(true)
        })
        .filter_map(|attachment| attachment.get("path").and_then(Value::as_str))
        .map(str::to_string)
        .collect();
    paths.extend(
        payload
            .get("input")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter(|item| matches!(item["type"].as_str(), Some("localImage" | "localAudio")))
            .filter_map(|item| item["path"].as_str().map(str::to_string)),
    );
    paths.sort();
    paths.dedup();
    let mut replacements = BTreeMap::new();
    let mut total = 0;
    for source in paths {
        let path = PathBuf::from(&source);
        if !path.is_absolute() {
            return Err(HostError::format(
                "Queued attachment paths must be absolute.",
            ));
        }
        let metadata = std::fs::metadata(&path).map_err(|_| {
            HostError::state(
                "An attachment is no longer available. Attach it again before sending.",
            )
        })?;
        if !metadata.is_file() {
            return Err(HostError::format("A queued attachment is not a file."));
        }
        total += metadata.len();
        if metadata.len() > 32 * 1024 * 1024 || total > 128 * 1024 * 1024 {
            return Err(HostError::format(
                "Queued attachments exceed the upload size limit.",
            ));
        }
        if path
            .canonicalize()
            .ok()
            .zip(root.canonicalize().ok())
            .is_some_and(|(path, root)| path.starts_with(root))
        {
            continue;
        }
        let directory = root.join(Uuid::new_v4().to_string());
        prepare_private_runtime_directory(&directory)
            .map_err(|e| HostError::state(e.to_string()))?;
        created.push(directory.clone());
        let target = directory.join(
            path.file_name()
                .ok_or_else(|| HostError::format("Attachment has no file name."))?,
        );
        let input = std::fs::File::open(&path).map_err(|e| HostError::state(e.to_string()))?;
        let mut output =
            open_private_runtime_file(&target).map_err(|e| HostError::state(e.to_string()))?;
        let copied = std::io::copy(
            &mut std::io::Read::take(input, metadata.len() + 1),
            &mut output,
        )
        .map_err(|e| HostError::state(e.to_string()))?;
        if copied != metadata.len() {
            return Err(HostError::state(
                "An attachment changed while it was being queued. Try attaching it again.",
            ));
        }
        output
            .sync_all()
            .map_err(|e| HostError::state(e.to_string()))?;
        replacements.insert(source, target.to_string_lossy().into_owned());
    }
    replace_paths(&mut payload, &replacements);
    let mut owned = payload
        .get("queueAttachmentDirectories")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    owned.extend(created.iter().map(|path| serde_json::json!(path)));
    payload["queueAttachmentDirectories"] = Value::Array(owned);
    Ok(payload)
}

fn replace_paths(value: &mut Value, replacements: &BTreeMap<String, String>) {
    match value {
        Value::String(text) => {
            *text = replace_text(text, replacements).0;
        }
        Value::Object(object) => {
            if object.get("type").and_then(Value::as_str) == Some("text") {
                if let Some(text) = object
                    .get("text")
                    .and_then(Value::as_str)
                    .map(str::to_string)
                {
                    let (_, edits) = replace_text(&text, replacements);
                    if let Some(elements) = object
                        .get_mut("text_elements")
                        .and_then(Value::as_array_mut)
                    {
                        for element in elements {
                            for edge in ["start", "end"] {
                                if let Some(offset) = element
                                    .pointer(&format!("/byteRange/{edge}"))
                                    .and_then(Value::as_u64)
                                {
                                    if text.is_char_boundary(offset as usize) {
                                        let mut mapped = offset as usize;
                                        for &(start, end, length) in &edits {
                                            if offset as usize >= end {
                                                mapped = mapped + length - (end - start);
                                            } else if offset as usize > start {
                                                mapped -= offset as usize - start;
                                                if edge == "end" {
                                                    mapped += length;
                                                }
                                                break;
                                            } else {
                                                break;
                                            }
                                        }
                                        element["byteRange"][edge] = serde_json::json!(mapped);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            for (key, value) in object.iter_mut() {
                if key == "path" {
                    if let Some(target) = value.as_str().and_then(|path| replacements.get(path)) {
                        *value = Value::String(target.clone());
                    }
                } else {
                    replace_paths(value, replacements);
                }
            }
        }
        Value::Array(items) => {
            for item in items {
                replace_paths(item, replacements);
            }
        }
        _ => {}
    }
}

fn replace_text(
    text: &str,
    replacements: &BTreeMap<String, String>,
) -> (String, Vec<(usize, usize, usize)>) {
    let mut result = String::new();
    let mut edits = Vec::new();
    let mut offset = 0;
    while let Some((start, source, target)) = replacements
        .iter()
        .filter(|(source, _)| !source.is_empty())
        .filter_map(|(source, target)| {
            text[offset..]
                .match_indices(source)
                .find(|(index, _)| complete_path_reference(text, offset + index, source.len()))
                .map(|(index, _)| (offset + index, source, target))
        })
        .min_by_key(|(start, source, _)| (*start, std::cmp::Reverse(source.len())))
    {
        result.push_str(&text[offset..start]);
        result.push_str(target);
        offset = start + source.len();
        edits.push((start, offset, target.len()));
    }
    result.push_str(&text[offset..]);
    (result, edits)
}

fn complete_path_reference(text: &str, start: usize, length: usize) -> bool {
    let before = text[..start].chars().next_back();
    let after = text[start + length..].chars().next();
    before.is_none_or(|ch| {
        ch.is_whitespace() || matches!(ch, '@' | '\'' | '"' | '`' | '(' | '[' | '{' | '<' | '=')
    }) && after.is_none_or(|ch| {
        ch.is_whitespace() || matches!(ch, '\'' | '"' | '`' | ')' | ']' | '}' | '>')
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn retention_only_rewrites_complete_references() {
        let replacements =
            BTreeMap::from([("/tmp/report.csv".into(), "/retained/report.csv".into())]);
        let text = "Sí @/tmp/report.csv.backup /else/tmp/report.csv [file](/tmp/report.csv) `/tmp/report.csv` @/tmp/report.csv";
        let mut payload = json!({"input":[{"type":"text","text":text}], "draft":{"text":text}, "userMessage":{"text":text,"attachments":[{"path":"/tmp/report.csv"},{"path":"/tmp/report.csv.backup"}]}});
        replace_paths(&mut payload, &replacements);
        let expected = "Sí @/tmp/report.csv.backup /else/tmp/report.csv [file](/retained/report.csv) `/retained/report.csv` @/retained/report.csv";
        assert_eq!(payload["input"][0]["text"], expected);
        assert_eq!(payload["draft"]["text"], expected);
        assert_eq!(payload["userMessage"]["text"], expected);
        assert_eq!(
            payload["userMessage"]["attachments"][0]["path"],
            "/retained/report.csv"
        );
        assert_eq!(
            payload["userMessage"]["attachments"][1]["path"],
            "/tmp/report.csv.backup"
        );
    }

    #[tokio::test]
    async fn queued_image_survives_upload_expiration() {
        let runtime = tempfile::tempdir().unwrap();
        let uploads = tempfile::tempdir().unwrap();
        let source = uploads.path().join("image.png");
        std::fs::write(&source, b"image bytes").unwrap();
        let payload = retain_attachments(runtime.path(), json!({"input":[{"type":"localImage","path":source}],"userMessage":{"attachments":[{"path":source,"isImage":true}]}})).await.unwrap();
        drop(uploads);
        let retained = payload["input"][0]["path"].as_str().unwrap();
        assert_eq!(std::fs::read(retained).unwrap(), b"image bytes");
        assert_eq!(payload["userMessage"]["attachments"][0]["path"], retained);
    }

    #[tokio::test]
    async fn rejects_a_missing_image_without_presentation_metadata() {
        let runtime = tempfile::tempdir().unwrap();
        let missing = runtime.path().join("missing.png");
        assert!(retain_attachments(
            runtime.path(),
            json!({"input":[{"type":"localImage","path":missing}]})
        )
        .await
        .is_err());
    }

    #[test]
    fn copied_reference_keeps_utf8_byte_ranges_valid() {
        let mut payload = json!({"type":"text","text":"Sí @/tmp/a", "text_elements":[{"byteRange":{"start":4,"end":11},"placeholder":"a"}]});
        let replacements = BTreeMap::from([("/tmp/a".into(), "/runtime/attachments/a".into())]);
        replace_paths(&mut payload, &replacements);
        let text = payload["text"].as_str().unwrap();
        let start = payload["text_elements"][0]["byteRange"]["start"]
            .as_u64()
            .unwrap() as usize;
        let end = payload["text_elements"][0]["byteRange"]["end"]
            .as_u64()
            .unwrap() as usize;
        assert_eq!(&text[start..end], "@/runtime/attachments/a");
    }

    #[tokio::test]
    async fn prefix_related_attachments_keep_distinct_copies_and_utf8_references() {
        let runtime = tempfile::tempdir().unwrap();
        let uploads = tempfile::tempdir().unwrap();
        let short = uploads.path().join("report.csv");
        let long = uploads.path().join("report.csv.backup");
        std::fs::write(&short, b"short").unwrap();
        std::fs::write(&long, b"long").unwrap();
        let text = format!("Sí @{} and @{}", short.display(), long.display());
        let start = text.find("and @").unwrap() + 4;
        let payload = retain_attachments(runtime.path(), json!({
            "input":[{"type":"text","text":text,"text_elements":[{"byteRange":{"start":start,"end":text.len()}}]}],
            "userMessage":{"attachments":[{"path":short},{"path":long}]}
        })).await.unwrap();
        drop(uploads);
        let retained_short = payload["userMessage"]["attachments"][0]["path"]
            .as_str()
            .unwrap();
        let retained_long = payload["userMessage"]["attachments"][1]["path"]
            .as_str()
            .unwrap();
        assert_eq!(std::fs::read(retained_short).unwrap(), b"short");
        assert_eq!(std::fs::read(retained_long).unwrap(), b"long");
        let input = &payload["input"][0];
        assert_eq!(
            input["text"],
            format!("Sí @{retained_short} and @{retained_long}")
        );
        let range = &input["text_elements"][0]["byteRange"];
        assert_eq!(
            &input["text"].as_str().unwrap()[range["start"].as_u64().unwrap() as usize
                ..range["end"].as_u64().unwrap() as usize],
            format!("@{retained_long}")
        );
    }
}
