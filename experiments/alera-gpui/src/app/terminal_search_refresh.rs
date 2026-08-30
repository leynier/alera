use std::time::Duration;

use gpui::Context;

use super::AleraApp;

impl AleraApp {
    pub(super) fn terminal_search_is_current(&self) -> bool {
        self.terminal_search.as_ref().is_some_and(|search| {
            self.terminal_sessions
                .get(&search.session_id)
                .is_some_and(|session| search.revision == Some(session.emulator.search_revision()))
        })
    }

    pub(super) fn schedule_terminal_search_refresh(&mut self, cx: &mut Context<Self>) {
        if self.terminal_search_is_current() {
            return;
        }
        let Some(search) = self.terminal_search.as_mut() else {
            return;
        };
        if search.refresh_task.is_some() {
            return;
        }
        let Some(session) = self.terminal_sessions.get(&search.session_id) else {
            return;
        };
        search.matches.clear();
        search.selected_index = 0;
        if search.matcher.is_empty() {
            search.revision = Some(session.emulator.search_revision());
            return;
        }
        let session_id = search.session_id.clone();
        let query = search.query.clone();
        let matcher = search.matcher.clone();
        search.refresh_task = Some(cx.spawn(async move |this, cx| {
            // Coalesce streaming writes, then yield between bounded grid slices.
            // Replacing/closing search drops this task; no permanent idle timer.
            cx.background_executor()
                .timer(Duration::from_millis(120))
                .await;
            let snapshot = this
                .update(cx, |this, _| {
                    let session = this.terminal_sessions.get(&session_id)?;
                    let (_, history, rows) = session.emulator.scroll_metrics();
                    Some((session.emulator.search_revision(), history + rows))
                })
                .ok()
                .flatten();
            let Some((revision, total)) = snapshot else {
                let _ = this.update(cx, |this, cx| {
                    if this.terminal_search.as_ref().is_some_and(|search| {
                        search.session_id == session_id && search.query == query
                    }) {
                        this.terminal_search = None;
                        cx.notify();
                    }
                });
                return;
            };
            let mut matches = Vec::new();
            let mut current = true;
            for start in (0..total).step_by(128) {
                let batch = this
                    .update(cx, |this, _| {
                        let session = this.terminal_sessions.get(&session_id)?;
                        if session.emulator.search_revision() != revision {
                            return None;
                        }
                        Some(
                            session
                                .emulator
                                .search_matches_in_rows(&matcher, start..start.saturating_add(128)),
                        )
                    })
                    .ok()
                    .flatten();
                let Some(batch) = batch else {
                    current = false;
                    break;
                };
                matches.extend(batch);
                if start + 128 < total {
                    cx.background_executor()
                        .timer(Duration::from_millis(1))
                        .await;
                }
            }
            let _ = this.update(cx, |this, cx| {
                let current = current
                    && this
                        .terminal_sessions
                        .get(&session_id)
                        .is_some_and(|session| session.emulator.search_revision() == revision);
                let Some(search) = this.terminal_search.as_mut() else {
                    return;
                };
                if search.session_id != session_id || search.query != query {
                    return;
                }
                search.refresh_task = None;
                let mut first_line = None;
                if current {
                    search.matches = matches;
                    search.revision = Some(revision);
                    if search.scroll_to_first {
                        first_line = search.matches.first().map(|hit| hit.line_index);
                        search.scroll_to_first = false;
                    }
                }
                if let Some(line) = first_line {
                    this.scroll_terminal_to_search_match(&session_id, line, cx);
                }
                if !current {
                    this.schedule_terminal_search_refresh(cx);
                }
                cx.notify();
            });
        }));
        cx.notify();
    }
}
