//! Agent profile configuration, which is administrative. Reading profiles is
//! open to every client; changing them needs the `admin` class (F2).

use serde_json::Value;

use super::{admin, profile_schema, read, with_profile, PROMPT_LIMIT};
use crate::mcp_tools::schema::{boolean, integer, object, one_of, string, text};
use crate::mcp_tools::{Invocation, ToolArguments, ToolInputError, ToolSpec};

const REVISION_LIMIT: u64 = i64::MAX as u64;

fn selected(action: &[&str], arguments: &ToolArguments) -> Result<Invocation, ToolInputError> {
    Ok(with_profile(
        Invocation::new("agent-profile", action),
        arguments.required("profile")?,
    ))
}

fn expected_revision(invocation: Invocation, arguments: &ToolArguments) -> Invocation {
    invocation.option_if(
        "--expected-revision",
        arguments
            .integer("expectedRevision")
            .map(|value| value.to_string()),
    )
}

fn revision_schema() -> Value {
    integer(
        "Profile revision from show_agent_profile. The change is refused if the profile changed since.",
        0,
        REVISION_LIMIT,
    )
}

/// Properties shared by create and update. Update treats each as optional.
fn profile_properties() -> Vec<(&'static str, Value)> {
    vec![
        ("name", text("Display name.", 200)),
        ("agentType", string("Agent adapter, such as claude, codex, or opencode.")),
        ("launchMode", one_of("Run a command line or a managed configuration.", &["command", "managed"])),
        ("command", text("Interactive command for the command launch mode.", 8_192)),
        ("managedConfig", serde_json::json!({
            "type": "object",
            "description": "Managed configuration for the managed launch mode, as show_agent_profile returns it.",
        })),
        ("customPrompt", text("Instructions added to every prompt this profile receives.", PROMPT_LIMIT)),
        ("description", text("Short description.", 2_000)),
        ("quotaGroup", string("Quota group the profile counts against.")),
        ("showInNewTabMenu", boolean("Show the profile in the app's new tab menu.")),
        ("confirmReducedProtections", boolean("Confirm settings that reduce the agent's protections, such as skipping permission prompts.")),
    ]
}

/// The options both create and update pass the same way.
fn profile_options(
    invocation: Invocation,
    arguments: &ToolArguments,
) -> Result<Invocation, ToolInputError> {
    let invocation = invocation
        .option_if("--name", arguments.string("name"))
        .option_if("--agent-type", arguments.string("agentType"))
        .option_if("--launch-mode", arguments.string("launchMode"))
        .option_if("--command", arguments.string("command"))
        .flag_if(
            "--confirm-reduced-protections",
            arguments.flag("confirmReducedProtections"),
        );
    Ok(match arguments.object("managedConfig") {
        Some(config) => {
            let config =
                serde_json::to_string(config).map_err(|error| ToolInputError(error.to_string()))?;
            invocation.flag("--managed-config-stdin").stdin(config)
        }
        None => invocation,
    })
}

/// A text option or its `--clear-…` flag, never both.
fn text_or_clear(
    invocation: Invocation,
    arguments: &ToolArguments,
    (property, flag): (&str, &str),
    (clear_property, clear_flag): (&str, &str),
) -> Result<Invocation, ToolInputError> {
    let value = arguments.string(property);
    let clear = arguments.flag(clear_property);
    if value.is_some() && clear {
        return Err(ToolInputError(format!(
            "Send {property} or {clear_property}, not both."
        )));
    }
    Ok(invocation.option_if(flag, value).flag_if(clear_flag, clear))
}

