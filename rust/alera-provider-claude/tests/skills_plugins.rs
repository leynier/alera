mod skill_fixtures;

use alera_provider_claude::{
    discover_skills, plan_claude_skill_dispatch, user_invocable_skills, ClaudeProviderConfig,
};
use serde_json::json;
use skill_fixtures::*;
use std::path::Path;

fn names(config: &ClaudeProviderConfig) -> Vec<String> {
    discover_skills(config)
        .into_iter()
        .map(|skill| skill.name)
        .collect()
}

fn summary(config: &ClaudeProviderConfig) -> Vec<(String, String, String)> {
    discover_skills(config)
        .into_iter()
        .map(|skill| (skill.name, skill.scope.unwrap_or_default(), skill.path))
        .collect()
}

fn row(name: &str, scope: &str, install: &Path) -> (String, String, String) {
    (
        name.into(),
        scope.into(),
        skill_path(&install.join("skills"), "review"),
    )
}

#[test]
fn discovers_enabled_plugin_skills_with_manifest_names_and_ignores_skill_overrides() {
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    let plugin = config_dir.join("plugins/cache/shop/plugin/1.0.0");
    let disabled = config_dir.join("plugins/disabled");
    write_skill(&disabled.join("skills"), "hidden", "# Hidden");
    write_skill(&plugin.join("skills"), "plain", "# Plain");
    write_skill(
        &plugin.join("engineering"),
        "review",
        "---\nname: review-alias\ndescription: Review changes.\ndisable-model-invocation: true\nuser-invocable: false\n---\n",
    );
    write(
        &plugin.join(".claude-plugin/plugin.json"),
        r#"{"name":"manifest-plugin","skills":["./engineering/review"]}"#,
    );
    write(
        &config_dir.join("plugins/installed_plugins.json"),
        &json!({"plugins": {
            "plugin@shop": [{"scope": "user", "installPath": plugin}],
            "disabled@shop": [{"scope": "user", "installPath": disabled}],
            "unconfigured@shop": [{"scope": "user", "installPath": disabled}],
        }})
        .to_string(),
    );
    write(
        &config_dir.join("settings.json"),
        r#"{"enabledPlugins":{"plugin@shop":true,"disabled@shop":false,"uninstalled@shop":true,"other@shop":["^1.0.0"]},"skillOverrides":{"manifest-plugin:plain":"off"}}"#,
    );
    assert_eq!(
        serde_json::to_value(discover_skills(&config(&config_dir, None))).unwrap(),
        json!([
            {
                "name": "manifest-plugin:plain",
                "path": skill_path(&plugin.join("skills"), "plain"),
                "enabled": true,
                "scope": "user"
            },
            {
                "name": "manifest-plugin:review-alias",
                "path": skill_path(&plugin.join("engineering"), "review"),
                "enabled": true,
                "scope": "user",
                "description": "Review changes.",
                "userInvocationOnly": true,
                "userInvocable": false
            }
        ])
    );
}

