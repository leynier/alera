use crate::workspace_git::{GitHistoryColor, GitHistoryItem, GitHistoryRef, GitSnapshot};

use super::{
    GraphNode, HistoryGraphKind, HistoryGraphRow, HistoryGraphViewModel, INCOMING_CHANGES_ID,
    OUTGOING_CHANGES_ID,
};

pub(super) fn add_boundary_rows(rows: &mut Vec<HistoryGraphViewModel>, snapshot: &GitSnapshot) {
    let metadata = &snapshot.history_metadata;
    let (Some(current_ref), Some(remote_ref), Some(merge_base)) = (
        metadata.current_ref.as_ref(),
        metadata.remote_ref.as_ref(),
        metadata.merge_base.as_deref(),
    ) else {
        return;
    };
    if current_ref.revision == remote_ref.revision {
        return;
    }
    if metadata.has_incoming_changes && remote_ref.revision.as_deref() != Some(merge_base) {
        add_incoming_row(rows, remote_ref, merge_base);
    }
    if metadata.has_outgoing_changes && current_ref.revision.as_deref() != Some(merge_base) {
        add_outgoing_row(rows, current_ref, merge_base);
    }
}

fn add_incoming_row(
    rows: &mut Vec<HistoryGraphViewModel>,
    remote_ref: &GitHistoryRef,
    merge_base: &str,
) {
    let before_index = rows
        .iter()
        .rposition(|row| row.graph.output.iter().any(|node| node.id == merge_base));
    let Some(after_index) = rows.iter().position(|row| row.item.full_id == merge_base) else {
        return;
    };
    if before_index.is_some_and(|index| {
        rows[index].item.parent_ids.len() == 2
            && rows[index]
                .item
                .parent_ids
                .iter()
                .any(|parent| parent == merge_base)
    }) {
        return;
    }

    let mut input = before_index
        .map(|index| rows[index].graph.output.clone())
        .unwrap_or_else(|| rows[after_index].graph.input.clone());
    input = input
        .into_iter()
        .map(|node| remote_boundary_input_node(node, merge_base))
        .collect();
    let mut output = rows[after_index].graph.input.clone();
    ensure_incoming_remote_lane(&mut input, &mut output, merge_base);
    if let Some(index) = before_index {
        rows[index].graph.input = rows[index]
            .graph
            .input
            .clone()
            .into_iter()
            .map(|node| remote_boundary_input_node(node, merge_base))
            .collect();
        rows[index].graph.output = input.clone();
    }

    rows.insert(
        after_index,
        boundary_view_model(
            INCOMING_CHANGES_ID,
            "Incoming Changes",
            remote_ref.name.clone(),
            merge_base,
            input,
            output.clone(),
            HistoryGraphKind::IncomingChanges,
            rows.first().map_or(0, |row| row.item.id.len()),
        ),
    );
    rows[after_index + 1].graph.input = output;
}

fn add_outgoing_row(
    rows: &mut Vec<HistoryGraphViewModel>,
    current_ref: &GitHistoryRef,
    merge_base: &str,
) {
    let Some(current_revision) = current_ref.revision.as_deref() else {
        return;
    };
    let current_index = rows
        .iter()
        .position(|row| row.kind == HistoryGraphKind::Head && row.item.full_id == current_revision);
    let anchor_index = current_index.or_else(|| first_visible_outgoing_index(rows, merge_base));
    let Some(anchor_index) = anchor_index else {
        return;
    };
    let anchor_revision = current_index
        .map(|_| current_revision.to_owned())
        .unwrap_or_else(|| rows[anchor_index].item.full_id.clone());
    let input = rows[anchor_index].graph.input.clone();
    let mut output = input.clone();
    output.push(GraphNode {
        id: anchor_revision.clone(),
        color: GitHistoryColor::Reference,
    });
    rows.insert(
        anchor_index,
        boundary_view_model(
            OUTGOING_CHANGES_ID,
            "Outgoing Changes",
            current_ref.name.clone(),
            &anchor_revision,
            input,
            output,
            HistoryGraphKind::OutgoingChanges,
            rows.first().map_or(0, |row| row.item.id.len()),
        ),
    );
    rows[anchor_index + 1].graph.input.push(GraphNode {
        id: anchor_revision,
        color: GitHistoryColor::Reference,
    });
}

#[allow(clippy::too_many_arguments)]
fn boundary_view_model(
    id: &str,
    subject: &str,
    author: String,
    parent_id: &str,
    input: Vec<GraphNode>,
    output: Vec<GraphNode>,
    kind: HistoryGraphKind,
    display_id_len: usize,
) -> HistoryGraphViewModel {
    let item = GitHistoryItem {
        full_id: id.to_owned(),
        id: "0".repeat(display_id_len),
        parent_ids: vec![parent_id.to_owned()],
        subject: subject.to_owned(),
        message: String::new(),
        author: Some(author),
        timestamp_millis: None,
        references: Vec::new(),
    };
    HistoryGraphViewModel {
        graph: HistoryGraphRow {
            input,
            output,
            item_id: item.full_id.clone(),
            parent_ids: item.parent_ids.clone(),
            kind,
        },
        item,
        kind,
    }
}

fn first_visible_outgoing_index(rows: &[HistoryGraphViewModel], merge_base: &str) -> Option<usize> {
    let end = rows
        .iter()
        .position(|row| row.item.full_id == merge_base)
        .unwrap_or(rows.len());
    (0..end).find(|index| !rows[*index].kind.boundary())
}

fn remote_boundary_input_node(mut node: GraphNode, merge_base: &str) -> GraphNode {
    if node.id == merge_base && node.color == GitHistoryColor::RemoteReference {
        node.id = INCOMING_CHANGES_ID.to_owned();
    }
    node
}

fn ensure_incoming_remote_lane(
    input: &mut Vec<GraphNode>,
    output: &mut Vec<GraphNode>,
    merge_base: &str,
) {
    if !has_node(output, merge_base, GitHistoryColor::RemoteReference) {
        let local_index = output
            .iter()
            .position(|node| node.id == merge_base && node.color == GitHistoryColor::Reference);
        output.insert(
            local_index.map_or(input.len(), |index| index + 1),
            GraphNode {
                id: merge_base.to_owned(),
                color: GitHistoryColor::RemoteReference,
            },
        );
    }
    if has_node(input, INCOMING_CHANGES_ID, GitHistoryColor::RemoteReference) {
        return;
    }
    let remote_index = output
        .iter()
        .position(|node| node.id == merge_base && node.color == GitHistoryColor::RemoteReference);
    input.insert(
        remote_index.unwrap_or(input.len()),
        GraphNode {
            id: INCOMING_CHANGES_ID.to_owned(),
            color: GitHistoryColor::RemoteReference,
        },
    );
}

fn has_node(nodes: &[GraphNode], id: &str, color: GitHistoryColor) -> bool {
    nodes
        .iter()
        .any(|node| node.id == id && node.color == color)
}
