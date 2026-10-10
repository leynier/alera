//! The `mobile.pullRequest.*` write verbs for every forge: comment, reply,
//! edit, merge, draft status, close, link, unlink, create, and Ship. Parsing
//! is forge-neutral; each forge decides what it supports (GitHub has no
//! provider-default merge, GitLab no review summaries).

use alera_core::runtime::{RuntimeStore, Workspace};
use serde_json::Value;

use crate::terminal_host::host_error::{HostError, HostResult};

use super::super::mobile_pull_request_busy::BusyGuard;
use super::super::mobile_pull_request_ship::{ship_pull_request, ShipRequest, ShipScope};
use super::super::requests::{optional_string_key, require_string_key};
use super::links::{create_and_link, save_link};
use super::model::MergeMethod;
use super::provider::{CommentLocator, CommentSource, CreateInput};
use super::{require_local_workspace, workspace_forge};

#[derive(Debug, PartialEq)]
pub(crate) enum ForgeAction {
    Comment {
        number: i64,
        body: String,
        reply_to: Option<CommentLocator>,
    },
    CommentUpdate {
        number: i64,
        locator: CommentLocator,
        body: String,
    },
    Merge {
        number: i64,
        method: MergeMethod,
        expected_head: Option<String>,
    },
    DraftStatus {
        number: i64,
        draft: bool,
    },
    Close {
        number: i64,
    },
    Link {
        reference: String,
    },
    Unlink {
        number: i64,
        url: Option<String>,
    },
    Create(CreateInput),
    Ship(ShipRequest),
}

pub(crate) fn parse_forge_action(request_type: &str, payload: &Value) -> HostResult<ForgeAction> {
    let number = || positive_i64(payload, "number");
    let body = || {
        let body = require_string_key(payload, "body")?;
        if body.trim().is_empty() {
            return Err(HostError::state("Enter a comment before posting."));
        }
        Ok(body)
    };
    let thread_id = |key: &str| optional_string_key(payload, key).filter(|id| !id.is_empty());
    Ok(match request_type {
        "mobile.pullRequest.comment" => ForgeAction::Comment {
            number: number()?,
            body: body()?,
            reply_to: payload
                .get("replyToCommentId")
                .and_then(Value::as_i64)
                .map(|comment_id| CommentLocator {
                    source: CommentSource::ReviewThread,
                    comment_id,
                    thread_id: thread_id("replyToThreadId"),
                }),
        },
        "mobile.pullRequest.commentUpdate" => ForgeAction::CommentUpdate {
            number: number()?,
            locator: CommentLocator {
                source: CommentSource::parse(&require_string_key(payload, "source")?)?,
                comment_id: positive_i64(payload, "commentId")?,
                thread_id: thread_id("threadId"),
            },
            body: body()?,
        },
        "mobile.pullRequest.merge" => {
            let method = require_string_key(payload, "method")?;
            ForgeAction::Merge {
                number: number()?,
                method: MergeMethod::parse(&method)
                    .ok_or_else(|| HostError::state(format!("Unknown merge method: {method}")))?,
                expected_head: optional_string_key(payload, "expectedHeadSha")
                    .filter(|sha| !sha.trim().is_empty()),
            }
        }
        "mobile.pullRequest.draftStatus" => ForgeAction::DraftStatus {
            number: number()?,
            draft: payload
                .get("draft")
                .and_then(Value::as_bool)
                .ok_or_else(|| HostError::state("draft must be a boolean."))?,
        },
        "mobile.pullRequest.close" => ForgeAction::Close { number: number()? },
        "mobile.pullRequest.link" => ForgeAction::Link {
            reference: require_string_key(payload, "reference")?,
        },
        "mobile.pullRequest.unlink" => ForgeAction::Unlink {
            number: number()?,
            url: optional_string_key(payload, "url"),
        },
        "mobile.pullRequest.create" => {
            let title = require_string_key(payload, "title")?;
            if title.trim().is_empty() {
                return Err(HostError::state(
                    "Enter a title before creating the pull request.",
                ));
            }
            ForgeAction::Create(CreateInput {
                base: required_base(payload, "Select a base branch.")?,
                head: String::new(),
                title: title.trim().to_string(),
                body: optional_string_key(payload, "body").unwrap_or_default(),
                draft: payload
                    .get("draft")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
            })
        }
        "mobile.pullRequest.ship" => ForgeAction::Ship(ShipRequest {
            base: required_base(payload, "Select a base branch before shipping.")?,
            draft: payload
                .get("draft")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            scope: match optional_string_key(payload, "scope").as_deref() {
                None | Some("all") => ShipScope::All,
                Some("staged") => ShipScope::Staged,
                Some(other) => {
                    return Err(HostError::state(format!("Unknown ship scope: {other}")));
                }
            },
        }),
        other => {
            return Err(HostError::state(format!(
                "Unsupported pull request action: {other}"
            )));
        }
    })
}

fn required_base(payload: &Value, message: &str) -> HostResult<String> {
    let base = require_string_key(payload, "baseBranch")?
        .trim()
        .to_string();
    if base.is_empty() {
        return Err(HostError::state(message));
    }
    Ok(base)
}

pub(crate) fn positive_i64(payload: &Value, key: &str) -> HostResult<i64> {
    payload
        .get(key)
        .and_then(Value::as_i64)
        .filter(|value| *value > 0)
        .ok_or_else(|| HostError::state(format!("{key} must be a positive integer.")))
}

/// Runs one write verb on a checkout of this runtime, one write per
/// workspace at a time.
pub(crate) async fn run_forge_action(
    store: &RuntimeStore,
    workspace: &Workspace,
    request_type: &str,
    payload: &Value,
) -> HostResult<()> {
    let action = parse_forge_action(request_type, payload)?;
    require_local_workspace(workspace)?;
    let (forge, remote) = workspace_forge(store, workspace).await?;
    let _busy = BusyGuard::acquire(&workspace.id)?;
    match action {
        ForgeAction::Link { reference } => {
            let number = forge.review_reference(&reference)?;
            let review = forge.review_by_number(number).await?.ok_or_else(|| {
                HostError::state(format!("Pull request #{number} was not found."))
            })?;
            let url = Some(review.url).filter(|url| !url.is_empty());
            save_link(store, &workspace.id, forge.kind(), number, url, false).await
        }
        ForgeAction::Unlink { number, url } => {
            save_link(store, &workspace.id, forge.kind(), number, url, true).await
        }
        ForgeAction::Create(mut input) => {
            input.head = remote
                .branch
                .filter(|branch| !branch.is_empty() && branch != "HEAD")
                .ok_or_else(|| {
                    HostError::state("Check out a branch before creating a pull request.")
                })?;
            create_and_link(store, workspace, forge.as_ref(), &input)
                .await
                .map(|_| ())
        }
        ForgeAction::Ship(request) => {
            let hub_settings =
                super::super::remote_ai_assist_requests::hub_ai_assist_settings(payload)?;
            ship_pull_request(store, workspace, forge.as_ref(), request, hub_settings).await
        }
        ForgeAction::Comment {
            number,
            body,
            reply_to,
        } => forge.comment(number, &body, reply_to.as_ref()).await,
        ForgeAction::CommentUpdate {
            number,
            locator,
            body,
        } => forge.update_comment(number, &locator, &body).await,
        ForgeAction::Merge {
            number,
            method,
            expected_head,
        } => forge.merge(number, method, expected_head.as_deref()).await,
        ForgeAction::DraftStatus { number, draft } => forge.set_draft(number, draft).await,
        ForgeAction::Close { number } => forge.close(number).await,
    }
}
