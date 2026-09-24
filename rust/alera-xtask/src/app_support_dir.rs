//! Mirrors the directory `path_provider` gives the desktop app, so xtask's
//! runtime paths point at the same `terminal_host` the app uses.

use std::path::PathBuf;

use crate::flavor;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HostOs {
    Macos,
    Windows,
    Other,
}

impl HostOs {
    pub fn current() -> Self {
        if cfg!(target_os = "macos") {
            Self::Macos
        } else if cfg!(windows) {
            Self::Windows
        } else {
            Self::Other
        }
    }
}

pub struct AppSupportEnvironment {
    pub home: PathBuf,
    pub app_data: Option<String>,
    pub xdg_data_home: Option<String>,
}

impl AppSupportEnvironment {
    pub fn from_process() -> Self {
        Self {
            home: home_directory(),
            app_data: std::env::var("APPDATA")
                .ok()
                .filter(|value| !value.is_empty()),
            xdg_data_home: std::env::var("XDG_DATA_HOME")
                .ok()
                .filter(|value| !value.is_empty()),
        }
    }
}

pub fn app_support_dir(os: HostOs, app_id: &str, environment: &AppSupportEnvironment) -> PathBuf {
    match os {
        HostOs::Macos => environment
            .home
            .join("Library/Application Support")
            .join(app_id),
        HostOs::Windows => {
            if let Some(app_data) = nonempty(&environment.app_data) {
                return PathBuf::from(app_data).join(flavor::windows_app_support_subdir(app_id));
            }
            data_home(app_id, environment)
        }
        HostOs::Other => data_home(app_id, environment),
    }
}

pub fn default_app_support_dir(app_id: &str) -> PathBuf {
    app_support_dir(
        HostOs::current(),
        app_id,
        &AppSupportEnvironment::from_process(),
    )
}

fn data_home(app_id: &str, environment: &AppSupportEnvironment) -> PathBuf {
    if let Some(xdg) = nonempty(&environment.xdg_data_home) {
        return PathBuf::from(xdg).join(app_id);
    }
    environment.home.join(".local/share").join(app_id)
}

fn nonempty(value: &Option<String>) -> Option<&str> {
    value.as_deref().filter(|item| !item.is_empty())
}

fn home_directory() -> PathBuf {
    if let Ok(home) = std::env::var("HOME") {
        return PathBuf::from(home);
    }
    if let Ok(profile) = std::env::var("USERPROFILE") {
        return PathBuf::from(profile);
    }
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::flavor::{DEV_BUNDLE_ID, RELEASE_BUNDLE_ID};

    fn environment(
        home: &str,
        app_data: Option<&str>,
        xdg_data_home: Option<&str>,
    ) -> AppSupportEnvironment {
        AppSupportEnvironment {
            home: PathBuf::from(home),
            app_data: app_data.map(str::to_string),
            xdg_data_home: xdg_data_home.map(str::to_string),
        }
    }

    #[test]
    fn windows_dev_uses_company_and_product_name() {
        let app_data = r"C:\Users\u\AppData\Roaming";
        assert_eq!(
            app_support_dir(
                HostOs::Windows,
                DEV_BUNDLE_ID,
                &environment(r"C:\Users\u", Some(app_data), None)
            ),
            PathBuf::from(app_data)
                .join("dev.leynier")
                .join("Alera Dev")
        );
    }

    #[test]
    fn windows_release_keeps_the_shipped_directory() {
        let app_data = r"C:\Users\u\AppData\Roaming";
        assert_eq!(
            app_support_dir(
                HostOs::Windows,
                RELEASE_BUNDLE_ID,
                &environment(r"C:\Users\u", Some(app_data), None)
            ),
            PathBuf::from(app_data).join("dev.leynier").join("Alera")
        );
    }

    #[test]
    fn windows_custom_id_keeps_the_app_id_layout() {
        let app_data = r"C:\Users\u\AppData\Roaming";
        assert_eq!(
            app_support_dir(
                HostOs::Windows,
                "custom.id",
                &environment(r"C:\Users\u", Some(app_data), None)
            ),
            PathBuf::from(app_data).join("custom.id")
        );
    }

    #[test]
    fn windows_without_appdata_falls_back_to_xdg_or_home() {
        let home = "/home/u";
        let xdg = "/xdg";
        assert_eq!(
            app_support_dir(
                HostOs::Windows,
                DEV_BUNDLE_ID,
                &environment(home, None, Some(xdg))
            ),
            PathBuf::from(xdg).join(DEV_BUNDLE_ID)
        );
        assert_eq!(
            app_support_dir(
                HostOs::Windows,
                DEV_BUNDLE_ID,
                &environment(home, Some(""), Some(xdg))
            ),
            PathBuf::from(xdg).join(DEV_BUNDLE_ID)
        );
        assert_eq!(
            app_support_dir(
                HostOs::Windows,
                DEV_BUNDLE_ID,
                &environment(home, Some(""), Some(""))
            ),
            PathBuf::from(home).join(".local/share").join(DEV_BUNDLE_ID)
        );
        assert_eq!(
            app_support_dir(HostOs::Windows, "custom.id", &environment(home, None, None)),
            PathBuf::from(home).join(".local/share").join("custom.id")
        );
    }

    #[test]
    fn macos_uses_application_support() {
        assert_eq!(
            app_support_dir(
                HostOs::Macos,
                DEV_BUNDLE_ID,
                &environment("/Users/u", Some(r"C:\ignored"), Some("/ignored"))
            ),
            PathBuf::from("/Users/u")
                .join("Library/Application Support")
                .join(DEV_BUNDLE_ID)
        );
    }

    #[test]
    fn other_uses_xdg_or_home_data_dir() {
        assert_eq!(
            app_support_dir(
                HostOs::Other,
                DEV_BUNDLE_ID,
                &environment("/home/u", None, Some("/xdg"))
            ),
            PathBuf::from("/xdg").join(DEV_BUNDLE_ID)
        );
        assert_eq!(
            app_support_dir(
                HostOs::Other,
                DEV_BUNDLE_ID,
                &environment("/home/u", None, None)
            ),
            PathBuf::from("/home/u")
                .join(".local/share")
                .join(DEV_BUNDLE_ID)
        );
    }
}
