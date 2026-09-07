use std::collections::{HashMap, HashSet};

use alera_core::runtime::{AgentProfile, AgentProfileLaunchMode, AgentProfileRemovalImpact};
use anyhow::{anyhow, bail, Context, Result};
use serde::Serialize;
use serde_json::{json, Value};

use crate::agent_profile_input::{
    draft_for_create, draft_for_update, ensure_expected_revision, ensure_risk_confirmation,
    managed_config_for_create, managed_config_for_update, parse_revision_overrides,
};
use crate::cli::{
    AgentProfileAction, AgentProfileCommand, AgentProfileReorderArgs, AgentProfileSelectorArgs,
};
use crate::runtime_host_client::RuntimeHostRpcClient;
use crate::terminal_host::agent_profile_capabilities::{
    RUNTIME_HOST_AGENT_PROFILE_REMOVAL_CAPABILITY, RUNTIME_HOST_AGENT_PROFILE_REVISIONS_CAPABILITY,
};
use crate::terminal_host::protocol::{
    RUNTIME_HOST_AGENT_PROFILES_CAPABILITY, RUNTIME_HOST_AGENT_PROFILE_ORDERING_CAPABILITY,
    RUNTIME_HOST_MANAGED_AGENT_PROFILES_CAPABILITY,
};

pub(crate) async fn run(command: AgentProfileCommand) -> i32 {
    match run_command(command).await {
        Ok(()) => 0,
        Err(error) => crate::print_error(error),
    }
}

