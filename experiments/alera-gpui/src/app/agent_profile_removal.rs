use serde_json::Value;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct AgentProfileTabReference {
    pub(super) workspace_id: String,
    pub(super) tab_id: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct AgentProfileRemovalImpact {
    pub(super) profile_id: String,
    pub(super) exists: bool,
    pub(super) revision: Option<i64>,
    pub(super) is_default: bool,
    pub(super) automation_ids: Vec<String>,
    pub(super) has_automation_policy: bool,
    pub(super) execution_policy_run_ids: Vec<String>,
    pub(super) tabs: Vec<AgentProfileTabReference>,
}

impl AgentProfileRemovalImpact {
    pub(super) fn has_blocking_references(&self) -> bool {
        !self.automation_ids.is_empty()
            || !self.execution_policy_run_ids.is_empty()
            || !self.tabs.is_empty()
    }

    pub(super) fn removal_message(&self, profile_name: &str) -> String {
        let mut references = Vec::new();
        if !self.automation_ids.is_empty() {
            references.push(pluralized_reference(
                self.automation_ids.len(),
                "automation",
            ));
        }
        if !self.tabs.is_empty() {
            references.push(pluralized_reference(self.tabs.len(), "tab"));
        }
        if self.is_default {
            references.push("the default profile setting".to_owned());
        }
        if self.has_automation_policy {
            references.push("an automation policy".to_owned());
        }
        if !self.execution_policy_run_ids.is_empty() {
            references.push(pluralized_reference(
                self.execution_policy_run_ids.len(),
                "active execution policy",
            ));
        }
        if references.is_empty() {
            return format!("{profile_name} has no references. Deleting it cannot be undone.");
        }
        let effect = references.join(", ");
        if self.has_blocking_references() {
            return format!(
                "{profile_name} is referenced by {effect}. Remove its automation and tab references before deleting it."
            );
        }
        format!(
            "{profile_name} is referenced by {effect}. These references will be cleared atomically when the profile is deleted."
        )
    }
}

pub(super) fn parse_agent_profile_removal_impact(
    value: &Value,
) -> Result<AgentProfileRemovalImpact, String> {
    let profile_id = value
        .get("profileId")
        .and_then(Value::as_str)
        .ok_or_else(|| "Agent Profile Removal Impact Omitted Profile Id".to_owned())?
        .to_owned();
    Ok(AgentProfileRemovalImpact {
        profile_id,
        exists: value
            .get("exists")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        revision: value.get("revision").and_then(Value::as_i64),
        is_default: value
            .get("isDefault")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        automation_ids: string_list(value, "automationIds"),
        has_automation_policy: value
            .get("hasAutomationPolicy")
            .and_then(Value::as_bool)
            .unwrap_or(false),
        execution_policy_run_ids: string_list(value, "executionPolicyRunIds"),
        tabs: value
            .get("tabs")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|item| {
                Some(AgentProfileTabReference {
                    workspace_id: item.get("workspaceId")?.as_str()?.to_owned(),
                    tab_id: item.get("tabId")?.as_str()?.to_owned(),
                })
            })
            .collect(),
    })
}

fn string_list(value: &Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::to_owned)
        .collect()
}

fn pluralized_reference(count: usize, singular: &str) -> String {
    if count == 1 {
        format!("1 {singular}")
    } else if singular == "active execution policy" {
        format!("{count} active execution policies")
    } else {
        format!("{count} {singular}s")
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::parse_agent_profile_removal_impact;

    #[test]
    fn blocking_references_disable_profile_removal() {
        let impact = parse_agent_profile_removal_impact(&json!({
            "profileId": "prof_a",
            "exists": true,
            "revision": 4,
            "isDefault": true,
            "automationIds": ["automation_a"],
            "hasAutomationPolicy": false,
            "executionPolicyRunIds": [],
            "tabs": [{"workspaceId": "workspace_a", "tabId": "tab_a"}]
        }))
        .expect("valid impact");

        assert!(impact.has_blocking_references());
        assert_eq!(impact.revision, Some(4));
        assert_eq!(
            impact.removal_message("Primary"),
            "Primary is referenced by 1 automation, 1 tab, the default profile setting. Remove its automation and tab references before deleting it."
        );
    }
}
