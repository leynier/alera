use std::collections::BTreeMap;
use serde_json::{Value, json};

macro_rules! fields {
    ($($field:ident => ($label:literal, $default:literal, $rows:literal)),+ $(,)?) => {
        #[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
        pub(super) enum Field { $($field),+ }
        impl Field {
            pub const ALL: &'static [Self] = &[$(Self::$field),+];
            pub fn label(self) -> &'static str { match self { $(Self::$field => $label),+ } }
            pub fn default_value(self) -> &'static str { match self { $(Self::$field => $default),+ } }
            pub fn rows(self) -> usize { match self { $(Self::$field => $rows),+ } }
        }
    }
}

fields! {
    Name => ("Name", "Daily Automation", 1),
    Slug => ("Slug", "daily-automation", 1),
    Description => ("Description", "", 3),
    Project => ("Project (Optional)", "", 1),
    Tags => ("Tag Ids (Comma-separated)", "", 1),
    Prompt => ("Prompt Template", "Review the current workspace and report the result.", 5),
    Cron => ("Five-field Cron", "0 9 * * 1-5", 1),
    At => ("Run At (UTC)", "", 1),
    Timezone => ("IANA Timezone", "UTC", 1),
    Start => ("Start At (Optional ISO-8601 UTC)", "", 1),
    End => ("End At (Optional ISO-8601 UTC)", "", 1),
    MaxRuns => ("Maximum Scheduled Runs (Optional)", "", 1),
    Workspace => ("Workspace", "", 1),
    Tab => ("Tab", "", 1),
    Conversation => ("Agent Conversation ID", "", 1),
    Profile => ("Agent Profile", "", 1),
    Branch => ("Source Branch", "main", 1),
    NameTemplate => ("Workspace Name Template", "auto-{{automation.slug}}-{{run.number}}", 1),
    Precheck => ("Precheck Command (Optional)", "", 1),
    PrecheckTimeout => ("Precheck Timeout (Seconds)", "120", 1),
    QueueCap => ("Queue Cap (Maximum 10)", "10", 1),
    Inactivity => ("Inactivity Timeout (Seconds)", "7200", 1),
    Heartbeat => ("Heartbeat Interval (Seconds)", "60", 1),
    MisfireGrace => ("Misfire Grace (Seconds)", "900", 1),
    RetryAttempts => ("Retry Attempts (Maximum 3)", "3", 1),
    RetryBackoff => ("Retry Backoff (Seconds)", "60", 1),
    CircuitThreshold => ("Circuit Failure Threshold", "3", 1),
    CircuitOpen => ("Circuit Open (Seconds)", "900", 1),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub(super) enum Choice { Schedule, Target, Setup, Overlap, Misfire, Cleanup }

impl Choice {
    pub const ALL: &'static [Self] = &[Self::Schedule, Self::Target, Self::Setup, Self::Overlap, Self::Misfire, Self::Cleanup];
    pub fn label(self) -> &'static str { match self { Self::Schedule => "Schedule", Self::Target => "Target", Self::Setup => "Setup", Self::Overlap => "Overlap", Self::Misfire => "Misfire", Self::Cleanup => "Cleanup" } }
    pub fn options(self) -> &'static [(&'static str, &'static str)] {
        match self {
            Self::Schedule => &[("recurring", "Recurring"), ("oneTime", "One-time")],
            Self::Target => &[("existingTab", "Existing Tab"), ("freshTab", "Fresh Tab"), ("managedWorkspace", "Managed Workspace")],
            Self::Setup => &[("wait", "Wait"), ("parallel", "Parallel"), ("skip", "Skip")],
            Self::Overlap => &[("skip", "Skip"), ("runLatestOnce", "Run Latest Once"), ("queue", "Queue"), ("forceParallel", "Force Parallel")],
            Self::Misfire => &[("skip", "Skip"), ("runLatestOnce", "Run Latest Once"), ("queue", "Queue")],
            Self::Cleanup => &[("preserve", "Preserve"), ("onSuccess", "On Success")],
        }
    }
    pub fn default_value(self) -> &'static str { if self == Self::Target { "freshTab" } else { self.options()[0].0 } }
}

