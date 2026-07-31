#[cfg(target_os = "linux")]
fn main() {
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

#[cfg(not(target_os = "linux"))]
fn main() {}
