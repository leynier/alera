use std::collections::BTreeMap;

use gpui::{
    canvas, div, point, px, quad, size, transparent_black, Bounds, IntoElement, ParentElement as _,
    PathBuilder, Pixels, Rgba, Styled as _, Window,
};

use crate::theme;
use crate::workspace_git::{GitHistoryColor, GitHistoryItem, GitHistoryRef, GitSnapshot};

mod boundaries;
#[cfg(test)]
mod tests;

const LANE_WIDTH: f32 = 11.0;
const GRAPH_HEIGHT: f32 = 24.0;
const NODE_Y: f32 = GRAPH_HEIGHT / 2.0;
const CIRCLE_RADIUS: f32 = 3.5;
const INCOMING_CHANGES_ID: &str = "git-history-incoming-changes";
const OUTGOING_CHANGES_ID: &str = "git-history-outgoing-changes";

#[derive(Clone)]
struct GraphNode {
    id: String,
    color: GitHistoryColor,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum HistoryGraphKind {
    Head,
    Node,
    IncomingChanges,
    OutgoingChanges,
}

impl HistoryGraphKind {
    pub(super) fn boundary(self) -> bool {
        matches!(self, Self::IncomingChanges | Self::OutgoingChanges)
    }
}

#[derive(Clone)]
pub(super) struct HistoryGraphRow {
    input: Vec<GraphNode>,
    output: Vec<GraphNode>,
    item_id: String,
    parent_ids: Vec<String>,
    kind: HistoryGraphKind,
}

#[derive(Clone)]
pub(super) struct HistoryGraphViewModel {
    pub(super) item: GitHistoryItem,
    pub(super) graph: HistoryGraphRow,
    pub(super) kind: HistoryGraphKind,
}

pub(super) fn build_history_graph_view_models(
    snapshot: &GitSnapshot,
) -> Vec<HistoryGraphViewModel> {
    let metadata = &snapshot.history_metadata;
    let color_map = default_color_map(snapshot);
    let mut rows = Vec::with_capacity(snapshot.history.len() + 2);
    let mut previous_output = Vec::<GraphNode>::new();
    let mut next_color = 0usize;

    for item in &snapshot.history {
        let input = previous_output.clone();
        let mut output = Vec::new();
        let mut first_parent_added = false;
        if !item.parent_ids.is_empty() {
            for node in &input {
                if node.id == item.full_id {
                    if !first_parent_added {
                        output.push(GraphNode {
                            id: item.parent_ids[0].clone(),
                            color: label_color(item, &color_map).unwrap_or(node.color),
                        });
                        first_parent_added = true;
                    }
                } else {
                    output.push(node.clone());
                }
            }
        }
        for parent_index in if first_parent_added { 1 } else { 0 }..item.parent_ids.len() {
            let color = if parent_index == 0 {
                label_color(item, &color_map)
            } else {
                parent_label_color(
                    &snapshot.history,
                    &item.parent_ids[parent_index],
                    &color_map,
                )
            }
            .unwrap_or_else(|| {
                let color = lane_color(next_color);
                next_color = (next_color + 1) % 5;
                color
            });
            output.push(GraphNode {
                id: item.parent_ids[parent_index].clone(),
                color,
            });
        }

        let kind = if metadata
            .current_ref
            .as_ref()
            .and_then(|item_ref| item_ref.revision.as_deref())
            == Some(item.full_id.as_str())
        {
            HistoryGraphKind::Head
        } else {
            HistoryGraphKind::Node
        };
        let mut item = item.clone();
        color_and_sort_refs(&mut item.references, snapshot, &color_map);
        rows.push(HistoryGraphViewModel {
            graph: HistoryGraphRow {
                input,
                output: output.clone(),
                item_id: item.full_id.clone(),
                parent_ids: item.parent_ids.clone(),
                kind,
            },
            item,
            kind,
        });
        previous_output = output;
    }

    boundaries::add_boundary_rows(&mut rows, snapshot);
    rows
}

fn default_color_map(snapshot: &GitSnapshot) -> BTreeMap<String, GitHistoryColor> {
    [
        (
            snapshot.history_metadata.current_ref.as_ref(),
            GitHistoryColor::Reference,
        ),
        (
            snapshot.history_metadata.remote_ref.as_ref(),
            GitHistoryColor::RemoteReference,
        ),
        (
            snapshot.history_metadata.base_ref.as_ref(),
            GitHistoryColor::BaseReference,
        ),
    ]
    .into_iter()
    .filter_map(|(item_ref, color)| item_ref.map(|item_ref| (item_ref.id.clone(), color)))
    .collect()
}

fn label_color(
    item: &GitHistoryItem,
    color_map: &BTreeMap<String, GitHistoryColor>,
) -> Option<GitHistoryColor> {
    if item.full_id == INCOMING_CHANGES_ID {
        return Some(GitHistoryColor::RemoteReference);
    }
    if item.full_id == OUTGOING_CHANGES_ID {
        return Some(GitHistoryColor::Reference);
    }
    item.references
        .iter()
        .find_map(|item_ref| color_map.get(&item_ref.id).copied())
}

fn parent_label_color(
    items: &[GitHistoryItem],
    parent_id: &str,
    color_map: &BTreeMap<String, GitHistoryColor>,
) -> Option<GitHistoryColor> {
    items
        .iter()
        .find(|item| item.full_id == parent_id)
        .and_then(|item| label_color(item, color_map))
}

fn color_and_sort_refs(
    references: &mut [GitHistoryRef],
    snapshot: &GitSnapshot,
    color_map: &BTreeMap<String, GitHistoryColor>,
) {
    for item_ref in references.iter_mut() {
        item_ref.color = color_map.get(&item_ref.id).copied();
    }
    references.sort_by_key(|item_ref| {
        if Some(item_ref.id.as_str())
            == snapshot
                .history_metadata
                .current_ref
                .as_ref()
                .map(|item_ref| item_ref.id.as_str())
        {
            1
        } else if Some(item_ref.id.as_str())
            == snapshot
                .history_metadata
                .remote_ref
                .as_ref()
                .map(|item_ref| item_ref.id.as_str())
        {
            2
        } else if Some(item_ref.id.as_str())
            == snapshot
                .history_metadata
                .base_ref
                .as_ref()
                .map(|item_ref| item_ref.id.as_str())
        {
            3
        } else if item_ref.color.is_some() {
            4
        } else {
            99
        }
    });
}

pub(super) fn history_graph(row: &HistoryGraphRow) -> impl IntoElement {
    let row = row.clone();
    let lanes = row.input.len().max(row.output.len()).max(1) + 1;
    div()
        .w(px(LANE_WIDTH * lanes as f32))
        .h(px(GRAPH_HEIGHT))
        .child(
            canvas(
                |_, _, _| {},
                move |bounds, _, window, _| paint_graph_row(window, bounds, &row),
            )
            .size_full(),
        )
}

fn paint_graph_row(window: &mut Window, bounds: Bounds<Pixels>, row: &HistoryGraphRow) {
    let input_index = row.input.iter().position(|node| node.id == row.item_id);
    let circle_index = input_index.unwrap_or(row.input.len());
    let circle_color = row
        .output
        .get(circle_index)
        .or_else(|| row.input.get(circle_index))
        .map(|node| node.color)
        .unwrap_or(GitHistoryColor::Reference);
    let mut output_index = 0usize;
    for (index, node) in row.input.iter().enumerate() {
        if input_index == Some(index) {
            if index != circle_index {
                stroke(window, node.color, |path| {
                    path.move_to(graph_point(bounds, index, 0.0));
                    path.curve_to(
                        graph_point(bounds, circle_index, NODE_Y),
                        graph_point(bounds, index, NODE_Y),
                    );
                });
            } else {
                output_index += 1;
            }
            continue;
        }
        if row
            .output
            .get(output_index)
            .is_some_and(|output| output.id == node.id)
        {
            stroke(window, node.color, |path| {
                path.move_to(graph_point(bounds, index, 0.0));
                if index == output_index {
                    path.line_to(graph_point(bounds, index, GRAPH_HEIGHT));
                } else {
                    path.line_to(graph_point(bounds, index, 6.0));
                    path.curve_to(
                        graph_point(bounds, output_index, NODE_Y),
                        graph_point(bounds, index, NODE_Y),
                    );
                    path.line_to(graph_point(bounds, output_index, GRAPH_HEIGHT));
                }
            });
            output_index += 1;
        }
    }
    for parent_id in row.parent_ids.iter().skip(1) {
        let Some(parent_index) = row.output.iter().rposition(|node| node.id == *parent_id) else {
            continue;
        };
        stroke(window, row.output[parent_index].color, |path| {
            path.move_to(graph_point(bounds, parent_index, NODE_Y));
            path.line_to(graph_point(bounds, circle_index, NODE_Y));
            path.move_to(graph_point(bounds, parent_index, NODE_Y));
            path.curve_to(
                graph_point(bounds, parent_index, GRAPH_HEIGHT),
                graph_point(bounds, parent_index, GRAPH_HEIGHT),
            );
        });
    }
    if let Some(index) = input_index {
        stroke(window, row.input[index].color, |path| {
            path.move_to(graph_point(bounds, circle_index, 0.0));
            path.line_to(graph_point(bounds, circle_index, NODE_Y));
        });
    }
    if !row.parent_ids.is_empty() {
        stroke(window, circle_color, |path| {
            path.move_to(graph_point(bounds, circle_index, NODE_Y));
            path.line_to(graph_point(bounds, circle_index, GRAPH_HEIGHT));
        });
    }
    paint_node(window, bounds, row, circle_index, circle_color);
}

fn paint_node(
    window: &mut Window,
    bounds: Bounds<Pixels>,
    row: &HistoryGraphRow,
    circle_index: usize,
    color: GitHistoryColor,
) {
    let center = graph_point(bounds, circle_index, NODE_Y);
    let boundary = row.kind.boundary();
    let radius = if row.kind == HistoryGraphKind::Head || boundary {
        CIRCLE_RADIUS + 3.0
    } else if row.parent_ids.len() > 1 {
        CIRCLE_RADIUS + 1.0
    } else {
        CIRCLE_RADIUS
    };
    paint_circle(
        window,
        center,
        radius,
        graph_color(color),
        px(0.0),
        transparent_black().into(),
    );
    if row.kind == HistoryGraphKind::Head || boundary || row.parent_ids.len() > 1 {
        let inner = if row.kind == HistoryGraphKind::Head || boundary {
            CIRCLE_RADIUS
        } else {
            CIRCLE_RADIUS - 1.5
        };
        paint_circle(
            window,
            center,
            inner,
            theme::app_background(),
            px(0.0),
            transparent_black().into(),
        );
    }
    if boundary {
        paint_circle(
            window,
            center,
            CIRCLE_RADIUS + 1.0,
            transparent_black().into(),
            px(1.0),
            graph_color(color),
        );
    }
}

fn paint_circle(
    window: &mut Window,
    center: gpui::Point<Pixels>,
    radius: f32,
    fill: Rgba,
    border_width: Pixels,
    border_color: Rgba,
) {
    window.paint_quad(quad(
        Bounds::new(
            point(center.x - px(radius), center.y - px(radius)),
            size(px(radius * 2.0), px(radius * 2.0)),
        ),
        px(radius),
        fill,
        border_width,
        border_color,
        Default::default(),
    ));
}

fn stroke(window: &mut Window, color: GitHistoryColor, build: impl FnOnce(&mut PathBuilder)) {
    let mut path = PathBuilder::stroke(px(1.0));
    build(&mut path);
    if let Ok(path) = path.build() {
        window.paint_path(path, graph_color(color));
    }
}

fn graph_point(bounds: Bounds<Pixels>, lane: usize, y: f32) -> gpui::Point<Pixels> {
    point(
        bounds.origin.x + px(LANE_WIDTH * (lane + 1) as f32),
        bounds.origin.y + px(y),
    )
}

fn lane_color(index: usize) -> GitHistoryColor {
    match index % 5 {
        0 => GitHistoryColor::Lane1,
        1 => GitHistoryColor::Lane2,
        2 => GitHistoryColor::Lane3,
        3 => GitHistoryColor::Lane4,
        _ => GitHistoryColor::Lane5,
    }
}

fn graph_color(color: GitHistoryColor) -> Rgba {
    match color {
        GitHistoryColor::Reference => theme::success(),
        GitHistoryColor::RemoteReference => theme::info(),
        GitHistoryColor::BaseReference => theme::warning(),
        GitHistoryColor::Lane1 => gpui::rgb(0x82aaff),
        GitHistoryColor::Lane2 => gpui::rgb(0xc792ea),
        GitHistoryColor::Lane3 => gpui::rgb(0xffcb6b),
        GitHistoryColor::Lane4 => gpui::rgb(0x89ddff),
        GitHistoryColor::Lane5 => theme::text_muted(),
    }
}
