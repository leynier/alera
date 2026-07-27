use std::process::Command;

fn main() {
    println!("cargo:rerun-if-env-changed=ALERA_BUILD_COMMIT");
    println!("cargo:rerun-if-env-changed=ALERA_BUILD_VERSION");
    watch_git_state();

    let commit = std::env::var("ALERA_BUILD_COMMIT")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .or_else(git_commit)
        .unwrap_or_else(|| "unknown".to_string());
    println!("cargo:rustc-env=ALERA_BUILD_COMMIT={commit}");

    if let Ok(version) = std::env::var("ALERA_BUILD_VERSION") {
        if !version.trim().is_empty() {
            println!("cargo:rustc-env=ALERA_BUILD_VERSION={version}");
        }
    }
}

fn git_commit() -> Option<String> {
    git_output(&["rev-parse", "HEAD"])
}

fn watch_git_state() {
    for name in ["HEAD", "refs", "packed-refs"] {
        if let Some(path) = git_output(&["rev-parse", "--path-format=absolute", "--git-path", name])
        {
            println!("cargo:rerun-if-changed={path}");
        }
    }
    if let Some(reference) = git_output(&["symbolic-ref", "-q", "HEAD"]) {
        if let Some(path) = git_output(&[
            "rev-parse",
            "--path-format=absolute",
            "--git-path",
            &reference,
        ]) {
            println!("cargo:rerun-if-changed={path}");
        }
    }
}

// Build script: it runs under cargo in a console, so the console-window
// suppression in `alera_core::child_process` does not apply.
#[allow(clippy::disallowed_methods)]
fn git_output(arguments: &[&str]) -> Option<String> {
    let output = Command::new("git")
        .args(arguments)
        .current_dir(std::env::var_os("CARGO_MANIFEST_DIR")?)
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_string())
        .filter(|value| !value.is_empty())
}