#[derive(Clone)]
pub(super) struct AutomationForm {
    pub fields: BTreeMap<Field, String>,
    pub choices: BTreeMap<Choice, String>,
    pub notify_on_success: bool,
}

impl AutomationForm {
    pub fn from_definition(value: &Value, now: &str) -> Self {
        use Field::*;
        let mut form = Self {
            fields: Field::ALL.iter().map(|field| (*field, field.default_value().into())).collect(),
            choices: Choice::ALL.iter().map(|choice| (*choice, choice.default_value().into())).collect(),
            notify_on_success: value["notifyOnSuccess"].as_bool().unwrap_or(false),
        };
        form.set(At, now);
        for (field, key) in [(Name,"name"),(Slug,"slug"),(Description,"description"),(Project,"projectId"),(Prompt,"promptTemplate"),
            (QueueCap,"queueCap"),(Inactivity,"inactivityTimeoutSeconds"),(Heartbeat,"heartbeatIntervalSeconds"),
            (MisfireGrace,"misfireGraceSeconds"),(RetryAttempts,"retryMaxAttempts"),(RetryBackoff,"retryBackoffSeconds"),
            (CircuitThreshold,"circuitFailureThreshold"),(CircuitOpen,"circuitOpenSeconds")] { form.seed(field, &value[key]); }
        if let Some(tags) = value["tagIds"].as_array() { form.set(Tags, tags.iter().filter_map(Value::as_str).collect::<Vec<_>>().join(", ")); }
        for (choice, key) in [(Choice::Setup,"setupPolicy"),(Choice::Overlap,"overlapPolicy"),(Choice::Misfire,"misfirePolicy"),(Choice::Cleanup,"cleanupPolicy")] {
            if let Some(raw) = value[key].as_str() { form.choices.insert(choice, raw.into()); }
        }
        if value.pointer("/schedule/oneTime").is_some() { form.choices.insert(Choice::Schedule, "oneTime".into()); }
        let schedule = &value["schedule"][form.choice(Choice::Schedule)];
        for (field, key) in [(Cron,"cron"),(At,"at"),(Timezone,"timezone"),(Start,"startAt"),(End,"endAt"),(MaxRuns,"maxScheduledRuns")] { form.seed(field, &schedule[key]); }
        for kind in ["existingTab", "managedWorkspace"] { if value["target"].get(kind).is_some() { form.choices.insert(Choice::Target, kind.into()); break; } }
        let target = &value["target"][form.choice(Choice::Target)];
        for (field, key) in [(Workspace,"workspaceId"),(Workspace,"sourceWorkspaceId"),(Tab,"tabId"),(Conversation,"conversationId"),(Profile,"agentProfileId"),(Branch,"sourceBranch"),(NameTemplate,"nameTemplate")] { form.seed(field, &target[key]); }
        form.seed(Precheck, &value["precheck"]["command"]);
        form.seed(PrecheckTimeout, &value["precheck"]["timeoutSeconds"]);
        form
    }

    fn seed(&mut self, field: Field, value: &Value) {
        if let Some(value) = value.as_str() { self.set(field, value); }
        else if value.is_number() { self.set(field, value.to_string()); }
    }
    pub fn set(&mut self, field: Field, value: impl Into<String>) { self.fields.insert(field, value.into()); }
    pub fn text(&self, field: Field) -> &str { self.fields.get(&field).map(String::as_str).unwrap_or(field.default_value()).trim() }
    pub fn choice(&self, choice: Choice) -> &str { self.choices.get(&choice).map(String::as_str).unwrap_or(choice.default_value()) }
    fn number(&self, field: Field, default: i64, min: i64, max: i64) -> i64 { self.text(field).parse::<i64>().unwrap_or(default).clamp(min, max) }

