use serde::Serialize;

/// A desktop application that owns at least one window.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppInfo {
    pub name: String,
    /// Absent where the platform has no stable application identifier. Linux
    /// AT-SPI reports only a display name, so agents match by name there.
    pub bundle_id: Option<String>,
    pub pid: u32,
}

/// What a provider can do in the current desktop session.
///
/// Every field is answered at runtime rather than compiled in: the same Linux
/// binary loses screenshots and hotkeys under Wayland, and a host with no
/// desktop session at all can do none of it.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Capabilities {
    pub platform: String,
    pub provider: String,
    pub provider_version: String,
    /// False when nothing can be driven at all. Callers check this once instead
    /// of discovering it through a failure on every verb.
    pub supported: bool,
    /// Why the session is unusable, in the words the agent should act on.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unsupported_reason: Option<String>,
    pub supports: SupportMatrix,
}

impl Capabilities {
    /// Capabilities for a session that can do nothing, with the reason kept.
    pub fn unsupported(
        platform: impl Into<String>,
        provider: impl Into<String>,
        reason: impl Into<String>,
    ) -> Self {
        Capabilities {
            platform: platform.into(),
            provider: provider.into(),
            provider_version: PROVIDER_VERSION.to_string(),
            supported: false,
            unsupported_reason: Some(reason.into()),
            supports: SupportMatrix::none(),
        }
    }
}

/// Version of the computer-use provider contract, reported so a client can tell
/// an old host from a new one without parsing capability names.
pub const PROVIDER_VERSION: &str = "1.0.0";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SupportMatrix {
    pub apps: AppSupport,
    pub windows: WindowSupport,
    pub observation: ObservationSupport,
    pub actions: ActionSupport,
}

impl SupportMatrix {
    pub fn none() -> Self {
        SupportMatrix {
            apps: AppSupport {
                list: false,
                bundle_ids: false,
                pids: false,
            },
            windows: WindowSupport {
                list: false,
                target_by_id: false,
                target_by_index: false,
                restore: false,
            },
            observation: ObservationSupport {
                tree: false,
                screenshot: false,
                element_frames: false,
            },
            actions: ActionSupport::none(),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSupport {
    pub list: bool,
    pub bundle_ids: bool,
    pub pids: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WindowSupport {
    pub list: bool,
    /// False on AT-SPI, which exposes no stable window handle. Agents must use
    /// the window index there.
    pub target_by_id: bool,
    pub target_by_index: bool,
    pub restore: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ObservationSupport {
    pub tree: bool,
    pub screenshot: bool,
    pub element_frames: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ActionSupport {
    pub click: bool,
    pub set_value: bool,
    pub perform_action: bool,
    pub type_text: bool,
    pub press_key: bool,
    pub hotkey: bool,
    pub paste_text: bool,
    pub scroll: bool,
    pub drag: bool,
}

impl ActionSupport {
    pub fn none() -> Self {
        ActionSupport {
            click: false,
            set_value: false,
            perform_action: false,
            type_text: false,
            press_key: false,
            hotkey: false,
            paste_text: false,
            scroll: false,
            drag: false,
        }
    }
}

/// One operating-system grant computer use depends on.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum PermissionId {
    Accessibility,
    Screenshots,
}

impl PermissionId {
    pub fn as_str(self) -> &'static str {
        match self {
            PermissionId::Accessibility => "accessibility",
            PermissionId::Screenshots => "screenshots",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "accessibility" => Some(PermissionId::Accessibility),
            "screenshots" => Some(PermissionId::Screenshots),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum PermissionState {
    Granted,
    Denied,
    /// The platform has no such grant, so there is nothing for the user to do.
    NotApplicable,
    Unknown,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PermissionItem {
    pub id: PermissionId,
    pub label: String,
    pub state: PermissionState,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PermissionsReport {
    pub platform: String,
    pub items: Vec<PermissionItem>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn permission_ids_round_trip_through_their_wire_names() {
        for id in [PermissionId::Accessibility, PermissionId::Screenshots] {
            assert_eq!(PermissionId::parse(id.as_str()), Some(id));
        }
        assert_eq!(PermissionId::parse("camera"), None);
    }

    #[test]
    fn an_unsupported_session_advertises_nothing() {
        let capabilities = Capabilities::unsupported("linux", "alera-computer-use-linux", "no bus");
        assert!(!capabilities.supported);
        assert_eq!(capabilities.unsupported_reason.as_deref(), Some("no bus"));
        assert!(!capabilities.supports.observation.tree);
        assert!(!capabilities.supports.actions.click);
    }

    /// The agent reads camelCase keys; a rename would silently break the skill.
    #[test]
    fn capabilities_serialize_with_camel_case_keys() {
        let capabilities = Capabilities::unsupported("linux", "p", "r");
        let value = serde_json::to_value(&capabilities).unwrap();
        assert!(value.get("providerVersion").is_some());
        assert!(value.get("unsupportedReason").is_some());
        assert!(value["supports"]["windows"].get("targetById").is_some());
        assert!(value["supports"]["actions"].get("setValue").is_some());
    }

    /// A supported session omits the reason instead of sending null, so the
    /// skill can treat presence of the field as "something is wrong".
    #[test]
    fn a_supported_session_omits_the_unsupported_reason() {
        let capabilities = Capabilities {
            platform: "linux".to_string(),
            provider: "p".to_string(),
            provider_version: PROVIDER_VERSION.to_string(),
            supported: true,
            unsupported_reason: None,
            supports: SupportMatrix::none(),
        };
        let value = serde_json::to_value(&capabilities).unwrap();
        assert!(value.get("unsupportedReason").is_none());
    }
}