#[cfg(unix)]
#[test]
fn merges_plugin_enablement_and_selects_installs_in_native_registry_order() {
    use std::os::unix::fs::symlink;
    let temp = TempDir::new();
    let config_dir = temp.join("claude-home");
    let workspace = temp.join("workspace");
    let nested_workspace = workspace.join("packages/app");
    let aliased_workspace = temp.join("aliased-workspace");
    let user_install = config_dir.join("plugins/user");
    let project_install = config_dir.join("plugins/project");
    let local_install = config_dir.join("plugins/local");
    let managed_install = config_dir.join("plugins/managed");
    mkdir(&workspace.join(".git"));
    mkdir(&nested_workspace);
    symlink(&workspace, &aliased_workspace).unwrap();
    for install in [
        &user_install,
        &project_install,
        &local_install,
        &managed_install,
    ] {
        write_skill(&install.join("skills"), "review", "# Review");
    }
    write(
        &config_dir.join("plugins/installed_plugins.json"),
        &json!({"plugins": {
            "plugin@shop": [
                {"scope": "project", "projectPath": aliased_workspace, "installPath": local_install},
                {"scope": "project", "projectPath": workspace, "installPath": project_install},
                {"scope": "user", "installPath": user_install},
                {"scope": "managed", "installPath": managed_install},
            ],
            "local@shop": [
                {"scope": "local", "projectPath": workspace, "installPath": local_install},
                {"scope": "project", "projectPath": workspace, "installPath": project_install},
                {"scope": "managed", "installPath": config_dir.join("plugins/missing")},
                {"scope": "managed", "installPath": managed_install},
                {"scope": "user", "installPath": user_install},
            ],
        }})
        .to_string(),
    );
    write(
        &config_dir.join("settings.json"),
        r#"{"enabledPlugins":{"plugin@shop":true,"local@shop":false}}"#,
    );
    write(
        &workspace.join(".claude/settings.json"),
        r#"{"enabledPlugins":{"plugin@shop":false,"local@shop":true,"other@shop":["^1.0.0"]}}"#,
    );
    let at = |cwd: Option<&Path>| config(&config_dir, cwd);
    let project_settings = summary(&at(Some(&workspace)));
    assert_eq!(
        project_settings,
        [row("local:review", "project", &local_install)]
    );
    assert_eq!(
        summary(&at(Some(&nested_workspace))),
        [row("plugin:review", "project", &project_install)]
    );
    // A file with an invalid override map is ignored whole, plugins included.
    write(
        &workspace.join(".claude/settings.local.json"),
        r#"{"enabledPlugins":{"plugin@shop":true,"local@shop":false},"skillOverrides":{"invalid":"bogus"}}"#,
    );
    assert_eq!(summary(&at(Some(&workspace))), project_settings);
    write(
        &workspace.join(".claude/settings.local.json"),
        r#"{"enabledPlugins":{"plugin@shop":true,"local@shop":true}}"#,
    );
    let local_settings = summary(&at(Some(&workspace)));
    assert_eq!(
        local_settings,
        [
            row("local:review", "project", &local_install),
            row("plugin:review", "project", &project_install),
        ]
    );
    assert_eq!(summary(&at(Some(&nested_workspace))), local_settings);
    assert_eq!(summary(&at(Some(&aliased_workspace))), local_settings);
    write(
        &workspace.join(".claude/settings.local.json"),
        r#"{"enabledPlugins":{"local@shop":["^1.0.0"]}}"#,
    );
    assert!(summary(&at(Some(&workspace))).is_empty());
    write(
        &config_dir.join("settings.json"),
        r#"{"enabledPlugins":{"plugin@shop":true,"local@shop":true}}"#,
    );
    let separate_repository = workspace.join("separate");
    mkdir(&separate_repository.join(".git"));
    let elsewhere = temp.join("elsewhere");
    for cwd in [None, Some(elsewhere.as_path()), Some(&separate_repository)] {
        assert_eq!(
            summary(&at(cwd)),
            [
                row("local:review", "user", &managed_install),
                row("plugin:review", "user", &user_install),
            ]
        );
    }
    let worktree = temp.join("worktree");
    let worktree_git_directory = workspace.join(".git/worktrees/fixture");
    mkdir(&worktree);
    write(
        &worktree.join(".git"),
        &format!("gitdir: {}\n", worktree_git_directory.display()),
    );
    write(&worktree_git_directory.join("commondir"), "../..\n");
    write(
        &worktree_git_directory.join("gitdir"),
        &worktree.join(".git").to_string_lossy(),
    );
    assert_eq!(summary(&at(Some(&worktree))), local_settings);
    let linked_worktree = temp.join("linked-worktree");
    symlink(&worktree, &linked_worktree).unwrap();
    assert_eq!(summary(&at(Some(&linked_worktree))), local_settings);
}