    pub fn definition(&self, original: &Value, id: &str, now: &str) -> Result<Value, String> {
        use Field::*;
        if [Name, Slug, Prompt].iter().any(|field| self.text(*field).is_empty()) { return Err("Name, slug, and prompt template are required.".into()); }
        validate_prompt(self.text(Prompt))?;
        let target_kind = self.choice(Choice::Target);
        if self.text(Workspace).is_empty() || (target_kind == "existingTab" && [Tab, Conversation].iter().any(|field| self.text(*field).is_empty())) || (target_kind != "existingTab" && self.text(Profile).is_empty()) {
            return Err(if target_kind == "existingTab" { "The existing tab requires workspace, tab, and conversation ids." } else { "The selected target requires its ids." }.into());
        }
        let target = match target_kind {
            "existingTab" => json!({"existingTab":{"workspaceId":self.text(Workspace),"tabId":self.text(Tab),"conversationId":self.text(Conversation)}}),
            "managedWorkspace" => json!({"managedWorkspace":{"sourceWorkspaceId":self.text(Workspace),"sourceBranch":self.text(Branch),"nameTemplate":self.text(NameTemplate),"agentProfileId":self.text(Profile)}}),
            _ => json!({"freshTab":{"workspaceId":self.text(Workspace),"agentProfileId":self.text(Profile)}}),
        };
        let schedule = if self.choice(Choice::Schedule) == "oneTime" {
            json!({"oneTime":{"at":self.text(At),"timezone":self.text(Timezone)}})
        } else {
            let mut value = json!({"cron":self.text(Cron),"timezone":self.text(Timezone)});
            for (field,key) in [(Start,"startAt"),(End,"endAt")] { if !self.text(field).is_empty() { value[key] = json!(self.text(field)); } }
            if !self.text(MaxRuns).is_empty() { value["maxScheduledRuns"] = json!(self.text(MaxRuns).parse::<i64>().unwrap_or(1)); }
            json!({"recurring":value})
        };
        let mut result = original.as_object().cloned().unwrap_or_default();
        let edits = json!({"id":id,"name":self.text(Name),"slug":self.text(Slug),"description":self.text(Description),
            "projectId":if self.text(Project).is_empty(){Value::Null}else{json!(self.text(Project))},
            "tagIds":self.text(Tags).split(',').map(str::trim).filter(|tag|!tag.is_empty()).collect::<Vec<_>>(),
            "promptTemplate":self.text(Prompt),"schedule":schedule,"target":target,
            "setupPolicy":self.choice(Choice::Setup),"overlapPolicy":self.choice(Choice::Overlap),"misfirePolicy":self.choice(Choice::Misfire),"cleanupPolicy":self.choice(Choice::Cleanup),
            "queueCap":self.number(QueueCap,10,1,10),"inactivityTimeoutSeconds":self.number(Inactivity,7200,1,86400),
            "heartbeatIntervalSeconds":self.number(Heartbeat,60,1,86400),"misfireGraceSeconds":self.number(MisfireGrace,900,0,86400),
            "retryMaxAttempts":self.number(RetryAttempts,3,1,3),"retryBackoffSeconds":self.number(RetryBackoff,60,1,86400),
            "circuitFailureThreshold":self.number(CircuitThreshold,3,1,100),"circuitOpenSeconds":self.number(CircuitOpen,900,1,86400),
            "precheck":if self.text(Precheck).is_empty(){Value::Null}else{json!({"command":self.text(Precheck),"timeoutSeconds":self.number(PrecheckTimeout,120,1,3600)})},
            "notifyOnSuccess":self.notify_on_success,"updatedAt":now});
        result.extend(edits.as_object().cloned().unwrap_or_default());
        for (key, value) in [("state",json!("draft")),("revision",json!(0)),("approvedRevision",Value::Null),
            ("createdBy",json!({"kind":"humanDesktop"})),("modifiedBy",json!({"kind":"humanDesktop"})),("createdAt",json!(now))] { result.entry(key).or_insert(value); }
        Ok(Value::Object(result))
    }
}

