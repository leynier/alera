// SPDX-License-Identifier: Apache-2.0
// Ported and modified from Meat revision f39f41dfe7b5b37a12b35fdfbaecc7e779855bd3.

use super::*;

const DIFF: &[u8] = b"diff --git a/app.py b/app.py\r\n--- a/app.py\r\n+++ b/app.py\r\n@@ -1,3 +1,4 @@\r\n import os\r\n-old = calculate_large_value(source)\r\n+new = calculate_large_value(source)\r\n+print(new)\r\n return old\r\n";

#[test]
fn compiles_only_source_projected_edits_and_preserves_crlf() {
    let plan = r#"{"version":1,"remove":[{"start_line":8,"end_line":8}],"replace":[{"line":7,"old":"calculate_large_value(source)","new":"calculate_...(source)"}],"fold":[],"summary":"Rename the calculated value."}"#;
    let result = compile(DIFF, plan).expect("valid plan");
    assert!(result.reading_diff.windows(2).all(|bytes| bytes != b"\n\n"));
    assert!(
        result
            .reading_diff
            .windows(2)
            .filter(|bytes| *bytes == b"\r\n")
            .count()
            > 4
    );
    let text = String::from_utf8(result.reading_diff).expect("utf8");
    assert!(text.contains("+new = calculate_...(source)"));
    assert!(!text.contains("+print(new)"));
}

#[test]
fn rejects_unknown_fields_and_invented_replacement_text() {
    let unknown = r#"{"version":1,"remove":[],"replace":[],"fold":[],"summary":"x","extra":true}"#;
    assert!(compile(DIFF, unknown)
        .unwrap_err()
        .message
        .contains("unknown field"));
    let invented = r#"{"version":1,"remove":[],"replace":[{"line":7,"old":"calculate_large_value(source)","new":"calculate_fast...(source)"}],"fold":[],"summary":"x"}"#;
    assert!(compile(DIFF, invented)
        .unwrap_err()
        .message
        .contains("invents or reorders"));
}

#[test]
fn rejects_structural_removal_and_combined_diff() {
    let structural = r#"{"version":1,"remove":[{"start_line":1,"end_line":1}],"replace":[],"fold":[],"summary":"x"}"#;
    assert!(compile(DIFF, structural)
        .unwrap_err()
        .message
        .contains("structural diff line"));
    assert!(prepare(b"diff --cc app.py\n@@@ -1,1 -1,1 +1,1 @@@\n", None)
        .unwrap_err()
        .message
        .contains("Combined diff"));
}

#[test]
fn chunks_only_at_file_or_hunk_boundaries() {
    let prepared = prepare(DIFF, Some(4096)).expect("prepared");
    assert_eq!(prepared.chunks.len(), 1);
    assert!(prepared.chunks[0].numbered_diff.contains("1|diff --git"));
}

#[test]
fn preserves_utf8_rename_metadata_and_missing_final_newline() {
    let diff = b"diff --git a/caf\xc3\xa9.txt b/caf\xc3\xa9-renamed.txt\n\
similarity index 90%\n\
rename from caf\xc3\xa9.txt\n\
rename to caf\xc3\xa9-renamed.txt\n\
--- a/caf\xc3\xa9.txt\n\
+++ b/caf\xc3\xa9-renamed.txt\n\
@@ -1 +1 @@\n\
-caf\xc3\xa9\n\
\\ No newline at end of file\n\
+caf\xc3\xa9!\n\
\\ No newline at end of file";
    let unchanged = compile(
        diff,
        r#"{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Rename the file."}"#,
    )
    .expect("valid plan");
    assert_eq!(unchanged.reading_diff, diff);

    let removed = compile(
        diff,
        r#"{"version":1,"remove":[{"start_line":10,"end_line":10}],"replace":[],"fold":[],"summary":"Keep the original side."}"#,
    )
    .expect("valid plan");
    assert_eq!(
        removed
            .reading_diff
            .windows(b"\\ No newline at end of file".len())
            .filter(|window| *window == b"\\ No newline at end of file")
            .count(),
        1
    );
}

#[test]
fn rejects_overlaps_marker_crossing_folds_and_asymmetric_moves() {
    let overlap = r#"{"version":1,"remove":[{"start_line":7,"end_line":8}],"replace":[],"fold":[{"start_line":7,"end_line":8}],"summary":"x"}"#;
    assert!(compile(DIFF, overlap)
        .unwrap_err()
        .message
        .contains("overlaps remove"));

    let marker_crossing = r#"{"version":1,"remove":[],"replace":[],"fold":[{"start_line":6,"end_line":7}],"summary":"x"}"#;
    assert!(compile(DIFF, marker_crossing)
        .unwrap_err()
        .message
        .contains("diff marker boundary"));

    let moved = b"diff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1,2 +1,2 @@\n-this exact line moved\n kept\n+this exact line moved\n";
    let asymmetric = r#"{"version":1,"remove":[{"start_line":5,"end_line":5}],"replace":[],"fold":[],"summary":"x"}"#;
    assert!(compile(moved, asymmetric)
        .unwrap_err()
        .message
        .contains("symmetrically"));
}

#[test]
fn elides_imports_and_protects_python_suite_owners() {
    let python = b"diff --git a/app.py b/app.py\n--- a/app.py\n+++ b/app.py\n@@ -1,2 +1,4 @@\n import os\n+from pathlib import Path\n+def run():\n     return True\n";
    let unchanged = compile(
        python,
        r#"{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Add a runner."}"#,
    )
    .expect("valid plan");
    let text = String::from_utf8(unchanged.reading_diff).expect("utf8");
    assert!(!text.contains("+from pathlib import Path"));

    let suite = r#"{"version":1,"remove":[{"start_line":7,"end_line":7}],"replace":[],"fold":[],"summary":"x"}"#;
    assert!(compile(python, suite)
        .unwrap_err()
        .message
        .contains("Python decorator or suite owner"));
}

#[test]
fn merges_chunks_by_index_and_accumulates_stats() {
    let merged = merge_chunks(vec![
        CompiledChunk {
            index: 1,
            result: CompileResult {
                reading_diff: b"second".to_vec(),
                summary: "Second.".to_string(),
                changed_lines: 3,
                retained_changed_lines: 2,
            },
        },
        CompiledChunk {
            index: 0,
            result: CompileResult {
                reading_diff: b"first\n".to_vec(),
                summary: "First.".to_string(),
                changed_lines: 2,
                retained_changed_lines: 1,
            },
        },
    ])
    .expect("complete chunks");
    assert_eq!(merged.reading_diff, b"first\nsecond\n");
    assert_eq!(merged.summary, "First. Second.");
    assert_eq!(merged.changed_lines, 5);
    assert_eq!(merged.retained_changed_lines, 3);
}
