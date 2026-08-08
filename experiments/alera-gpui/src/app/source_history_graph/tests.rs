use crate::workspace_git::{
    GitHistoryColor, GitHistoryItem, GitHistoryMetadata, GitHistoryRef, GitSnapshot,
};

use super::{
    build_history_graph_view_models, HistoryGraphKind, INCOMING_CHANGES_ID, OUTGOING_CHANGES_ID,
};

#[test]
fn adds_incoming_and_outgoing_boundary_rows_for_divergent_branches() {
    let current_ref = history_ref("refs/heads/main", "main", "local");
    let remote_ref = history_ref("refs/remotes/origin/main", "origin/main", "remote");
    let snapshot = snapshot(
        current_ref,
        remote_ref,
        Some("base"),
        true,
        true,
        vec![
            history_item(
                "local",
                &["base"],
                &[history_ref("refs/heads/main", "main", "local")],
            ),
            history_item(
                "remote",
                &["base"],
                &[history_ref(
                    "refs/remotes/origin/main",
                    "origin/main",
                    "remote",
                )],
            ),
            history_item("base", &[], &[]),
        ],
    );

    let rows = build_history_graph_view_models(&snapshot);
    let ids = rows
        .iter()
        .map(|row| row.item.full_id.as_str())
        .collect::<Vec<_>>();

    let outgoing = ids
        .iter()
        .position(|id| *id == OUTGOING_CHANGES_ID)
        .expect("outgoing boundary");
    let incoming = ids
        .iter()
        .position(|id| *id == INCOMING_CHANGES_ID)
        .expect("incoming boundary");
    assert!(outgoing < ids.iter().position(|id| *id == "local").unwrap());
    assert!(incoming < ids.iter().position(|id| *id == "base").unwrap());
}

#[test]
fn colors_and_sorts_current_and_remote_refs() {
    let current_ref = history_ref("refs/heads/main", "main", "head");
    let remote_ref = history_ref("refs/remotes/origin/main", "origin/main", "head");
    let snapshot = snapshot(
        current_ref.clone(),
        remote_ref.clone(),
        None,
        false,
        false,
        vec![history_item("head", &[], &[remote_ref, current_ref])],
    );

    let rows = build_history_graph_view_models(&snapshot);
    let references = &rows[0].item.references;

    assert_eq!(references[0].id, "refs/heads/main");
    assert_eq!(references[0].color, Some(GitHistoryColor::Reference));
    assert_eq!(references[1].id, "refs/remotes/origin/main");
    assert_eq!(references[1].color, Some(GitHistoryColor::RemoteReference));
}

#[test]
fn adds_outgoing_boundary_when_head_revision_is_filtered_out() {
    let current_ref = history_ref("refs/heads/main", "main", "head");
    let remote_ref = history_ref("refs/remotes/origin/main", "origin/main", "base");
    let snapshot = snapshot(
        current_ref,
        remote_ref,
        Some("base"),
        false,
        true,
        vec![
            history_item("scoped-local", &["base"], &[]),
            history_item(
                "base",
                &[],
                &[history_ref(
                    "refs/remotes/origin/main",
                    "origin/main",
                    "base",
                )],
            ),
        ],
    );

    let rows = build_history_graph_view_models(&snapshot);
    let outgoing_index = rows
        .iter()
        .position(|row| row.item.full_id == OUTGOING_CHANGES_ID)
        .expect("outgoing boundary");

    assert_eq!(outgoing_index, 0);
    assert_eq!(rows[1].item.full_id, "scoped-local");
    assert_eq!(rows[0].item.parent_ids, vec!["scoped-local"]);
    assert_eq!(rows[0].kind, HistoryGraphKind::OutgoingChanges);
    assert!(rows[1]
        .graph
        .input
        .iter()
        .any(|node| { node.id == "scoped-local" && node.color == GitHistoryColor::Reference }));
}

fn snapshot(
    current_ref: GitHistoryRef,
    remote_ref: GitHistoryRef,
    merge_base: Option<&str>,
    has_incoming_changes: bool,
    has_outgoing_changes: bool,
    history: Vec<GitHistoryItem>,
) -> GitSnapshot {
    GitSnapshot {
        history,
        history_metadata: GitHistoryMetadata {
            current_ref: Some(current_ref),
            remote_ref: Some(remote_ref),
            merge_base: merge_base.map(str::to_owned),
            has_incoming_changes,
            has_outgoing_changes,
            limit: 50,
            ..GitHistoryMetadata::default()
        },
        ..GitSnapshot::default()
    }
}

fn history_item(id: &str, parent_ids: &[&str], references: &[GitHistoryRef]) -> GitHistoryItem {
    GitHistoryItem {
        full_id: id.to_owned(),
        id: id.to_owned(),
        parent_ids: parent_ids
            .iter()
            .map(|parent| (*parent).to_owned())
            .collect(),
        subject: format!("{id} commit"),
        message: format!("{id} commit"),
        author: None,
        timestamp_millis: None,
        references: references.to_vec(),
    }
}

fn history_ref(id: &str, name: &str, revision: &str) -> GitHistoryRef {
    GitHistoryRef {
        id: id.to_owned(),
        name: name.to_owned(),
        revision: Some(revision.to_owned()),
        category: String::new(),
        color: None,
    }
}
