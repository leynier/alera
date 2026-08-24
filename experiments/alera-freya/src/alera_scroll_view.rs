use freya::prelude::*;

const TRACK_WIDTH: f32 = 12.;
const THUMB_WIDTH: f32 = 4.;
const HOVER_THUMB_WIDTH: f32 = 6.;
const MIN_THUMB_SIZE: f32 = 50.;
const THUMB_IDLE: (u8, u8, u8) = (50, 50, 50);
const THUMB_HOVER: (u8, u8, u8) = (96, 96, 96);
const THUMB_ACTIVE: (u8, u8, u8) = (161, 161, 161);

/// Alera's scroll view keeps Freya's scrolling behavior but supplies a corrected,
/// Flutter-sized scrollbar. Freya v0.5.0-rc.1 mixes local and global coordinates
/// while dragging its thumb, so a nested view cannot reach the end of its track.
#[derive(Clone, PartialEq)]
pub(crate) struct AleraScrollView {
    children: Vec<Element>,
    layout: LayoutData,
    show_scrollbar: bool,
    direction: Direction,
    key: DiffKey,
}

impl Default for AleraScrollView {
    #[allow(clippy::field_reassign_with_default)]
    fn default() -> Self {
        let mut layout = LayoutData::default();
        layout.width = Size::fill();
        layout.height = Size::fill();
        Self {
            children: Vec::new(),
            layout,
            show_scrollbar: true,
            direction: Direction::Vertical,
            key: DiffKey::None,
        }
    }
}

impl AleraScrollView {
    pub(crate) fn new() -> Self {
        Self::default()
    }

    pub(crate) fn show_scrollbar(mut self, show: bool) -> Self {
        self.show_scrollbar = show;
        self
    }

    pub(crate) fn direction(mut self, direction: Direction) -> Self {
        self.direction = direction;
        self
    }
}

impl ChildrenExt for AleraScrollView {
    fn get_children(&mut self) -> &mut Vec<Element> {
        &mut self.children
    }
}

impl KeyExt for AleraScrollView {
    fn write_key(&mut self) -> &mut DiffKey {
        &mut self.key
    }
}

impl LayoutExt for AleraScrollView {
    fn get_layout(&mut self) -> &mut LayoutData {
        &mut self.layout
    }
}

impl ContainerExt for AleraScrollView {}

impl Component for AleraScrollView {
    fn render(&self) -> impl IntoElement {
        if !self.show_scrollbar || self.direction == Direction::Horizontal {
            return native_scroll_view(self).into_element();
        }

        CorrectedVerticalScrollView {
            children: self.children.clone(),
            layout: self.layout.clone(),
        }
        .into_element()
    }

    fn render_key(&self) -> DiffKey {
        self.key.clone().or(self.default_key())
    }
}

fn native_scroll_view(view: &AleraScrollView) -> freya::components::ScrollView {
    freya::components::ScrollView::new()
        .width(view.layout.width.clone())
        .height(view.layout.height.clone())
        .max_width(view.layout.maximum_width.clone())
        .max_height(view.layout.maximum_height.clone())
        .direction(view.direction)
        .show_scrollbar(false)
        .children(view.children.clone())
}

#[derive(Clone, PartialEq)]
struct CorrectedVerticalScrollView {
    children: Vec<Element>,
    layout: LayoutData,
}

