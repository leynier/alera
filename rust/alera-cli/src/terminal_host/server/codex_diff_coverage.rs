use serde_json::Value;

const SUPERSEDED_KEY: &str = "supersededByStructuredFileChanges";

#[derive(Debug, PartialEq, Eq)]
struct DiffSection {
    source: Option<String>,
    destination: Option<String>,
    hunks: Option<String>,
    added_content: Option<FileContent>,
    deleted_content: Option<FileContent>,
    has_unrepresented_metadata: bool,
}

#[derive(Debug, PartialEq, Eq)]
struct StructuredChange {
    source: String,
    destination: String,
    kind: StructuredChangeKind,
    hunks: Option<String>,
    content: FileContent,
}

#[derive(Debug, PartialEq, Eq)]
enum StructuredChangeKind {
    Add,
    Delete,
    Update,
}

#[derive(Debug, PartialEq, Eq)]
struct FileContent {
    text: String,
    ends_with_newline: bool,
}

pub(super) fn mark_superseded_aggregate_diff(cells: &mut [Value], turn_id: &str) {
    if turn_id.is_empty() {
        return;
    }
    let aggregate_id = format!("diff-{turn_id}");
    let Some(aggregate_index) = cells
        .iter()
        .position(|cell| cell.get("id").and_then(Value::as_str) == Some(&aggregate_id))
    else {
        return;
    };
    let diff = cells[aggregate_index]
        .get("detailsText")
        .or_else(|| cells[aggregate_index].get("markdownText"))
        .and_then(Value::as_str)
        .unwrap_or_default();
    let sections = diff_sections(diff);
    let structured = structured_changes(cells, turn_id);
    let superseded = !sections.is_empty()
        && sections
            .iter()
            .all(|section| structured.iter().any(|change| covers(change, section)));
    let Some(metadata) = cells[aggregate_index]
        .get_mut("metadata")
        .and_then(Value::as_object_mut)
    else {
        return;
    };
    if superseded {
        metadata.insert(SUPERSEDED_KEY.to_string(), Value::Bool(true));
    } else {
        metadata.remove(SUPERSEDED_KEY);
    }
}

pub(super) fn revalidate_superseded_aggregate_diffs(cells: &mut [Value]) {
    let turn_ids = cells
        .iter()
        .filter(|cell| {
            cell.pointer(&format!("/metadata/{SUPERSEDED_KEY}"))
                .and_then(Value::as_bool)
                == Some(true)
        })
        .filter_map(|cell| cell.get("turnId").and_then(Value::as_str))
        .map(str::to_string)
        .collect::<Vec<_>>();
    for turn_id in turn_ids {
        mark_superseded_aggregate_diff(cells, &turn_id);
    }
}

fn covers(change: &StructuredChange, section: &DiffSection) -> bool {
    if section.has_unrepresented_metadata {
        return false;
    }
    match change.kind {
        StructuredChangeKind::Add => {
            section.source.is_none()
                && section
                    .destination
                    .as_ref()
                    .is_some_and(|path| paths_match(&change.destination, path))
                && section.added_content.as_ref() == Some(&change.content)
        }
        StructuredChangeKind::Delete => {
            section.destination.is_none()
                && section
                    .source
                    .as_ref()
                    .is_some_and(|path| paths_match(&change.source, path))
                && section.deleted_content.as_ref() == Some(&change.content)
        }
        StructuredChangeKind::Update => {
            let endpoints_match = section
                .source
                .as_ref()
                .is_some_and(|path| paths_match(&change.source, path))
                && section
                    .destination
                    .as_ref()
                    .is_some_and(|path| paths_match(&change.destination, path));
            endpoints_match
                && match &section.hunks {
                    Some(hunks) => change.hunks.as_ref() == Some(hunks),
                    None => change.source != change.destination,
                }
        }
    }
}

fn paths_match(structured: &str, aggregate: &str) -> bool {
    let structured = normalized_path(structured);
    let aggregate = normalized_path(aggregate);
    if structured == aggregate {
        return true;
    }
    match (is_absolute_path(&structured), is_absolute_path(&aggregate)) {
        (true, false) => structured.ends_with(&format!("/{aggregate}")),
        (false, true) => aggregate.ends_with(&format!("/{structured}")),
        _ => false,
    }
}