fn validate_prompt(template: &str) -> Result<(), String> {
    const KNOWN: &[&str] = &["automation.id","automation.name","automation.slug","run.id","run.number","run.scheduledAt","workspace.id","workspace.name","workspace.path","project.id","project.name"];
    let mut tail = template;
    loop {
        let Some(start) = tail.find("{{") else { return if tail.contains("}}") { Err("Prompt template contains an unmatched closing delimiter.".into()) } else { Ok(()) }; };
        if tail[..start].contains("}}") { return Err("Prompt template contains an unmatched closing delimiter.".into()); }
        let variable = &tail[start + 2..];
        let Some(end) = variable.find("}}") else { return Err("Prompt template contains an unterminated variable.".into()); };
        let name = variable[..end].trim();
        if !KNOWN.contains(&name) { return Err(format!("Unknown prompt variable: {{{{{name}}}}}")); }
        tail = &variable[end + 2..];
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    const NOW: &str = "2030-01-01T00:00:00Z";
    #[test]
    fn automation_form_seeds_every_input_and_keeps_all_target_schedule_variants() {
        for target in [json!({"existingTab":{"workspaceId":"w","tabId":"t","conversationId":"c"}}),json!({"freshTab":{"workspaceId":"w","agentProfileId":"p"}}),json!({"managedWorkspace":{"sourceWorkspaceId":"w","agentProfileId":"p","sourceBranch":"review","nameTemplate":"auto-{{run.id}}"}})] {
            for schedule in [json!({"oneTime":{"at":NOW,"timezone":"America/Mexico_City"}}),json!({"recurring":{"cron":"0 9 * * *","timezone":"UTC","startAt":NOW,"endAt":"2031-01-01T00:00:00Z","maxScheduledRuns":7}})] {
                let original = json!({"name":"Review","slug":"review","promptTemplate":"á {{workspace.name}} 😀","target":target,"schedule":schedule,"revision":8,"approvedRevision":7,"state":"paused","customMetadata":true});
                let form = AutomationForm::from_definition(&original,NOW);
                assert_eq!(form.fields.len(),Field::ALL.len());
                let output = form.definition(&original,"id",NOW).unwrap();
                for key in ["target","schedule","revision","approvedRevision","state","customMetadata"] { assert_eq!(output[key], original[key],"{key}"); }
            }
        }
    }
    #[test]
    fn automation_form_validates_targets_templates_and_clamps_like_flutter() {
        let mut form = AutomationForm::from_definition(&Value::Null,NOW);
        assert!(form.definition(&Value::Null,"id",NOW).is_err());
        form.set(Field::Workspace,"w"); form.set(Field::Profile,"p");
        form.set(Field::QueueCap,"999"); form.set(Field::RetryAttempts,"0"); form.set(Field::Heartbeat,"invalid");
        form.set(Field::Precheck,"echo safe"); form.set(Field::PrecheckTimeout,"0");
        let value=form.definition(&Value::Null,"id",NOW).unwrap();
        assert_eq!(value["queueCap"],10); assert_eq!(value["retryMaxAttempts"],1); assert_eq!(value["heartbeatIntervalSeconds"],60); assert_eq!(value["precheck"]["timeoutSeconds"],1);
        assert_eq!(value["state"],"draft"); assert!(value["approvedRevision"].is_null());
        for invalid in ["{{unknown}}","{{run.id","}} {{run.id}}"] { form.set(Field::Prompt,invalid); assert!(form.definition(&Value::Null,"id",NOW).is_err()); }
    }

    #[test]
    fn automation_form_round_trips_policies_and_does_not_execute_or_reapprove() {
        let initial=json!({"name":"Fixture","slug":"fixture","promptTemplate":"Read only", "target":{"freshTab":{"workspaceId":"w","agentProfileId":"p"}},
            "projectId":"project","tagIds":["first","second"],"setupPolicy":"parallel","overlapPolicy":"runLatestOnce","misfirePolicy":"queue","cleanupPolicy":"onSuccess",
            "precheck":{"command":"echo ready","timeoutSeconds":320},"notifyOnSuccess":true,"queueCap":7,"inactivityTimeoutSeconds":800,"heartbeatIntervalSeconds":15,
            "misfireGraceSeconds":70,"retryMaxAttempts":2,"retryBackoffSeconds":20,"circuitFailureThreshold":9,"circuitOpenSeconds":200,
            "state":"draft","revision":10,"approvedRevision":8,"createdAt":"2029-01-01T00:00:00Z"});
        let form=AutomationForm::from_definition(&initial,NOW);
        let output=form.definition(&initial,"id",NOW).unwrap();
        for (key,value) in initial.as_object().unwrap() { assert_eq!(&output[key],value,"{key}"); }
        assert!(output.get("runNow").is_none());
    }
}