impl Component for CorrectedVerticalScrollView {
    fn render(&self) -> impl IntoElement {
        let controller = use_scroll_controller(ScrollConfig::default);
        let viewport = use_state(SizedEventData::default);
        let content = use_state(SizedEventData::default);
        let dragging_thumb = use_state(|| None::<f64>);
        let hovering_track = use_state(|| false);
        let (_, raw_scroll_y): (i32, i32) = controller.into();
        let viewport_height = viewport.read().area.height();
        let content_height = content.read().area.height();
        let scroll_y =
            corrected_scroll_position(content_height, viewport_height, raw_scroll_y as f32);
        let (thumb_y, thumb_height) = scrollbar_geometry(content_height, viewport_height, scroll_y);
        let visible = content_height > viewport_height && viewport_height > MIN_THUMB_SIZE;
        let active = dragging_thumb.read().is_some();
        let hovered = *hovering_track.read();
        let thumb_width = if active || hovered {
            HOVER_THUMB_WIDTH
        } else {
            THUMB_WIDTH
        };
        let thumb_color = if active {
            THUMB_ACTIVE
        } else if hovered {
            THUMB_HOVER
        } else {
            THUMB_IDLE
        };
        let mut viewport_for_size = viewport;
        let mut content_for_size = content;
        let viewport_for_drag = viewport;
        let content_for_drag = content;
        let mut controller_for_drag = controller;
        let dragging_for_move = dragging_thumb;
        let on_global_pointer_move = move |event: Event<PointerEventData>| {
            let Some(grab_offset) = *dragging_for_move.read() else {
                return;
            };
            let viewport = viewport_for_drag.read();
            let content = content_for_drag.read();
            let cursor = event.global_location().y - viewport.area.min_y() as f64 - grab_offset;
            controller_for_drag.scroll_to_y(scroll_position_from_cursor(
                cursor as f32,
                content.area.height(),
                viewport.area.height(),
            ));
            event.prevent_default();
        };
        let mut dragging_for_release = dragging_thumb;
        let on_global_pointer_press = move |_| {
            if dragging_for_release.read().is_some() {
                dragging_for_release.set(None);
            }
        };

        rect()
            .width(self.layout.width.clone())
            .height(self.layout.height.clone())
            .max_width(self.layout.maximum_width.clone())
            .max_height(self.layout.maximum_height.clone())
            .on_sized(move |event: Event<SizedEventData>| {
                viewport_for_size.set_if_modified(event.clone())
            })
            .on_global_pointer_move(on_global_pointer_move)
            .on_global_pointer_press(on_global_pointer_press)
            .child(
                freya::components::ScrollView::new_controlled(controller)
                    .width(Size::fill())
                    .height(Size::fill())
                    .show_scrollbar(false)
                    .child(
                        rect()
                            .width(Size::fill())
                            .height(Size::Inner)
                            .vertical()
                            .on_sized(move |event: Event<SizedEventData>| {
                                content_for_size.set_if_modified(event.clone())
                            })
                            .children(self.children.clone()),
                    ),
            )
            .maybe_child(visible.then(|| {
                let viewport_for_track = viewport;
                let content_for_track = content;
                let mut controller_for_track = controller;
                let mut dragging_for_track = dragging_thumb;
                let mut hovering_for_enter = hovering_track;
                let mut hovering_for_leave = hovering_track;
                let mut dragging_for_thumb = dragging_thumb;
                rect()
                    .position(Position::new_absolute().top(0.).right(0.))
                    .layer(999)
                    .width(Size::px(TRACK_WIDTH))
                    .height(Size::fill())
                    .vertical()
                    .cross_align(Alignment::Center)
                    .on_pointer_enter(move |_| hovering_for_enter.set(true))
                    .on_pointer_leave(move |_| hovering_for_leave.set(false))
                    .on_pointer_down(move |event: Event<PointerEventData>| {
                        if !event.data().is_primary() {
                            return;
                        }
                        let viewport = viewport_for_track.read();
                        let content = content_for_track.read();
                        let grab_offset = thumb_height / 2.;
                        let cursor = event.global_location().y
                            - viewport.area.min_y() as f64
                            - grab_offset as f64;
                        controller_for_track.scroll_to_y(scroll_position_from_cursor(
                            cursor as f32,
                            content.area.height(),
                            viewport.area.height(),
                        ));
                        dragging_for_track.set(Some(grab_offset as f64));
                        event.prevent_default();
                        event.stop_propagation();
                    })
                    .child(rect().height(Size::px(thumb_y)))
                    .child(
                        rect()
                            .width(Size::px(thumb_width))
                            .height(Size::px(thumb_height))
                            .background(thumb_color)
                            .corner_radius(2.)
                            .on_pointer_down(move |event: Event<PointerEventData>| {
                                if !event.data().is_primary() {
                                    return;
                                }
                                dragging_for_thumb.set(Some(event.element_location().y));
                                event.prevent_default();
                                event.stop_propagation();
                            }),
                    )
            }))
    }
}