pub(super) fn tools() -> Vec<ToolSpec> {
    vec![
        read(
            "show_agent_profile",
            "Show Agent Profile",
            "Show one agent profile with its launch configuration and revision.",
            || object(&[("profile", profile_schema())], &["profile"]),
            |arguments| selected(&["show"], arguments),
        ),
        read(
            "preview_agent_profile_removal",
            "Preview Agent Profile Removal",
            "Show what refers to an agent profile, such as automations, before removing it.",
            || object(&[("profile", profile_schema())], &["profile"]),
            |arguments| selected(&["removal-impact"], arguments),
        ),
        admin(
            "create_agent_profile",
            "Create Agent Profile",
            "Create an agent profile. A managed profile takes managedConfig; a command profile takes command.",
            || object(&profile_properties(), &["name", "agentType", "launchMode"]),
            |arguments| {
                let invocation = profile_options(Invocation::new("agent-profile", &["create"]), arguments)?
                    .option_if("--custom-prompt", arguments.string("customPrompt"))
                    .option_if("--description", arguments.string("description"))
                    .option_if("--quota-group", arguments.string("quotaGroup"))
                    .flag_if("--show-in-new-tab-menu", arguments.flag("showInNewTabMenu"));
                Ok(invocation)
            },
        ),
        ToolSpec {
            idempotent: true,
            ..admin(
                "update_agent_profile",
                "Update Agent Profile",
                "Change an agent profile. Fields left out keep their values; the clear fields remove an optional text.",
                || {
                    let mut properties = vec![
                        ("profile", profile_schema()),
                        ("expectedRevision", revision_schema()),
                    ];
                    properties.extend(profile_properties());
                    properties.extend([
                        ("clearCustomPrompt", boolean("Remove the custom prompt.")),
                        ("clearDescription", boolean("Remove the description.")),
                        ("clearQuotaGroup", boolean("Remove the quota group.")),
                    ]);
                    object(&properties, &["profile"])
                },
                |arguments| {
                    let invocation = expected_revision(selected(&["update"], arguments)?, arguments);
                    let invocation = profile_options(invocation, arguments)?.option_if(
                        "--show-in-new-tab-menu",
                        arguments.optional_flag("showInNewTabMenu").map(|value| value.to_string()),
                    );
                    let invocation = text_or_clear(invocation, arguments, ("customPrompt", "--custom-prompt"), ("clearCustomPrompt", "--clear-custom-prompt"))?;
                    let invocation = text_or_clear(invocation, arguments, ("description", "--description"), ("clearDescription", "--clear-description"))?;
                    text_or_clear(invocation, arguments, ("quotaGroup", "--quota-group"), ("clearQuotaGroup", "--clear-quota-group"))
                },
            )
        },
        ToolSpec {
            destructive: true,
            ..admin(
                "remove_agent_profile",
                "Remove Agent Profile",
                "Remove an agent profile after the runtime checks what refers to it.",
                || {
                    object(
                        &[("profile", profile_schema()), ("expectedRevision", revision_schema())],
                        &["profile"],
                    )
                },
                |arguments| {
                    Ok(expected_revision(selected(&["remove"], arguments)?, arguments).flag("--confirm"))
                },
            )
        },
        ToolSpec {
            idempotent: true,
            ..admin(
                "reorder_agent_profiles",
                "Reorder Agent Profiles",
                "Set the order of every agent profile. List each profile id once, in the new order.",
                || {
                    object(
                        &[(
                            "ids",
                            serde_json::json!({
                                "type": "array",
                                "items": { "type": "string", "minLength": 1 },
                                "minItems": 1,
                                "uniqueItems": true,
                                "description": "Every profile id from list_agent_profiles, in the new order.",
                            }),
                        )],
                        &["ids"],
                    )
                },
                |arguments| {
                    let ids = arguments.list("ids").unwrap_or_default();
                    if ids.is_empty() {
                        return Err(ToolInputError("Missing required argument `ids`.".into()));
                    }
                    Ok(ids
                        .into_iter()
                        .fold(Invocation::new("agent-profile", &["reorder"]), |invocation, id| {
                            invocation.option("--id", id)
                        }))
                },
            )
        },
        ToolSpec {
            idempotent: true,
            ..admin(
                "set_default_agent_profile",
                "Set Default Agent Profile",
                "Choose the agent profile new workspaces from a prompt use when none is named.",
                || object(&[("profileId", string("Profile id from list_agent_profiles."))], &["profileId"]),
                |arguments| {
                    let assignment = format!("defaultAgentProfileId={}", arguments.required("profileId")?);
                    Ok(Invocation::new("runtime", &["settings", "set", &assignment]))
                },
            )
        },
    ]
}
