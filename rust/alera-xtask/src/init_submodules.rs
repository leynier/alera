use std::io::{self, Write};
use std::path::{Path, PathBuf};

use alera_core::child_process::windowless_command;

use crate::spawn::quote_for_log;

const REQUIRED_SUBMODULES: &[&str] = &["third_party/xterm", "third_party/dart_terminal"];

#[derive(Debug)]
pub struct CommandFailure(pub String);

impl std::fmt::Display for CommandFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for CommandFailure {}

#[derive(Debug)]
struct CommandResult {
    exit_code: i32,
    stdout: String,
    stderr: String,
}

pub fn run(repo_root: PathBuf) -> Result<(), CommandFailure> {
    run_with_submodules(repo_root, REQUIRED_SUBMODULES)
}

pub fn run_with_submodules(repo_root: PathBuf, submodules: &[&str]) -> Result<(), CommandFailure> {
    let repo_root = if repo_root.is_absolute() {
        repo_root
    } else {
        std::env::current_dir()
            .map_err(|error| CommandFailure(error.to_string()))?
            .join(repo_root)
    };
    SubmoduleInitializer {
        repo_root,
        submodules: submodules.iter().map(|path| (*path).to_string()).collect(),
    }
    .run()
}

struct SubmoduleInitializer {
    repo_root: PathBuf,
    submodules: Vec<String>,
}

impl SubmoduleInitializer {
    fn run(&self) -> Result<(), CommandFailure> {
        let git_dir = self.repo_root.join(".git");
        if !git_dir.is_dir() && !git_dir.is_file() {
            return Err(CommandFailure(format!(
                "Repository metadata was not found. Run this command from the Alera \
                 checkout.\n{}",
                self.repo_root.display()
            )));
        }

        self.git(&["submodule", "sync", "--recursive"], None, false)?;
        for path in &self.submodules {
            self.checkout_submodule(&self.repo_root, path)?;
        }
        println!("Required Alera submodules are ready.");
        Ok(())
    }

    fn checkout_submodule(&self, parent: &Path, relative_path: &str) -> Result<(), CommandFailure> {
        let expected_commit = self
            .git(
                &["rev-parse", &format!("HEAD:{relative_path}")],
                Some(parent),
                false,
            )?
            .stdout
            .trim()
            .to_string();
        let directory = join(parent, relative_path);

        self.git(
            &["submodule", "sync", "--", relative_path],
            Some(parent),
            false,
        )?;
        self.git(
            &["submodule", "init", "--", relative_path],
            Some(parent),
            false,
        )?;

        if is_git_checkout(&directory) {
            self.refuse_dirty_checkout(&directory, &expected_commit)?;
        }

        let update = self.git(
            &["submodule", "update", "--init", "--", relative_path],
            Some(parent),
            true,
        )?;
        if update.exit_code != 0 {
            if !is_git_checkout(&directory) {
                return Err(CommandFailure(format!(
                    "Git could not initialize {relative_path}.\n{}",
                    update.stderr.trim()
                )));
            }
            println!("Fetching missing pinned commit {expected_commit} for {relative_path}...");
            self.git(
                &["fetch", "--no-tags", "origin", &expected_commit],
                Some(&directory),
                false,
            )?;
            self.git(
                &["checkout", "--detach", &expected_commit],
                Some(&directory),
                false,
            )?;
        }

        let actual_commit = self
            .git(&["rev-parse", "HEAD"], Some(&directory), false)?
            .stdout
            .trim()
            .to_string();
        if actual_commit != expected_commit {
            return Err(CommandFailure(format!(
                "{relative_path} is at {actual_commit} instead of {expected_commit}."
            )));
        }

        for nested_path in nested_submodule_paths(&directory)? {
            self.checkout_submodule(&directory, &nested_path)?;
        }
        Ok(())
    }

    fn refuse_dirty_checkout(
        &self,
        directory: &Path,
        expected_commit: &str,
    ) -> Result<(), CommandFailure> {
        let current_commit = self.git(&["rev-parse", "HEAD"], Some(directory), true)?;
        if current_commit.exit_code == 0 && current_commit.stdout.trim() == expected_commit {
            return Ok(());
        }
        let status = self.git(
            &["status", "--porcelain", "--untracked-files=all"],
            Some(directory),
            false,
        )?;
        if !status.stdout.trim().is_empty() {
            return Err(CommandFailure(format!(
                "Refusing to move {} to {expected_commit} because the \
                 submodule contains local changes. Commit, stash, or remove those \
                 changes first.",
                directory.display()
            )));
        }
        Ok(())
    }

    fn git(
        &self,
        arguments: &[&str],
        working_directory: Option<&Path>,
        allow_failure: bool,
    ) -> Result<CommandResult, CommandFailure> {
        let cwd = working_directory.unwrap_or(&self.repo_root);
        let logged = arguments
            .iter()
            .map(|argument| quote_for_log(argument))
            .collect::<Vec<_>>()
            .join(" ");
        println!("{}> git {logged}", cwd.display());

        let output = windowless_command("git")
            .args(arguments)
            .current_dir(cwd)
            .output()
            .map_err(|error| {
                CommandFailure(format!(
                    "Git failed in {}: git {}\n{error}",
                    cwd.display(),
                    arguments.join(" ")
                ))
            })?;
        let result = CommandResult {
            exit_code: output.status.code().unwrap_or(1),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        };
        if !allow_failure && result.exit_code != 0 {
            return Err(CommandFailure(format!(
                "Git failed in {}: git {}\n{}",
                cwd.display(),
                arguments.join(" "),
                result.stderr.trim()
            )));
        }
        Ok(result)
    }
}

fn is_git_checkout(directory: &Path) -> bool {
    if !directory.exists() {
        return false;
    }
    windowless_command("git")
        .args(["rev-parse", "--git-dir"])
        .current_dir(directory)
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

fn nested_submodule_paths(directory: &Path) -> Result<Vec<String>, CommandFailure> {
    let modules = directory.join(".gitmodules");
    if !modules.is_file() {
        return Ok(Vec::new());
    }
    let output = windowless_command("git")
        .args([
            "config",
            "--file",
            ".gitmodules",
            "--get-regexp",
            r"^submodule\..*\.path$",
        ])
        .current_dir(directory)
        .output()
        .map_err(|error| {
            CommandFailure(format!(
                "Could not read nested submodules in {}.\n{error}",
                directory.display()
            ))
        })?;
    parse_nested_submodule_paths(
        output.status.code().unwrap_or(1),
        &String::from_utf8_lossy(&output.stdout),
        &String::from_utf8_lossy(&output.stderr),
        directory,
    )
}

pub fn parse_nested_submodule_paths(
    exit_code: i32,
    stdout: &str,
    stderr: &str,
    directory: &Path,
) -> Result<Vec<String>, CommandFailure> {
    if exit_code == 1 && stdout.trim().is_empty() {
        return Ok(Vec::new());
    }
    if exit_code != 0 {
        return Err(CommandFailure(format!(
            "Could not read nested submodules in {}.\n{}",
            directory.display(),
            stderr.trim()
        )));
    }
    Ok(stdout
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .filter_map(|line| line.split_whitespace().last().map(str::to_string))
        .filter(|path| !path.is_empty())
        .collect())
}

fn join(first: &Path, second: &str) -> PathBuf {
    first.join(second.replace('\\', "/"))
}

pub fn eprint_failure(error: CommandFailure) {
    let _ = writeln!(io::stderr(), "{}", error.0);
}

#[cfg(test)]
#[path = "init_submodules_tests.rs"]
mod tests;
