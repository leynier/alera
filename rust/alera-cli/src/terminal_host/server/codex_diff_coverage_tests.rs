use serde_json::json;

use super::*;

fn aggregate(diff: &str) -> Value {
    json!({
        "id": "diff-turn",
        "turnId": "turn",
        "kind": "diff",
        "detailsText": diff,
        "metadata": {"lastDelta": diff}
    })
}

fn structured(changes: Value) -> Value {
    json!({
        "id": "item-files",
        "turnId": "turn",
        "kind": "diff",
        "metadata": {"itemType": "fileChange", "changes": changes}
    })
}

fn superseded(cells: &[Value]) -> bool {
    cells[0].pointer("/metadata/supersededByStructuredFileChanges") == Some(&Value::Bool(true))
}

#[test]
fn marks_exact_text_diff_coverage_with_absolute_structured_path() {
    let diff = "diff --git a/lib/foo bar.dart b/lib/foo bar.dart\n--- a/lib/foo bar.dart\n+++ b/lib/foo bar.dart\n@@ -1 +1 @@\n-old\n+new";
    let mut cells = vec![
        aggregate(diff),
        structured(json!([{
            "path": "/workspace/lib/foo bar.dart",
            "kind": {"type": "update"},
            "diff": "@@ -1 +1 @@\n-old\n+new"
        }])),
    ];
    mark_superseded_aggregate_diff(&mut cells, "turn");
    assert!(superseded(&cells));
}

#[test]
fn marks_exact_text_diff_coverage_with_quoted_unicode() {
    let diff = "diff --git \"a/lib/caf\\303\\251.dart\" \"b/lib/caf\\303\\251.dart\"\n--- \"a/lib/caf\\303\\251.dart\"\n+++ \"b/lib/caf\\303\\251.dart\"\n@@ -1 +1 @@\n-old\n+new";
    let mut cells = vec![
        aggregate(diff),
        structured(json!([{
            "path": "lib/café.dart",
            "kind": {"type": "update"},
            "diff": "@@ -1 +1 @@\n-old\n+new"
        }])),
    ];
    mark_superseded_aggregate_diff(&mut cells, "turn");
    assert!(superseded(&cells));
}

#[test]
fn marks_add_and_delete_content_coverage() {
    let diff = "diff --git a/lib/new.dart b/lib/new.dart\nnew file mode 100644\n--- /dev/null\n+++ b/lib/new.dart\n@@ -0,0 +1 @@\n+new\ndiff --git a/lib/old.dart b/lib/old.dart\ndeleted file mode 100644\n--- a/lib/old.dart\n+++ /dev/null\n@@ -1 +0,0 @@\n-old";
    let mut cells = vec![
        aggregate(diff),
        structured(json!([
            {"path": "lib/new.dart", "kind": {"type": "add"}, "diff": "new\n"},
            {"path": "lib/old.dart", "kind": {"type": "delete"}, "diff": "old\n"}
        ])),
    ];
    mark_superseded_aggregate_diff(&mut cells, "turn");
    assert!(superseded(&cells));
}

#[test]
fn marks_rename_only_coverage() {
    let diff = "diff --git a/lib/old.dart b/lib/new.dart\nsimilarity index 100%\nrename from lib/old.dart\nrename to lib/new.dart";
    let mut cells = vec![
        aggregate(diff),
        structured(json!([{
            "path": "lib/old.dart",
            "kind": {"type": "update", "move_path": "lib/new.dart"},
            "diff": ""
        }])),
    ];
    mark_superseded_aggregate_diff(&mut cells, "turn");
    assert!(superseded(&cells));
}

#[test]
fn marks_rename_with_matching_hunks_and_move_suffix() {
    let diff = "diff --git a/lib/old.dart b/lib/new.dart\n--- a/lib/old.dart\n+++ b/lib/new.dart\n@@ -1 +1 @@\n-old\n+new";
    let mut cells = vec![
        aggregate(diff),
        structured(json!([{
            "path": "lib/old.dart",
            "kind": {"type": "update", "move_path": "lib/new.dart"},
            "diff": "@@ -1 +1 @@\n-old\n+new\n\nMoved to: lib/new.dart"
        }])),
    ];
    mark_superseded_aggregate_diff(&mut cells, "turn");
    assert!(superseded(&cells));
}

#[test]
fn keeps_rename_with_different_destination_and_matching_hunks() {
    let diff = "diff --git a/lib/old.dart b/lib/new.dart\n--- a/lib/old.dart\n+++ b/lib/new.dart\n@@ -1 +1 @@\n-old\n+new";
    let mut cells = vec![
        aggregate(diff),
        structured(json!([{
            "path": "lib/old.dart",
            "kind": {"type": "update", "move_path": "lib/other.dart"},
            "diff": "@@ -1 +1 @@\n-old\n+new"
        }])),
    ];
    mark_superseded_aggregate_diff(&mut cells, "turn");
    assert!(!superseded(&cells));
}

#[test]
fn keeps_mode_changes_with_matching_hunks() {
    let diff = "diff --git a/script.sh b/script.sh\nold mode 100644\nnew mode 100755\n--- a/script.sh\n+++ b/script.sh\n@@ -1 +1 @@\n-old\n+new";
    let mut cells = vec![
        aggregate(diff),
        structured(json!([{
            "path": "script.sh",
            "kind": {"type": "update"},
            "diff": "@@ -1 +1 @@\n-old\n+new"
        }])),
    ];
    mark_superseded_aggregate_diff(&mut cells, "turn");
    assert!(!superseded(&cells));
}

#[test]
fn keeps_nonstandard_deleted_file_modes() {
    let diff = "diff --git a/script.sh b/script.sh\ndeleted file mode 100755\n--- a/script.sh\n+++ /dev/null\n@@ -1 +0,0 @@\n-old";
    let mut cells = vec![
        aggregate(diff),
        structured(json!([{
            "path": "script.sh",
            "kind": {"type": "delete"},
            "diff": "old\n"
        }])),
    ];
    mark_superseded_aggregate_diff(&mut cells, "turn");
    assert!(!superseded(&cells));
}

#[test]
fn keeps_additional_hunks_on_the_same_path() {
    let diff = "diff --git a/lib/a.dart b/lib/a.dart\n--- a/lib/a.dart\n+++ b/lib/a.dart\n@@ -1 +1 @@\n-old\n+new\n@@ -8 +8 @@\n-before\n+after";
    let mut cells = vec![
        aggregate(diff),
        structured(json!([{
            "path": "lib/a.dart",
            "kind": {"type": "update"},
            "diff": "@@ -1 +1 @@\n-old\n+new"
        }])),
    ];
    mark_superseded_aggregate_diff(&mut cells, "turn");
    assert!(!superseded(&cells));
}

#[test]
fn keeps_uncovered_header_only_sections_in_mixed_diffs() {
    let diff = "diff --git a/lib/a.dart b/lib/a.dart\n--- a/lib/a.dart\n+++ b/lib/a.dart\n@@ -1 +1 @@\n-old\n+new\ndiff --git a/image.png b/image.png\nBinary files a/image.png and b/image.png differ";
    let mut cells = vec![
        aggregate(diff),
        structured(json!([{
            "path": "lib/a.dart",
            "kind": {"type": "update"},
            "diff": "@@ -1 +1 @@\n-old\n+new"
        }])),
    ];
    mark_superseded_aggregate_diff(&mut cells, "turn");
    assert!(!superseded(&cells));
}