async fn run_command(command: AgentProfileCommand) -> Result<()> {
    let json_output = command.output.json;
    let mut client = RuntimeHostRpcClient::connect_or_start_with_required_capability(
        &crate::runtime_dir(&command.runtime),
        RUNTIME_HOST_AGENT_PROFILES_CAPABILITY,
    )
    .await?;
    match command.action {
        AgentProfileAction::List => {
            let (payload, profiles) = list_profiles(&mut client).await?;
            if json_output {
                print_json(&payload)?;
            } else {
                print_profile_list(&profiles);
            }
        }
        AgentProfileAction::Show(selector) => {
            let (_, profiles) = list_profiles(&mut client).await?;
            let profile = select_profile(&profiles, &selector)?;
            if json_output {
                print_json(profile)?;
            } else {
                print_profile_detail(profile)?;
            }
        }
        AgentProfileAction::Create(args) => {
            let managed_config = managed_config_for_create(&args, &mut std::io::stdin().lock())?;
            let draft = draft_for_create(&args, managed_config)?;
            ensure_risk_confirmation(None, &draft, args.confirm_reduced_protections)?;
            if draft.launch_mode == AgentProfileLaunchMode::Managed {
                ensure_capabilities(
                    &mut client,
                    &[RUNTIME_HOST_MANAGED_AGENT_PROFILES_CAPABILITY],
                )
                .await?;
            }
            let saved = client
                .request_value("agentProfile.upsert", &draft.create_payload())
                .await?;
            print_saved(&saved, json_output)?;
        }
        AgentProfileAction::Update(args) => {
            let (_, profiles) = list_profiles(&mut client).await?;
            let existing = select_profile(&profiles, &args.target.selector)?;
            let expected_revision =
                ensure_expected_revision(existing, args.target.expected_revision)?;
            let managed_config =
                managed_config_for_update(existing, &args, &mut std::io::stdin().lock())?;
            let draft = draft_for_update(existing, &args, managed_config)?;
            ensure_risk_confirmation(Some(existing), &draft, args.confirm_reduced_protections)?;
            let mut capabilities = vec![RUNTIME_HOST_AGENT_PROFILE_REVISIONS_CAPABILITY];
            if draft.launch_mode == AgentProfileLaunchMode::Managed {
                capabilities.push(RUNTIME_HOST_MANAGED_AGENT_PROFILES_CAPABILITY);
            }
            ensure_capabilities(&mut client, &capabilities).await?;
            let saved = client
                .request_value(
                    "agentProfile.upsert",
                    &draft.update_payload(&existing.id, expected_revision),
                )
                .await?;
            print_saved(&saved, json_output)?;
        }
        AgentProfileAction::RemovalImpact(args) => {
            let (_, profiles) = list_profiles(&mut client).await?;
            let profile = select_profile(&profiles, &args.selector)?;
            let expected_revision = ensure_expected_revision(profile, args.expected_revision)?;
            ensure_capabilities(
                &mut client,
                &[
                    RUNTIME_HOST_AGENT_PROFILE_REVISIONS_CAPABILITY,
                    RUNTIME_HOST_AGENT_PROFILE_REMOVAL_CAPABILITY,
                ],
            )
            .await?;
            let impact = client
                .request_value(
                    "agentProfile.removalImpact",
                    &json!({"id": profile.id, "expectedRevision": expected_revision}),
                )
                .await?;
            if json_output {
                print_json(&impact)?;
            } else {
                print_removal_impact(&impact, &profile.name)?;
            }
        }
        AgentProfileAction::Remove(args) => {
            let (_, profiles) = list_profiles(&mut client).await?;
            let profile = select_profile(&profiles, &args.target.selector)?;
            let expected_revision =
                ensure_expected_revision(profile, args.target.expected_revision)?;
            ensure_capabilities(
                &mut client,
                &[
                    RUNTIME_HOST_AGENT_PROFILE_REVISIONS_CAPABILITY,
                    RUNTIME_HOST_AGENT_PROFILE_REMOVAL_CAPABILITY,
                ],
            )
            .await?;
            let impact_value = client
                .request_value(
                    "agentProfile.removalImpact",
                    &json!({"id": profile.id, "expectedRevision": expected_revision}),
                )
                .await?;
            let impact: AgentProfileRemovalImpact = serde_json::from_value(impact_value)
                .context("runtime host returned an invalid agent profile removal impact")?;
            if impact.has_blocking_references() {
                bail!(
                    "agent profile removal is blocked by {} reference(s); run removal-impact for details",
                    impact.automation_ids.len()
                        + impact.execution_policy_run_ids.len()
                        + impact.tabs.len()
                );
            }
            let removed = client
                .request_value(
                    "agentProfile.remove",
                    &json!({
                        "id": profile.id,
                        "expectedRevision": expected_revision,
                        "confirmed": args.confirm,
                    }),
                )
                .await?;
            if json_output {
                print_json(&removed)?;
            } else if removed.get("removed").and_then(Value::as_bool) == Some(true) {
                println!("agent profile removed: {} ({})", profile.name, profile.id);
            } else {
                println!("agent profile was already absent: {}", profile.id);
            }
        }
        AgentProfileAction::Launch(args) => {
            crate::agent_profile_launch::run(&command.runtime, &mut client, args, json_output)
                .await?;
        }
        AgentProfileAction::Reorder(args) => {
            let (_, profiles) = list_profiles(&mut client).await?;
            let expected_revisions = reorder_revisions(&profiles, &args)?;
            ensure_capabilities(
                &mut client,
                &[
                    RUNTIME_HOST_AGENT_PROFILE_REVISIONS_CAPABILITY,
                    RUNTIME_HOST_AGENT_PROFILE_ORDERING_CAPABILITY,
                ],
            )
            .await?;
            let payload = client
                .request_value(
                    "agentProfile.reorder",
                    &json!({"ids": args.ids, "expectedRevisions": expected_revisions}),
                )
                .await?;
            if json_output {
                print_json(&payload)?;
            } else {
                let reordered = profiles_from_payload(&payload)?;
                print_profile_list(&reordered);
            }
        }
    }
    Ok(())
}

pub(crate) async fn list_profiles(
    client: &mut RuntimeHostRpcClient,
) -> Result<(Value, Vec<AgentProfile>)> {
    let payload = client
        .request_value("agentProfile.list", &json!({}))
        .await?;
    let profiles = profiles_from_payload(&payload)?;
    Ok((payload, profiles))
}

fn profiles_from_payload(payload: &Value) -> Result<Vec<AgentProfile>> {
    let items = payload
        .get("items")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("runtime agent profile payload must carry an items array"))?;
    items
        .iter()
        .cloned()
        .map(|value| {
            serde_json::from_value(value).context("runtime host returned an invalid agent profile")
        })
        .collect()
}

pub(crate) fn select_profile<'a>(
    profiles: &'a [AgentProfile],
    selector: &AgentProfileSelectorArgs,
) -> Result<&'a AgentProfile> {
    if let Some(id) = selector.profile_id.as_deref() {
        let id = id.trim();
        if id.is_empty() {
            bail!("profile id cannot be empty");
        }
        return profiles
            .iter()
            .find(|profile| profile.id == id)
            .ok_or_else(|| anyhow!("agent profile not found: {id}"));
    }
    let name = selector
        .profile_name_or_alias()
        .ok_or_else(|| anyhow!("profile name cannot be empty"))?;
    profiles
        .iter()
        .find(|profile| profile.name.eq_ignore_ascii_case(name))
        .ok_or_else(|| anyhow!("agent profile not found: {name}"))
}

