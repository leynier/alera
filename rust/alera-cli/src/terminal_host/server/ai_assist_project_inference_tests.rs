use alera_core::runtime::{Project, ProjectKind, WorkspaceSection};
use chrono::Utc;

use super::{parse_project_identity, project_identity_prompt};

fn project(id: &str, name: &str) -> Project {
    Project {
        id: id.to_owned(),
        name: name.to_owned(),
        repo_path: format!("/repos/{id}"),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        kind: ProjectKind::GitRepository,
    }
}

fn section(id: &str, name: &str) -> WorkspaceSection {
    WorkspaceSection {
        id: id.to_owned(),
        name: name.to_owned(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
    }
}

#[test]
fn prompt_lists_projects_and_sections_and_asks_for_the_project() {
    let text = project_identity_prompt(
        "Fix the login screen",
        "Use fix/ branches.",
        &[project("p1", "Alera"), project("p2", "EducUp")],
        &[section("s1", "Alera")],
    );
    assert!(text.contains("project, workspaceName, branchName, and section"));
    assert!(text.contains("- Alera (/repos/p1)"));
    assert!(text.contains("- EducUp (/repos/p2)"));
    assert!(text.contains("Sections:\n- Alera"));
    assert!(text.contains("Fix the login screen"));
    assert!(text.contains("Use fix/ branches."));
}

#[test]
fn a_listed_project_resolves_to_its_id_with_section() {
    let projects = [project("p1", "Alera"), project("p2", "EducUp")];
    let sections = [section("s1", "Alera")];
    let value = parse_project_identity(
        r#"{"project":"alera","workspaceName":"Fix Login","branchName":"fix/login","section":"Alera"}"#,
        &projects,
        &sections,
    )
    .unwrap();
    assert_eq!(value["projectId"], "p1");
    assert_eq!(value["branchName"], "fix/login");
    assert_eq!(value["sectionId"], "s1");
}

#[test]
fn unknown_unlisted_or_ambiguous_projects_are_not_guessed() {
    let projects = [project("p1", "Alera"), project("p2", "alera")];
    for raw in [
        r#"{"project":"Unknown","workspaceName":"X","branchName":"fix/x"}"#,
        r#"{"project":"Other","workspaceName":"X","branchName":"fix/x"}"#,
        r#"{"project":"ALERA","workspaceName":"X","branchName":"fix/x"}"#,
        r#"{"workspaceName":"X","branchName":"fix/x"}"#,
    ] {
        let value = parse_project_identity(raw, &projects, &[]).unwrap();
        assert_eq!(value["projectUnknown"], true, "{raw}");
        assert!(value.get("projectId").is_none());
    }
}