#[test]
fn publishes_and_dispatches_canonical_plugin_folder_names_regardless_of_aliases() {
    let temp = TempDir::new();
    let config_dir = temp.path();
    let plugin = config_dir.join("plugins/installed");
    write_skill(
        &plugin.join("skills"),
        "review",
        "---\nname: review-alias\n---\n",
    );
    write_skill(
        &plugin.join("skills"),
        "alias",
        "---\nname: dot.alias\n---\n",
    );
    write(
        &config_dir.join("plugins/installed_plugins.json"),
        &json!({"plugins": {"plugin@shop": [{"scope": "user", "installPath": plugin}]}})
            .to_string(),
    );
    write(
        &config_dir.join("settings.json"),
        r#"{"enabledPlugins":{"plugin@shop":true}}"#,
    );
    let skills = discover_skills(&config(config_dir, None));
    assert_eq!(
        skills
            .iter()
            .map(|skill| skill.name.as_str())
            .collect::<Vec<_>>(),
        ["plugin:alias", "plugin:review"]
    );
    let dispatch = plan_claude_skill_dispatch(
        "$plugin:alias focus on auth",
        &user_invocable_skills(skills),
    )
    .unwrap();
    assert_eq!(dispatch.leading_text, None);
    assert_eq!(dispatch.command_text, "/plugin:alias focus on auth");
    assert_eq!(dispatch.skill_name, "plugin:alias");
}

#[cfg(unix)]
#[test]
fn uses_the_native_cache_root_root_skill_fallback_and_manifest_path_boundaries() {
    let temp = TempDir::new();
    let workspace = temp.path();
    let config_dir = workspace.join("config");
    let plugins_dir = workspace.join("plugin-cache");
    let plugin = plugins_dir.join("installed");
    let outside = workspace.join("outside");
    write_skill(
        &plugins_dir,
        "installed",
        "---\nname: plugin:root.alias\n---\n",
    );
    write(
        &config_dir.join("settings.json"),
        r#"{"enabledPlugins":{"plugin@shop":true}}"#,
    );
    write(
        &plugins_dir.join("installed_plugins.json"),
        &json!({"plugins": {"plugin@shop": [{"scope": "user", "installPath": plugin}]}})
            .to_string(),
    );
    let mut cached = config(&config_dir, Some(workspace));
    cached
        .options
        .env
        .insert("CLAUDE_CODE_PLUGIN_CACHE_DIR".into(), "plugin-cache".into());
    assert_eq!(names(&cached), ["plugin:root-alias"]);

    write_skill(&plugin.join("skills"), "plain", "# Plain");
    write_skill(&plugin, "custom", "---\nname: custom.review\n---\n");
    write_skill(&outside, "escaped", "# Outside");
    std::os::unix::fs::symlink(&outside, plugin.join("escape")).unwrap();
    write(
        &plugin.join(".claude-plugin/plugin.json"),
        r#"{"skills":["./custom","./escape","../../outside"]}"#,
    );
    assert_eq!(names(&cached), ["plugin:custom-review", "plugin:plain"]);
}

#[test]
fn plugin_names_outside_the_mention_grammar_are_not_advertised() {
    let temp = TempDir::new();
    let config_dir = temp.path();
    let plugin = config_dir.join("plugins/installed");
    write_skill(&plugin.join("skills"), "ok", "# Ok");
    write(
        &plugin.join(".claude-plugin/plugin.json"),
        r#"{"name":"bad prefix"}"#,
    );
    let good = config_dir.join("plugins/good");
    write_skill(&good.join("skills"), "ünïcode", "# Sanitized");
    write(
        &config_dir.join("plugins/installed_plugins.json"),
        &json!({"plugins": {
            "bad@shop": [{"scope": "user", "installPath": plugin}],
            "good@shop": [{"scope": "user", "installPath": good}],
        }})
        .to_string(),
    );
    write(
        &config_dir.join("settings.json"),
        r#"{"enabledPlugins":{"bad@shop":true,"good@shop":true}}"#,
    );
    assert_eq!(names(&config(config_dir, None)), ["good:-n-code"]);
}
