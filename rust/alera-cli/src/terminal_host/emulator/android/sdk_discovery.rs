use std::env;
use std::path::{Path, PathBuf};

pub(super) struct AndroidSdkPaths {
    pub adb: PathBuf,
    pub emulator: PathBuf,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum HostPlatform {
    Linux,
    Macos,
    Windows,
    Other,
}

impl HostPlatform {
    const fn current() -> Self {
        if cfg!(target_os = "linux") {
            Self::Linux
        } else if cfg!(target_os = "macos") {
            Self::Macos
        } else if cfg!(target_os = "windows") {
            Self::Windows
        } else {
            Self::Other
        }
    }

    const fn executable_suffix(self) -> &'static str {
        if matches!(self, Self::Windows) {
            ".exe"
        } else {
            ""
        }
    }
}

struct DiscoveryInputs {
    platform: HostPlatform,
    sdk_root: Option<PathBuf>,
    sdk_home: Option<PathBuf>,
    home: Option<PathBuf>,
    local_app_data: Option<PathBuf>,
}

impl DiscoveryInputs {
    fn current() -> Self {
        Self {
            platform: HostPlatform::current(),
            sdk_root: non_empty_env_path("ANDROID_SDK_ROOT"),
            sdk_home: non_empty_env_path("ANDROID_HOME"),
            home: dirs::home_dir(),
            local_app_data: non_empty_env_path("LOCALAPPDATA").or_else(dirs::data_local_dir),
        }
    }
}

pub(super) fn discover() -> AndroidSdkPaths {
    resolve(&DiscoveryInputs::current(), Path::is_file)
}

fn resolve(inputs: &DiscoveryInputs, is_file: impl Fn(&Path) -> bool) -> AndroidSdkPaths {
    for root in candidate_roots(inputs) {
        let paths = paths_in_root(&root, inputs.platform);
        if is_file(&paths.adb) && is_file(&paths.emulator) {
            return paths;
        }
    }
    bare_paths(inputs.platform)
}

fn candidate_roots(inputs: &DiscoveryInputs) -> Vec<PathBuf> {
    let mut roots = Vec::new();
    for root in [&inputs.sdk_root, &inputs.sdk_home].into_iter().flatten() {
        push_unique(&mut roots, root);
    }
    let conventional = match inputs.platform {
        HostPlatform::Linux => inputs.home.as_ref().map(|home| home.join("Android/Sdk")),
        HostPlatform::Macos => inputs
            .home
            .as_ref()
            .map(|home| home.join("Library/Android/sdk")),
        HostPlatform::Windows => inputs
            .local_app_data
            .as_ref()
            .map(|root| root.join("Android").join("Sdk")),
        HostPlatform::Other => None,
    };
    if let Some(root) = conventional {
        push_unique(&mut roots, &root);
    }
    roots
}

fn paths_in_root(root: &Path, platform: HostPlatform) -> AndroidSdkPaths {
    let suffix = platform.executable_suffix();
    AndroidSdkPaths {
        adb: root.join("platform-tools").join(format!("adb{suffix}")),
        emulator: root.join("emulator").join(format!("emulator{suffix}")),
    }
}

fn bare_paths(platform: HostPlatform) -> AndroidSdkPaths {
    let suffix = platform.executable_suffix();
    AndroidSdkPaths {
        adb: PathBuf::from(format!("adb{suffix}")),
        emulator: PathBuf::from(format!("emulator{suffix}")),
    }
}

fn non_empty_env_path(name: &str) -> Option<PathBuf> {
    env::var_os(name)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

fn push_unique(paths: &mut Vec<PathBuf>, candidate: &Path) {
    if !candidate.as_os_str().is_empty() && !paths.iter().any(|path| path == candidate) {
        paths.push(candidate.to_path_buf());
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashSet;

    use super::*;

    fn inputs(platform: HostPlatform) -> DiscoveryInputs {
        DiscoveryInputs {
            platform,
            sdk_root: None,
            sdk_home: None,
            home: None,
            local_app_data: None,
        }
    }

    fn resolve_with_roots(inputs: &DiscoveryInputs, valid_roots: &[&str]) -> AndroidSdkPaths {
        let files: HashSet<PathBuf> = valid_roots
            .iter()
            .flat_map(|root| {
                let paths = paths_in_root(Path::new(root), inputs.platform);
                [paths.adb, paths.emulator]
            })
            .collect();
        resolve(inputs, |path| files.contains(path))
    }

    #[test]
    fn valid_sdk_root_wins_over_home_and_conventional_paths() {
        let mut values = inputs(HostPlatform::Linux);
        values.sdk_root = Some("sdk-root".into());
        values.sdk_home = Some("sdk-home".into());
        values.home = Some("user-home".into());

        let paths = resolve_with_roots(&values, &["sdk-root", "sdk-home", "user-home/Android/Sdk"]);

        assert_eq!(paths.adb, Path::new("sdk-root/platform-tools/adb"));
        assert_eq!(paths.emulator, Path::new("sdk-root/emulator/emulator"));
    }

    #[test]
    fn invalid_sdk_root_falls_through_to_valid_android_home() {
        let mut values = inputs(HostPlatform::Macos);
        values.sdk_root = Some("invalid-root".into());
        values.sdk_home = Some("sdk-home".into());
        values.home = Some("user-home".into());

        let paths = resolve_with_roots(&values, &["sdk-home"]);

        assert_eq!(paths.adb, Path::new("sdk-home/platform-tools/adb"));
        assert_eq!(paths.emulator, Path::new("sdk-home/emulator/emulator"));
    }

    #[test]
    fn conventional_paths_are_platform_specific() {
        let cases = [
            (
                HostPlatform::Linux,
                Some("home"),
                None,
                "home/Android/Sdk",
                "adb",
            ),
            (
                HostPlatform::Macos,
                Some("home"),
                None,
                "home/Library/Android/sdk",
                "adb",
            ),
            (
                HostPlatform::Windows,
                None,
                Some("local"),
                "local/Android/Sdk",
                "adb.exe",
            ),
        ];
        for (platform, home, local, root, adb_name) in cases {
            let mut values = inputs(platform);
            values.home = home.map(PathBuf::from);
            values.local_app_data = local.map(PathBuf::from);

            let paths = resolve_with_roots(&values, &[root]);

            assert_eq!(
                paths.adb,
                Path::new(root).join("platform-tools").join(adb_name)
            );
            assert_eq!(
                paths.emulator,
                Path::new(root)
                    .join("emulator")
                    .join(format!("emulator{}", platform.executable_suffix()))
            );
        }
    }

    #[test]
    fn incomplete_roots_fall_back_to_exact_path_commands() {
        for (platform, adb, emulator) in [
            (HostPlatform::Linux, "adb", "emulator"),
            (HostPlatform::Macos, "adb", "emulator"),
            (HostPlatform::Windows, "adb.exe", "emulator.exe"),
            (HostPlatform::Other, "adb", "emulator"),
        ] {
            let mut values = inputs(platform);
            values.sdk_root = Some("partial-sdk".into());
            let only_adb = paths_in_root(Path::new("partial-sdk"), platform).adb;
            let paths = resolve(&values, |path| path == only_adb);

            assert_eq!(paths.adb, Path::new(adb));
            assert_eq!(paths.emulator, Path::new(emulator));
        }
    }
}