fn normalized_path(path: &str) -> String {
    path.replace('\\', "/")
        .trim_start_matches("./")
        .trim_end_matches('/')
        .to_string()
}

fn is_absolute_path(path: &str) -> bool {
    path.starts_with('/') || path.as_bytes().get(1) == Some(&b':')
}

fn structured_changes(cells: &[Value], turn_id: &str) -> Vec<StructuredChange> {
    cells
        .iter()
        .filter(|cell| cell.get("turnId").and_then(Value::as_str) == Some(turn_id))
        .filter(|cell| {
            cell.pointer("/metadata/itemType")
                .and_then(Value::as_str)
                .is_some_and(|value| value.eq_ignore_ascii_case("fileChange"))
        })
        .flat_map(|cell| {
            cell.pointer("/metadata/changes")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
        })
        .filter(|change| change.get("truncated").and_then(Value::as_bool) != Some(true))
        .filter_map(|change| {
            let source = change.get("path")?.as_str()?.to_string();
            let kind_name = change
                .pointer("/kind/type")
                .or_else(|| change.get("kind"))
                .and_then(Value::as_str)
                .unwrap_or("update");
            let kind = match kind_name.to_ascii_lowercase().as_str() {
                "add" => StructuredChangeKind::Add,
                "delete" => StructuredChangeKind::Delete,
                _ => StructuredChangeKind::Update,
            };
            let destination = change
                .pointer("/kind/move_path")
                .or_else(|| change.pointer("/kind/movePath"))
                .or_else(|| change.get("move_path"))
                .or_else(|| change.get("movePath"))
                .and_then(Value::as_str)
                .unwrap_or(&source)
                .to_string();
            let diff = change
                .get("diff")
                .and_then(Value::as_str)
                .unwrap_or_default();
            Some(StructuredChange {
                source,
                destination,
                kind,
                hunks: canonical_hunks(diff),
                content: file_content(diff),
            })
        })
        .collect()
}

fn diff_sections(diff: &str) -> Vec<DiffSection> {
    let mut sections = Vec::new();
    let mut current: Option<Vec<&str>> = None;
    for line in diff.lines() {
        if line.starts_with("diff --git ") {
            if let Some(lines) = current.take() {
                if let Some(section) = diff_section(&lines) {
                    sections.push(section);
                }
            }
            current = Some(vec![line]);
        } else if let Some(lines) = current.as_mut() {
            lines.push(line);
        }
    }
    if let Some(lines) = current {
        if let Some(section) = diff_section(&lines) {
            sections.push(section);
        }
    }
    sections
}

fn diff_section(lines: &[&str]) -> Option<DiffSection> {
    let (mut source, mut destination) =
        parse_diff_header(lines.first()?.strip_prefix("diff --git ")?);
    for line in lines {
        if let Some(value) = line.strip_prefix("--- ") {
            source = normalize_marker_path(value);
        } else if let Some(value) = line.strip_prefix("+++ ") {
            destination = normalize_marker_path(value);
        }
    }
    Some(DiffSection {
        source,
        destination,
        hunks: canonical_hunks(&lines.join("\n")),
        added_content: changed_file_content(lines, '+'),
        deleted_content: changed_file_content(lines, '-'),
        has_unrepresented_metadata: has_unrepresented_metadata(lines),
    })
}

fn changed_file_content(lines: &[&str], prefix: char) -> Option<FileContent> {
    let start = lines.iter().position(|line| line.starts_with("@@"));
    let Some(start) = start else {
        return Some(file_content(""));
    };
    let opposite = if prefix == '+' { '-' } else { '+' };
    let mut content = Vec::new();
    let mut ends_with_newline = true;
    for line in &lines[start + 1..] {
        if line.starts_with("@@") {
            continue;
        }
        if *line == "\\ No newline at end of file" {
            ends_with_newline = false;
            continue;
        }
        if let Some(value) = line.strip_prefix(prefix) {
            content.push(value);
        } else if line.starts_with(opposite) || line.starts_with(' ') {
            return None;
        }
    }
    Some(FileContent {
        text: content.join("\n"),
        ends_with_newline,
    })
}