fn corrected_scroll_position(inner: f32, viewport: f32, position: f32) -> f32 {
    if position > 0. {
        0.
    } else if -position + viewport > inner {
        if viewport < inner {
            -(inner - viewport)
        } else {
            0.
        }
    } else {
        position
    }
}

fn scrollbar_geometry(inner: f32, viewport: f32, position: f32) -> (f32, f32) {
    if viewport <= MIN_THUMB_SIZE || viewport >= inner {
        return (0., 0.);
    }
    let thumb = (viewport * viewport / inner).max(MIN_THUMB_SIZE);
    let available_scroll = inner - viewport;
    let available_track = viewport - thumb;
    let offset = (-position / available_scroll) * available_track;
    (offset, thumb)
}

fn scroll_position_from_cursor(cursor: f32, inner: f32, viewport: f32) -> i32 {
    if viewport <= MIN_THUMB_SIZE || viewport >= inner {
        return 0;
    }
    let thumb = (viewport * viewport / inner).max(MIN_THUMB_SIZE);
    let available_track = viewport - thumb;
    let normalized = cursor.clamp(0., available_track) / available_track;
    -(normalized * (inner - viewport)) as i32
}

#[cfg(test)]
mod tests {
    use super::*;
    use freya_testing::prelude::*;

    #[test]
    fn thumb_reaches_both_ends_even_when_viewport_has_a_global_offset() {
        let inner = 1_600.;
        let viewport = 400.;
        let (_, thumb) = scrollbar_geometry(inner, viewport, 0.);
        assert_eq!(scroll_position_from_cursor(0., inner, viewport), 0);
        assert_eq!(
            scroll_position_from_cursor(viewport - thumb, inner, viewport),
            -1_200
        );
    }

    #[test]
    fn scrollbar_geometry_matches_the_scrollable_range() {
        let (start, thumb) = scrollbar_geometry(1_000., 250., 0.);
        let (end, end_thumb) = scrollbar_geometry(1_000., 250., -750.);
        assert_eq!((start, thumb), (0., 62.5));
        assert_eq!(end_thumb, thumb);
        assert_eq!(end, 187.5);
    }

    #[test]
    fn nested_scrollbar_drag_reaches_the_last_row() {
        let mut runner = launch_test(|| {
            rect().padding(Gaps::new(100., 100., 100., 100.)).child(
                AleraScrollView::new()
                    .width(Size::px(300.))
                    .height(Size::px(300.))
                    .children((0..4).map(|index| {
                        rect()
                            .height(Size::px(200.))
                            .child(label().text(format!("Row {index}")))
                    })),
            )
        });
        runner.sync_and_update();
        let first = runner
            .find(|node, element| {
                Label::try_downcast(element)
                    .filter(|label| label.text.as_ref() == "Row 0")
                    .map(|_| node)
            })
            .expect("first row");
        let last = runner
            .find(|node, element| {
                Label::try_downcast(element)
                    .filter(|label| label.text.as_ref() == "Row 3")
                    .map(|_| node)
            })
            .expect("last row");
        assert!(first.is_visible());
        assert!(!last.is_visible());

        runner.move_cursor((395., 120.));
        runner.press_cursor((395., 120.));
        runner.move_cursor((395., 307.5));
        runner.release_cursor((395., 307.5));

        assert!(!first.is_visible());
        assert!(last.is_visible());
    }
}
