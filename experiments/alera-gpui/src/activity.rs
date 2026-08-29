#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum ContextPanel {
    Explorer,
    Search,
    #[default]
    SourceControl,
    PullRequest,
    AgentCanvas,
}

impl ContextPanel {
    pub const ALL: [Self; 5] = [
        Self::Explorer,
        Self::Search,
        Self::SourceControl,
        Self::PullRequest,
        Self::AgentCanvas,
    ];

    pub const fn icon(self) -> AleraIcon {
        match self {
            Self::Explorer => AleraIcon::Files,
            Self::Search => AleraIcon::Search,
            Self::SourceControl => AleraIcon::GitBranch,
            Self::PullRequest => AleraIcon::GitPullRequest,
            Self::AgentCanvas => AleraIcon::Agent,
        }
    }

    pub const fn label(self) -> &'static str {
        match self {
            Self::Explorer => "Explorer",
            Self::Search => "Search",
            Self::SourceControl => "Source Control",
            Self::PullRequest => "Pull Request",
            Self::AgentCanvas => "Agent Canvas",
        }
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum StatusPopover {
    #[default]
    None,
    Quotas,
    QuotaProvider(usize),
    Resources,
    Runtime,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord)]
pub enum SettingsPane {
    #[default]
    Application,
    Agents,
    Quotas,
    AiAssist,
    TextActions,
    Editor,
    Terminal,
    Keyboard,
    Projects,
    MobileDevices,
    AgentProfiles,
}

impl SettingsPane {
    pub const ALL: [Self; 11] = [
        Self::Application,
        Self::Agents,
        Self::Quotas,
        Self::AiAssist,
        Self::TextActions,
        Self::Editor,
        Self::Terminal,
        Self::Keyboard,
        Self::Projects,
        Self::MobileDevices,
        Self::AgentProfiles,
    ];

    pub const fn label(self) -> &'static str {
        match self {
            Self::Application => "Application",
            Self::Agents => "Agents",
            Self::Quotas => "Quotas",
            Self::AiAssist => "AI Assist",
            Self::TextActions => "Text Actions",
            Self::Editor => "Editor",
            Self::Terminal => "Terminal",
            Self::Keyboard => "Keyboard",
            Self::Projects => "Projects",
            Self::MobileDevices => "Mobile Devices",
            Self::AgentProfiles => "Agent Profiles",
        }
    }

    pub const fn section(self) -> &'static str {
        match self {
            Self::Application
            | Self::Agents
            | Self::Quotas
            | Self::AiAssist
            | Self::Editor
            | Self::Terminal
            | Self::Keyboard => "Preferences",
            Self::TextActions | Self::Projects | Self::MobileDevices | Self::AgentProfiles => {
                "Resources"
            }
        }
    }

    pub const fn icon(self) -> AleraIcon {
        match self {
            Self::Application => AleraIcon::Tune,
            Self::Agents => AleraIcon::Agent,
            Self::Quotas => AleraIcon::Quota,
            Self::AiAssist => AleraIcon::Ai,
            Self::TextActions => AleraIcon::Text,
            Self::Editor => AleraIcon::Code,
            Self::Terminal => AleraIcon::Terminal,
            Self::Keyboard => AleraIcon::Keyboard,
            Self::Projects => AleraIcon::FolderSpecial,
            Self::MobileDevices => AleraIcon::MobileDevice,
            Self::AgentProfiles => AleraIcon::Agent,
        }
    }
}
use crate::icons::AleraIcon;
