use std::process::Command;

fn main() {
    let cli_manifest =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../rust/alera-cli/Cargo.toml");
    println!("cargo:rerun-if-changed={}", cli_manifest.display());
    println!("cargo:rerun-if-env-changed=ALERA_BUILD_COMMIT");
    println!("cargo:rerun-if-env-changed=ALERA_BUILD_VERSION");
    let cli_version = std::env::var("ALERA_BUILD_VERSION")
        .ok()
        .filter(|version| !version.trim().is_empty())
        .or_else(|| {
            std::fs::read_to_string(&cli_manifest)
                .ok()
                .and_then(|manifest| {
                    let package = manifest.split_once("[package]")?.1;
                    package.lines().find_map(|line| {
                        let (key, value) = line.split_once('=')?;
                        (key.trim() == "version").then(|| value.trim().trim_matches('"').to_owned())
                    })
                })
        })
        .filter(|version| !version.is_empty())
        .unwrap_or_else(|| "0.1.0".to_owned());
    println!("cargo:rustc-env=ALERA_RUNTIME_BUNDLED_VERSION={cli_version}");

    // The Flutter client compares the bundled CLI identity with the live
    // runtime host. GPUI must publish the same commit instead of treating an
    // unknown bundled build as always compatible.
    watch_git_state();
    let commit = std::env::var("ALERA_BUILD_COMMIT")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .or_else(git_commit)
        .unwrap_or_else(|| "unknown".to_owned());
    println!("cargo:rustc-env=ALERA_BUILD_COMMIT={commit}");

    #[cfg(target_os = "linux")]
    configure_linux();
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

// Build scripts run under cargo, outside the desktop process-spawn boundary.
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
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_owned())
        .filter(|value| !value.is_empty())
}

#[cfg(target_os = "linux")]
fn configure_linux() {
    use std::path::{Path, PathBuf};

    const SEARCH_ROOTS: &[&str] = &[
        "/usr/lib/x86_64-linux-gnu",
        "/lib/x86_64-linux-gnu",
        "/usr/lib/aarch64-linux-gnu",
        "/lib/aarch64-linux-gnu",
        "/usr/lib64",
        "/lib64",
    ];

    println!("cargo:rerun-if-env-changed=OUT_DIR");
    if SEARCH_ROOTS
        .iter()
        .map(Path::new)
        .any(|root| root.join("libxkbcommon-x11.so").exists())
    {
        return;
    }

    let Some(runtime_library) = SEARCH_ROOTS
        .iter()
        .map(Path::new)
        .map(|root| root.join("libxkbcommon-x11.so.0"))
        .find(|candidate| candidate.exists())
    else {
        println!(
            "cargo:warning=libxkbcommon-x11 was not found; install the platform development package"
        );
        return;
    };
    let output_directory = PathBuf::from(
        std::env::var_os("OUT_DIR").expect("Cargo did not provide an output directory"),
    );
    let linker_name = output_directory.join("libxkbcommon-x11.so");
    if !linker_name.exists() {
        std::os::unix::fs::symlink(runtime_library, &linker_name)
            .expect("failed to expose the installed xkbcommon-x11 runtime library to the linker");
    }
    println!(
        "cargo:rustc-link-search=native={}",
        output_directory.display()
    );
}
