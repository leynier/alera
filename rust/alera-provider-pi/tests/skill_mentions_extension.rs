//! Runs the injected Pi input hook under Node with a stand-in extension API.
//! Pi itself loads the hook, so the test is skipped where Node is missing.

use std::path::Path;
use std::process::Command;

const HOOK: &str = include_str!("../src/skill_mentions_extension.mjs");

const HARNESS: &str = r#"
import { registerSkillMentions } from "./skill_mentions_extension.mjs";

const [deploy, review, missing] = process.argv.slice(2);
let hook;
const notices = [];
const pi = {
  on(name, handler) { if (name === "input") hook = handler; },
  getCommands: () => [
    { name: "skill:deploy", source: "skill", sourceInfo: { path: deploy } },
    { name: "skill:review", source: "skill", sourceInfo: { path: review } },
    { name: "skill:gone", source: "skill", sourceInfo: { path: missing } },
    { name: "deploy", source: "prompt", sourceInfo: { path: "/unused" } },
  ],
};
registerSkillMentions(pi);
const ctx = { ui: { notify: (message, level) => notices.push([message, level]) } };
const results = [];
for (const text of [
  "Ship it: $deploy then $review and $deploy again, not $25 or a$review",
  "/skill:deploy now run $deploy and $gone",
  "no mentions here",
  "$unknown",
]) {
  results.push(await hook({ text, images: [{ type: "image" }] }, ctx) ?? null);
}
console.log(JSON.stringify({ results, notices }));
"#;

// A test-only Node child; no Windows GUI host spawns it, so no console
// window can appear.
#[allow(clippy::disallowed_methods)]
#[test]
fn dollar_mentions_append_skill_bodies_like_t3_code() {
    if Command::new("node").arg("--version").output().is_err() {
        eprintln!("node is not installed; skipping the Pi input hook test");
        return;
    }
    let directory = std::env::temp_dir().join(format!(
        "alera-pi-skill-hook-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(directory.join("deploy")).unwrap();
    std::fs::create_dir_all(directory.join("review")).unwrap();
    let deploy = directory.join("deploy/SKILL.md");
    let review = directory.join("review/SKILL.md");
    std::fs::write(
        &deploy,
        "---\r\nname: deploy\r\ndescription: Deploy.\r\n---\r\n\r\nRun the deploy script.\r\n",
    )
    .unwrap();
    std::fs::write(&review, "Read the diff first.\n").unwrap();
    std::fs::write(directory.join("skill_mentions_extension.mjs"), HOOK).unwrap();
    std::fs::write(directory.join("harness.mjs"), HARNESS).unwrap();
    let output = Command::new("node")
        .arg(directory.join("harness.mjs"))
        .arg(&deploy)
        .arg(&review)
        .arg(directory.join("gone/SKILL.md"))
        .output()
        .unwrap();
    let result = String::from_utf8(output.stdout).unwrap();
    let missing = directory.join("gone/SKILL.md");
    std::fs::remove_dir_all(&directory).unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let result: serde_json::Value = serde_json::from_str(&result).unwrap();
    let block = |name: &str, path: &Path, body: &str| {
        format!(
            "<skill name=\"{name}\" location=\"{}\">\nReferences are relative to {}.\n\n{body}\n</skill>",
            path.display(),
            path.parent().unwrap().display()
        )
    };
    assert_eq!(
        result["results"][0],
        serde_json::json!({
            "action": "transform",
            "text": format!(
                "Ship it: $deploy then $review and $deploy again, not $25 or a$review\n\n{}\n\n{}",
                block("deploy", &deploy, "Run the deploy script."),
                block("review", &review, "Read the diff first.")
            ),
            "images": [{ "type": "image" }]
        })
    );
    // Pi already expands the leading `/skill:deploy`, and an unreadable skill
    // is reported instead of appended.
    assert_eq!(result["results"][1], serde_json::Value::Null);
    assert_eq!(
        result["notices"],
        serde_json::json!([[
            format!("Could not load skill gone from {}.", missing.display()),
            "error"
        ]])
    );
    assert_eq!(result["results"][2], serde_json::Value::Null);
    assert_eq!(result["results"][3], serde_json::Value::Null);
}