pub(crate) async fn ensure_capabilities(
    client: &mut RuntimeHostRpcClient,
    required: &[&str],
) -> Result<()> {
    if required.is_empty() {
        return Ok(());
    }
    let status = client.request_value("status.get", &json!({})).await?;
    let capabilities = status
        .get("runtimeCapabilities")
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("runtime host status did not include capabilities"))?;
    for required in required {
        if !capabilities
            .iter()
            .any(|capability| capability.as_str() == Some(required))
        {
            bail!(
                "A live Alera runtime host does not support {required}. Restart Alera and retry."
            );
        }
    }
    Ok(())
}

fn reorder_revisions(
    profiles: &[AgentProfile],
    args: &AgentProfileReorderArgs,
) -> Result<HashMap<String, i64>> {
    let requested = args
        .ids
        .iter()
        .map(|id| id.trim().to_string())
        .collect::<Vec<_>>();
    if requested.iter().any(String::is_empty) {
        bail!("profile ids in the requested order cannot be empty");
    }
    let unique = requested.iter().collect::<HashSet<_>>();
    if unique.len() != requested.len() {
        bail!("agent profile order must contain each profile exactly once");
    }
    let current = profiles
        .iter()
        .map(|profile| profile.id.as_str())
        .collect::<HashSet<_>>();
    let requested_set = requested.iter().map(String::as_str).collect::<HashSet<_>>();
    if requested_set != current {
        bail!("agent profile order must contain every current profile exactly once");
    }
    let mut revisions = profiles
        .iter()
        .map(|profile| (profile.id.clone(), profile.revision))
        .collect::<HashMap<_, _>>();
    for (id, revision) in parse_revision_overrides(&args.expected_revisions)? {
        if !revisions.contains_key(&id) {
            bail!("expected revision references an unknown profile: {id}");
        }
        revisions.insert(id, revision);
    }
    Ok(revisions)
}

fn print_saved(value: &Value, json_output: bool) -> Result<()> {
    if json_output {
        return print_json(value);
    }
    let profile: AgentProfile = serde_json::from_value(value.clone())
        .context("runtime host returned an invalid saved agent profile")?;
    println!(
        "agent profile saved: {} ({}, revision {})",
        profile.name, profile.id, profile.revision
    );
    Ok(())
}

fn print_profile_list(profiles: &[AgentProfile]) {
    if profiles.is_empty() {
        println!("no agent profiles declared");
        return;
    }
    println!("{} agent profile(s)", profiles.len());
    for profile in profiles {
        let quota = profile
            .quota_group
            .as_deref()
            .map(|group| format!(" [{group}]"))
            .unwrap_or_default();
        println!(
            "  {} | {} | {} | {} | revision {}{}",
            profile.id,
            profile.name,
            profile.agent_type,
            profile.launch_mode.as_str(),
            profile.revision,
            quota
        );
    }
}

fn print_profile_detail(profile: &AgentProfile) -> Result<()> {
    print_json(profile)
}

fn print_removal_impact(value: &Value, profile_name: &str) -> Result<()> {
    let impact: AgentProfileRemovalImpact = serde_json::from_value(value.clone())
        .context("runtime host returned an invalid agent profile removal impact")?;
    let reference_count = value
        .get("referenceCount")
        .and_then(Value::as_u64)
        .unwrap_or_else(|| impact.reference_count() as u64);
    let blocking_count = value
        .get("blockingReferenceCount")
        .and_then(Value::as_u64)
        .unwrap_or_else(|| {
            (impact.automation_ids.len()
                + impact.execution_policy_run_ids.len()
                + impact.tabs.len()) as u64
        });
    println!("agent profile removal impact: {profile_name}");
    println!("  references: {reference_count}");
    println!("  blocking references: {blocking_count}");
    println!("  default profile: {}", impact.is_default);
    if !impact.automation_ids.is_empty() {
        println!("  automations: {}", impact.automation_ids.join(", "));
    }
    if !impact.execution_policy_run_ids.is_empty() {
        println!(
            "  execution policies: {}",
            impact.execution_policy_run_ids.join(", ")
        );
    }
    if !impact.tabs.is_empty() {
        println!("  recoverable tabs: {}", impact.tabs.len());
    }
    Ok(())
}

pub(crate) fn print_json(value: &impl Serialize) -> Result<()> {
    println!(
        "{}",
        serde_json::to_string_pretty(value).context("failed to render JSON output")?
    );
    Ok(())
}

#[cfg(test)]
#[path = "agent_profile_commands_tests.rs"]
mod tests;
