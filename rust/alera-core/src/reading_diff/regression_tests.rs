// SPDX-License-Identifier: Apache-2.0
// Ported and modified from Meat revision f39f41dfe7b5b37a12b35fdfbaecc7e779855bd3.

use super::compile;

const EMPTY_PLAN: &str =
    r#"{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep behavior."}"#;

#[test]
fn preserves_behavior_after_an_import_on_the_same_row() {
    let diff = b"diff --git a/a.py b/a.py\n--- a/a.py\n+++ b/a.py\n@@ -1 +1 @@\n-import old; print(\"old\")\n+import new; print(\"new\")\n";

    let result = compile(diff, EMPTY_PLAN).expect("inline statements");

    assert_eq!(result.reading_diff, diff);
}

#[test]
fn ignores_comment_and_string_delimiters_while_scanning_imports() {
    let diff = b"diff --git a/a.py b/a.py\n--- a/a.py\n+++ b/a.py\n@@ -1,2 +1,2 @@\n-import old  # (\n-print(\")\")\n+import new  # (\n+print(\"changed)\")\n";

    let result = compile(diff, EMPTY_PLAN).expect("non-syntax delimiters");
    let text = String::from_utf8(result.reading_diff).expect("utf8 result");

    assert!(!text.contains("import old"));
    assert!(!text.contains("import new"));
    assert!(text.contains("-print(\")\")"));
    assert!(text.contains("+print(\"changed)\")"));
}

#[test]
fn preserves_format_patch_trailers_after_import_only_files() {
    let diff = b"From abc Mon Sep 17 00:00:00 2001\nSubject: [PATCH] imports\n\ndiff --git a/a.py b/a.py\nindex 1111111..2222222 100644\n--- a/a.py\n+++ b/a.py\n@@ -1 +1 @@\n-import old\n+import new\n-- \n2.39.0\n";

    let result = compile(diff, EMPTY_PLAN).expect("format-patch trailer");

    assert_eq!(
        result.reading_diff,
        b"From abc Mon Sep 17 00:00:00 2001\nSubject: [PATCH] imports\n\n-- \n2.39.0\n"
    );
}
