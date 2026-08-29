pub(super) const ADAPTERS: &[(&str, &str)] = &[
    ("codex", "Codex"),
    ("claude", "Claude Code"),
    ("copilot", "GitHub Copilot"),
    ("cursor", "Cursor"),
    ("agy", "Antigravity"),
    ("opencode", "OpenCode"),
    ("opencode2", "OpenCode 2"),
    ("pi", "Pi"),
    ("amp", "Amp"),
];

pub(super) const LAUNCH_MODES: &[(&str, &str)] = &[("managed", "Managed"), ("command", "Command")];

pub(super) struct ManagedOption {
    pub(super) value: &'static str,
    pub(super) label: &'static str,
}

pub(super) enum ManagedControl {
    Choice {
        key: &'static str,
        title: &'static str,
        description: &'static str,
        options: &'static [ManagedOption],
    },
    Flag {
        key: &'static str,
        title: &'static str,
        description: &'static str,
    },
    Number {
        key: &'static str,
        title: &'static str,
        description: &'static str,
    },
}

const CODEX_EFFORT: &[ManagedOption] = &[
    ManagedOption {
        value: "minimal",
        label: "Minimal",
    },
    ManagedOption {
        value: "low",
        label: "Low",
    },
    ManagedOption {
        value: "medium",
        label: "Medium",
    },
    ManagedOption {
        value: "high",
        label: "High",
    },
    ManagedOption {
        value: "xhigh",
        label: "Extra High",
    },
    ManagedOption {
        value: "max",
        label: "Max",
    },
    ManagedOption {
        value: "ultra",
        label: "Ultra",
    },
];

const CLAUDE_EFFORT: &[ManagedOption] = &[
    ManagedOption {
        value: "low",
        label: "Low",
    },
    ManagedOption {
        value: "medium",
        label: "Medium",
    },
    ManagedOption {
        value: "high",
        label: "High",
    },
    ManagedOption {
        value: "xhigh",
        label: "Extra High",
    },
    ManagedOption {
        value: "max",
        label: "Max",
    },
];

const COPILOT_EFFORT: &[ManagedOption] = &[
    ManagedOption {
        value: "none",
        label: "None",
    },
    ManagedOption {
        value: "minimal",
        label: "Minimal",
    },
    ManagedOption {
        value: "low",
        label: "Low",
    },
    ManagedOption {
        value: "medium",
        label: "Medium",
    },
    ManagedOption {
        value: "high",
        label: "High",
    },
    ManagedOption {
        value: "xhigh",
        label: "Extra High",
    },
    ManagedOption {
        value: "max",
        label: "Max",
    },
];

const BASIC_EFFORT: &[ManagedOption] = &[
    ManagedOption {
        value: "low",
        label: "Low",
    },
    ManagedOption {
        value: "medium",
        label: "Medium",
    },
    ManagedOption {
        value: "high",
        label: "High",
    },
];

const CODEX_SANDBOX: &[ManagedOption] = &[
    ManagedOption {
        value: "read-only",
        label: "Read Only",
    },
    ManagedOption {
        value: "workspace-write",
        label: "Workspace Write",
    },
    ManagedOption {
        value: "danger-full-access",
        label: "Full Access",
    },
];

const CODEX_APPROVAL: &[ManagedOption] = &[
    ManagedOption {
        value: "untrusted",
        label: "Untrusted",
    },
    ManagedOption {
        value: "on-request",
        label: "On Request",
    },
    ManagedOption {
        value: "never",
        label: "Never Ask",
    },
];

const CLAUDE_PERMISSION: &[ManagedOption] = &[
    ManagedOption {
        value: "acceptEdits",
        label: "Accept Edits",
    },
    ManagedOption {
        value: "auto",
        label: "Auto",
    },
    ManagedOption {
        value: "bypassPermissions",
        label: "Bypass Permissions",
    },
    ManagedOption {
        value: "manual",
        label: "Manual",
    },
    ManagedOption {
        value: "dontAsk",
        label: "Do Not Ask",
    },
    ManagedOption {
        value: "plan",
        label: "Plan",
    },
];

const COPILOT_MODE: &[ManagedOption] = &[
    ManagedOption {
        value: "interactive",
        label: "Interactive",
    },
    ManagedOption {
        value: "plan",
        label: "Plan",
    },
    ManagedOption {
        value: "autopilot",
        label: "Autopilot",
    },
];

const COPILOT_CONTEXT: &[ManagedOption] = &[
    ManagedOption {
        value: "default",
        label: "Default Context",
    },
    ManagedOption {
        value: "long_context",
        label: "Long Context",
    },
];

const CURSOR_MODE: &[ManagedOption] = &[
    ManagedOption {
        value: "plan",
        label: "Plan",
    },
    ManagedOption {
        value: "ask",
        label: "Ask",
    },
];

const CURSOR_PERMISSION: &[ManagedOption] = &[
    ManagedOption {
        value: "autoReview",
        label: "Auto Review",
    },
    ManagedOption {
        value: "force",
        label: "Force",
    },
];

const CURSOR_SANDBOX: &[ManagedOption] = &[
    ManagedOption {
        value: "enabled",
        label: "Enabled",
    },
    ManagedOption {
        value: "disabled",
        label: "Disabled",
    },
];

