use super::*;

#[tokio::test]
async fn offline_cli_project_removal_refuses_dependencies_without_implicit_cancellation() {
    use clap::Parser;

    let (fixture, definition) = empty_project().await;
    fixture
        .actor
        .runtime_store
        .approve_automation(
            &definition.id,
            definition.revision,
            definition.created_by.clone(),
        )
        .await
        .unwrap();
    let cli = crate::cli::Cli::try_parse_from([
        "alera",
        "project",
        "--runtime-dir",
        fixture._runtime_dir.path().to_str().unwrap(),
        "remove",
        "--id",
        "project-1",
    ])
    .unwrap();
    let crate::cli::Command::Project(command) = cli.command else {
        panic!("project command expected");
    };
    assert_eq!(
        tokio::time::timeout(
            std::time::Duration::from_secs(10),
            crate::run_project_command(command)
        )
        .await
        .unwrap(),
        1
    );
    assert!(fixture
        .actor
        .runtime_store
        .find_project("project-1")
        .await
        .unwrap()
        .is_some());
    assert_eq!(
        fixture
            .actor
            .runtime_store
            .find_automation(&definition.id)
            .await
            .unwrap()
            .unwrap()
            .state,
        AutomationState::Active
    );
}
