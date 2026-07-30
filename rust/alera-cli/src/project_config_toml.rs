//! Parses a project's `alera.toml` into a [`ProjectConfig`].
//!
//! Split out of `worktree_setup.rs`, which keeps the execution side: applying
//! the copy rules and running the setup commands.

use alera_core::runtime::{NewWorkspaceConfig, ProjectConfig, WorktreeCopyRule};
use anyhow::{anyhow, bail, Context, Result};

pub(crate) fn parse_project_config_toml(contents: &str) -> Result<ProjectConfig> {
    let value: toml::Value = toml::from_str(contents).context("Invalid alera.toml")?;
    let Some(root) = value.as_table() else {
        bail!("alera.toml must contain a table");
    };
    let git_hosting_provider = parse_git_hosting_provider(root.get("git_hosting_provider"))?;
    let new_workspace = parse_new_workspace_config(root.get("new_workspace"))?;
    let Some(worktree) = root.get("worktree") else {
        return Ok(ProjectConfig {
            new_workspace,
            git_hosting_provider,
            ..ProjectConfig::default()
        });
    };
    let Some(worktree) = worktree.as_table() else {
        bail!("alera.toml [worktree] must be a table");
    };
    let copy = parse_copy_rules(worktree.get("copy"))?;
    let setup = parse_setup_commands(worktree.get("setup"))?;
    Ok(ProjectConfig {
        worktree: alera_core::runtime::WorktreeSetupConfig { copy, setup },
        new_workspace,
        git_hosting_provider,
    })
}

fn parse_new_workspace_config(value: Option<&toml::Value>) -> Result<NewWorkspaceConfig> {
    let Some(value) = value else {
        return Ok(NewWorkspaceConfig::default());
    };
    let Some(table) = value.as_table() else {
        bail!("alera.toml [new_workspace] must be a table");
    };
    let prompt_append = table
        .get("prompt_append")
        .map(|value| {
            value
                .as_str()
                .map(str::trim)
                .map(str::to_string)
                .ok_or_else(|| anyhow!("new_workspace.prompt_append must be a string"))
        })
        .transpose()?
        .unwrap_or_default();
    Ok(NewWorkspaceConfig { prompt_append })
}

fn parse_git_hosting_provider(value: Option<&toml::Value>) -> Result<Option<String>> {
    let Some(value) = value else {
        return Ok(None);
    };
    let Some(raw) = value.as_str() else {
        bail!("git_hosting_provider must be a string");
    };
    match raw.trim().to_lowercase().as_str() {
        "github" | "githubenterprise" | "github_enterprise" | "github-enterprise" => {
            Ok(Some("github".to_string()))
        }
        "azuredevops" | "azure_devops" | "azure-devops" | "azure" => {
            Ok(Some("azureDevops".to_string()))
        }
        "gitlab" | "git_lab" | "git-lab" => Ok(Some("gitlab".to_string())),
        _ => bail!(
            "git_hosting_provider must be one of: github, githubEnterprise, azureDevops, gitlab"
        ),
    }
}

fn parse_copy_rules(value: Option<&toml::Value>) -> Result<Vec<WorktreeCopyRule>> {
    let Some(value) = value else {
        return Ok(Vec::new());
    };
    let Some(items) = value.as_array() else {
        bail!("worktree.copy must be a list");
    };
    let mut rules = Vec::with_capacity(items.len());
    for (index, item) in items.iter().enumerate() {
        let Some(table) = item.as_table() else {
            bail!("worktree.copy[{index}] must be a table");
        };
        let from = required_string(table.get("from"), &format!("worktree.copy[{index}].from"))?;
        let to = optional_string(table.get("to"), &format!("worktree.copy[{index}].to"))?;
        let overwrite = table
            .get("overwrite")
            .map(|value| {
                value
                    .as_bool()
                    .ok_or_else(|| anyhow!("worktree.copy[{index}].overwrite must be a boolean"))
            })
            .transpose()?
            .unwrap_or(false);
        rules.push(WorktreeCopyRule {
            from: normalize_config_path(&from, &format!("worktree.copy[{index}].from"))?,
            to: to
                .map(|value| normalize_config_path(&value, &format!("worktree.copy[{index}].to")))
                .transpose()?,
            overwrite,
        });
    }
    Ok(rules)
}

fn parse_setup_commands(value: Option<&toml::Value>) -> Result<Vec<String>> {
    let Some(value) = value else {
        return Ok(Vec::new());
    };
    let Some(items) = value.as_array() else {
        bail!("worktree.setup must be a list");
    };
    let mut commands = Vec::with_capacity(items.len());
    for (index, item) in items.iter().enumerate() {
        commands.push(required_string(
            Some(item),
            &format!("worktree.setup[{index}]"),
        )?);
    }
    Ok(commands)
}

fn required_string(value: Option<&toml::Value>, label: &str) -> Result<String> {
    let Some(value) = value else {
        bail!("{label} must be a non-empty string");
    };
    let Some(value) = value.as_str() else {
        bail!("{label} must be a non-empty string");
    };
    let trimmed = value.trim();
    if trimmed.is_empty() {
        bail!("{label} must be a non-empty string");
    }
    Ok(trimmed.to_string())
}

fn optional_string(value: Option<&toml::Value>, label: &str) -> Result<Option<String>> {
    match value {
        Some(value) => required_string(Some(value), label).map(Some),
        None => Ok(None),
    }
}

pub(crate) fn normalize_config_path(value: &str, label: &str) -> Result<String> {
    let path = value.trim().replace('\\', "/");
    if path.is_empty() {
        bail!("{label} must be a non-empty string");
    }
    if path.starts_with('/') || path.contains(':') {
        bail!("{label} Must Be a Relative Path");
    }
    let mut parts = Vec::new();
    for part in path.split('/') {
        if part.is_empty() || part == "." {
            continue;
        }
        if part == ".." {
            bail!("{label} Must Stay Inside the Project");
        }
        parts.push(part);
    }
    if parts.is_empty() {
        bail!("{label} must be a non-empty string");
    }
    Ok(parts.join("/"))
}

#[cfg(test)]
mod tests {
    use super::parse_project_config_toml;

    #[test]
    fn project_config_accepts_gitlab_hosting_provider() {
        let config = parse_project_config_toml("git_hosting_provider = \"gitlab\"").unwrap();
        assert_eq!(config.git_hosting_provider.as_deref(), Some("gitlab"));
    }

    #[test]
    fn project_config_accepts_github_enterprise_alias() {
        let config =
            parse_project_config_toml("git_hosting_provider = \"githubEnterprise\"").unwrap();
        assert_eq!(config.git_hosting_provider.as_deref(), Some("github"));
    }

    #[test]
    fn project_config_reads_new_workspace_prompt_append() {
        let config = parse_project_config_toml(
            r#"
[new_workspace]
prompt_append = """
Run The Focused Tests.
Preserve Existing APIs.
"""
"#,
        )
        .unwrap();
        assert_eq!(
            config.new_workspace.prompt_append,
            "Run The Focused Tests.\nPreserve Existing APIs."
        );
    }
}
