use crate::activity::SettingsPane;

const APPLICATION: &[&str] = &[
    "Workspace Directory worktree folder location path storage",
    "Confirm Project Removal safety destructive remove delete",
    "Confirm Workspace Removal safety destructive remove delete",
    "Keep Computer Awake idle display sleep power",
    "Keep Runtime Open When App Quits host sidecar lifecycle shutdown",
    "Empty Host Shutdown host sidecar lifetime timeout",
    "Detached Session Shutdown host sidecar session timeout",
    "Automations schedules runs autostart retention history",
    "Open Logs Folder diagnostics debug",
    "Export Diagnostics logs bundle report zip",
    "Log Level verbose debug diagnostics",
    "Send Crash Reports sentry telemetry error",
    "Updates check release version download",
    "Support Alera GitHub star community",
];
const AGENTS: &[&str] = &[
    "All Alera Skills install update computer use emulator orchestration",
    "Alera CLI Skill codex workspace",
    "Alera Orchestration Skill handoff task dispatch",
    "Agent Canvas Skill publish decision structured updates",
    "Alera Computer Use Skill desktop accessibility click window",
    "Codex Hooks agent status",
    "Claude Code Hooks agent status",
    "GitHub Copilot Hooks agent status",
    "Cursor Hooks agent status cli",
    "Antigravity Hooks agy agent status",
    "OpenCode Hooks plugin agent status",
    "Pi Hooks extension agent status",
    "Amp Hooks plugin agent status",
    "Grok Build Hooks xai agent status",
    "fx Status Herdr agent status",
    "Agent Status Notifications attention",
    "Agent Finished Notifications done turn",
    "Keep Computer Awake While Agents Are Working sleep power display",
];
const QUOTAS: &[&str] = &[
    "Provider Quotas usage codex kimi grok antigravity minimax z.ai order pin status bar",
    "Claude Code Quotas usage default CCS accounts",
    "Claude Default Quotas account",
    "Claude Default In Usage usage visible",
    "Claude CCS Profiles alias profile pin usage",
    "Kimi API Key Variable environment",
    "Quota Credential Environment Kimi Z.ai MiniMax remote host",
];
const AI_ASSIST: &[&str] = &[
    "AI Assist short local agent jobs source control workspace identity speech",
    "Enable AI Assist generation source control pull requests",
    "Agent CLI AI Assist jobs",
    "Model refresh discover",
    "Thinking reasoning effort",
    "Custom Command prompt stdin",
    "Commit Messages Agent Model prompt override",
    "Pull Request Details Agent Model prompt override",
    "Workspace Identity Agent Model prompt override",
    "Reading Diffs Agent Model reasoning instructions diff only",
    "Instructions optional prompt guidance",
];
const TEXT_ACTIONS: &[&str] = &[
    "Text Actions reusable replacements selected text AI prompt",
    "New Action create add",
    "Enabled show action menu",
    "Agent Model Reasoning action overrides",
    "Duplicate Reorder action menu order",
    "Delete remove action",
];
const EDITOR: &[&str] = &[
    "Editor Theme syntax colors appearance",
    "Tab Size indentation spaces",
    "Autosave automatic save idle changes",
    "Autosave Delay debounce seconds editor",
];
const TERMINAL: &[&str] = &[
    "Font Family monospace jetbrains typeface",
    "Font Size terminal text zoom",
    "Font Weight terminal text bold",
    "Line Height spacing rows",
    "Cursor Shape caret block bar underline",
    "Blinking Cursor caret blink",
    "Cursor Opacity caret alpha",
    "Theme Preset color appearance palette",
    "Background Opacity transparent alpha",
    "Horizontal Padding inset space",
    "Vertical Padding inset space",
    "Toolbar Corner buttons overlay position corner move",
    "Color Overrides foreground background selection cursor",
    "TUI Scroll Speed mouse wheel opencode amp claude",
    "Copy On Select clipboard selection mouse",
    "Allow OSC 52 Clipboard Writes tui ssh tmux",
    "Show Terminal Composer By Default prompt compose",
    "Scrollback Lines history buffer",
    "Host Scrollback Size memory host",
    "Word Separators boundary selection double click",
    "Terminal Memory Budget buffer advanced",
    "Use Login Shell environment path",
];
const KEYBOARD: &[&str] = &[
    "Keyboard Shortcuts key bindings remap",
    "Terminal Shortcut Policy terminal first app first",
    "Search Shortcuts",
    "Record Binding conflict disable reset",
];
const PROJECTS: &[&str] = &[
    "Project Worktree Setup repository workspace copy setup prompt append agent instructions alera.toml",
];
const MOBILE: &[&str] = &[
    "Mobile Gateway bind port enable wss endpoint tailscale vpn remote encrypted relay",
    "Link Mobile Device QR pair scan phone companion",
    "Active Pairing Offers cancel copy",
    "Paired Devices rename revoke delete token",
];
const AGENT_PROFILES: &[&str] = &[
    "Agent Profiles catalog orchestration adapter command model quota group fallback",
    "Managed Agent Profile discovery launch configuration",
];

