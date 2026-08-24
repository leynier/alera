use std::path::{Path, PathBuf};

use alera_core::child_process::windowless_command;

#[derive(Clone, Debug, Eq, PartialEq)]
struct RevealCommand {
    executable: &'static str,
    arguments: Vec<String>,
}

pub fn reveal_in_file_manager(path: &Path) -> Result<(), String> {
    if !path.exists() {
        return Err("Path Was Not Found".to_string());
    }
    for command in reveal_commands(path) {
        let status = windowless_command(command.executable)
            .args(command.arguments)
            .status();
        if status.is_ok_and(|status| status.success()) {
            return Ok(());
        }
    }
    Err("Could Not Reveal Item In The File Manager".to_string())
}

fn reveal_commands(path: &Path) -> Vec<RevealCommand> {
    reveal_commands_for_platform(path, std::env::consts::OS)
}

fn reveal_commands_for_platform(path: &Path, platform: &str) -> Vec<RevealCommand> {
    let path = path.to_string_lossy().into_owned();
    match platform {
        "macos" => vec![RevealCommand {
            executable: "open",
            arguments: vec!["-R".to_string(), path],
        }],
        "windows" => vec![RevealCommand {
            executable: "explorer.exe",
            arguments: vec![format!("/select,{path}")],
        }],
        _ => {
            let parent = PathBuf::from(&path)
                .parent()
                .unwrap_or_else(|| Path::new(&path))
                .to_string_lossy()
                .into_owned();
            vec![
                RevealCommand {
                    executable: "xdg-open",
                    arguments: vec![parent.clone()],
                },
                RevealCommand {
                    executable: "gio",
                    arguments: vec!["open".to_string(), parent],
                },
            ]
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reveal_commands_match_each_desktop_platform() {
        let path = Path::new("/workspace/src/main.rs");
        assert_eq!(
            reveal_commands_for_platform(path, "macos"),
            [RevealCommand {
                executable: "open",
                arguments: vec!["-R".to_string(), "/workspace/src/main.rs".to_string()],
            }]
        );
        assert_eq!(
            reveal_commands_for_platform(path, "windows")[0].executable,
            "explorer.exe"
        );
        assert_eq!(
            reveal_commands_for_platform(path, "linux")[0],
            RevealCommand {
                executable: "xdg-open",
                arguments: vec!["/workspace/src".to_string()],
            }
        );
    }
}
