use super::*;
use crate::runtime::workflow_plan_tests::{fixture, valid_profile};

fn task(id: &str, integrated: bool) -> TaskState {
    TaskState {
        id: id.into(),
        logical_id: id.into(),
        status: if integrated { "completed" } else { "pending" }.into(),
        integrated,
        workspace: None,
        phase: None,
        integration: None,
        integration_request: None,
    }
}

#[tokio::test]
async fn human_gates_block_dependents_and_final_completion() {
    let (_dir, store, request) = fixture(true).await;
    let plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap()
        .plan;
    let mut tasks = plan
        .tasks
        .iter()
        .map(|frozen| task(&frozen.task.id, false))
        .collect::<Vec<_>>();
    tasks
        .iter_mut()
        .find(|item| item.id == "foundation")
        .map(|item| *item = task("foundation", true))
        .unwrap();
    let mut gates = BTreeMap::new();
    assert!(matches!(
        choose("run", 1, &plan, &tasks, &gates).unwrap(),
        WorkflowExecutionStep::Waiting
    ));
    gates.insert("foundation".into(), "approved".into());
    assert!(matches!(
        choose("run", 1, &plan, &tasks, &gates).unwrap(),
        WorkflowExecutionStep::PrepareWorkspace(_)
    ));
    for item in &mut tasks {
        *item = task(&item.id, true);
    }
    assert!(matches!(
        choose("run", 1, &plan, &tasks, &gates).unwrap(),
        WorkflowExecutionStep::Waiting
    ));
    for stage in &plan.recipe.recipe.stages {
        if stage.gate.is_some() {
            gates.insert(stage.id.clone(), "approved".into());
        }
    }
    assert!(matches!(
        choose("run", 1, &plan, &tasks, &gates).unwrap(),
        WorkflowExecutionStep::Complete
    ));
}

#[tokio::test]
async fn preparation_respects_capacity_but_can_launch_an_already_reserved_slot() {
    let (_dir, store, request) = fixture(false).await;
    let mut plan = store
        .prepare_workflow_plan(request, valid_profile)
        .await
        .unwrap()
        .plan;
    let mut extra = plan.tasks[0].clone();
    extra.task.id = "parallel".into();
    extra.task.depends_on.clear();
    plan.tasks.push(extra);
    plan.max_concurrent = 1;
    let mut active = task("fix", false);
    active.workspace = Some("attempt".into());
    active.phase = Some("creating".into());
    let mut tasks = vec![active, task("parallel", false), task("verify", false)];
    assert!(matches!(
        choose("run", 1, &plan, &tasks, &BTreeMap::new()).unwrap(),
        WorkflowExecutionStep::Waiting
    ));
    tasks[0].phase = Some("ready".into());
    assert!(matches!(
        choose("run", 1, &plan, &tasks, &BTreeMap::new()).unwrap(),
        WorkflowExecutionStep::LaunchTask(_)
    ));
    tasks[0].phase = Some("attention".into());
    assert!(matches!(
        choose("run", 1, &plan, &tasks, &BTreeMap::new()).unwrap(),
        WorkflowExecutionStep::Attention { .. }
    ));
}
