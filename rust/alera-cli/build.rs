use std::process::Command;

fn main() {
    println!("cargo:rerun-if-env-changed=ALERA_BUILD_COMMIT");
    println!("cargo:rerun-if-env-changed=ALERA_BUILD_VERSION");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows")
        && std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc")
    {
        // The terminal-host actor owns deeply nested async futures; match the
        // stack reservation it receives by default on Unix hosts.
        println!("cargo:rustc-link-arg-bin=alera=/STACK:8388608");
    }
    let commit = std::env::var("ALERA_BUILD_COMMIT")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .or_else(|| {
            // Explicit check identities must not depend on the checkout's HEAD.
            watch_git_state();
            git_commit()
        })
        .unwrap_or_else(|| "unknown".to_string());
    println!("cargo:rustc-env=ALERA_BUILD_COMMIT={commit}");

    // Make clears inherited check overrides by exporting an empty value.
    let version = std::env::var("ALERA_BUILD_VERSION")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| std::env::var("CARGO_PKG_VERSION").expect("Cargo package version"));
    println!("cargo:rustc-env=ALERA_BUILD_VERSION={version}");
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