fn has_unrepresented_metadata(lines: &[&str]) -> bool {
    lines.iter().any(|line| {
        !(line.is_empty()
            || line.starts_with("diff --git ")
            || line.starts_with("index ")
            || line.starts_with("--- ")
            || line.starts_with("+++ ")
            || line.starts_with("@@")
            || line.starts_with('+')
            || line.starts_with('-')
            || line.starts_with(' ')
            || *line == "\\ No newline at end of file"
            || line.starts_with("similarity index ")
            || line.starts_with("dissimilarity index ")
            || line.starts_with("rename from ")
            || line.starts_with("rename to ")
            || *line == "new file mode 100644"
            || *line == "deleted file mode 100644")
    })
}

fn parse_diff_header(value: &str) -> (Option<String>, Option<String>) {
    if value.starts_with('"') {
        let Some((source, consumed)) = quoted_path(value) else {
            return (None, None);
        };
        let remainder = value[consumed..].trim_start();
        let destination = quoted_path(remainder).map(|(path, _)| path);
        return (
            normalize_git_side_path(source),
            destination.and_then(normalize_git_side_path),
        );
    }
    let Some(separator) = value.rfind(" b/") else {
        return (None, None);
    };
    (
        normalize_git_side_path(value[..separator].to_string()),
        normalize_git_side_path(value[separator + 1..].to_string()),
    )
}

fn normalize_marker_path(value: &str) -> Option<String> {
    let value = value.split('\t').next().unwrap_or_default().trim();
    if value == "/dev/null" {
        return None;
    }
    if value.starts_with('"') {
        return quoted_path(value)
            .map(|(path, _)| path)
            .and_then(normalize_git_side_path);
    }
    normalize_git_side_path(value.to_string())
}

fn normalize_git_side_path(mut path: String) -> Option<String> {
    if path == "/dev/null" || path.is_empty() {
        return None;
    }
    if path.starts_with("a/") || path.starts_with("b/") {
        path.drain(..2);
    }
    Some(path)
}

fn quoted_path(value: &str) -> Option<(String, usize)> {
    let bytes = value.as_bytes();
    if bytes.first() != Some(&b'"') {
        return None;
    }
    let mut decoded = Vec::new();
    let mut index = 1;
    while index < bytes.len() {
        match bytes[index] {
            b'"' => {
                return String::from_utf8(decoded)
                    .ok()
                    .map(|path| (path, index + 1))
            }
            b'\\' => {
                index += 1;
                let escaped = *bytes.get(index)?;
                if (b'0'..=b'7').contains(&escaped) {
                    let mut octal = 0u16;
                    let mut digits = 0;
                    while index < bytes.len() && digits < 3 && (b'0'..=b'7').contains(&bytes[index])
                    {
                        octal = octal * 8 + u16::from(bytes[index] - b'0');
                        index += 1;
                        digits += 1;
                    }
                    decoded.push(u8::try_from(octal).ok()?);
                    continue;
                }
                decoded.push(match escaped {
                    b'a' => 0x07,
                    b'b' => 0x08,
                    b't' => 0x09,
                    b'n' => 0x0a,
                    b'v' => 0x0b,
                    b'f' => 0x0c,
                    b'r' => 0x0d,
                    other => other,
                });
            }
            byte => decoded.push(byte),
        }
        index += 1;
    }
    None
}

fn canonical_hunks(diff: &str) -> Option<String> {
    let diff = diff.split("\n\nMoved to: ").next().unwrap_or(diff);
    let lines = diff.lines().collect::<Vec<_>>();
    let start = lines.iter().position(|line| line.starts_with("@@"))?;
    Some(lines[start..].join("\n"))
}

#[cfg(test)]
#[path = "codex_diff_coverage_tests.rs"]
mod tests;

fn file_content(value: &str) -> FileContent {
    let normalized = value.replace("\r\n", "\n");
    FileContent {
        ends_with_newline: normalized.ends_with('\n'),
        text: normalized
            .strip_suffix('\n')
            .unwrap_or(&normalized)
            .to_string(),
    }
}
