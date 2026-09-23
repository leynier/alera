mod app_support_dir;
mod cli;
mod cli_binary;
mod debug;
mod debug_processes;
mod flavor;
mod init_submodules;
mod spawn;

use clap::{error::ErrorKind, Parser};

use cli::{Command, Xtask};
use debug::DebugContext;

fn main() {
    let xtask = match Xtask::try_parse() {
        Ok(xtask) => xtask,
        Err(error) => {
            let _ = error.print();
            let code = match error.kind() {
                ErrorKind::DisplayHelp | ErrorKind::DisplayVersion => 0,
                _ => 64,
            };
            std::process::exit(code);
        }
    };
    let code = match dispatch(xtask) {
        Ok(code) => code,
        Err(error) => {
            eprintln!("{error:#}");
            1
        }
    };
    if code != 0 {
        std::process::exit(code);
    }
}

fn dispatch(xtask: Xtask) -> anyhow::Result<i32> {
    match xtask.command {
        Command::InitSubmodules(args) => {
            let repo_root = args
                .repo_root
                .unwrap_or_else(|| std::env::current_dir().expect("current directory"));
            match init_submodules::run(repo_root) {
                Ok(()) => Ok(0),
                Err(error) => {
                    init_submodules::eprint_failure(error);
                    Ok(1)
                }
            }
        }
        Command::CliBuild(args) => DebugContext::new(args)?.cli_build(),
        Command::CliHelp(args) => DebugContext::new(args)?.cli_help(),
        Command::RuntimeDevBuild(args) => DebugContext::new(args)?.runtime_dev_build(),
        Command::HostDebug(args) => DebugContext::new(args)?.host_debug_foreground(),
        Command::AppDebug(args) => DebugContext::new(args)?.app_debug(),
        Command::AppProfile(args) => DebugContext::new(args)?.app_profile(),
        Command::AppDebugBundledCli(args) => DebugContext::new(args)?.app_debug_bundled_cli(),
        Command::AppDebugRuntimeDev(args) => DebugContext::new(args)?.app_debug_runtime_dev(),
        Command::DebugProcesses(args) => DebugContext::new(args)?.debug_processes(),
        Command::HostStop(args) => DebugContext::new(args)?.host_stop(),
    }
}

#[cfg(test)]
mod makefile_contract_tests {
    use std::fs;
    use std::path::PathBuf;

    fn repo_file(relative: &str) -> String {
        let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .join(relative);
        fs::read_to_string(&path).unwrap_or_else(|error| {
            panic!("read {}: {error}", path.display());
        })
    }

    #[test]
    fn makefile_invokes_alera_xtask_not_dart() {
        let makefile = repo_file("makefile");
        assert!(makefile.contains("ALERA_XTASK"));
        assert!(makefile.contains("init-submodules"));
        assert!(makefile.contains("ALERA_RUNTIME_DEV_BUNDLE_DIR ?= .dart_tool/alera-dev"));
        assert!(makefile.contains("runtime-dev-build:"));
        assert!(makefile.contains("app-debug-runtime-dev:"));
        assert!(!makefile.contains("tool/debug/alera_debug.dart"));
        assert!(!makefile.contains("tool/development/initialize_required_submodules.dart"));
        assert!(!makefile.contains("$(DART) $(ALERA_DEBUG_TOOL)"));
    }

    #[test]
    fn runtime_dev_guard_lives_in_xtask() {
        let source = repo_file("rust/alera-xtask/src/debug.rs");
        assert!(source.contains("The dev runtime can only be launched with the dev flavor."));
        assert!(source.contains("ALERA_CLI_BUNDLE_DIR"));
        assert!(
            source.contains("build_cli(None, false)")
                || source.contains("build_cli(Some(&output_dir), false)")
        );
    }
}
