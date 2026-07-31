#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Activity {
    #[default]
    Workbench,
    Explorer,
    Search,
    SourceControl,
    PullRequests,
    AiText,
    Agents,
    Resources,
    Orchestration,
    Settings,
    Devices,
    Diagnostics,
}

impl Activity {
    pub const ALL: [Self; 12] = [
        Self::Workbench,
        Self::Explorer,
        Self::Search,
        Self::SourceControl,
        Self::PullRequests,
        Self::AiText,
        Self::Agents,
        Self::Resources,
        Self::Orchestration,
        Self::Settings,
        Self::Devices,
        Self::Diagnostics,
    ];

    pub const fn label(self) -> &'static str {
        match self {
            Self::Workbench => "Workbench",
            Self::Explorer => "Explorer",
            Self::Search => "Search And Replace",
            Self::SourceControl => "Source Control",
            Self::PullRequests => "Pull Requests And CI",
            Self::AiText => "AI Text",
            Self::Agents => "Agents And Quotas",
            Self::Resources => "Resource Manager",
            Self::Orchestration => "Orchestration",
            Self::Settings => "Settings",
            Self::Devices => "Mobile Devices",
            Self::Diagnostics => "Diagnostics",
        }
    }

    pub const fn icon(self) -> &'static str {
        match self {
            Self::Workbench => "⌂",
            Self::Explorer => "▱",
            Self::Search => "⌕",
            Self::SourceControl => "⑂",
            Self::PullRequests => "⑃",
            Self::AiText => "AI",
            Self::Agents => "◇",
            Self::Resources => "▥",
            Self::Orchestration => "⌘",
            Self::Settings => "⚙",
            Self::Devices => "▯",
            Self::Diagnostics => "i",
        }
    }

    pub const fn uses_runtime_catalog(self) -> bool {
        matches!(
            self,
            Self::Agents
                | Self::Resources
                | Self::Orchestration
                | Self::Settings
                | Self::Devices
                | Self::Diagnostics
        )
    }
}