pub(super) fn pane_matches(pane: SettingsPane, query: &str) -> bool {
    query.is_empty()
        || pane.label().to_lowercase().contains(query)
        || pane_entries(pane)
            .iter()
            .any(|entry| entry.to_lowercase().contains(query))
}

pub(super) fn pane_match_count(pane: SettingsPane, query: &str) -> usize {
    if query.is_empty() {
        return 0;
    }
    pane_entries(pane)
        .iter()
        .filter(|entry| entry.to_lowercase().contains(query))
        .count()
}

/// Returns the first group that contains a matching setting. Flutter keeps
/// the complete pane mounted while searching and scrolls the first matching
/// group into view; GPUI mirrors that behavior instead of hiding unrelated
/// controls.
pub(super) fn first_matching_group(pane: SettingsPane, query: &str) -> Option<usize> {
    if query.is_empty() {
        return None;
    }
    let groups: &[&[&str]] = match pane {
        SettingsPane::Terminal => &[
            &[
                "Typography",
                "Font Family",
                "Font Size",
                "Font Weight",
                "Line Height",
            ],
            &[
                "Cursor",
                "Cursor Shape",
                "Blinking Cursor",
                "Cursor Opacity",
            ],
            &[
                "Appearance",
                "Theme Preset",
                "Background Opacity",
                "Horizontal Padding",
                "Vertical Padding",
                "Foreground Color",
                "Background Color",
                "Cursor Color",
                "Selection Color",
            ],
            &[
                "Interaction",
                "TUI Scroll Speed",
                "Copy On Select",
                "Allow OSC 52 Clipboard Writes",
            ],
            &[
                "Advanced",
                "Use Login Shell",
                "Reload Shell Environment",
                "Scrollback Lines",
                "Host Scrollback Size",
                "Terminal Memory Budget",
                "Word Separators",
            ],
        ],
        SettingsPane::AiAssist => &[
            &[
                "Generation",
                "AI Assist",
                "Enable AI Assist",
                "Agent",
                "Model",
                "Reasoning",
                "Custom Command",
            ],
            &[
                "Commit Messages",
                "Agent",
                "Model",
                "Reasoning",
                "Instructions",
            ],
            &[
                "Pull Request Details",
                "Agent",
                "Model",
                "Reasoning",
                "Instructions",
            ],
            &[
                "Reading Diffs",
                "Agent",
                "Model",
                "Reasoning",
                "Instructions",
            ],
            &[
                "Workspace Identity",
                "Agent",
                "Model",
                "Reasoning",
                "Instructions",
            ],
        ],
        SettingsPane::TextActions => &[&[
            "Actions",
            "Text Actions",
            "New Action",
            "Enabled",
            "Agent",
            "Model",
            "Reasoning",
            "Duplicate",
            "Reorder",
            "Delete",
        ]],
        _ => return None,
    };
    groups.iter().position(|group| {
        group
            .iter()
            .any(|entry| entry.to_lowercase().contains(query))
    })
}

fn pane_entries(pane: SettingsPane) -> &'static [&'static str] {
    match pane {
        SettingsPane::Application => APPLICATION,
        SettingsPane::Agents => AGENTS,
        SettingsPane::Quotas => QUOTAS,
        SettingsPane::AiAssist => AI_ASSIST,
        SettingsPane::TextActions => TEXT_ACTIONS,
        SettingsPane::Editor => EDITOR,
        SettingsPane::Terminal => TERMINAL,
        SettingsPane::Keyboard => KEYBOARD,
        SettingsPane::Projects => PROJECTS,
        SettingsPane::MobileDevices => MOBILE,
        SettingsPane::AgentProfiles => AGENT_PROFILES,
    }
}

#[cfg(test)]
mod tests {
    use super::{pane_match_count, pane_matches};
    use crate::activity::SettingsPane;

    #[test]
    fn search_matches_setting_keywords_and_counts_entries() {
        assert!(pane_matches(SettingsPane::Terminal, "clipboard"));
        assert_eq!(pane_match_count(SettingsPane::Terminal, "clipboard"), 2);
        assert!(pane_matches(SettingsPane::Projects, "alera.toml"));
        assert!(pane_matches(SettingsPane::AiAssist, "speech"));
        assert!(!pane_matches(SettingsPane::AiAssist, "scrollback"));
    }

    #[test]
    fn search_scrolls_terminal_clipboard_matches_into_view() {
        assert_eq!(
            super::first_matching_group(SettingsPane::Terminal, "clipboard"),
            Some(3)
        );
        assert_eq!(
            super::first_matching_group(SettingsPane::Terminal, "font"),
            Some(0)
        );
        assert_eq!(
            super::first_matching_group(SettingsPane::AiAssist, "reading"),
            Some(3)
        );
        assert_eq!(
            super::first_matching_group(SettingsPane::AiAssist, "workspace"),
            Some(4)
        );
    }
}
