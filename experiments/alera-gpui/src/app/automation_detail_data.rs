use serde_json::Value;
use std::sync::OnceLock;

#[derive(Clone,Copy,Debug,Default,PartialEq,Eq)]
pub(super) enum DetailTab { #[default] Overview, Runs, Audit }
impl DetailTab {
    pub const ALL:[Self;3]=[Self::Overview,Self::Runs,Self::Audit];
    pub fn label(self)->&'static str{match self{Self::Overview=>"Overview",Self::Runs=>"Runs",Self::Audit=>"Audit"}}
    pub fn next(self,forward:bool)->Self{let index=Self::ALL.iter().position(|tab|*tab==self).unwrap_or(0);Self::ALL[(index+if forward{1}else{2})%3]}
}

pub(super) fn text(value:&Value)->String{
    match value {
        Value::String(value)=>value.clone(),
        Value::Array(values)=>format!("[{}]",values.iter().map(text).collect::<Vec<_>>().join(", ")),
        Value::Object(values)=>format!("{{{}}}",values.iter().map(|(key,value)|format!("{key}: {}",text(value))).collect::<Vec<_>>().join(", ")),
        value=>value.to_string(),
    }
}

fn field(value:&Value,key:&str,fallback:&str)->String{value.get(key).filter(|v|!v.is_null()).map(text).unwrap_or_else(||fallback.into())}

pub(super) fn info_rows(value:&Value)->Vec<(String,String)>{
    let recurring=value["schedule"].get("recurring");
    let schedule=recurring.or_else(||value["schedule"].get("oneTime")).unwrap_or(&Value::Null);
    let (target_kind,target)=value["target"].as_object().and_then(|target|target.iter().next()).map(|(kind,target)|{
        (match kind.as_str(){"existingTab"=>"Existing tab","managedWorkspace"=>"Managed workspace",_=>"Fresh tab"},target)
    }).unwrap_or(("Target",&Value::Null));
    let mut rows=vec![
        ("Slug".into(),field(value,"slug","")),
        ("Schedule".into(),format!("{} · {}",if recurring.is_some(){"Recurring"}else{"One-time"},field(schedule,"timezone","UTC"))),
        ("Cron / Time".into(),schedule.get("cron").or_else(||schedule.get("at")).map(text).unwrap_or_else(||"Not set".into())),
        ("Target".into(),format!("{target_kind} · {}",target.get("workspaceId").or_else(||target.get("sourceWorkspaceId")).map(text).unwrap_or_else(||"Not set".into()))),
        ("Policies".into(),format!("Setup {} · Overlap {} · Misfire {} · Cleanup {}",field(value,"setupPolicy","wait"),field(value,"overlapPolicy","skip"),field(value,"misfirePolicy","skip"),field(value,"cleanupPolicy","preserve"))),
        ("Limits".into(),format!("Queue {} · Inactivity {}s · Heartbeat {}s · Retries {}",field(value,"queueCap","10"),field(value,"inactivityTimeoutSeconds","7200"),field(value,"heartbeatIntervalSeconds","60"),field(value,"retryMaxAttempts","3"))),
    ];
    if let Some(project)=value["projectId"].as_str().filter(|value|!value.is_empty()){rows.push(("Project".into(),project.into()));}
    let tags=value["tagIds"].as_array().into_iter().flatten().filter_map(Value::as_str).collect::<Vec<_>>().join(", ");
    if !tags.is_empty(){rows.push(("Tags".into(),tags));}
    rows.push(("Revision".into(),format!("{} · {}",field(value,"revision","0"),if value["approvedRevision"].as_i64().is_some_and(|revision|Some(revision)==value["revision"].as_i64()){"approved"}else{"draft changes"})));
    if let Some(description)=value["description"].as_str().filter(|value|!value.is_empty()){rows.push(("Description".into(),description.into()));}
    rows.push(("Prompt".into(),field(value,"promptTemplate","")));
    rows.push(("Prompt Preview".into(),prompt_preview(value)));
    rows
}

pub(super) fn prompt_preview(automation:&Value)->String{
    static VARIABLES:OnceLock<regex::Regex>=OnceLock::new();
    let expression=VARIABLES.get_or_init(||regex::Regex::new(r"\{\{([^}]+)\}\}").expect("literal automation template expression"));
    const KNOWN:&[&str]=&["automation.id","automation.name","automation.slug","run.id","run.number","run.scheduledAt","workspace.id","workspace.name","workspace.path","project.id","project.name"];
    let mut invalid=Vec::new();
    let source=automation["promptTemplate"].as_str().unwrap_or_default();
    let rendered=expression.replace_all(source,|captures:&regex::Captures<'_>|{
        let variable=captures.get(1).map(|value|value.as_str().trim()).unwrap_or_default();
        if !KNOWN.contains(&variable){if !invalid.iter().any(|known|known==variable){invalid.push(variable.to_owned());}return captures[0].to_owned();}
        match variable.strip_prefix("automation."){
            Some(key)=>automation[key].as_str().unwrap_or_default().to_owned(),
            None=>format!("<{variable}>"),
        }
    }).into_owned();
    if invalid.is_empty(){rendered}else{format!("Unknown prompt variable: {}",invalid.join(", "))}
}

pub(super) fn is_final(status:&str)->bool{
    ["success","failure","blocked","timeout","cancelled","precheckSkipped","misfireSkipped","overlapSkipped","queueLimitSkipped"].contains(&status)
}

#[cfg(test)]
mod tests{
    use super::*;use serde_json::json;
    #[test]
    fn automation_detail_rows_include_project_tags_and_prompt_preview(){
        let value=json!({"id":"a","name":"Revisión","slug":"review","revision":2,"approvedRevision":1,"projectId":"p","tagIds":["first","second"],"promptTemplate":"{{automation.name}} / {{workspace.path}} / 😀","target":{"existingTab":{"workspaceId":"w"}},"schedule":{"oneTime":{"at":"2031-01-01T00:00:00Z","timezone":"UTC"}}});
        let rows=info_rows(&value);assert!(rows.contains(&("Project".into(),"p".into())));assert!(rows.contains(&("Tags".into(),"first, second".into())));
        assert!(rows.contains(&("Prompt Preview".into(),"Revisión / <workspace.path> / 😀".into())));
        assert!(rows.contains(&("Revision".into(),"2 · draft changes".into())));
    }
    #[test]
    fn automation_detail_preview_reports_unknown_variables_and_dart_style_values(){
        assert_eq!(prompt_preview(&json!({"promptTemplate":"{{unknown}} {{unknown}} {{another}}"})),"Unknown prompt variable: unknown, another");
        assert_eq!(text(&json!({"kind":"humanDesktop"})),"{kind: humanDesktop}");
        assert!(is_final("success"));assert!(!is_final("waitingForUser"));
        assert_eq!(DetailTab::Overview.next(false),DetailTab::Audit);
    }
}
