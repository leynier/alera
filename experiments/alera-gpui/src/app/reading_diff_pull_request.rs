use gpui::{
    div, px, AnyElement, Context, InteractiveElement as _, IntoElement as _,
    ParentElement as _, Styled as _,
};

use super::forge_surface::resolve_forge_identity;
use super::AleraApp;
use crate::reading_diff_service::{ReadingDiffProgress, ReadingDiffStage};
use crate::theme;

impl AleraApp {
    pub(super) fn request_pull_request_reading_diff(
        &mut self,
        review_number: u64,
        ignore_cache: bool,
        cx: &mut Context<Self>,
    ) {
        let Some(workspace_path) = self.selected_source_control_path() else {
            return;
        };
        let Some(workspace_id) = self.selected_workspace_id.clone() else {
            return;
        };
        let project_id = self
            .snapshot
            .project_for_workspace(&workspace_id)
            .map(|project| project.id.clone());
        let key = reading_diff_review_key(&workspace_id, review_number);
        self.reading_diff_busy_key = Some(key.clone());
        self.reading_diff_progress = Some(ReadingDiffProgress {
            stage: ReadingDiffStage::Preparing,
            completed_chunks: 0,
            total_chunks: 0,
            current_chunk: None,
        });
        self.reading_diff_errors.remove(&key);
        let bridge = self.bridge.clone();
        let workspace_service = self.workspace_service.clone();
        let forge_service = self.forge_service.clone();
        cx.spawn(async move |this, cx| {
            let result = match resolve_forge_identity(
                &bridge,
                &workspace_service,
                &workspace_id,
                &workspace_path,
                project_id.as_deref(),
            )
            .await
            {
                Ok(identity) => forge_service.review_diff(identity, review_number).await,
                Err(reason) => Err(format!("Pull Request Diff Is Unavailable: {reason:?}")),
            };
            let Some(this) = this.upgrade() else {
                return;
            };
            this.update(cx, |this, cx| {
                if this.reading_diff_busy_key.as_deref() != Some(&key) {
                    return;
                }
                this.reading_diff_busy_key = None;
                this.reading_diff_progress = None;
                match result {
                    Ok(raw_diff) => {
                        this.reading_diff_confirmation = Some(this.build_reading_diff_request(
                            key.clone(),
                            raw_diff,
                            workspace_path,
                            ignore_cache,
                        ));
                    }
                    Err(error) => {
                        this.reading_diff_errors.insert(key.clone(), error.into());
                    }
                }
                cx.notify();
            });
        })
        .detach();
        cx.notify();
    }

    pub(super) fn render_pull_request_reading_diff(
        &self,
        workspace_id: &str,
        review_number: u64,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let key = reading_diff_review_key(workspace_id, review_number);
        if !self.reading_diff_visible(&key) {
            return div().into_any_element();
        }
        div()
            .id("pull-request-reading-diff")
            .mt_3()
            .min_h(px(320.0))
            .rounded_md()
            .border_1()
            .border_color(theme::border_subtle())
            .overflow_hidden()
            .child(self.render_reading_diff_content(&key, cx))
            .into_any_element()
    }
}
 
pub(super) fn reading_diff_review_key(workspace_id: &str, review_number: u64) -> String {
    format!("pull-request:{workspace_id}:{review_number}")
}
