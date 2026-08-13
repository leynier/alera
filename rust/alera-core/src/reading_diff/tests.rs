// SPDX-License-Identifier: Apache-2.0
// Ported and modified from Meat revision f39f41dfe7b5b37a12b35fdfbaecc7e779855bd3.

use super::*;

const DIFF: &[u8] = b"diff --git a/app.py b/app.py\r\n--- a/app.py\r\n+++ b/app.py\r\n@@ -1,3 +1,4 @@\r\n import os\r\n-old = calculate_large_value(source)\r\n+new = calculate_large_value(source)\r\n+print(new)\r\n return old\r\n";

#[test]
fn plan_schema_declares_a_type_for_the_version_constant() {
    let schema: serde_json::Value = serde_json::from_str(&plan_schema()).expect("valid schema");

    assert_eq!(schema["properties"]["version"]["type"], "integer");
    assert_eq!(schema["properties"]["version"]["const"], SCHEMA_VERSION);
}

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
    assert!(prepared.chunks[0].continuation_preamble.is_empty());
}

#[test]
fn reconstructs_split_files_once_and_preserves_the_final_eol() {
    let old = "o".repeat(1100);
    let new = "n".repeat(1100);
    let source = format!(
        "diff --git a/large.txt b/large.txt\n--- a/large.txt\n+++ b/large.txt\n\
@@ -1 +1 @@\n-{old}\n+{new}\n\
@@ -10 +10 @@\n-{old}\n+{new}\n"
    );
    let prepared = prepare(source.as_bytes(), Some(4096)).expect("split diff");
    assert_eq!(prepared.chunks.len(), 2);
    assert!(prepared.chunks[0].continuation_preamble.is_empty());
    assert!(!prepared.chunks[1].continuation_preamble.is_empty());
    let plan = r#"{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep the changes."}"#;
    let compiled = prepared
        .chunks
        .into_iter()
        .map(|chunk| CompiledChunk {
            index: chunk.index,
            continuation_preamble: chunk.continuation_preamble,
            result: compile(&chunk.raw_diff, plan).expect("compiled chunk"),
        })
        .collect();

    let merged = merge_chunks(compiled, source.as_bytes()).expect("merged split diff");
    assert_eq!(merged.reading_diff, source.as_bytes());
    assert_eq!(
        merged
            .reading_diff
            .windows(b"diff --git".len())
            .filter(|window| *window == b"diff --git")
            .count(),
        1
    );

    let no_final_eol = b"diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1 +1 @@\n-old\n+new\n\\ No newline at end of file";
    let compiled = compile(no_final_eol, plan).expect("compiled missing final eol");
    let merged = merge_chunks(
        vec![CompiledChunk {
            index: 0,
            continuation_preamble: Vec::new(),
            result: compiled,
        }],
        no_final_eol,
    )
    .expect("merged missing final eol");
    assert_eq!(merged.reading_diff, no_final_eol);
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
fn preserves_exported_declarations_but_elides_reexports() {
    let declaration = b"diff --git a/config.ts b/config.ts\n\
--- a/config.ts\n\
+++ b/config.ts\n\
@@ -1 +1 @@\n\
-export const enabled = false;\n\
+export const enabled = true;\n";
    let unchanged = compile(
        declaration,
        r#"{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Toggle the exported setting."}"#,
    )
    .expect("export declaration");
    assert_eq!(unchanged.reading_diff, declaration);

    let reexport = b"diff --git a/index.ts b/index.ts\n\
--- a/index.ts\n\
+++ b/index.ts\n\
@@ -0,0 +1 @@\n\
+export { Feature } from './feature';\n";
    let elided = compile(
        reexport,
        r#"{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Expose the feature."}"#,
    )
    .expect("reexport");
    assert!(elided.reading_diff.is_empty());
}

#[test]
fn rejects_partial_python_expressions_and_elides_multiline_imports() {
    let expression = b"diff --git a/app.py b/app.py\n--- a/app.py\n+++ b/app.py\n@@ -0,0 +1,3 @@\n+result = call(\n+    argument,\n+)\n";
    let partial = r#"{"version":1,"remove":[{"start_line":5,"end_line":5}],"replace":[],"fold":[],"summary":"x"}"#;
    assert!(compile(expression, partial)
        .unwrap_err()
        .message
        .contains("Python expression"));

    let imports = b"diff --git a/app.py b/app.py\n--- a/app.py\n+++ b/app.py\n@@ -0,0 +1,5 @@\n+from package import (\n+    First,\n+    Second,\n+)\n+value = First()\n";
    let result = compile(
        imports,
        r#"{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Use the imported value."}"#,
    )
    .expect("multiline import");
    let text = String::from_utf8(result.reading_diff).expect("utf8");
    assert!(!text.contains("from package import"));
    assert!(!text.contains("First,"));
    assert!(!text.contains("Second,"));
    assert!(text.contains("+value = First()"));
}

#[test]
fn rejects_asymmetric_moves_after_chunk_merge() {
    const OLD: &[u8] = b"diff --git a/old.txt b/old.txt\n--- a/old.txt\n+++ b/old.txt\n@@ -1 +0,0 @@\n-this exact line moved\n";
    const NEW: &[u8] = b"diff --git a/new.txt b/new.txt\n--- a/new.txt\n+++ b/new.txt\n@@ -0,0 +1 @@\n+this exact line moved\n";
    let source = [OLD, NEW].concat();
    let remove_old = r#"{"version":1,"remove":[{"start_line":5,"end_line":5}],"replace":[],"fold":[],"summary":"Move the line."}"#;
    assert!(compile_with_source(OLD, &source, remove_old)
        .unwrap_err()
        .message
        .contains("another chunk"));
    let old_result = compile(OLD, remove_old).expect("single-sided chunk");
    let new_result = compile(
        NEW,
        r#"{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Move the line."}"#,
    )
    .expect("retained chunk");
    assert!(merge_chunks(
        vec![
            CompiledChunk {
                index: 0,
                continuation_preamble: Vec::new(),
                result: old_result,
            },
            CompiledChunk {
                index: 1,
                continuation_preamble: Vec::new(),
                result: new_result,
            },
        ],
        &source,
    )
    .unwrap_err()
    .message
    .contains("split across chunks"));
}

#[test]
fn allows_symmetric_automatic_import_elision_across_chunks() {
    const OLD: &[u8] = b"diff --git a/old.py b/old.py\n--- a/old.py\n+++ b/old.py\n@@ -1 +0,0 @@\n-from package import moved_symbol\n";
    const NEW: &[u8] = b"diff --git a/new.py b/new.py\n--- a/new.py\n+++ b/new.py\n@@ -0,0 +1 @@\n+from package import moved_symbol\n";
    let source = [OLD, NEW].concat();
    let plan = r#"{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Move the import."}"#;
    let old_result = compile_with_source(OLD, &source, plan).expect("old import chunk");
    let new_result = compile_with_source(NEW, &source, plan).expect("new import chunk");

    let merged = merge_chunks(
        vec![
            CompiledChunk {
                index: 0,
                continuation_preamble: Vec::new(),
                result: old_result,
            },
            CompiledChunk {
                index: 1,
                continuation_preamble: Vec::new(),
                result: new_result,
            },
        ],
        &source,
    )
    .expect("symmetric automatic elision");

    assert_eq!(merged.retained_changed_lines, 0);
}

#[test]
fn merges_chunks_by_index_and_accumulates_stats() {
    const FIRST: &[u8] = b"diff --git a/first.txt b/first.txt\n--- a/first.txt\n+++ b/first.txt\n@@ -1 +1 @@\n-old first\n+new first\n";
    const SECOND: &[u8] = b"diff --git a/second.txt b/second.txt\n--- a/second.txt\n+++ b/second.txt\n@@ -1 +1 @@\n-old second\n+new second\n";
    let source = [FIRST, SECOND].concat();
    let merged = merge_chunks(
        vec![
            CompiledChunk {
                index: 1,
                continuation_preamble: Vec::new(),
                result: CompileResult {
                    reading_diff: SECOND.to_vec(),
                    summary: "Second.".to_string(),
                    changed_lines: 3,
                    retained_changed_lines: 2,
                },
            },
            CompiledChunk {
                index: 0,
                continuation_preamble: Vec::new(),
                result: CompileResult {
                    reading_diff: FIRST.to_vec(),
                    summary: "First.".to_string(),
                    changed_lines: 2,
                    retained_changed_lines: 1,
                },
            },
        ],
        &source,
    )
    .expect("complete chunks");
    assert_eq!(merged.reading_diff, source);
    assert_eq!(merged.summary, "First. Second.");
    assert_eq!(merged.changed_lines, 5);
    assert_eq!(merged.retained_changed_lines, 3);
}
