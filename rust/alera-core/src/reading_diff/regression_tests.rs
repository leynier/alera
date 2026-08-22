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
fn preserves_behavior_in_mixed_common_js_declarations() {
    let diff = b"diff --git a/a.js b/a.js\n--- a/a.js\n+++ b/a.js\n@@ -1 +1 @@\n-const fs = require('fs'), server = oldServer();\n+const fs = require('fs'), server = newServer();\n";

    let result = compile(diff, EMPTY_PLAN).expect("mixed CommonJS declarations");

    assert_eq!(result.reading_diff, diff);
}

#[test]
fn elides_single_common_js_import_declarations() {
    let diff = b"diff --git a/a.js b/a.js\n--- a/a.js\n+++ b/a.js\n@@ -1 +1 @@\n-const fs = require('fs');\n+const path = require('path');\n";

    let result = compile(diff, EMPTY_PLAN).expect("CommonJS imports");

    assert!(result.reading_diff.is_empty());
}

#[test]
fn preserves_behavior_chained_from_bare_common_js_requires() {
    let diff = b"diff --git a/a.js b/a.js\n--- a/a.js\n+++ b/a.js\n@@ -1 +1 @@\n-require('./setup').initializeOld();\n+require('./setup').initializeNew();\n";

    let result = compile(diff, EMPTY_PLAN).expect("behavioral CommonJS calls");

    assert_eq!(result.reading_diff, diff);
}

#[test]
fn preserves_mode_metadata_when_common_js_import_hunks_are_elided() {
    let diff = b"diff --git a/a.js b/a.js\nold mode 100644\nnew mode 100755\n--- a/a.js\n+++ b/a.js\n@@ -1 +1 @@\n-const old = require('old');\n+const new = require('new');\n";

    let result = compile(diff, EMPTY_PLAN).expect("mode and CommonJS import change");
    let text = String::from_utf8(result.reading_diff).expect("utf8 result");

    assert!(text.contains("old mode 100644"));
    assert!(text.contains("new mode 100755"));
    assert!(!text.contains("const old"));
    assert!(!text.contains("const new"));
}

#[test]
fn rejects_removing_python_suite_owners_with_inline_comments() {
    let diff = b"diff --git a/a.py b/a.py\n--- a/a.py\n+++ b/a.py\n@@ -1,2 +1,2 @@\n-def old():  # pragma: no cover\n+def new(value='#'):  # pragma: no cover\n     pass\n";
    let plan = r#"{"version":1,"remove":[{"start_line":5,"end_line":6}],"replace":[],"fold":[],"summary":"Hide owner."}"#;

    let error = compile(diff, plan).expect_err("suite owners must remain visible");

    assert!(error.message.contains("suite owner"));
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