const AGY_MODE: &[ManagedOption] = &[
    ManagedOption {
        value: "accept-edits",
        label: "Accept Edits",
    },
    ManagedOption {
        value: "plan",
        label: "Plan",
    },
];

const PI_THINKING: &[ManagedOption] = &[
    ManagedOption {
        value: "off",
        label: "Off",
    },
    ManagedOption {
        value: "minimal",
        label: "Minimal",
    },
    ManagedOption {
        value: "low",
        label: "Low",
    },
    ManagedOption {
        value: "medium",
        label: "Medium",
    },
    ManagedOption {
        value: "high",
        label: "High",
    },
    ManagedOption {
        value: "xhigh",
        label: "Extra High",
    },
    ManagedOption {
        value: "max",
        label: "Max",
    },
];

const PI_TRUST: &[ManagedOption] = &[
    ManagedOption {
        value: "approve",
        label: "Approve",
    },
    ManagedOption {
        value: "ignore",
        label: "Ignore",
    },
];

const AMP_MODE: &[ManagedOption] = &[
    ManagedOption {
        value: "low",
        label: "Low",
    },
    ManagedOption {
        value: "medium",
        label: "Medium",
    },
    ManagedOption {
        value: "high",
        label: "High",
    },
    ManagedOption {
        value: "ultra",
        label: "Ultra",
    },
];

pub(super) fn supports_model(adapter: &str) -> bool {
    adapter != "amp"
}

pub(super) fn supports_persona(adapter: &str) -> bool {
    matches!(adapter, "claude" | "copilot" | "agy" | "opencode" | "opencode2")
}

pub(super) fn controls_for(adapter: &str) -> Vec<ManagedControl> {
    let choice = |key, title, options| ManagedControl::Choice {
        key,
        title,
        description: "",
        options,
    };
    let flag = |key, title, description| ManagedControl::Flag {
        key,
        title,
        description,
    };
    match adapter {
        "codex" => vec![
            choice("effort", "Reasoning Effort", CODEX_EFFORT),
            choice(
                "planModeEffort",
                "Plan Mode Reasoning Effort",
                CODEX_EFFORT,
            ),
            choice("sandbox", "Sandbox", CODEX_SANDBOX),
            choice("approvalPolicy", "Approval Policy", CODEX_APPROVAL),
            flag("webSearch", "Web Search", "Allow Codex To Search The Web."),
            flag(
                "bypassApprovalsAndSandbox",
                "Bypass All Protections",
                "Bypass Both Approval Prompts And Sandbox Isolation.",
            ),
        ],
        "claude" => vec![
            choice("effort", "Reasoning Effort", CLAUDE_EFFORT),
            choice("permissionMode", "Permission Mode", CLAUDE_PERMISSION),
            flag(
                "allowSkipPermissions",
                "Allow Skip Permissions",
                "Allow Claude To Bypass Permission Checks During The Session.",
            ),
        ],
        "copilot" => vec![
            choice("effort", "Reasoning Effort", COPILOT_EFFORT),
            choice("mode", "Mode", COPILOT_MODE),
            choice("context", "Context", COPILOT_CONTEXT),
            flag(
                "allowAll",
                "Allow All",
                "Allow Tools And Paths Without Individual Prompts.",
            ),
            ManagedControl::Number {
                key: "maxAiCredits",
                title: "Maximum AI Credits",
                description: "Leave Empty To Use The Agent Default.",
            },
            ManagedControl::Number {
                key: "maxAutopilotContinues",
                title: "Maximum Autopilot Continues",
                description: "Leave Empty To Use The Agent Default.",
            },
            flag(
                "noAskUser",
                "Do Not Ask User",
                "Continue Without Asking The User For Input.",
            ),
        ],
        "cursor" => vec![
            choice("mode", "Mode", CURSOR_MODE),
            choice("permissionMode", "Review Mode", CURSOR_PERMISSION),
            choice("sandbox", "Sandbox", CURSOR_SANDBOX),
            flag(
                "trustWorkspace",
                "Trust Workspace",
                "Trust The Workspace Without An Interactive Prompt.",
            ),
        ],
        "agy" => vec![
            choice("effort", "Reasoning Effort", BASIC_EFFORT),
            choice("mode", "Mode", AGY_MODE),
            flag(
                "skipPermissions",
                "Skip Permissions",
                "Run Without Antigravity Permission Checks.",
            ),
            flag("sandbox", "Sandbox", "Enable The Antigravity Sandbox."),
        ],
        "opencode" => vec![flag(
            "autoApprove",
            "Auto Approve",
            "Approve OpenCode Actions Automatically.",
        )],
        "opencode2" => vec![flag(
            "autoApprove",
            "Auto Approve",
            "Approve OpenCode 2 Actions Automatically.",
        )],
        "pi" => vec![
            choice("thinking", "Thinking", PI_THINKING),
            choice("projectTrust", "Project Trust", PI_TRUST),
        ],
        "amp" => vec![
            ManagedControl::Choice {
                key: "mode",
                title: "Mode",
                description:
                    "Amp Permission Rules Continue To Come From The Global Amp Configuration.",
                options: AMP_MODE,
            },
            flag("fast", "Fast Mode", "Prefer Lower Latency Responses."),
        ],
        _ => Vec::new(),
    }
}
